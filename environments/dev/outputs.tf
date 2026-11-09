output "aks_name" {
  description = "Cluster name."
  value       = module.aks.name
}

output "aks_resource_group" {
  description = "Cluster resource group."
  value       = azurerm_resource_group.this["aks"].name
}

output "aks_private_fqdn" {
  description = "Private API server FQDN."
  value       = module.aks.private_fqdn
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer for workload identity."
  value       = module.aks.oidc_issuer_url
}

output "acr_login_server" {
  description = "Private container registry."
  value       = module.acr.login_server
}

output "key_vault_uri" {
  description = "Private Key Vault URI."
  value       = module.keyvault.vault_uri
}

output "log_analytics_workspace" {
  description = "Central Log Analytics workspace."
  value       = module.monitoring.workspace_name
}
