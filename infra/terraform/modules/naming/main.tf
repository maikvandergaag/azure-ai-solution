# Builds resource names as <abbreviation>-<workload>-<environment>-<region>-<instance>,
# using the Cloud Adoption Framework abbreviations. Globally unique names get a short
# deterministic suffix derived from the subscription so they are stable and predictable.

terraform {
  required_version = ">= 1.11"
}

variable "workload" {
  description = "Workload abbreviation, for example owui or owui-hub."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,8}[a-z0-9]$", var.workload)) && !strcontains(var.workload, "--")
    error_message = "workload must be 2-10 lowercase letters, digits or single hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment abbreviation, for example demo, dev or prod."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,6}$", var.environment))
    error_message = "environment must be 2-7 lowercase letters or digits and start with a letter."
  }
}

variable "location" {
  description = "Azure region, for example uksouth."
  type        = string

  validation {
    condition = (
      var.location_short != null ||
      contains(keys(local.region_abbreviations), lower(replace(var.location, " ", "")))
    )
    error_message = "No built-in abbreviation exists for location; set location_short explicitly."
  }
}

variable "location_short" {
  description = "Region abbreviation. Defaults to a built-in abbreviation for the region."
  type        = string
  default     = null

  validation {
    condition     = var.location_short == null || can(regex("^[a-z][a-z0-9]{1,5}$", coalesce(var.location_short, "x")))
    error_message = "location_short must be 2-6 lowercase letters or digits and start with a letter."
  }
}

variable "instance" {
  description = "Instance number, for example 01."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{2,3}$", var.instance))
    error_message = "instance must be 2 or 3 digits, for example 01."
  }
}

variable "subscription_id" {
  description = "Subscription ID used to derive the suffix of globally unique names."
  type        = string
}

locals {
  region_abbreviations = {
    australiaeast      = "aue"
    brazilsouth        = "brs"
    canadacentral      = "cac"
    centralindia       = "inc"
    centralus          = "cus"
    eastasia           = "ea"
    eastus             = "eus"
    eastus2            = "eus2"
    francecentral      = "frc"
    germanywestcentral = "gwc"
    italynorth         = "itn"
    japaneast          = "jpe"
    koreacentral       = "krc"
    northcentralus     = "ncus"
    northeurope        = "neu"
    norwayeast         = "noe"
    polandcentral      = "plc"
    southafricanorth   = "san"
    southcentralus     = "scus"
    southeastasia      = "sea"
    spaincentral       = "spc"
    swedencentral      = "sdc"
    switzerlandnorth   = "szn"
    uaenorth           = "uan"
    uksouth            = "uks"
    ukwest             = "ukw"
    westeurope         = "weu"
    westus             = "wus"
    westus2            = "wus2"
    westus3            = "wus3"
  }

  region = coalesce(var.location_short, lookup(local.region_abbreviations, lower(replace(var.location, " ", "")), "unknown"))
  base   = "${var.workload}-${var.environment}-${local.region}-${var.instance}"
  flat   = replace(local.base, "-", "")
  unique = substr(sha1("${lower(var.subscription_id)}/${local.base}"), 0, 4)

  # Key Vault: 3-24 characters, without a trailing hyphen before the suffix.
  key_vault_stem = replace(substr("kv-${local.base}", 0, 19), "/-+$/", "")
}

output "base" {
  description = "Shared name segment <workload>-<environment>-<region>-<instance>."
  value       = local.base
}

output "unique_suffix" {
  description = "Deterministic suffix for globally unique names."
  value       = local.unique
}

output "names" {
  description = "Resource names by purpose."
  value = {
    resource_group               = "rg-${local.base}"
    virtual_network              = "vnet-${local.base}"
    subnet_apim                  = "snet-apim-${local.base}"
    subnet_app_gateway           = "snet-agw-${local.base}"
    subnet_private_endpoints     = "snet-pep-${local.base}"
    subnet_container_apps        = "snet-cae-${local.base}"
    network_security_group_apim  = "nsg-apim-${local.base}"
    network_security_group_aca   = "nsg-cae-${local.base}"
    route_table_apim             = "rt-apim-${local.base}"
    public_ip_app_gateway        = "pip-agw-${local.base}"
    public_ip_apim               = "pip-apim-${local.base}"
    application_gateway          = "agw-${local.base}"
    api_management               = "apim-${local.base}-${local.unique}"
    managed_identity             = "id-${local.base}"
    managed_identity_app_gateway = "id-agw-${local.base}"
    log_analytics_workspace      = "log-${local.base}"
    application_insights         = "appi-${local.base}"
    diagnostic_setting_apim      = "diag-apim-${local.base}"
    key_vault                    = "${local.key_vault_stem}-${local.unique}"
    storage_account              = "${substr("st${local.flat}", 0, 20)}${local.unique}"
    storage_share                = "share-${local.base}"
    postgresql_server            = "psql-${local.base}-${local.unique}"
    private_endpoint_postgresql  = "pep-psql-${local.base}"
    container_apps_environment   = "cae-${local.base}"
    container_app                = "ca-${local.base}"
    container                    = "ctr-${local.base}"
    foundry                      = "aif-${local.base}"
    foundry_custom_subdomain     = "aif-${local.base}-${local.unique}"
    private_endpoint_foundry     = "pep-aif-${local.base}"
    app_registration             = "app-${local.base}"
    certificate_order            = substr("cert${local.flat}", 0, 50)
    certificate_secret           = "cert-${local.base}"
  }
}
