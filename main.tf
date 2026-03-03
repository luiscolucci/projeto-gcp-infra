# ==========================================
# 1. PROVIDER E ATIVAÇÃO DE APIs
# ==========================================
provider "google" {
  project = "projeto-infra-corp" # Ex: projeto-gcp-v3-prod
  region  = "us-central1"
  user_project_override = true
  billing_project       = "projeto-infra-corp"
}

resource "google_project_service" "api_compute" { service = "compute.googleapis.com" }
resource "google_project_service" "api_sqladmin" { service = "sqladmin.googleapis.com" }
resource "google_project_service" "api_servicenetworking" { service = "servicenetworking.googleapis.com" }
resource "google_project_service" "api_monitoring" { service = "monitoring.googleapis.com" }
resource "google_project_service" "api_billing" { service = "billingbudgets.googleapis.com" }

# ==========================================
# 2. REDE CORPORATIVA (VPC E SUBNET)
# ==========================================
resource "google_compute_network" "vpc_corporativa" {
  name                    = "vpc-corporativa"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.api_compute]
}

resource "google_compute_subnetwork" "subnet_us_central1" {
  name          = "subnet-us-central1"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc_corporativa.id
}

# ==========================================
# 3. SEGURANÇA (FIREWALL)
# ==========================================
resource "google_compute_firewall" "fw_permitir_web_ssh" {
  name    = "fw-permitir-web-ssh"
  network = google_compute_network.vpc_corporativa.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

# =================================================
# 4. BANCO DE DADOS ISOLADO (CLOUD SQL VIA PEERING)
# =================================================
resource "google_compute_global_address" "ip_privado_peering" {
  name          = "ip-privado-peering"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_corporativa.id
}

resource "google_service_networking_connection" "conexao_privada" {
  network                 = google_compute_network.vpc_corporativa.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.ip_privado_peering.name]
  depends_on              = [google_project_service.api_servicenetworking]
}

resource "google_sql_database_instance" "db_master_01" {
  name             = "db-master-01"
  database_version = "MYSQL_8_0"
  region           = "us-central1"
  depends_on       = [google_service_networking_connection.conexao_privada, google_project_service.api_sqladmin]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false # Garante que o banco não tem IP Público
      private_network = google_compute_network.vpc_corporativa.id
    }
  }
  deletion_protection = false
}

resource "google_sql_database" "app_producao_db" {
  name     = "app_producao_db"
  instance = google_sql_database_instance.db_master_01.name
}

resource "google_sql_user" "db_admin" {
  name     = "admin"
  instance = google_sql_database_instance.db_master_01.name
  password = "SenhaSegura123!"
}

# =============================================
# 5. MÁQUINA VIRTUAL SRE (DAEMON EM TEMPO REAL)
# =============================================
resource "google_compute_instance" "srv_web_01" {
  name         = "srv-web-01"
  machine_type = "e2-small"
  zone         = "us-central1-a"
  tags         = ["web"]

  metadata_startup_script = <<-EOF
    #!/bin/bash
    
    # Instalação Base
    apt-get update
    apt-get install -y apache2 netcat-openbsd default-mysql-client
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Infraestrutura Corporativa - Auto-Healing e Alertas Ativos!</h1>" > /var/www/html/index.html

    # Injeção do IP do Banco
    echo "${google_sql_database_instance.db_master_01.private_ip_address}" > /etc/db_ip.txt

    # Script do Agente SRE
    cat << 'EOF_SRE' > /usr/local/bin/health_check.sh
    #!/bin/bash
    LOG_FILE="/var/log/sre_agent.log"
    DB_IP=$(cat /etc/db_ip.txt)
    
    while true; do
        DATA=$(date '+%Y-%m-%d %H:%M:%S')

        # Log Rotation (1MB)
        if [ -f "$LOG_FILE" ]; then
            TAMANHO=$(du -k "$LOG_FILE" | cut -f1)
            if [ "$TAMANHO" -gt 1024 ]; then
                mv "$LOG_FILE" "/var/log/sre_agent_backup.log"
                echo "[$DATA] SRE Agent: Ficheiro atingiu 1MB. Limpeza executada!" > "$LOG_FILE"
            fi
        fi

        # Checagem da VPC
        if ping -c 1 -W 1 8.8.8.8 &> /dev/null; then
            VPC_STATUS="ONLINE"
        else
            VPC_STATUS="FALHA"
            echo "[$DATA] SRE Agent: ALERTA CRITICO! Falha de routing na VPC." >> "$LOG_FILE"
        fi

        # Auto-Healing do Apache
        if systemctl is-active --quiet apache2; then
            echo "[$DATA] SRE Agent: Apache ONLINE | VPC: $VPC_STATUS" >> "$LOG_FILE"
        else
            echo "[$DATA] SRE Agent: ALERTA! Apache offline. Iniciando Auto-Healing..." >> "$LOG_FILE"
            systemctl restart apache2
        fi

        # Checagem do Banco de Dados
        if ! nc -z -w2 "$DB_IP" 3306; then
            echo "[$DATA] SRE Agent: CRITICO! Conexao com o Banco falhou!" >> "$LOG_FILE"
        fi

        sleep 10
    done
    EOF_SRE

    chmod +x /usr/local/bin/health_check.sh

    # Criação do Serviço Linux (Daemon)
    cat << 'EOF_SVC' > /etc/systemd/system/sre-agent.service
    [Unit]
    Description=Agente SRE Daemon
    After=network.target
    [Service]
    ExecStart=/usr/local/bin/health_check.sh
    Restart=always
    User=root
    [Install]
    WantedBy=multi-user.target
    EOF_SVC

    systemctl daemon-reload
    systemctl enable sre-agent
    systemctl start sre-agent
  EOF

  boot_disk {
    initialize_params { image = "debian-cloud/debian-11" }
  }

  network_interface {
    network = google_compute_network.vpc_corporativa.id
    subnetwork = google_compute_subnetwork.subnet_us_central1.id #
    access_config {}
  }
}

# ==========================================
# 6. CANAIS DE NOTIFICAÇÃO (SMS E E-MAIL)
# ==========================================
resource "google_monitoring_notification_channel" "alerta_email" {
  display_name = "Alerta SRE - Email"
  type         = "email"
  depends_on   = [google_project_service.api_monitoring]
  labels = {
    email_address = "colucci.devops@gmail.com" # <--- MUDE AQUI
  }
}

resource "google_monitoring_notification_channel" "alerta_sms" {
  display_name = "Alerta SRE - SMS"
  type         = "sms"
  depends_on   = [google_project_service.api_monitoring]
  labels = {
    number = "+5511979597052" # <--- MUDE AQUI (Ex: +5511999999999)
  }
}

# ==========================================
# 7. FINOPS: ALERTA DE FATURAMENTO
# ==========================================
resource "google_billing_budget" "alerta_custos" {
  billing_account = "01FC41-A27AF2-DABEDE" # <--- MUDE AQUI (Ex: XXXXXX-XXXXXX-XXXXXX)
  display_name    = "Alerta de Custos - Infra Corp Prod"
  depends_on      = [google_project_service.api_billing]

  amount {
    specified_amount {
      currency_code = "BRL"
      units         = "150" # Limite de R$ 150,00
    }
  }

  threshold_rules { threshold_percent = 0.5 } # Avisa em 50%
  threshold_rules { threshold_percent = 0.9 } # Avisa em 90%
  threshold_rules { threshold_percent = 1.0 } # Avisa em 100%
}

# ==========================================
# 8. OBSERVABILIDADE: UPTIME CHECK
# ==========================================
resource "google_monitoring_uptime_check_config" "apache_uptime" {
  display_name = "Uptime Check - Servidor Web"
  timeout      = "10s"
  period       = "60s"
  depends_on   = [google_project_service.api_monitoring]

  http_check {
    path = "/"
    port = "80"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = "projeto-infra-corp" # <--- MUDE AQUI (Igual ao do Bloco 1)
      host       = google_compute_instance.srv_web_01.network_interface[0].access_config[0].nat_ip
    }
  }
}

# ==========================================
# 9. MONITORAMENTO DE DISPONIBILIDADE (UP/DOWN)
# ==========================================
resource "google_monitoring_alert_policy" "alerta_queda_apache" {
  display_name = "CRÍTICO: Servidor Web OFF"
  combiner     = "OR"
  depends_on   = [google_project_service.api_monitoring]
  
  notification_channels = [
    google_monitoring_notification_channel.alerta_email.id,
    google_monitoring_notification_channel.alerta_sms.id
  ]

  conditions {
    display_name = "Uptime Check Falhou"
    condition_threshold {
      filter     = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.apache_uptime.uptime_check_id}\""
      duration   = "60s"
      comparison = "COMPARISON_LT"
      threshold_value = 1
      
      trigger { count = 1 }
    }
  }
}
# ==========================================
# 10. OUTPUTS (O MEGAFONE DO TERRAFORM)
# ==========================================
output "ip_publico_servidor_web" {
  description = "IP Publico para acessar o Apache e conectar via SSH"
  value       = google_compute_instance.srv_web_01.network_interface[0].access_config[0].nat_ip
}

output "ip_privado_banco_dados" {
  description = "IP Privado do Banco (Acessivel apenas por dentro da VPC)"
  value       = google_sql_database_instance.db_master_01.private_ip_address
}
