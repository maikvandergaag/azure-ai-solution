locals {
  # Foundry returns a cognitiveservices.azure.com endpoint; APIM should call the unified services.ai.azure.com endpoint.
  foundry_ai_endpoint = replace(azurerm_cognitive_account.foundry.endpoint, ".cognitiveservices.azure.com", ".services.ai.azure.com")

  # Split "<tier>_<capacity>" (for example Developer_1) for the ARM sku object.
  apim_sku_parts    = regex("^(.+)_([0-9]+)$", var.apim_sku_name)
  apim_sku_tier     = local.apim_sku_parts[0]
  apim_sku_capacity = tonumber(local.apim_sku_parts[1])
}

# Managed with azapi instead of azurerm_api_management: the azurerm resource reads tenant access
# secrets through the retired direct management API, which Azure permanently disables on new
# instances, failing every refresh (hashicorp/terraform-provider-azurerm#33800).
resource "azapi_resource" "apim" {
  type      = "Microsoft.ApiManagement/service@2024-05-01"
  name      = local.hub_names.api_management
  parent_id = azurerm_resource_group.hub.id
  location  = azurerm_resource_group.hub.location

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name     = local.apim_sku_tier
      capacity = local.apim_sku_capacity
    }
    properties = {
      publisherEmail     = var.apim_publisher_email
      publisherName      = var.apim_publisher_name
      virtualNetworkType = "Internal"
      publicIpAddressId  = azurerm_public_ip.apim.id
      virtualNetworkConfiguration = {
        subnetResourceId = azurerm_subnet.apim.id
      }
    }
  }

  response_export_values = [
    "properties.gatewayUrl",
    "properties.privateIPAddresses",
  ]

  timeouts {
    create = "3h"
    update = "3h"
    delete = "4h"
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.apim,
    azurerm_subnet_route_table_association.apim,
  ]
}

resource "azurerm_monitor_diagnostic_setting" "apim" {
  name                           = local.hub_names.diagnostic_setting_apim
  target_resource_id             = azapi_resource.apim.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.hub.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "GatewayLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_role_assignment" "apim_metrics_publisher" {
  scope                = azurerm_application_insights.hub.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azapi_resource.apim.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Application Insights has local auth disabled, so APIM ingests telemetry with its system-assigned identity.
resource "azurerm_api_management_logger" "app_insights" {
  name                = azurerm_application_insights.hub.name
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.hub.name
  resource_id         = azurerm_application_insights.hub.id
  description         = "Logger for Application Insights"

  application_insights {
    connection_string  = azurerm_application_insights.hub.connection_string
    identity_client_id = "SystemAssigned"
  }

  depends_on = [azurerm_role_assignment.apim_metrics_publisher]
}

resource "azurerm_api_management_named_value" "tenant_id" {
  name                = "tenant-id"
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.hub.name
  display_name        = "tenant-id"
  value               = data.azurerm_client_config.current.tenant_id
}

resource "azurerm_api_management_named_value" "openwebui_app_id" {
  name                = "openwebui-app-id"
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.hub.name
  display_name        = "openwebui-app-id"
  value               = azuread_application.open_webui.client_id
}

# Gateway key enforced by the API policy: as the api-key header for interactive calls and as a
# bearer token for server-side image/embedding calls.
resource "azurerm_api_management_named_value" "openwebui_gateway_key" {
  name                = "openwebui-gateway-key"
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.hub.name
  display_name        = "openwebui-gateway-key"
  secret              = true
  value               = azurerm_api_management_subscription.open_webui.primary_key
}

resource "azurerm_api_management_backend" "foundry" {
  name                = "foundry-backend"
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.hub.name
  protocol            = "http"
  url                 = "${local.foundry_ai_endpoint}openai/v1"

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}

resource "azurerm_api_management_product" "platform_services" {
  product_id            = "platform-services"
  api_management_name   = azapi_resource.apim.name
  resource_group_name   = azurerm_resource_group.hub.name
  display_name          = "Platform Services"
  description           = "AI and ML services managed by Platform Engineering team"
  subscription_required = true
  approval_required     = false
  published             = true
}

# Operations are imported separately from infra/terraform/assets/openai.openapi.json (see README).
# Subscription enforcement happens in the policy (check-header on the gateway key named value), because
# server-side Open WebUI engines (images, embeddings) can only send the key as a bearer token.
resource "azurerm_api_management_api" "openai" {
  name                  = "openai"
  api_management_name   = azapi_resource.apim.name
  resource_group_name   = azurerm_resource_group.hub.name
  revision              = "1"
  display_name          = "Azure OpenAI v1 API"
  path                  = "openai/v1"
  api_type              = "http"
  protocols             = ["https"]
  subscription_required = false

  subscription_key_parameter_names {
    header = "api-key"
    query  = "subscription-key"
  }

  lifecycle {
    ignore_changes = [description, service_url, contact, license]
  }
}

resource "azurerm_api_management_api_policy" "openai" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.hub.name
  xml_content         = file("${path.module}/../assets/openai-api.xml")

  depends_on = [
    azurerm_api_management_named_value.tenant_id,
    azurerm_api_management_named_value.openwebui_app_id,
    azurerm_api_management_named_value.openwebui_gateway_key,
    azurerm_api_management_backend.foundry,
  ]
}

resource "azurerm_api_management_product_api" "openai" {
  product_id          = azurerm_api_management_product.platform_services.product_id
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.hub.name
}

# azurerm does not expose large language model logging on API diagnostics yet.
resource "azapi_resource" "openai_diagnostic" {
  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview"
  name      = "applicationinsights"
  parent_id = "${azapi_resource.apim.id}/apis/${azurerm_api_management_api.openai.name}"

  body = {
    properties = {
      alwaysLog               = "allErrors"
      logClientIp             = true
      httpCorrelationProtocol = "W3C"
      verbosity               = "information"
      loggerId                = azurerm_api_management_logger.app_insights.id
      metrics                 = true
      sampling = {
        samplingType = "fixed"
        percentage   = 100
      }
      largeLanguageModel = {
        logs = "disabled"
      }
    }
  }
}

resource "azurerm_role_assignment" "apim_foundry_cognitive_services_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azapi_resource.apim.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Subscription used by Open WebUI; configure its primary key as the api-key header in the
# Open WebUI OpenAI connection (see the deployment checklist in infra/terraform/README.md).
resource "azurerm_api_management_subscription" "open_webui" {
  subscription_id     = "open-webui"
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.hub.name
  product_id          = azurerm_api_management_product.platform_services.id
  display_name        = "Open WebUI"
  state               = "active"
  allow_tracing       = false
}
