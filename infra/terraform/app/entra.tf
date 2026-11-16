resource "azuread_application" "open_webui" {
  display_name                   = local.app_registration_name
  sign_in_audience               = "AzureADMyOrg"
  fallback_public_client_enabled = true
  group_membership_claims        = ["SecurityGroup"]
  identifier_uris                = ["api://${local.app_registration_name}"]
  owners                         = [data.azurerm_client_config.current.object_id]

  app_role {
    allowed_member_types = ["User"]
    description          = "Administrator role with full access to Open WebUI"
    display_name         = "Administrator"
    id                   = uuidv5("url", "api://${local.app_registration_name}/roles/admin")
    enabled              = true
    value                = "admin"
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "Standard user role with default permissions"
    display_name         = "User"
    id                   = uuidv5("url", "api://${local.app_registration_name}/roles/user")
    enabled              = true
    value                = "user"
  }

  optional_claims {
    id_token {
      name      = "groups"
      essential = false
    }

    id_token {
      name      = "ipaddr"
      essential = false
    }

    access_token {
      name      = "groups"
      essential = false
    }

    access_token {
      name      = "ipaddr"
      essential = false
    }
  }

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access Open WebUI on behalf of the signed-in user"
      admin_consent_display_name = "Access Open WebUI"
      id                         = uuidv5("url", "api://${local.app_registration_name}/scopes/user_impersonation")
      enabled                    = true
      type                       = "User"
      user_consent_description   = "Allow the application to access Open WebUI on your behalf"
      user_consent_display_name  = "Access Open WebUI"
      value                      = "user_impersonation"
    }
  }

  # The redirect URI must only be registered as a public client (mobile/desktop): Open WebUI uses the
  # authorization code flow with PKCE and no client secret, which Entra rejects for Web-platform URIs
  # (AADSTS7000218).
  public_client {
    redirect_uris = ["https://${var.custom_domain}/oauth/oidc/callback"]
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read (Delegated)
      type = "Scope"
    }

    resource_access {
      id   = "bc024368-1153-4739-b217-4326f2e966d0" # GroupMember.Read.All (Delegated)
      type = "Scope"
    }

    resource_access {
      id   = "c72d93c1-a342-4d87-90ff-27b3e0e79e0c" # ProfilePhoto.Read.All (Delegated)
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "open_webui" {
  client_id                    = azuread_application.open_webui.client_id
  app_role_assignment_required = true
  owners                       = [data.azurerm_client_config.current.object_id]
}

data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
}

# Tenant-wide admin consent for the delegated Graph permissions used at sign-in.
# The deploying identity needs the DelegatedPermissionGrant.ReadWrite.All Graph permission.
resource "azuread_service_principal_delegated_permission_grant" "open_webui_msgraph" {
  service_principal_object_id          = azuread_service_principal.open_webui.object_id
  resource_service_principal_object_id = data.azuread_service_principal.msgraph.object_id
  claim_values                         = ["openid", "email", "profile", "User.Read", "GroupMember.Read.All", "ProfilePhoto.Read.All"]
}

# Consent for the app's own user_impersonation scope. Without it, Entra drops the scope at sign-in and
# issues a Graph access token, which the APIM validate-azure-ad-token policy cannot validate.
resource "azuread_service_principal_delegated_permission_grant" "open_webui_self" {
  service_principal_object_id          = azuread_service_principal.open_webui.object_id
  resource_service_principal_object_id = azuread_service_principal.open_webui.object_id
  claim_values                         = ["user_impersonation"]
}

# Group-based access: Terraform creates the groups and assigns them the user or admin app role,
# required for sign-in (app_role_assignment_required) and for the roles claim that the APIM policy
# validates. Manage membership in Entra ID; it is not managed here.
resource "azuread_group" "open_webui_users" {
  count = var.open_webui_user_group_name != "" ? 1 : 0

  display_name     = var.open_webui_user_group_name
  description      = "Members get the Open WebUI user app role."
  security_enabled = true
  owners           = [data.azurerm_client_config.current.object_id]
}

resource "azuread_group" "open_webui_admins" {
  count = var.open_webui_admin_group_name != "" ? 1 : 0

  display_name     = var.open_webui_admin_group_name
  description      = "Members get the Open WebUI admin app role."
  security_enabled = true
  owners           = [data.azurerm_client_config.current.object_id]
}

resource "azuread_app_role_assignment" "open_webui_users" {
  count = var.open_webui_user_group_name != "" ? 1 : 0

  app_role_id         = azuread_application.open_webui.app_role_ids["user"]
  principal_object_id = azuread_group.open_webui_users[0].object_id
  resource_object_id  = azuread_service_principal.open_webui.object_id
}

resource "azuread_app_role_assignment" "open_webui_admins" {
  count = var.open_webui_admin_group_name != "" ? 1 : 0

  app_role_id         = azuread_application.open_webui.app_role_ids["admin"]
  principal_object_id = azuread_group.open_webui_admins[0].object_id
  resource_object_id  = azuread_service_principal.open_webui.object_id
}
