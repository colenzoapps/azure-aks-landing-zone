# Partial configuration. The storage account, resource group and container are
# supplied at init time, so no environment-specific values are committed:
#
#   terraform init \
#     -backend-config="resource_group_name=<TFSTATE_RESOURCE_GROUP>" \
#     -backend-config="storage_account_name=<TFSTATE_STORAGE_ACCOUNT>" \
#     -backend-config="container_name=<TFSTATE_CONTAINER>"
terraform {
  backend "azurerm" {
    key              = "dev/landing-zone.tfstate"
    use_azuread_auth = true
  }
}
