# Run once, locally, with your own Azure CLI login (Owner or User Access
# Administrator + Contributor on the subscription). It creates:
#   1. A locked-down storage account for Terraform remote state.
#   2. Two Entra ID workload identities for GitHub Actions, federated by OIDC
#      (no client secrets anywhere):
#        - plan  : read-only, trusted for pull requests.
#        - apply : can change infrastructure, trusted only for the protected
#                  GitHub environment, so every apply passes its approval gate.

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

locals {
  github_issuer = "https://token.actions.githubusercontent.com"
  repo          = "${var.github_owner}/${var.github_repo}"
  tags = merge(var.tags, {
    workload   = "terraform-state"
    managed_by = "terraform-bootstrap"
  })

  identities = {
    plan = {
      subjects = {
        pull-request = "repo:${local.repo}:pull_request"
        main         = "repo:${local.repo}:ref:refs/heads/main"
      }
    }
    apply = {
      subjects = {
        for env in var.github_environments : "env-${env}" => "repo:${local.repo}:environment:${env}"
      }
    }
  }

  federated_credentials = merge([
    for identity, cfg in local.identities : {
      for label, subject in cfg.subjects : "${identity}/${label}" => {
        identity = identity
        label    = label
        subject  = subject
      }
    }
  ]...)

  # Roles the apply identity is allowed to hand out. The landing zone needs
  # exactly these; the ABAC condition below blocks everything else, so a
  # compromised pipeline cannot grant itself Owner.
  delegable_role_ids = [
    "4d97b98b-1d4f-4787-a291-c67834d212e7", # Network Contributor
    "b12aa53e-6015-4669-85d0-8515ebb3ae7f", # Private DNS Zone Contributor
    "7f951dda-4ed3-4680-a7ca-43fe172d538d", # AcrPull
    "4633458b-17de-408a-b874-0445c86b69e6", # Key Vault Secrets User
    "b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b", # Azure Kubernetes Service RBAC Cluster Admin
  ]

  delegable_roles_csv = join(", ", local.delegable_role_ids)

  rbac_admin_condition = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
      )
      OR
      (
        @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegable_roles_csv}}
      )
    )
    AND
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
      )
      OR
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegable_roles_csv}}
      )
    )
  EOT
}

# ---------------------------------------------------------------------------
# Remote state
# ---------------------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.project}-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_33:Queue service is unused; there is nothing to log.
  #checkov:skip=CKV_AZURE_59:Public network access stays on so GitHub-hosted runners can reach state; key auth is disabled and access is Entra ID RBAC only.
  #checkov:skip=CKV_AZURE_206:LRS is enough for a dev state store; versioning and soft delete cover recovery.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys are acceptable for Terraform state in this context.
  #checkov:skip=CKV2_AZURE_33:No private endpoint so hosted runners can reach the state; see CKV_AZURE_59.
  #checkov:skip=CKV2_AZURE_40:Shared key access is already disabled (shared_access_key_enabled = false).
  #checkov:skip=CKV2_AZURE_41:No SAS tokens are issued; shared key access is disabled.
  name                            = "st${var.project}tfstate${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  tags                            = local.tags

  lifecycle {
    prevent_destroy = true
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "state" {
  #checkov:skip=CKV2_AZURE_21:Blob read logging is not needed for state; versioning gives the audit trail.
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_management_lock" "state" {
  name       = "do-not-delete-tfstate"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Holds Terraform state for ${local.repo}."
}

# You (the bootstrapper) need data-plane access too, for local init/debugging.
resource "azurerm_role_assignment" "bootstrapper_state" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# GitHub Actions workload identities (OIDC)
# ---------------------------------------------------------------------------

resource "azuread_application" "github" {
  for_each = local.identities

  display_name = "gh-${var.github_repo}-${each.key}"
  owners       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal" "github" {
  for_each = local.identities

  client_id = azuread_application.github[each.key].client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "github" {
  #checkov:skip=CKV_AZURE_249:Subjects are computed and exact (no wildcards): pull_request and refs/heads/main for plan, environment-scoped for apply.
  for_each = local.federated_credentials

  application_id = azuread_application.github[each.value.identity].id
  display_name   = "github-${each.value.label}"
  description    = "GitHub Actions: ${each.value.subject}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = local.github_issuer
  subject        = each.value.subject
}

# Both identities read and lock state.
resource "azurerm_role_assignment" "state_access" {
  for_each = local.identities

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github[each.key].object_id
  principal_type       = "ServicePrincipal"
}

# plan: read-only on the subscription. The AKS Cluster User role lets the
# provider read the cluster's user kubeconfig during refresh.
resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.github["plan"].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "plan_aks_user" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.github["plan"].object_id
  principal_type       = "ServicePrincipal"
}

# apply: Contributor, plus role-assignment rights constrained by ABAC.
resource "azurerm_role_assignment" "apply_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github["apply"].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.github["apply"].object_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.rbac_admin_condition
  description          = "Pipeline may only assign the roles the landing zone needs."
}
