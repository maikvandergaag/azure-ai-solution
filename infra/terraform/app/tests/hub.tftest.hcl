mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "azapi" {}

override_data {
  target = data.azurerm_client_config.current
  values = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    tenant_id       = "00000000-0000-0000-0000-000000000001"
    object_id       = "00000000-0000-0000-0000-000000000002"
  }
}

override_resource {
  target          = azurerm_key_vault.app
  override_during = plan
  values = {
    id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-owui-test-uks-01/providers/Microsoft.KeyVault/vaults/kv-owui-test-uks-01-4ee0"
    vault_uri = "https://kv-owui-test-uks-01-4ee0.vault.azure.net/"
  }
}

override_resource {
  target          = azurerm_virtual_network.app
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-owui-test-uks-01/providers/Microsoft.Network/virtualNetworks/vnet-owui-test-uks-01"
  }
}

override_resource {
  target          = azurerm_cognitive_account.foundry
  override_during = plan
  values = {
    id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-owui-test-uks-01/providers/Microsoft.CognitiveServices/accounts/aif-owui-test-uks-01"
    endpoint = "https://aif-owui-test-uks-01-4ee0.cognitiveservices.azure.com/"
  }
}

override_resource {
  target          = azuread_application.open_webui
  override_during = plan
  values = {
    client_id = "00000000-0000-0000-0000-000000000005"
  }
}

variables {
  subscription_id                    = "00000000-0000-0000-0000-000000000000"
  location                           = "uksouth"
  workload                           = "owui"
  hub_workload                       = "owui-hub"
  environment                        = "test"
  apim_publisher_email               = "test@example.com"
  apim_publisher_name                = "Test"
  hub_virtual_network_address_prefix = "10.0.0.0/24"
  apim_subnet_address_prefix         = "10.0.0.0/28"
  app_gateway_subnet_address_prefix  = "10.0.0.64/26"
  pe_subnet_address_prefix           = "10.0.0.128/28"
  virtual_network_address_prefix     = "10.0.4.0/22"
  aca_subnet_address_prefix          = "10.0.4.0/23"
  custom_domain                      = "openwebui.example.com"
  postgres_admin_password            = "test-password"
  webui_secret_key                   = "test-webui-secret-key-at-least-32-characters"
  tags = {
    purpose     = "Open WebUI test"
    environment = "dev"
    owner       = "Terraform test"
  }
}

run "shared_assets_are_wired" {
  command = plan

  plan_options {
    target = [
      azurerm_network_security_group.apim,
      azurerm_application_gateway.this,
      azurerm_api_management_api_policy.openai,
      azurerm_monitor_diagnostic_setting.apim,
    ]
  }

  assert {
    condition = (
      toset([for rule in azurerm_network_security_group.apim.security_rule : rule.name]) ==
      toset([for rule in jsondecode(file("${path.module}/../assets/nsg-rules.json")) : rule.name]) &&
      contains([for rule in azurerm_network_security_group.apim.security_rule : rule.name], "Allow-Inbound-ApiManagement")
    )
    error_message = "The APIM NSG must load the shared security rules."
  }

  assert {
    condition     = length(azurerm_application_gateway.this.trusted_root_certificate) == 0
    error_message = "Application Gateway must rely on publicly trusted CAs, not a custom trusted root."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.apim.name == "diag-apim-owui-hub-test-uks-01"
    error_message = "The APIM diagnostic setting must use the generated hub name."
  }

  assert {
    condition = (
      azurerm_api_management_api_policy.openai.xml_content == file("${path.module}/../assets/openai-api.xml") &&
      strcontains(azurerm_api_management_api_policy.openai.xml_content, "validate-azure-ad-token") &&
      strcontains(azurerm_api_management_api_policy.openai.xml_content, "foundry-backend")
    )
    error_message = "The APIM API must use the shared policy with token validation and the Foundry backend."
  }

  assert {
    condition = (
      length(azurerm_network_security_group.apim.security_rule) > 0 &&
      jsondecode(file("${path.module}/../assets/openai.openapi.json")).openapi == "3.0.1" &&
      contains(keys(jsondecode(file("${path.module}/../assets/openai.openapi.json")).paths), "/chat/completions")
    )
    error_message = "The shared OpenAPI definition must be available for the API import."
  }
}

run "names_follow_convention" {
  command = plan

  plan_options {
    target = [
      azurerm_application_gateway.this,
      azapi_resource.apim,
      azurerm_virtual_network_peering.hub_to_spoke,
      azurerm_subnet.private_endpoints,
      azurerm_api_management_backend.foundry,
      azurerm_api_management_named_value.openwebui_app_id,
    ]
  }

  assert {
    condition = (
      azurerm_resource_group.hub.name == "rg-owui-hub-test-uks-01" &&
      azurerm_virtual_network.hub.name == "vnet-owui-hub-test-uks-01" &&
      one(azurerm_virtual_network.hub.address_space) == var.hub_virtual_network_address_prefix &&
      azurerm_subnet.private_endpoints.name == "snet-pep-owui-hub-test-uks-01" &&
      azurerm_application_gateway.this.name == "agw-owui-hub-test-uks-01" &&
      can(regex("^apim-owui-hub-test-uks-01-[0-9a-f]{4}$", azapi_resource.apim.name)) &&
      azurerm_public_ip.apim.domain_name_label == azapi_resource.apim.name
    )
    error_message = "Hub resources must be named <type>-<workload>-<environment>-<region>-<instance>."
  }

  assert {
    condition = (
      azurerm_virtual_network_peering.hub_to_spoke.remote_virtual_network_id == azurerm_virtual_network.app.id &&
      azurerm_cognitive_account.foundry.name == "aif-owui-test-uks-01" &&
      azurerm_api_management_backend.foundry.url == "https://aif-owui-test-uks-01-4ee0.services.ai.azure.com/openai/v1" &&
      azurerm_api_management_named_value.openwebui_app_id.value == azuread_application.open_webui.client_id &&
      azurerm_key_vault.app.name == "kv-owui-test-uks-01-4ee0" &&
      local.appgw_ssl_certificate_secret == "https://kv-owui-test-uks-01-4ee0.vault.azure.net/secrets/cert-owui-test-uks-01" &&
      one(azurerm_application_gateway.this.ssl_certificate).name == "cert-owui-test-uks-01" &&
      one(azurerm_application_gateway.this.ssl_certificate).key_vault_secret_id == local.appgw_ssl_certificate_secret &&
      can(regex("^stowuitestuks01[0-9a-f]{4}$", local.names.storage_account))
    )
    error_message = "The hub must wire directly to the generated app resources."
  }
}

run "honors_certificate_name_override" {
  command = plan

  variables {
    certificate_name = "existing-tls-cert"
  }

  plan_options {
    target = [azurerm_application_gateway.this]
  }

  assert {
    condition = (
      one(azurerm_application_gateway.this.ssl_certificate).name == "existing-tls-cert" &&
      one(azurerm_application_gateway.this.ssl_certificate).key_vault_secret_id ==
      "https://kv-owui-test-uks-01-4ee0.vault.azure.net/secrets/existing-tls-cert"
    )
    error_message = "The Application Gateway must use the explicitly configured certificate secret."
  }
}

run "hub_region_can_differ" {
  command = plan

  variables {
    hub_location       = "norwayeast"
    hub_location_short = "nor2"
  }

  plan_options {
    target = [
      azurerm_subnet.private_endpoints,
      azurerm_resource_group.app,
    ]
  }

  assert {
    condition = (
      azurerm_resource_group.hub.name == "rg-owui-hub-test-nor2-01" &&
      azurerm_resource_group.hub.location == "norwayeast" &&
      azurerm_subnet.private_endpoints.name == "snet-pep-owui-hub-test-nor2-01" &&
      azurerm_resource_group.app.name == "rg-owui-test-uks-01"
    )
    error_message = "Hub resources must use the hub region and abbreviation."
  }
}
