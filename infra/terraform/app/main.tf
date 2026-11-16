data "azurerm_client_config" "current" {}

locals {
  app_registration_name = local.names.app_registration
  certificate_name      = var.certificate_name != null ? var.certificate_name : local.names.certificate_secret
  postgres_sku_prefix   = { Burstable = "B", GeneralPurpose = "GP", MemoryOptimized = "MO" }

  has_certificate = nonsensitive(var.certificate_pfx_base64 != "")
}

resource "azurerm_resource_group" "hub" {
  name     = local.hub_names.resource_group
  location = coalesce(var.hub_location, var.location)
  tags     = var.tags
}

resource "azurerm_resource_group" "app" {
  name     = local.names.resource_group
  location = var.location
  tags     = var.tags
}
