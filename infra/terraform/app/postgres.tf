resource "azurerm_postgresql_flexible_server" "app" {
  name                              = local.names.postgresql_server
  location                          = azurerm_resource_group.app.location
  resource_group_name               = azurerm_resource_group.app.name
  sku_name                          = "${local.postgres_sku_prefix[var.postgres_config.tier]}_${var.postgres_config.sku_name}"
  version                           = var.postgres_config.version
  storage_mb                        = var.postgres_config.storage_size_gb * 1024
  administrator_login               = var.postgres_config.admin_username
  administrator_password_wo         = var.postgres_admin_password
  administrator_password_wo_version = var.postgres_admin_password_version
  public_network_access_enabled     = false

  # Open WebUI does not support Entra ID authentication for PostgreSQL.
  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "open_webui" {
  name      = var.postgres_config.database_name
  server_id = azurerm_postgresql_flexible_server.app.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_private_endpoint" "postgres" {
  name                = local.names.private_endpoint_postgresql
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = local.names.private_endpoint_postgresql
    private_connection_resource_id = azurerm_postgresql_flexible_server.app.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.private_link["privatelink.postgres.database.azure.com"].id]
  }
}
