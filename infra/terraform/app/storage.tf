resource "azurerm_storage_account" "app" {
  name                            = local.names.storage_account
  location                        = azurerm_resource_group.app.location
  resource_group_name             = azurerm_resource_group.app.name
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false
  smb_oauth_enabled               = true
  allow_nested_items_to_be_public = false

  identity {
    type = "SystemAssigned"
  }

  share_properties {
    retention_policy {
      days = 7
    }

    smb {
      authentication_types = ["Kerberos"]
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.aca.id]
  }
}

resource "azurerm_storage_share" "open_webui" {
  name               = local.names.storage_share
  storage_account_id = azurerm_storage_account.app.id
  quota              = 100
  enabled_protocol   = "SMB"
  access_tier        = "TransactionOptimized"
}
