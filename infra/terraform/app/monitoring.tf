resource "azurerm_log_analytics_workspace" "app" {
  name                         = local.names.log_analytics_workspace
  location                     = azurerm_resource_group.app.location
  resource_group_name          = azurerm_resource_group.app.name
  sku                          = "PerGB2018"
  retention_in_days            = 30
  daily_quota_gb               = 1
  local_authentication_enabled = false
}

resource "azurerm_application_insights" "app" {
  name                         = local.names.application_insights
  location                     = azurerm_resource_group.app.location
  resource_group_name          = azurerm_resource_group.app.name
  workspace_id                 = azurerm_log_analytics_workspace.app.id
  application_type             = "web"
  local_authentication_enabled = false
}
