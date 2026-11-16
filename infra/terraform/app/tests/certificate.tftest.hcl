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

override_data {
  target = data.azuread_service_principal.certificate_registration[0]
  values = {
    object_id = "00000000-0000-0000-0000-000000000004"
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
  target          = azapi_resource.certificate_order[0]
  override_during = plan
  values = {
    id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-owui-test-uks-01/providers/Microsoft.CertificateRegistration/certificateOrders/certowuitestuks01"
    output = { properties = { domainVerificationToken = "test-token", status = "Pendingissuance" } }
  }
}

variables {
  subscription_id                     = "00000000-0000-0000-0000-000000000000"
  location                            = "uksouth"
  workload                            = "owui"
  environment                         = "test"
  virtual_network_address_prefix      = "10.0.4.0/22"
  aca_subnet_address_prefix           = "10.0.4.0/23"
  apim_publisher_email                = "test@example.com"
  apim_publisher_name                 = "Test"
  hub_virtual_network_address_prefix  = "10.0.0.0/24"
  apim_subnet_address_prefix          = "10.0.0.0/28"
  app_gateway_subnet_address_prefix   = "10.0.0.64/26"
  pe_subnet_address_prefix            = "10.0.0.128/28"
  hub_workload                        = "owui-hub"
  custom_domain                       = "openwebui.example.com"
  use_app_service_certificate         = true
  public_dns_zone_name                = "example.com"
  public_dns_zone_resource_group_name = "rg-dns"
  postgres_admin_password             = "test-password"
  webui_secret_key                    = "test-webui-secret-key-at-least-32-characters"
  tags = {
    purpose     = "Open WebUI test"
    environment = "dev"
    owner       = "Terraform test"
  }
}

run "app_service_certificate" {
  command = plan

  plan_options {
    target = [
      azurerm_container_app_environment_certificate.custom_domain,
      azurerm_dns_txt_record.certificate_verification,
    ]
  }

  assert {
    condition = (
      azapi_resource.certificate_order[0].name == "certowuitestuks01" &&
      endswith(azapi_resource.certificate_order[0].id, "/certificateOrders/${azapi_resource.certificate_order[0].name}") &&
      azapi_resource.certificate_order[0].body.properties.distinguishedName == "CN=openwebui.example.com" &&
      azapi_resource.certificate_order[0].body.properties.productType == "StandardDomainValidatedSsl" &&
      azapi_resource.certificate_order[0].body.properties.autoRenew &&
      azapi_resource.certificate_order[0].location == "global"
    )
    error_message = "The certificate order must request an auto-renewing standard certificate for the custom domain."
  }

  assert {
    condition = (
      azurerm_key_vault.app.name == "kv-owui-test-uks-01-4ee0" &&
      endswith(azurerm_key_vault.app.id, "/vaults/${azurerm_key_vault.app.name}") &&
      azapi_resource.certificate_order_key_vault[0].body.properties.keyVaultId == azurerm_key_vault.app.id &&
      azapi_resource.certificate_order_key_vault[0].body.properties.keyVaultSecretName == "cert-owui-test-uks-01" &&
      azurerm_role_assignment.certificate_registration_key_vault[0].role_definition_name == "Key Vault Secrets Officer" &&
      azurerm_role_assignment.certificate_registration_key_vault[0].principal_id == "00000000-0000-0000-0000-000000000004"
    )
    error_message = "The certificate must be stored in the spoke Key Vault by the authorized certificate registration provider."
  }

  assert {
    condition = (
      azurerm_dns_txt_record.certificate_verification[0].name == "@" &&
      azurerm_dns_txt_record.certificate_verification[0].zone_name == "example.com" &&
      one(azurerm_dns_txt_record.certificate_verification[0].record).value == "test-token"
    )
    error_message = "The domain-verification TXT record must contain the order token at the zone root."
  }

  assert {
    condition = (
      azurerm_container_app_environment_certificate.custom_domain.name == "cert-owui-test-uks-01" &&
      azurerm_container_app_environment_certificate.custom_domain.certificate_key_vault[0].key_vault_secret_id ==
      "https://kv-owui-test-uks-01-4ee0.vault.azure.net/secrets/cert-owui-test-uks-01" &&
      length(azapi_resource.certificate_secret) == 0
    )
    error_message = "The Container Apps certificate must use the versionless Key Vault secret written by the certificate order."
  }
}

run "honors_certificate_name_override" {
  command = plan

  variables {
    certificate_name = "existing-tls-cert"
  }

  plan_options {
    target = [azurerm_container_app_environment_certificate.custom_domain]
  }

  assert {
    condition = (
      azurerm_container_app_environment_certificate.custom_domain.name == "existing-tls-cert" &&
      azapi_resource.certificate_order_key_vault[0].body.properties.keyVaultSecretName == "existing-tls-cert" &&
      azurerm_container_app_environment_certificate.custom_domain.certificate_key_vault[0].key_vault_secret_id ==
      "https://kv-owui-test-uks-01-4ee0.vault.azure.net/secrets/existing-tls-cert"
    )
    error_message = "An explicit certificate name must be used consistently by the certificate order and Container Apps."
  }
}

run "supplied_pfx_uses_generated_certificate_name" {
  command = plan

  variables {
    use_app_service_certificate = false
    certificate_pfx_base64      = "dGVzdA=="
  }

  plan_options {
    target = [azurerm_container_app_environment_certificate.custom_domain]
  }

  assert {
    condition = (
      azapi_resource.certificate_secret[0].name == "cert-owui-test-uks-01" &&
      azurerm_container_app_environment_certificate.custom_domain.name == azapi_resource.certificate_secret[0].name &&
      azurerm_container_app_environment_certificate.custom_domain.certificate_key_vault[0].key_vault_secret_id ==
      "https://kv-owui-test-uks-01-4ee0.vault.azure.net/secrets/cert-owui-test-uks-01" &&
      length(azapi_resource.certificate_order) == 0
    )
    error_message = "A supplied PFX must use the generated certificate name without creating an App Service Certificate order."
  }
}

run "rejects_invalid_certificate_name" {
  command = plan

  variables {
    certificate_name = "invalid/name"
  }

  plan_options {
    target = [azapi_resource.certificate_order]
  }

  expect_failures = [var.certificate_name]
}

run "rejects_pfx_with_app_service_certificate" {
  command = plan

  variables {
    certificate_pfx_base64 = "dGVzdA=="
  }

  plan_options {
    target = [azapi_resource.certificate_order]
  }

  expect_failures = [azapi_resource.certificate_order]
}
