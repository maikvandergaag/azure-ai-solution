# Terraform deployment

Terraform deploys the hub and spoke architecture from a single root module, [`app/`](app), with one state file and the native `azurerm`, `azuread` and `azapi` providers. Terraform resolves the ordering between hub and app resources, so one `apply` deploys everything.

| Files | Deploys |
| --- | --- |
| `app/hub_*.tf` | Hub resource group: VNet, NSG/route table, private DNS zones, Log Analytics/App Insights, Application Gateway, internal APIM |
| Other `app/*.tf` | App (spoke) resource group: Entra ID app, spoke VNet + peering, Key Vault, Storage, PostgreSQL, Container Apps, Foundry |

Shared assets are in [`assets/`](assets): the APIM policy and OpenAPI definition, and NSG rules. The [`modules/naming`](modules/naming) module builds resource names as `<type>-<workload>-<environment>-<region>-<instance>`, using `workload` for app resources and `hub_workload` for hub resources; see [Resource naming](../../README.md#resource-naming).

## Prerequisites

- Terraform >= 1.11 (write-only arguments are used for secrets)
- Azure CLI, logged in (`az login`) with Owner (or Contributor + User Access Administrator) on the subscription
- Permission to create Entra ID app registrations
- An Azure Storage account and container for Terraform state, with appropriate Entra ID access
- The same prerequisites as the main [README](../../README.md) (custom domain, certificate, DNS)

The root module declares a partial `azurerm` backend (`backend.tf`). Supply the storage settings at init time, for example:

```bash
terraform -chdir=infra/terraform/app init \
  -backend-config="storage_account_name=<state-account>" \
  -backend-config="container_name=<state-container>" \
  -backend-config="key=openwebui.tfstate" \
  -backend-config="use_azuread_auth=true"
```

The GitHub Actions workflow uses the development state key `ibex-infra-dev.tfstate`.

## Deployment

Review `app/terraform.tfvars`, including `workload`, `hub_workload`, `environment`, `instance` and the address prefixes. Then supply secrets through environment variables and apply from the repository root:

```bash
export TF_VAR_postgres_admin_password='<strong-password>'
export TF_VAR_webui_secret_key='<stable-random-secret>'
terraform -chdir=infra/terraform/app apply
```

Initialize the backend as shown above first. APIM provisioning takes 30-45 minutes.

- `postgres_admin_password` is ephemeral and write-only, so it is never stored in state. Supply it on every plan/apply; increment `postgres_admin_password_version` to rotate it.
- `webui_secret_key` is also ephemeral and write-only. Keep it in a secret manager, supply the same value on every plan/apply, and increment `webui_secret_key_version` only when intentionally rotating it.
- With `use_app_service_certificate = true` (the sample default), Terraform purchases an App Service Certificate, triggers domain verification (with external DNS, add the verification TXT record while the apply retries), and polls with the Azure CLI until the issued certificate is stored in the spoke Key Vault before the Container Apps environment certificate and the Application Gateway HTTPS listener use it. See [TLS certificate](../../README.md#tls-certificate) in the main README.
- Otherwise set `TF_VAR_certificate_pfx_base64`, or import the certificate into the spoke Key Vault under the generated certificate secret name (or `certificate_name`) before applying.
- The Container App custom domain requires the `asuid` TXT record to validate. See the main README. After a successful apply, `terraform -chdir=infra/terraform/app output dns_records` lists all records for external DNS providers.

The sample Foundry deployments omit models that are retired, deprecated for new customers, or scheduled to retire soon. Verify model, version, SKU, quota, and regional availability before applying.

### Optional Databalance theme

The optional custom image in [`../docker/openwebui`](../docker/openwebui) layers Databalance-inspired CSS over the pinned Open WebUI v0.13.0 image. It changes colors only: the Open WebUI name and logo remain intact, and no Databalance assets or fonts are bundled. The app continues to use the upstream `:main` image unless `open_webui_image` is overridden.

Build and publish the image to a registry that Container Apps can pull from, from the repository root:

```bash
docker buildx build --platform linux/amd64 \
  -t <registry>/<repository>/open-webui-databalance:v0.13.0 \
  --push infra/docker/openwebui
```

Set `open_webui_image` in `app/terraform.tfvars` to the published image URI, then apply. This repository does not provision a registry.

### Azure Files authentication

The app's SMB mount uses the Container Apps environment's user-assigned managed identity instead of a storage account key. This [Container Apps feature is in preview](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts#azure-files). Terraform enables SMB OAuth and Kerberos on the storage account and grants the identity **Storage File Data SMB MI Admin** at the account scope. Role assignment propagation can take time: if the mount or revision fails immediately after the assignment is created, verify the permissions and retry after they propagate.

The storage account disables Shared Key access and allows only Kerberos for SMB. Account-key and service SAS requests are therefore rejected; the file share is managed through the Azure Resource Manager API.

Terraform does not export the storage keys and connection strings to Key Vault. The AzureRM storage account resource can still read account keys into Terraform state, even when Shared Key access is disabled. Protect state and backups accordingly.

### Import the OpenAI API definition

The operations come from the OpenAPI document and are imported separately for manual deployments (Terraform manages the API shell, policy and diagnostics):

```bash
az apim api import --resource-group <hub-rg> --service-name <apim-name> --api-id openai --path "openai/v1" \
  --specification-format OpenApiJson --specification-path infra/terraform/assets/openai.openapi.json \
  --display-name "Azure OpenAI v1 API" --protocols https --subscription-required false
```

### Local deployment checklist

Terraform manages the infrastructure, the Entra ID app (including admin consent and group-based app role assignments) and the `open-webui` APIM subscription. The following steps remain manual for a local deployment, in order:

1. **Before the first apply**
   - Sign in with the Azure CLI and register the resource providers:

     ```bash
     az provider register --namespace Microsoft.App --wait
     az provider register --namespace Microsoft.CertificateRegistration --wait
     ```

   - Review `app/terraform.tfvars`. Set `open_webui_user_group_name` and `open_webui_admin_group_name` to have Terraform create the Entra ID security groups and assign them the `user`/`admin` app roles required to sign in; add members to the groups in Entra ID.
   - The deploying identity needs the **DelegatedPermissionGrant.ReadWrite.All** Microsoft Graph permission (or Privileged Role Administrator) because Terraform creates the tenant-wide admin consent grants.
2. **During the apply (external DNS only)** - read the certificate verification token while the issuance wait polls and add it as a TXT record named `@` at the root domain. Keep the record for renewals.
3. **After the apply**
   - Create the DNS records listed by `terraform -chdir=infra/terraform/app output dns_records` (the A record and the `asuid` TXT record).
   - Import the OpenAI API definition into APIM (see above).
   - In Open WebUI, as an admin user: **Admin Settings → Connections**, add or edit the OpenAI connection with the API base URL `https://<apim-name>.azure-api.net/openai/v1`, OAuth token forwarding enabled, the headers `{"api-key": "<subscription key>"}` and the deployed model IDs. Read the key with:

     ```bash
     terraform -chdir=infra/terraform/app output -raw apim_open_webui_subscription_key
     ```

   - Optionally disable the default Ollama connection in **Admin Settings → Connections** to avoid connection errors in the logs.

## CI/CD with GitHub Actions

[`.github/workflows/deploy-azure.yml`](../../.github/workflows/deploy-azure.yml) and [`.github/workflows/validate-terraform.yml`](../../.github/workflows/validate-terraform.yml) target only development. They authenticate to Azure with OpenID Connect (federated credentials), so no client secret is stored.

| Trigger | Job | What it does |
| --- | --- | --- |
| Pull request or manual validation | `validate`, `terraform-plan` | Checks formatting and configuration, then publishes a speculative plan in the run summary |
| Manual deployment | `terraform-plan`, `terraform-apply` | Plans, then applies or destroys the approved plan; an apply imports the APIM OpenAPI definition last |

Plan summaries and saved plan artifacts can contain sensitive values; restrict access to workflow runs and artifacts. The API policy and NSG rules are managed by Terraform, while the OpenAPI definition is imported after every successful apply, including when infrastructure has no changes. Plan and destroy runs do not import it.

### One-time setup

1. Create an Entra ID app registration (or user-assigned managed identity) and give it Owner (or Contributor + User Access Administrator) on the subscription, permission to create app registrations (for the Open WebUI app), and **Storage Blob Data Contributor** on the state container. For the App Service Certificate it also needs to read service principals (for example the `Application.Read.All` Graph permission) and **DNS Zone Contributor** on `public_dns_zone_name` if that zone is outside the subscription. The plan identity needs the same service-principal read access.
2. Add federated credentials for this repository:

   | Name | Subject |
   | --- | --- |
  | `github-plan` | `repo:<owner>/<repo>:environment:Development` |
  | `github-deploy` | `repo:<owner>/<repo>:environment:Development-Apply` |

   ```bash
   az ad app federated-credential create --id <app-id> --parameters '{
     "name": "github-deploy",
     "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<owner>/<repo>:environment:Development-Apply",
     "audiences": ["api://AzureADTokenExchange"]
   }'
   ```

  Use a separate, read-only identity for `Development` if you want PR plans to run with fewer permissions (Reader + Storage Blob Data Contributor on state, plus read access to the Entra app).
3. Create a storage account and container for Terraform state (Entra ID authentication; shared key can be disabled).
4. Create the GitHub environments `Development` and `Development-Apply`. Add required reviewers to `Development-Apply` to gate deployments.
5. Configure variables and secrets for both environments (or at repository level):

   | Type | Name | Value |
   | --- | --- | --- |
   | Variable | `AZURE_CLIENT_ID` | Client ID of the federated identity |
   | Variable | `AZURE_TENANT_ID` | Tenant ID |
   | Variable | `AZURE_SUBSCRIPTION_ID` | Target subscription |
  | Variable | `TF_STATE_SUBSCRIPTION_ID` | State storage subscription ID |
  | Variable | `TF_STATE_RESOURCE_GROUP` | State storage resource group |
   | Variable | `TF_STATE_STORAGE_ACCOUNT` | State storage account name |
   | Variable | `TF_STATE_CONTAINER` | State container name |
   | Secret | `POSTGRES_ADMIN_PASSWORD` | PostgreSQL admin password |
   | Secret | `WEBUI_SECRET_KEY` | Stable Open WebUI secret key |
   | Secret | `CERTIFICATE_PFX_BASE64` | Optional: base64 PFX, only when `use_app_service_certificate = false` |

6. Review `app/terraform.tfvars` and `app/environment/dev.tfvars`.

### First deployment

Prepare DNS (the `asuid` TXT record) and the certificate, then run the deployment workflow manually with the `apply` action. The first run takes over an hour, mostly for APIM. Admin consent, user/role assignment and public DNS remain manual steps.

## Implementation details

- Key Vault secrets are written through the ARM control plane (`azapi`), so the deploying identity needs no Key Vault data-plane role. The PFX and PostgreSQL connection string are write-only and are not stored in state.
- The Azure Files SMB mount uses the environment's managed identity (preview).
- The Container App resolves its database secret with the user-assigned identity, which has Key Vault access before the app is created. The system-assigned identity and its role assignment are kept.
- Hub resources reference app resources directly (Container App FQDN and static IP, Foundry endpoint, Entra app ID, Key Vault), so no outputs need to be copied between deployments.
- Application Gateway waits for the TLS certificate in the spoke Key Vault before it creates the HTTPS listener.
- `app_gateway_public_ip` returns the Application Gateway's public IP address.

## Migrating from separate hub and app states

Earlier versions used separate `hub/` and `app/` roots with `hub.tfstate` and `app.tfstate`. To keep the deployed resources, merge both states into the new key before the first plan:

```bash
cd "$(mktemp -d)"
az storage blob download --auth-mode login --account-name <state-account> -c <state-container> -n hub.tfstate -f hub.tfstate
az storage blob download --auth-mode login --account-name <state-account> -c <state-container> -n app.tfstate -f merged.tfstate
for addr in $(terraform state list -state=hub.tfstate | grep -v '^data\.'); do
  new="${addr%\[0\]}"
  new="${new/app_gateway_spoke_key_vault/app_gateway_key_vault}"
  terraform state mv -state=hub.tfstate -state-out=merged.tfstate "$addr" "$new"
done
az storage blob upload --auth-mode login --account-name <state-account> -c <state-container> -n openwebui.tfstate -f merged.tfstate
```

Merge the hub-specific values from the old `hub/terraform.tfvars` into `app/terraform.tfvars` (the hub VNet prefix is now `hub_virtual_network_address_prefix`, and `ssl_certificate_secret_name` is replaced by `certificate_name`). Then initialize with `key=openwebui.tfstate` and review the plan: it should not replace existing resources. Keep the old state blobs until the first apply succeeds.

## Validate

```bash
terraform fmt -check -recursive infra/terraform
terraform -chdir=infra/terraform/app init -backend=false && terraform -chdir=infra/terraform/app validate
terraform -chdir=infra/terraform/app test
terraform -chdir=infra/terraform/modules/naming init -backend=false && terraform -chdir=infra/terraform/modules/naming test
```
