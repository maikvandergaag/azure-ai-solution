locals {
  # All three zones are required for private endpoint resolution of the AIServices (Foundry) kind.
  private_dns_zones = toset([
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.services.ai.azure.com",
    "privatelink.postgres.database.azure.com",
  ])
}

resource "azurerm_private_dns_zone" "private_link" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "private_link_hub" {
  for_each = azurerm_private_dns_zone.private_link

  name                 = "link-${azurerm_virtual_network.hub.name}"
  private_dns_zone_id  = each.value.id
  virtual_network_id   = azurerm_virtual_network.hub.id
  registration_enabled = false
}

# Private DNS zone for the internal Container Apps environment, used by Application Gateway to resolve the backend.
resource "azurerm_private_dns_zone" "container_app" {
  name                = azurerm_container_app_environment.app.default_domain
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_private_dns_a_record" "container_app" {
  name                = azurerm_container_app.open_webui.name
  private_dns_zone_id = azurerm_private_dns_zone.container_app.id
  ttl                 = 3600
  records             = [azurerm_container_app_environment.app.static_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "container_app_hub" {
  name                 = "link-${azurerm_virtual_network.hub.name}"
  private_dns_zone_id  = azurerm_private_dns_zone.container_app.id
  virtual_network_id   = azurerm_virtual_network.hub.id
  registration_enabled = false
}

# Private DNS zone for APIM in internal VNet mode.
resource "azurerm_private_dns_zone" "apim" {
  name                = "azure-api.net"
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim_hub" {
  name                 = "link-${azurerm_virtual_network.hub.name}"
  private_dns_zone_id  = azurerm_private_dns_zone.apim.id
  virtual_network_id   = azurerm_virtual_network.hub.id
  registration_enabled = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim_spoke" {
  name                 = "link-${azurerm_virtual_network.app.name}"
  private_dns_zone_id  = azurerm_private_dns_zone.apim.id
  virtual_network_id   = azurerm_virtual_network.app.id
  registration_enabled = false
}

resource "azurerm_private_dns_a_record" "apim" {
  name                = azapi_resource.apim.name
  private_dns_zone_id = azurerm_private_dns_zone.apim.id
  ttl                 = 3600
  records             = [azapi_resource.apim.output.properties.privateIPAddresses[0]]
}
