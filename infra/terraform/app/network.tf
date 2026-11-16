resource "azurerm_network_security_group" "aca" {
  name                = local.names.network_security_group_aca
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
}

resource "azurerm_virtual_network" "app" {
  name                = local.names.virtual_network
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  address_space       = [var.virtual_network_address_prefix]
}

# Delegated to Microsoft.App/environments, required by the Container Apps environment.
resource "azurerm_subnet" "aca" {
  name                 = local.names.subnet_container_apps
  resource_group_name  = azurerm_resource_group.app.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = [var.aca_subnet_address_prefix]

  delegation {
    name = "aca-environments"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  service_endpoint {
    service = "Microsoft.Storage"
  }
}

resource "azurerm_subnet_network_security_group_association" "aca" {
  subnet_id                 = azurerm_subnet.aca.id
  network_security_group_id = azurerm_network_security_group.aca.id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-${azurerm_virtual_network.app.name}-to-${azurerm_virtual_network.hub.name}"
  resource_group_name          = azurerm_resource_group.app.name
  virtual_network_name         = azurerm_virtual_network.app.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Link the hub private DNS zones to the spoke VNet so private endpoints resolve from the Container App.
resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = azurerm_private_dns_zone.private_link

  name                 = "link-${azurerm_virtual_network.app.name}"
  private_dns_zone_id  = each.value.id
  virtual_network_id   = azurerm_virtual_network.app.id
  registration_enabled = false
}
