# ☁️ Projeto GCP Infra - Arquitetura Corporativa Resiliente

Este repositório contém o provisionamento completo de uma infraestrutura corporativa no Google Cloud Platform (GCP) utilizando **Terraform** (Infrastructure as Code). O projeto demonstra práticas reais de DevOps e SRE, com foco em alta disponibilidade, segurança e observabilidade.

## 🚀 Principais Recursos da Arquitetura

* **Infraestrutura como Código (IaC):** Automação total do provisionamento e gerenciamento de estado via Terraform.
* **Segurança e Isolamento:** VPC customizada garantindo tráfego restrito e regras de firewall estruturadas.
* **Auto-Healing (SRE):** Instâncias Compute Engine configuradas com scripts de inicialização (Apache) e capacidade de auto-recuperação (ressurreição do serviço em caso de falha).
* **Banco de Dados Gerenciado:** Cloud SQL provisionado e integrado de forma segura à rede.
* **Observabilidade Global e Alertas:** Uptime Checks do Google Cloud Monitoring verificando a saúde da aplicação, com gatilhos de alerta multicanal via E-mail e SMS.
* **Governança e FinOps:** Alertas de custo e orçamento configurados desde o dia zero para evitar surpresas no faturamento do laboratório.

## 🛠️ Tecnologias Utilizadas

* **Provedor Cloud:** Google Cloud Platform (GCP)
* **IaC:** HashiCorp Terraform
* **Serviços GCP:** Compute Engine, Cloud SQL, VPC Network, Cloud Monitoring, Service Networking API.

## 📋 Pré-requisitos

Antes de executar este projeto, certifique-se de ter:
1. Uma conta no GCP com uma conta de faturamento (Billing) ativa.
2. O [Google Cloud CLI (`gcloud`)](https://cloud.google.com/sdk/docs/install) instalado e configurado.
3. O [Terraform](https://developer.hashicorp.com/terraform/install) instalado na sua máquina local.

## ⚙️ Como Executar o Laboratório

**1. Autenticação e Configuração do Projeto:**
No seu terminal, autentique-se no GCP e aponte para o projeto desejado:
```bash
gcloud auth application-default login
gcloud config set project SEU_ID_DO_PROJETO
gcloud auth application-default set-quota-project SEU_ID_DO_PROJETO

2. Destrancando as APIs essenciais (Troubleshooting Sênior):
Para garantir que o Terraform consiga operar livremente num projeto novo, libere as APIs base:

-> gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com

3. Iniciando o Terraform:
Baixa os plugins e prepara o diretório de trabalho:

-> terraform init

4. Validação e Planejamento:
Verifica o que será criado antes de impactar a nuvem:

-> terraform plan

5. Aplicação da Infraestrutura:
Sobe a arquitetura completa:

-> terraform apply

(Confirme com yes quando solicitado. O processo pode levar alguns minutos, especialmente o provisionamento do Cloud SQL).

🧹 Limpeza (FinOps)
A regra de ouro de Cloud Computing é não deixar recursos ociosos. Para desmontar todo o laboratório de forma segura e zerar os custos:

-> terraform destroy

#Para excluir do GCP

-> gcloud projects delete [ID do PROJETO]

#Excluindo de forma definitiva CUIDADO COM ESSE COMANDO NÃO HÁ COMO RESTAURAR

-> gcloud projects list --filter="lifecycleState:DELETE_REQUESTED"

---------------------------------------------------------------------------------------------------------------------------------------------------------
Desenvolvido por Luis Colucci
