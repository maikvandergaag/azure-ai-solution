# Optional App Service Certificate: Azure buys a publicly trusted certificate (issued by GoDaddy), stores it
# in the spoke Key Vault as local.certificate_name and renews it. The Container Apps environment and
# the hub Application Gateway both read that versionless secret, so renewals roll out automatically.
locals {
  # Application (client) ID of the Microsoft.Azure.CertificateRegistration resource provider.
  certificate_registration_client_id = "f3c21649-0979-4721-ac85-b0216b2cf413"

  has_public_dns_zone = var.public_dns_zone_name != ""
}

data "azuread_service_principal" "certificate_registration" {
  count = var.use_app_service_certificate ? 1 : 0

  client_id = local.certificate_registration_client_id
}

resource "azurerm_role_assignment" "certificate_registration_key_vault" {
  count = var.use_app_service_certificate ? 1 : 0

  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_service_principal.certificate_registration[0].object_id
  principal_type       = "ServicePrincipal"
}

# Creating this resource purchases the certificate and charges the subscription.
resource "azapi_resource" "certificate_order" {
  count = var.use_app_service_certificate ? 1 : 0

  type      = "Microsoft.CertificateRegistration/certificateOrders@2024-11-01"
  name      = local.names.certificate_order
  parent_id = azurerm_resource_group.app.id
  location  = "global"
  tags      = var.tags

  body = {
    properties = {
      productType       = var.app_service_certificate_product_type
      distinguishedName = "CN=${var.custom_domain}"
      autoRenew         = var.app_service_certificate_auto_renew
      validityInYears   = 1
      keySize           = 2048
    }
  }

  response_export_values = ["properties.domainVerificationToken", "properties.status"]

  lifecycle {
    precondition {
      condition     = !local.has_certificate
      error_message = "Leave certificate_pfx_base64 empty when use_app_service_certificate is true."
    }
  }
}

resource "azapi_resource" "certificate_order_key_vault" {
  count = var.use_app_service_certificate ? 1 : 0

  type      = "Microsoft.CertificateRegistration/certificateOrders/certificates@2024-11-01"
  name      = local.certificate_name
  parent_id = azapi_resource.certificate_order[0].id
  location  = "global"

  body = {
    properties = {
      keyVaultId         = azurerm_key_vault.app.id
      keyVaultSecretName = local.certificate_name
    }
  }

  # The new role assignment can take a few minutes to propagate.
  retry = {
    error_message_regex = ["AzureServiceUnauthorizedToAccessKeyVault", "Forbidden", "Unauthorized"]
  }

  depends_on = [azurerm_role_assignment.certificate_registration_key_vault]
}

# Domain ownership: a TXT record "@" with the verification token at the root domain. Created here when the
# root domain is an Azure DNS public zone; otherwise add it at your DNS provider while the apply waits.
resource "azurerm_dns_txt_record" "certificate_verification" {
  count = var.use_app_service_certificate && local.has_public_dns_zone ? 1 : 0

  name                = "@"
  zone_name           = var.public_dns_zone_name
  resource_group_name = var.public_dns_zone_resource_group_name
  ttl                 = 3600

  record {
    value = azapi_resource.certificate_order[0].output.properties.domainVerificationToken
  }
}

# Binding the order to Key Vault creates an empty placeholder secret immediately, so the secret's existence
# does not prove issuance. Trigger domain verification while the order is pending (with external DNS, add
# the TXT record while this polls) and wait until the issued certificate is stored in Key Vault, otherwise
# the Container Apps environment certificate and Application Gateway read empty certificate data.
resource "terraform_data" "certificate_issued_wait" {
  count = var.use_app_service_certificate ? 1 : 0

  triggers_replace = [azapi_resource.certificate_order_key_vault[0].id]

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      for i in $(seq 1 120); do
        content_type=$(az rest --method GET --url "https://management.azure.com${azurerm_key_vault.app.id}/secrets/${local.certificate_name}?api-version=2023-07-01" --query properties.contentType -o tsv 2>/dev/null || true)
        if [ "$content_type" = "application/x-pkcs12" ]; then
          echo "App Service Certificate issued and stored in Key Vault."
          exit 0
        fi
        order_status=$(az resource show --ids "${azapi_resource.certificate_order[0].id}" --query properties.status -o tsv 2>/dev/null || true)
        if [ "$order_status" = "Pendingissuance" ]; then
          az rest --method POST --url "https://management.azure.com${azapi_resource.certificate_order[0].id}/verifyDomainOwnership?api-version=2024-11-01" >/dev/null 2>&1 || true
        fi
        echo "Waiting for the App Service Certificate (order: $${order_status:-unknown}, secret content type: $${content_type:-none})..."
        sleep 30
      done
      echo "Timed out waiting for the App Service Certificate to be issued. Verify the domain-verification TXT record and re-run the apply." >&2
      exit 1
    EOT
  }

  depends_on = [azurerm_dns_txt_record.certificate_verification]
}

# Waits until the issued certificate has been written to Key Vault before the environment certificate uses it.
data "azapi_resource" "certificate_issued" {
  count = var.use_app_service_certificate ? 1 : 0

  type      = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  name      = local.certificate_name
  parent_id = azurerm_key_vault.app.id

  retry = {
    error_message_regex  = ["NotFound"]
    interval_seconds     = 30
    max_interval_seconds = 120
  }

  timeouts {
    read = "60m"
  }

  depends_on = [
    azapi_resource.certificate_order_key_vault,
    terraform_data.certificate_issued_wait,
  ]
}
