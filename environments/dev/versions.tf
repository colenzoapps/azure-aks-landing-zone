terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Authentication comes from the environment, never from code:
#   CI    : ARM_USE_OIDC, ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
#   Local : `az login` plus ARM_SUBSCRIPTION_ID
provider "azurerm" {
  features {
    key_vault {
      # Purge protection is on, so purging on destroy would fail anyway.
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      # Refuse to delete resource groups holding resources Terraform does not manage,
      # unless a teardown run has reviewed them (scripts/teardown-audit.sh) and opted in.
      prevent_deletion_if_contains_resources = !var.allow_unmanaged_resource_deletion
    }
  }
  storage_use_azuread = true
}
