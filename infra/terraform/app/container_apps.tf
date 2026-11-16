locals {
  # See https://docs.openwebui.com/getting-started/env-configuration/
  open_webui_env = {
    WEBUI_URL                      = "https://${var.custom_domain}"
    ENABLE_OAUTH_SIGNUP            = "true"
    ENABLE_LOGIN_FORM              = "false"
    ENABLE_OAUTH_PERSISTENT_CONFIG = "false"
    OAUTH_CLIENT_ID                = azuread_application.open_webui.client_id
    OAUTH_CODE_CHALLENGE_METHOD    = "S256"
    OAUTH_PROVIDER_NAME            = "Microsoft Entra ID"
    OAUTH_SCOPES                   = "openid email profile api://${local.app_registration_name}/user_impersonation User.Read GroupMember.Read.All ProfilePhoto.Read.All"
    OPENID_PROVIDER_URL            = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0/.well-known/openid-configuration"
    OAUTH_EMAIL_CLAIM              = "email"
    OAUTH_USERNAME_CLAIM           = "name"
    OPENAI_API_BASE_URL            = "https://${local.hub_names.api_management}.azure-api.net/openai/v1"
    ENV                            = "prod"
    DATA_DIR                       = "/app/backend/data"
    WEBUI_NAME                     = "Open WebUI"
    ENABLE_SIGNUP                  = "false"
    DEFAULT_USER_ROLE              = "user"
    ENABLE_ADMIN_CHAT_ACCESS       = "true"
    ENABLE_ADMIN_EXPORT            = "true"
    WEBUI_SESSION_COOKIE_SAME_SITE = "lax"
    WEBUI_SESSION_COOKIE_SECURE    = "true"
    ENABLE_COMMUNITY_SHARING       = "false"
    ENABLE_MESSAGE_RATING          = "true"
    GLOBAL_LOG_LEVEL               = "INFO"
    ENABLE_OAUTH_ROLE_MANAGEMENT   = "true"
    OAUTH_ROLES_CLAIM              = "roles"
    OAUTH_ALLOWED_ROLES            = "user,admin"
    OAUTH_ADMIN_ROLES              = "admin"
    ENABLE_OAUTH_GROUP_MANAGEMENT  = "true"
    ENABLE_OAUTH_GROUP_CREATION    = "true"
    OAUTH_GROUPS_CLAIM             = "groups"
    AIOHTTP_CLIENT_TIMEOUT         = "300"
  }
}

resource "azurerm_container_app_environment" "app" {
  name                                        = local.names.container_apps_environment
  location                                    = azurerm_resource_group.app.location
  resource_group_name                         = azurerm_resource_group.app.name
  infrastructure_subnet_id                    = azurerm_subnet.aca.id
  internal_load_balancer_enabled              = true
  public_network_access                       = "Disabled"
  dapr_application_insights_connection_string = azurerm_application_insights.app.connection_string

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.aca,
    azurerm_role_assignment.environment_storage_smb,
  ]
}

resource "azapi_resource" "open_webui_storage" {
  type      = "Microsoft.App/managedEnvironments/storages@2026-03-02-preview"
  name      = azurerm_storage_share.open_webui.name
  parent_id = azurerm_container_app_environment.app.id

  # This preview API is newer than the AzAPI provider's embedded schema.
  schema_validation_enabled = false

  body = {
    properties = {
      azureFile = {
        accountName = azurerm_storage_account.app.name
        shareName   = azurerm_storage_share.open_webui.name
        accessMode  = "ReadWrite"
        identity    = azurerm_user_assigned_identity.environment.id
      }
    }
  }

  depends_on = [azurerm_role_assignment.environment_storage_smb]
}

# The certificate comes from the App Service Certificate (use_app_service_certificate), certificate_pfx_base64,
# or a manual import before applying:
# az keyvault certificate import --vault-name <kv-name> --name <certificate_name> --file file.pfx
resource "azurerm_container_app_environment_certificate" "custom_domain" {
  name                         = local.certificate_name
  container_app_environment_id = azurerm_container_app_environment.app.id

  certificate_key_vault {
    identity            = azurerm_user_assigned_identity.environment.id
    key_vault_secret_id = "${azurerm_key_vault.app.vault_uri}secrets/${local.certificate_name}"
  }

  depends_on = [
    azapi_resource.certificate_secret,
    data.azapi_resource.certificate_issued,
    azurerm_role_assignment.environment_key_vault,
  ]
}

resource "azurerm_container_app" "open_webui" {
  name                         = local.names.container_app
  container_app_environment_id = azurerm_container_app_environment.app.id
  resource_group_name          = azurerm_resource_group.app.name
  revision_mode                = "Single"

  # The user-assigned identity already holds Key Vault Secrets User before the app is created,
  # so the first revision can resolve the database secret.
  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  secret {
    name                = "database-url"
    identity            = azurerm_user_assigned_identity.environment.id
    key_vault_secret_id = "${azurerm_key_vault.app.vault_uri}secrets/postgres-connection-string"
  }

  secret {
    name                = "webui-secret-key"
    identity            = azurerm_user_assigned_identity.environment.id
    key_vault_secret_id = "${azurerm_key_vault.app.vault_uri}secrets/webui-secret-key"
  }

  ingress {
    external_enabled           = true
    target_port                = 8080
    allow_insecure_connections = false
    session_affinity_enabled   = true

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }

    dynamic "ip_security_restriction" {
      for_each = var.container_app_allowed_ip_addresses

      content {
        name             = "allow-${replace(ip_security_restriction.value, "/", "-")}"
        ip_address_range = ip_security_restriction.value
        action           = "Allow"
      }
    }
  }

  template {
    min_replicas = var.container_app_scale_settings.min_replicas
    max_replicas = var.container_app_scale_settings.max_replicas

    container {
      name   = local.names.container
      image  = var.open_webui_image
      cpu    = 0.5
      memory = "1Gi"

      dynamic "env" {
        for_each = local.open_webui_env

        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }

      env {
        name        = "WEBUI_SECRET_KEY"
        secret_name = "webui-secret-key"
      }

      volume_mounts {
        name = azapi_resource.open_webui_storage.name
        path = "/app/backend/data"
      }
    }

    volume {
      name          = azapi_resource.open_webui_storage.name
      storage_name  = azapi_resource.open_webui_storage.name
      storage_type  = "AzureFile"
      mount_options = "nobrl,noperm,mfsymlinks,cache=strict"
    }
  }

  depends_on = [
    azurerm_role_assignment.environment_key_vault,
    azapi_resource.postgres_connection_string_secret,
    azapi_resource.webui_secret_key,
    azurerm_postgresql_flexible_server_database.open_webui,
  ]
}

# Requires the asuid TXT and CNAME/A DNS records for the custom domain to validate.
resource "azurerm_container_app_custom_domain" "open_webui" {
  name                                     = var.custom_domain
  container_app_id                         = azurerm_container_app.open_webui.id
  container_app_environment_certificate_id = azurerm_container_app_environment_certificate.custom_domain.id
  certificate_binding_type                 = "SniEnabled"
}
