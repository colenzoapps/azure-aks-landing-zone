output "tfstate_resource_group" {
  description = "Resource group holding the state account."
  value       = azurerm_resource_group.state.name
}

output "tfstate_storage_account" {
  description = "State storage account name."
  value       = azurerm_storage_account.state.name
}

output "tfstate_container" {
  description = "State container name."
  value       = azurerm_storage_container.state.name
}

output "plan_client_id" {
  description = "Client ID of the read-only plan identity."
  value       = azuread_application.github["plan"].client_id
}

output "apply_client_id" {
  description = "Client ID of the apply identity."
  value       = azuread_application.github["apply"].client_id
}

output "github_cli_commands" {
  description = "Paste into a shell with the GitHub CLI to configure the repo variables the workflows read."
  value       = <<-EOT
    gh variable set AZURE_TENANT_ID       --repo ${local.repo} --body "${data.azurerm_client_config.current.tenant_id}"
    gh variable set AZURE_SUBSCRIPTION_ID --repo ${local.repo} --body "${var.subscription_id}"
    gh variable set AZURE_CLIENT_ID_PLAN  --repo ${local.repo} --body "${azuread_application.github["plan"].client_id}"
    gh variable set AZURE_CLIENT_ID_APPLY --repo ${local.repo} --body "${azuread_application.github["apply"].client_id}"
    gh variable set AZURE_APPLY_OBJECT_ID --repo ${local.repo} --body "${azuread_service_principal.github["apply"].object_id}"
    gh variable set TFSTATE_RESOURCE_GROUP --repo ${local.repo} --body "${azurerm_resource_group.state.name}"
    gh variable set TFSTATE_STORAGE_ACCOUNT --repo ${local.repo} --body "${azurerm_storage_account.state.name}"
    gh variable set TFSTATE_CONTAINER      --repo ${local.repo} --body "${azurerm_storage_container.state.name}"
  EOT
}
