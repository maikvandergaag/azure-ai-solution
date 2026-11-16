variables {
  workload        = "owui"
  environment     = "demo"
  location        = "uksouth"
  instance        = "01"
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "follows_convention" {
  command = plan

  assert {
    condition = (
      output.base == "owui-demo-uks-01" &&
      output.names.resource_group == "rg-owui-demo-uks-01" &&
      output.names.container_app == "ca-owui-demo-uks-01" &&
      output.names.container == "ctr-owui-demo-uks-01" &&
      output.names.diagnostic_setting_apim == "diag-apim-owui-demo-uks-01" &&
      output.names.key_vault == "kv-owui-demo-uks-01-${output.unique_suffix}" &&
      output.names.storage_account == "stowuidemouks01${output.unique_suffix}" &&
      output.names.storage_share == "share-owui-demo-uks-01" &&
      output.names.certificate_secret == "cert-owui-demo-uks-01" &&
      can(regex("^[0-9a-f]{4}$", output.unique_suffix))
    )
    error_message = "Names must follow <type>-<workload>-<environment>-<region>-<instance>."
  }
}

run "long_inputs_fit_limits" {
  command = plan

  variables {
    workload       = "openwebui1"
    environment    = "staging"
    location       = "germanywestcentral"
    location_short = "gwcntr"
    instance       = "001"
  }

  assert {
    condition = (
      length(output.names.key_vault) <= 24 &&
      !strcontains(output.names.key_vault, "--") &&
      length(output.names.storage_account) <= 24 &&
      can(regex("^[a-z0-9]+$", output.names.storage_account)) &&
      length(output.names.storage_share) <= 63 &&
      can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", output.names.storage_share)) &&
      length(output.names.container_app) <= 32 &&
      length(output.names.api_management) <= 50 &&
      length(output.names.postgresql_server) <= 63 &&
      can(regex("^[a-z0-9]+$", output.names.certificate_order))
    )
    error_message = "Generated names must respect the Azure naming rules."
  }
}

run "rejects_invalid_workload" {
  command = plan

  variables {
    workload = "Open_WebUI"
  }

  expect_failures = [var.workload]
}

run "rejects_unknown_region_without_abbreviation" {
  command = plan

  variables {
    location = "unknownregion"
  }

  expect_failures = [var.location]
}

run "accepts_unknown_region_with_abbreviation" {
  command = plan

  variables {
    location       = "unknownregion"
    location_short = "custom"
  }

  assert {
    condition     = output.base == "owui-demo-custom-01"
    error_message = "An explicit abbreviation must be used for regions outside the built-in list."
  }
}
