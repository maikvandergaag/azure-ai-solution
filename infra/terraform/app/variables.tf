variable "subscription_id" {
  description = "Subscription to deploy into. Defaults to ARM_SUBSCRIPTION_ID or the Azure CLI default subscription."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for the app (spoke) resources."
  type        = string
}

variable "workload" {
  description = "Workload abbreviation used in spoke resource names, for example owui. Names follow <type>-<workload>-<environment>-<region>-<instance>."
  type        = string
}

variable "environment" {
  description = "Environment abbreviation used in resource names, for example demo, dev or prod. Shared by the hub and app resources."
  type        = string
}

variable "location_short" {
  description = "Region abbreviation used in resource names. Leave null to use the built-in abbreviation for location."
  type        = string
  default     = null
}

variable "instance" {
  description = "Instance number used in resource names, for example 01. Shared by the hub and app resources."
  type        = string
  default     = "01"
}

variable "hub_workload" {
  description = "Workload abbreviation used in hub resource names, for example owui-hub."
  type        = string
}

variable "hub_location" {
  description = "Azure region for the hub resources. Leave null to use location."
  type        = string
  default     = null
}

variable "hub_location_short" {
  description = "Hub region abbreviation. Leave null to use location_short when hub_location equals location, or the built-in abbreviation otherwise."
  type        = string
  default     = null
}

variable "apim_publisher_email" {
  description = "API Management publisher email address."
  type        = string
}

variable "apim_publisher_name" {
  description = "API Management publisher name."
  type        = string
}

variable "apim_sku_name" {
  description = "API Management SKU in the form <tier>_<capacity>, for example Developer_1."
  type        = string
  default     = "Developer_1"
}

variable "app_gateway_sku" {
  description = "Application Gateway SKU name and tier."
  type        = string
  default     = "Standard_v2"
}

variable "hub_virtual_network_address_prefix" {
  description = "Address prefix of the hub virtual network."
  type        = string
}

variable "apim_subnet_address_prefix" {
  description = "Address prefix of the API Management subnet."
  type        = string
}

variable "app_gateway_subnet_address_prefix" {
  description = "Address prefix of the Application Gateway subnet."
  type        = string
}

variable "pe_subnet_address_prefix" {
  description = "Address prefix of the private endpoint subnet."
  type        = string
}

variable "virtual_network_address_prefix" {
  description = "Address prefix of the spoke virtual network."
  type        = string
}

variable "aca_subnet_address_prefix" {
  description = "Address prefix of the Container Apps environment subnet (minimum /23 for a consumption-only environment)."
  type        = string
}

variable "custom_domain" {
  description = "Custom domain for Open WebUI, for example openwebui.example.com."
  type        = string
}

variable "certificate_name" {
  description = "Optional name of the Key Vault secret and Container Apps environment certificate. Defaults to the generated certificate name. Application Gateway uses the same secret."
  type        = string
  default     = null

  validation {
    condition     = var.certificate_name == null || can(regex("^[a-zA-Z0-9-]{1,127}$", var.certificate_name))
    error_message = "certificate_name must be 1-127 letters, digits or hyphens."
  }
}

variable "certificate_pfx_base64" {
  description = "Base64-encoded PFX for the custom domain. Leave empty when use_app_service_certificate is true, or to import the certificate into the spoke Key Vault yourself under the generated certificate name or certificate_name override."
  type        = string
  default     = ""
  sensitive   = true
}

variable "use_app_service_certificate" {
  description = "Purchase an App Service Certificate for custom_domain and store it in the spoke Key Vault. Charges the subscription."
  type        = bool
  default     = false
}

variable "app_service_certificate_product_type" {
  description = "App Service Certificate SKU: StandardDomainValidatedSsl or StandardDomainValidatedWildCardSsl."
  type        = string
  default     = "StandardDomainValidatedSsl"

  validation {
    condition     = contains(["StandardDomainValidatedSsl", "StandardDomainValidatedWildCardSsl"], var.app_service_certificate_product_type)
    error_message = "app_service_certificate_product_type must be StandardDomainValidatedSsl or StandardDomainValidatedWildCardSsl."
  }
}

variable "app_service_certificate_auto_renew" {
  description = "Automatically renew the App Service Certificate each year."
  type        = bool
  default     = true
}

variable "public_dns_zone_name" {
  description = "Azure DNS public zone for the root domain of custom_domain, for example example.com. When set, Terraform creates the certificate domain-verification TXT record. Leave empty for external DNS."
  type        = string
  default     = ""
}

variable "public_dns_zone_resource_group_name" {
  description = "Resource group of public_dns_zone_name."
  type        = string
  default     = ""
}

variable "open_webui_image" {
  description = "Open WebUI container image. Override with a published custom image to apply the optional Databalance theme."
  type        = string
  default     = "ghcr.io/open-webui/open-webui:main"
}

variable "postgres_admin_password" {
  description = "PostgreSQL administrator password. Write-only: it is never stored in Terraform state. Supply it via TF_VAR_postgres_admin_password."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "postgres_admin_password_version" {
  description = "Increment to push a changed postgres_admin_password to the server and the Key Vault connection string."
  type        = number
  default     = 1
}

variable "webui_secret_key" {
  description = "Stable Open WebUI signing key. Write-only: it is never stored in Terraform state. Supply it via TF_VAR_webui_secret_key."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = length(var.webui_secret_key) >= 32
    error_message = "webui_secret_key must contain at least 32 characters."
  }
}

variable "webui_secret_key_version" {
  description = "Increment to push a changed webui_secret_key to Key Vault."
  type        = number
  default     = 1
}

variable "postgres_config" {
  description = "PostgreSQL Flexible Server configuration."
  type = object({
    sku_name        = string
    tier            = string
    version         = string
    storage_size_gb = number
    database_name   = string
    admin_username  = string
  })
  default = {
    sku_name        = "Standard_B1ms"
    tier            = "Burstable"
    version         = "16"
    storage_size_gb = 32
    database_name   = "openwebui"
    admin_username  = "pgadmin"
  }

  validation {
    condition     = contains(["Burstable", "GeneralPurpose", "MemoryOptimized"], var.postgres_config.tier)
    error_message = "postgres_config.tier must be Burstable, GeneralPurpose or MemoryOptimized."
  }
}

variable "container_app_allowed_ip_addresses" {
  description = "CIDR ranges allowed to reach the Container App ingress. Empty allows all."
  type        = list(string)
  default     = []
}

variable "container_app_scale_settings" {
  description = "Container App replica limits."
  type = object({
    min_replicas = number
    max_replicas = number
  })
  default = {
    min_replicas = 1
    max_replicas = 1
  }
}

variable "foundry_deployments" {
  description = "Model deployments to create on the Foundry account."
  type = list(object({
    name = string
    model = object({
      format  = string
      name    = string
      version = string
    })
    sku = object({
      name     = string
      capacity = number
    })
  }))
  default = []
}

variable "open_webui_user_group_name" {
  description = "Display name of the Entra ID security group Terraform creates and assigns the Open WebUI user app role. Empty to manage access outside Terraform."
  type        = string
  default     = ""
}

variable "open_webui_admin_group_name" {
  description = "Display name of the Entra ID security group Terraform creates and assigns the Open WebUI admin app role. Empty to manage access outside Terraform."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the hub and app resource groups."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["purpose", "environment", "owner"] : contains(keys(var.tags), k)])
    error_message = "tags must contain purpose, environment and owner."
  }

  validation {
    condition     = contains(["mvp", "dev", "prd"], lookup(var.tags, "environment", ""))
    error_message = "tags.environment must be one of mvp, dev or prd."
  }
}
