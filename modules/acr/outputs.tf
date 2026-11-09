output "id" {
  description = "Registry resource ID."
  value       = azurerm_container_registry.this.id
}

output "login_server" {
  description = "Registry login server (resolves privately inside the VNets)."
  value       = azurerm_container_registry.this.login_server
}
