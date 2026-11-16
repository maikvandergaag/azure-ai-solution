locals {
  appgw_frontend_ip_name       = "appgw-frontend-ip"
  appgw_backend_pool_name      = "containerapp-backend-pool"
  appgw_backend_settings_name  = "containerapp-backend-settings"
  appgw_probe_name             = "containerapp-health-probe"
  appgw_http_listener_name     = "containerapp-http-listener"
  appgw_https_listener_name    = "containerapp-https-listener"
  appgw_redirect_name          = "http-to-https-redirect"
  appgw_ssl_certificate_secret = "${azurerm_key_vault.app.vault_uri}secrets/${local.certificate_name}"
}

resource "azurerm_application_gateway" "this" {
  name                = local.hub_names.application_gateway
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  sku {
    name     = var.app_gateway_sku
    tier     = var.app_gateway_sku
    capacity = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app_gateway.id]
  }

  ssl_certificate {
    name                = local.certificate_name
    key_vault_secret_id = local.appgw_ssl_certificate_secret
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.app_gateway.id
  }

  frontend_ip_configuration {
    name                 = local.appgw_frontend_ip_name
    public_ip_address_id = azurerm_public_ip.app_gateway.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  backend_address_pool {
    name  = local.appgw_backend_pool_name
    fqdns = [azurerm_container_app.open_webui.ingress[0].fqdn]
  }

  backend_http_settings {
    name                                = local.appgw_backend_settings_name
    port                                = 443
    protocol                            = "Https"
    cookie_based_affinity               = "Enabled"
    pick_host_name_from_backend_address = false
    host_name                           = var.custom_domain
    # Tolerate slower cold starts and long-running requests (default is 30s).
    # No trusted_root_certificate: Application Gateway v2 validates the backend against well-known public CAs,
    # so the custom-domain certificate on the Container App must be issued by a publicly trusted CA.
    request_timeout = 120
    probe_name      = local.appgw_probe_name
  }

  probe {
    name     = local.appgw_probe_name
    protocol = "Https"
    path     = "/api/version"
    # timeout must be less than interval; keep a generous timeout for slow cold starts.
    interval                                  = 90
    timeout                                   = 60
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    minimum_servers                           = 0

    match {
      status_code = ["200-399"]
    }
  }

  http_listener {
    name                           = local.appgw_http_listener_name
    frontend_ip_configuration_name = local.appgw_frontend_ip_name
    frontend_port_name             = "port-80"
    protocol                       = "Http"
    host_name                      = var.custom_domain
  }

  http_listener {
    name                           = local.appgw_https_listener_name
    frontend_ip_configuration_name = local.appgw_frontend_ip_name
    frontend_port_name             = "port-443"
    protocol                       = "Https"
    host_name                      = var.custom_domain
    ssl_certificate_name           = local.certificate_name
  }

  redirect_configuration {
    name                 = local.appgw_redirect_name
    redirect_type        = "Permanent"
    target_listener_name = local.appgw_https_listener_name
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name                        = "containerapp-routing-rule"
    rule_type                   = "Basic"
    priority                    = 100
    http_listener_name          = local.appgw_http_listener_name
    redirect_configuration_name = local.appgw_redirect_name
  }

  request_routing_rule {
    name                       = "containerapp-https-routing-rule"
    rule_type                  = "Basic"
    priority                   = 101
    http_listener_name         = local.appgw_https_listener_name
    backend_address_pool_name  = local.appgw_backend_pool_name
    backend_http_settings_name = local.appgw_backend_settings_name
  }

  # The TLS certificate must be in Key Vault before the HTTPS listener can read it.
  depends_on = [
    azurerm_role_assignment.app_gateway_key_vault,
    azapi_resource.certificate_secret,
    data.azapi_resource.certificate_issued,
  ]
}
