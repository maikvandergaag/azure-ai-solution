output "container_app_fqdn" {
  description = "Container App FQDN, used as the Application Gateway backend."
  value       = azurerm_container_app.open_webui.ingress[0].fqdn
}

output "container_app_id" {
  description = "Container App resource ID."
  value       = azurerm_container_app.open_webui.id
}

output "container_app_env_default_domain" {
  description = "Container Apps environment default domain."
  value       = azurerm_container_app_environment.app.default_domain
}

output "container_app_env_static_ip" {
  description = "Container Apps environment static IP."
  value       = azurerm_container_app_environment.app.static_ip_address
}

output "virtual_network_name" {
  description = "Spoke virtual network name."
  value       = azurerm_virtual_network.app.name
}

output "virtual_network_id" {
  description = "Spoke virtual network resource ID."
  value       = azurerm_virtual_network.app.id
}

output "certificate_domain_verification_token" {
  description = "App Service Certificate verification token. For external DNS, add it as a TXT record named @ at the root domain."
  value       = var.use_app_service_certificate ? azapi_resource.certificate_order[0].output.properties.domainVerificationToken : null
}

output "dns_records" {
  description = "DNS records to create at the external DNS provider. The certificate verification TXT record is named @ at the root domain (for example example.com)."
  value = {
    app_gateway = {
      name  = var.custom_domain
      type  = "A"
      value = azurerm_public_ip.app_gateway.ip_address
    }
    certificate_verification = var.use_app_service_certificate ? {
      name  = "@"
      type  = "TXT"
      value = azapi_resource.certificate_order[0].output.properties.domainVerificationToken
    } : null
    container_app_asuid = {
      name  = "asuid.${var.custom_domain}"
      type  = "TXT"
      value = azurerm_container_app.open_webui.custom_domain_verification_id
    }
  }
  # custom_domain_verification_id is provider-sensitive; read with: terraform output dns_records
  sensitive = true
}

output "certificate_name" {
  description = "Name of the certificate secret in the spoke Key Vault."
  value       = local.certificate_name
}

output "key_vault_name" {
  description = "Spoke Key Vault name."
  value       = azurerm_key_vault.app.name
}

output "foundry_endpoint" {
  description = "Foundry endpoint."
  value       = azurerm_cognitive_account.foundry.endpoint
}

output "open_webui_app_id" {
  description = "Open WebUI Entra ID application (client) ID, validated by the APIM token policy."
  value       = azuread_application.open_webui.client_id
}

output "resource_group_name" {
  description = "Spoke resource group name."
  value       = azurerm_resource_group.app.name
}

output "apim_name" {
  description = "API Management service name."
  value       = azapi_resource.apim.name
}

output "apim_id" {
  description = "API Management service resource ID."
  value       = azapi_resource.apim.id
}

output "apim_gateway_url" {
  description = "API Management gateway URL."
  value       = azapi_resource.apim.output.properties.gatewayUrl
}

output "apim_principal_id" {
  description = "Principal ID of the API Management system-assigned identity."
  value       = azapi_resource.apim.identity[0].principal_id
}

output "apim_open_webui_subscription_key" {
  description = "Primary key of the open-webui APIM subscription, used as the api-key header in the Open WebUI OpenAI connection."
  value       = azurerm_api_management_subscription.open_webui.primary_key
  sensitive   = true
}

output "app_insights_connection_string" {
  description = "Hub Application Insights connection string."
  value       = azurerm_application_insights.hub.connection_string
  sensitive   = true
}

output "app_insights_id" {
  description = "Hub Application Insights resource ID."
  value       = azurerm_application_insights.hub.id
}

output "app_gateway_public_ip" {
  description = "Public IP address of the Application Gateway. Point the custom domain DNS record here."
  value       = azurerm_public_ip.app_gateway.ip_address
}

output "apim_public_ip" {
  description = "Public IP address of API Management (management plane)."
  value       = azurerm_public_ip.apim.ip_address
}

output "hub_virtual_network_id" {
  description = "Hub virtual network resource ID."
  value       = azurerm_virtual_network.hub.id
}

output "hub_virtual_network_name" {
  description = "Hub virtual network name."
  value       = azurerm_virtual_network.hub.name
}

output "hub_resource_group_name" {
  description = "Hub resource group name."
  value       = azurerm_resource_group.hub.name
}
