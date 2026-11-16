resource "azurerm_user_assigned_identity" "app_gateway" {
  name                = local.hub_names.managed_identity_app_gateway
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_role_assignment" "app_gateway_key_vault" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app_gateway.principal_id
  principal_type       = "ServicePrincipal"
}
