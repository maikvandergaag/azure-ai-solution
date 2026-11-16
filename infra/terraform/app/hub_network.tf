resource "azurerm_network_security_group" "apim" {
  name                = local.hub_names.network_security_group_apim
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  dynamic "security_rule" {
    for_each = jsondecode(file("${path.module}/../assets/nsg-rules.json"))

    content {
      name                       = security_rule.value.name
      description                = try(security_rule.value.properties.description, null)
      priority                   = security_rule.value.properties.priority
      direction                  = security_rule.value.properties.direction
      access                     = security_rule.value.properties.access
      protocol                   = security_rule.value.properties.protocol
      source_port_range          = security_rule.value.properties.sourcePortRange
      source_address_prefix      = security_rule.value.properties.sourceAddressPrefix
      destination_address_prefix = security_rule.value.properties.destinationAddressPrefix
      destination_port_range     = try(security_rule.value.properties.destinationPortRange, null)
      destination_port_ranges    = try(security_rule.value.properties.destinationPortRanges, null)
    }
  }
}

# Prevents forced tunnelling of the APIM management endpoint traffic.
resource "azurerm_route_table" "apim" {
  name                = local.hub_names.route_table_apim
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  route {
    name           = "apim-management-endpoint"
    address_prefix = "ApiManagement"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_virtual_network" "hub" {
  name                = local.hub_names.virtual_network
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = [var.hub_virtual_network_address_prefix]
}

resource "azurerm_subnet" "apim" {
  name                 = local.hub_names.subnet_apim
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.apim_subnet_address_prefix]
  dynamic "service_endpoint" {
    for_each = toset([
      "Microsoft.Storage",
      "Microsoft.Sql",
      "Microsoft.EventHub",
      "Microsoft.KeyVault",
      "Microsoft.ServiceBus",
      "Microsoft.AzureActiveDirectory",
    ])
    content {
      service = service_endpoint.value
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

resource "azurerm_subnet_route_table_association" "apim" {
  subnet_id      = azurerm_subnet.apim.id
  route_table_id = azurerm_route_table.apim.id
}

resource "azurerm_subnet" "app_gateway" {
  name                 = local.hub_names.subnet_app_gateway
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.app_gateway_subnet_address_prefix]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = local.hub_names.subnet_private_endpoints
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.pe_subnet_address_prefix]
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-${azurerm_virtual_network.hub.name}-to-${azurerm_virtual_network.app.name}"
  resource_group_name          = azurerm_resource_group.hub.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.app.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_public_ip" "app_gateway" {
  name                = local.hub_names.public_ip_app_gateway
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "apim" {
  name                = local.hub_names.public_ip_apim
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "Standard"
  allocation_method   = "Static"
  domain_name_label   = local.hub_names.api_management
}
