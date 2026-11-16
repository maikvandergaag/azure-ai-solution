resource "azurerm_cognitive_account" "foundry" {
  name                          = local.names.foundry
  location                      = azurerm_resource_group.app.location
  resource_group_name           = azurerm_resource_group.app.name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = local.names.foundry_custom_subdomain
  local_auth_enabled            = false
  project_management_enabled    = true
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Deny"
  }
}

# Deployments on one account must be created one at a time; the lock serialises them.
resource "azapi_resource" "foundry_deployment" {
  for_each = { for d in var.foundry_deployments : d.name => d }

  type      = "Microsoft.CognitiveServices/accounts/deployments@2024-10-01"
  name      = each.key
  parent_id = azurerm_cognitive_account.foundry.id
  locks     = [azurerm_cognitive_account.foundry.id]

  body = {
    sku = {
      name     = each.value.sku.name
      capacity = each.value.sku.capacity
    }
    properties = {
      model = {
        format  = each.value.model.format
        name    = each.value.model.name
        version = each.value.model.version
      }
    }
  }
}

resource "azurerm_private_endpoint" "foundry" {
  name                = local.names.private_endpoint_foundry
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = local.names.private_endpoint_foundry
    private_connection_resource_id = azurerm_cognitive_account.foundry.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.private_link["privatelink.cognitiveservices.azure.com"].id,
      azurerm_private_dns_zone.private_link["privatelink.openai.azure.com"].id,
      azurerm_private_dns_zone.private_link["privatelink.services.ai.azure.com"].id,
    ]
  }
}
