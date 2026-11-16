# Sample values - change as required for your setup/demo/poc.
# Secrets are not stored here. Supply them as environment variables:
#   export TF_VAR_postgres_admin_password='<password>'
#   export TF_VAR_certificate_pfx_base64="$(base64 -i cert.pfx)"   # only without the App Service Certificate
#
# Resource names follow <type>-<workload>-<environment>-<region>-<instance>,
# for example rg-owui-demo-uks-01 (app) and rg-owui-hub-demo-uks-01 (hub).
# Globally unique names get a short suffix.
location    = "swedencentral"
workload    = "dbs-chat"
environment = "dev"
instance    = "01"

hub_workload = "dbs-hub"
# hub_location       = "uksouth" # set to deploy the hub in a different region
# hub_location_short = "uks"     # set when the hub uses a custom region abbreviation

apim_publisher_email = "maik@familie-vandergaag.nl"
apim_publisher_name  = "MSFTPlayground"
apim_sku_name        = "Developer_1" # Cheap for demo purposes
app_gateway_sku      = "Standard_v2"

hub_virtual_network_address_prefix = "10.0.0.0/24"
apim_subnet_address_prefix         = "10.0.0.0/28"
app_gateway_subnet_address_prefix  = "10.0.0.64/26"
pe_subnet_address_prefix           = "10.0.0.128/28"

virtual_network_address_prefix = "10.0.4.0/22"
aca_subnet_address_prefix      = "10.0.4.0/23"
custom_domain                  = "webui.msftplayground.com"

# Entra ID security groups granted the Open WebUI app roles (group-based access).
# Leave empty to assign users/groups outside Terraform.
open_webui_user_group_name  = "SG-DBS-chat-users"
open_webui_admin_group_name = "SG-DBS-chat-admins"

# Azure purchases, verifies, stores and renews the TLS certificate (about USD 70/year).
use_app_service_certificate = true
# DNS is managed externally: Terraform creates no DNS records (public_dns_zone_name defaults to "").
# Run `terraform output dns_records` for the records to create at the DNS provider.
# Set to a published custom image to apply the optional Databalance theme.
 open_webui_image = "ghcr.io/open-webui/open-webui:v0.13.3"

postgres_config = {
  sku_name        = "Standard_D2ds_v5" # Burstable and D*_v3 SKUs have no capacity in swedencentral (SkuNotAvailable)
  tier            = "GeneralPurpose"
  version         = "16"
  storage_size_gb = 32
  database_name   = "dbswebui"
  admin_username  = "pgadmin"
}

container_app_allowed_ip_addresses = [
  "10.0.0.64/26", # App Gateway subnet
]

container_app_scale_settings = {
  min_replicas = 1
  max_replicas = 1
}

tags = {
  purpose     = "Hosting DBS chat WebUI"
  environment = "dev"
  owner       = "Team Microsoft"
  clean       = "false"
}

foundry_deployments = [
  # OpenAI models use DataZoneStandard: inference stays within the EU data zone.
  {
    name  = "gpt-5-mini"
    model = { format = "OpenAI", name = "gpt-5-mini", version = "2025-08-07" }
    sku   = { name = "DataZoneStandard", capacity = 100 }
  },
  {
    name  = "gpt-6.1-terra"
    model = { format = "OpenAI", name = "gpt-6.1-terra", version = "2026-10-26" }
    sku   = { name = "DataZoneStandard", capacity = 100 }
  },
  {
    name  = "gpt-image-1.5"
    model = { format = "OpenAI", name = "gpt-image-1.5", version = "2025-12-16" }
    sku   = { name = "DataZoneStandard", capacity = 3 }
  },
  {
    name  = "text-embedding-3-large"
    model = { format = "OpenAI", name = "text-embedding-3-large", version = "1" }
    sku   = { name = "DataZoneStandard", capacity = 100 }
  },
  # No EU data zone SKU is available for the models below; they process globally.
  {
    name  = "Phi-4-reasoning"
    model = { format = "Microsoft", name = "Phi-4-reasoning", version = "1" }
    sku   = { name = "GlobalStandard", capacity = 20 }
  },
  {
    name  = "gpt-oss-120b"
    model = { format = "OpenAI-OSS", name = "gpt-oss-120b", version = "1" }
    sku   = { name = "GlobalStandard", capacity = 100 }
  },
  {
    name  = "grok-4.7"
    model = { format = "xAI", name = "grok-4.7", version = "1" }
    sku   = { name = "GlobalStandard", capacity = 80 }
  }
]
