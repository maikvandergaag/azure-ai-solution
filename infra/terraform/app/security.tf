resource "azurerm_key_vault" "app" {
  name                       = local.names.key_vault
  location                   = azurerm_resource_group.app.location
  resource_group_name        = azurerm_resource_group.app.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

# Secrets are written through the control plane, so the deploying identity needs no Key Vault data-plane role.
# Secret values go in sensitive_body (write-only) and are kept out of Terraform state.
resource "azapi_resource" "certificate_secret" {
  count = local.has_certificate ? 1 : 0

  type      = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  name      = local.certificate_name
  parent_id = azurerm_key_vault.app.id

  body = {
    properties = {
      contentType = "application/x-pkcs12"
    }
  }

  sensitive_body = {
    properties = {
      value = var.certificate_pfx_base64
    }
  }

  sensitive_body_version = {
    "properties.value" = nonsensitive(sha256(var.certificate_pfx_base64))
  }
}

resource "azapi_resource" "postgres_connection_string_secret" {
  type      = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  name      = "postgres-connection-string"
  parent_id = azurerm_key_vault.app.id

  body = {
    properties = {}
  }

  sensitive_body = {
    properties = {
      value = "postgresql://${var.postgres_config.admin_username}:${var.postgres_admin_password}@${azurerm_postgresql_flexible_server.app.fqdn}:5432/${var.postgres_config.database_name}?sslmode=require"
    }
  }

  sensitive_body_version = {
    "properties.value" = "${var.postgres_admin_password_version}-${azurerm_postgresql_flexible_server.app.fqdn}"
  }
}

resource "azapi_resource" "webui_secret_key" {
  type      = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  name      = "webui-secret-key"
  parent_id = azurerm_key_vault.app.id

  body = {
    properties = {}
  }

  sensitive_body = {
    properties = {
      value = var.webui_secret_key
    }
  }

  sensitive_body_version = {
    "properties.value" = "${var.webui_secret_key_version}"
  }
}

resource "azurerm_user_assigned_identity" "environment" {
  name                = local.names.managed_identity
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
}

resource "azurerm_role_assignment" "environment_key_vault" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "environment_storage_smb" {
  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage File Data SMB MI Admin"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "container_app_key_vault" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.open_webui.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
