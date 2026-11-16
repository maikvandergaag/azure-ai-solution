resource "azurerm_log_analytics_workspace" "hub" {
  name                         = local.hub_names.log_analytics_workspace
  location                     = azurerm_resource_group.hub.location
  resource_group_name          = azurerm_resource_group.hub.name
  sku                          = "PerGB2018"
  retention_in_days            = 30
  daily_quota_gb               = 1
  local_authentication_enabled = false
}

resource "azurerm_application_insights" "hub" {
  name                         = local.hub_names.application_insights
  location                     = azurerm_resource_group.hub.location
  resource_group_name          = azurerm_resource_group.hub.name
  workspace_id                 = azurerm_log_analytics_workspace.hub.id
  application_type             = "web"
  local_authentication_enabled = false
}
