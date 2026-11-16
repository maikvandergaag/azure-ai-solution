mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "azapi" {}

override_data {
  target = data.azurerm_client_config.current
  values = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    object_id       = "00000000-0000-0000-0000-000000000002"
    tenant_id       = "00000000-0000-0000-0000-000000000003"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.environment
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-owui-test-uks-01/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-owui-test-uks-01"
    principal_id = "00000000-0000-0000-0000-000000000001"
  }
}

override_resource {
  target          = azurerm_storage_account.app
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-owui-test-uks-01/providers/Microsoft.Storage/storageAccounts/stowuitestuks014ee0"
  }
}

override_resource {
  target          = azurerm_container_app_environment.app
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-owui-test-uks-01/providers/Microsoft.App/managedEnvironments/cae-owui-test-uks-01"
  }
}

variables {
  subscription_id                    = "00000000-0000-0000-0000-000000000000"
  location                           = "uksouth"
  workload                           = "owui"
  environment                        = "test"
  virtual_network_address_prefix     = "10.0.4.0/22"
  aca_subnet_address_prefix          = "10.0.4.0/23"
  apim_publisher_email               = "test@example.com"
  apim_publisher_name                = "Test"
  hub_virtual_network_address_prefix = "10.0.0.0/24"
  apim_subnet_address_prefix         = "10.0.0.0/28"
  app_gateway_subnet_address_prefix  = "10.0.0.64/26"
  pe_subnet_address_prefix           = "10.0.0.128/28"
  hub_workload                       = "owui-hub"
  custom_domain                      = "openwebui.example.com"
  postgres_admin_password            = "test-password"
  webui_secret_key                   = "test-webui-secret-key-at-least-32-characters"
  tags = {
    purpose     = "Open WebUI test"
    environment = "dev"
    owner       = "Terraform test"
  }
}

run "managed_identity_smb_mount" {
  command = plan

  plan_options {
    target = [azurerm_container_app.open_webui]
  }

  assert {
    condition = (
      azurerm_storage_share.open_webui.name == "share-owui-test-uks-01" &&
      azapi_resource.open_webui_storage.name == azurerm_storage_share.open_webui.name &&
      azapi_resource.open_webui_storage.type == "Microsoft.App/managedEnvironments/storages@2026-03-02-preview" &&
      azapi_resource.open_webui_storage.parent_id == azurerm_container_app_environment.app.id &&
      azapi_resource.open_webui_storage.body.properties.azureFile.accountName == azurerm_storage_account.app.name &&
      azapi_resource.open_webui_storage.body.properties.azureFile.shareName == azurerm_storage_share.open_webui.name &&
      azapi_resource.open_webui_storage.body.properties.azureFile.accessMode == "ReadWrite" &&
      azapi_resource.open_webui_storage.body.properties.azureFile.identity == azurerm_user_assigned_identity.environment.id &&
      toset(keys(azapi_resource.open_webui_storage.body.properties.azureFile)) == toset(["accountName", "shareName", "accessMode", "identity"])
    )
    error_message = "The Azure Files mount must use the environment identity and must not contain account-key credentials."
  }

  assert {
    condition = (
      azurerm_storage_account.app.smb_oauth_enabled &&
      !azurerm_storage_account.app.shared_access_key_enabled &&
      toset(azurerm_storage_account.app.share_properties[0].smb[0].authentication_types) == toset(["Kerberos"]) &&
      azurerm_storage_share.open_webui.storage_account_id == azurerm_storage_account.app.id
    )
    error_message = "The storage account must use SMB OAuth and Kerberos without Shared Key access, and manage the share through Azure Resource Manager."
  }

  assert {
    condition = (
      contains(azurerm_container_app_environment.app.identity[0].identity_ids, azurerm_user_assigned_identity.environment.id) &&
      azurerm_role_assignment.environment_storage_smb.scope == azurerm_storage_account.app.id &&
      azurerm_role_assignment.environment_storage_smb.principal_id == azurerm_user_assigned_identity.environment.principal_id &&
      azurerm_role_assignment.environment_storage_smb.role_definition_name == "Storage File Data SMB MI Admin"
    )
    error_message = "The environment identity must have the SMB managed-identity role on the storage account."
  }

  assert {
    condition = (
      azurerm_container_app.open_webui.template[0].container[0].name == "ctr-owui-test-uks-01" &&
      azurerm_container_app.open_webui.template[0].container[0].volume_mounts[0].name == azurerm_container_app.open_webui.template[0].volume[0].name &&
      azurerm_container_app.open_webui.template[0].volume[0].name == azapi_resource.open_webui_storage.name &&
      azurerm_container_app.open_webui.template[0].volume[0].storage_name == azapi_resource.open_webui_storage.name &&
      azurerm_container_app.open_webui.template[0].volume[0].storage_type == "AzureFile" &&
      azurerm_container_app.open_webui.template[0].container[0].volume_mounts[0].path == "/app/backend/data"
    )
    error_message = "Open WebUI must mount the managed-identity Azure Files storage at its data directory."
  }

  assert {
    condition = (
      azurerm_resource_group.app.name == "rg-owui-test-uks-01" &&
      azurerm_storage_account.app.name == "stowuitestuks014ee0" &&
      endswith(azurerm_storage_account.app.id, "/storageAccounts/${azurerm_storage_account.app.name}") &&
      endswith(azurerm_user_assigned_identity.environment.id, "/userAssignedIdentities/${azurerm_user_assigned_identity.environment.name}") &&
      endswith(azurerm_container_app_environment.app.id, "/managedEnvironments/${azurerm_container_app_environment.app.name}")
    )
    error_message = "Mock resource IDs must match the generated resource names."
  }
}

run "hub_names_follow_convention" {
  command = plan

  plan_options {
    target = [
      azurerm_virtual_network.hub,
      azurerm_subnet.private_endpoints,
      azurerm_container_app.open_webui,
    ]
  }

  assert {
    condition = (
      azurerm_virtual_network.hub.name == "vnet-owui-hub-test-uks-01" &&
      azurerm_virtual_network.hub.resource_group_name == "rg-owui-hub-test-uks-01" &&
      azurerm_subnet.private_endpoints.name == "snet-pep-owui-hub-test-uks-01" &&
      azurerm_subnet.private_endpoints.virtual_network_name == azurerm_virtual_network.hub.name &&
      azurerm_subnet.private_endpoints.resource_group_name == azurerm_virtual_network.hub.resource_group_name &&
      local.open_webui_env.OPENAI_API_BASE_URL == "https://apim-owui-hub-test-uks-01-d5bd.azure-api.net/openai/v1"
    )
    error_message = "Hub network, subnet and APIM names must follow the convention."
  }

  assert {
    condition = (
      azuread_application.open_webui.display_name == "app-owui-test-uks-01" &&
      contains(azuread_application.open_webui.identifier_uris, "api://app-owui-test-uks-01") &&
      strcontains(local.open_webui_env.OAUTH_SCOPES, "api://app-owui-test-uks-01/user_impersonation")
    )
    error_message = "The Entra application and Open WebUI scope must use the same generated name."
  }
}

run "same_region_custom_short_matches_hub" {
  command = plan

  variables {
    location_short = "ukso"
    hub_location   = "uksouth"
  }

  plan_options {
    target = [azurerm_subnet.private_endpoints]
  }

  assert {
    condition     = azurerm_subnet.private_endpoints.name == "snet-pep-owui-hub-test-ukso-01"
    error_message = "An explicit hub location in the same region must use the shared abbreviation."
  }
}

run "different_region_custom_short_matches_hub" {
  command = plan

  variables {
    hub_location       = "norwayeast"
    hub_location_short = "nor2"
  }

  plan_options {
    target = [azurerm_subnet.private_endpoints]
  }

  assert {
    condition = (
      azurerm_subnet.private_endpoints.name == "snet-pep-owui-hub-test-nor2-01" &&
      azurerm_subnet.private_endpoints.virtual_network_name == "vnet-owui-hub-test-nor2-01" &&
      azurerm_subnet.private_endpoints.resource_group_name == "rg-owui-hub-test-nor2-01"
    )
    error_message = "Hub resource references must use the hub's custom region abbreviation."
  }
}
