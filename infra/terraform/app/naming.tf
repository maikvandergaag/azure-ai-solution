module "naming" {
  source = "../modules/naming"

  workload        = var.workload
  environment     = var.environment
  location        = var.location
  location_short  = var.location_short
  instance        = var.instance
  subscription_id = data.azurerm_client_config.current.subscription_id
}

# Hub resources use the same convention with their own workload and, optionally, region.
module "hub_naming" {
  source = "../modules/naming"

  workload    = var.hub_workload
  environment = var.environment
  location    = coalesce(var.hub_location, var.location)
  location_short = var.hub_location_short != null ? var.hub_location_short : (
    lower(replace(coalesce(var.hub_location, var.location), " ", "")) == lower(replace(var.location, " ", "")) ? var.location_short : null
  )
  instance        = var.instance
  subscription_id = data.azurerm_client_config.current.subscription_id
}

locals {
  names     = module.naming.names
  hub_names = module.hub_naming.names
}
