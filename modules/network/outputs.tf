output "hub_vnet_id" {
  description = "Hub VNet resource ID."
  value       = azurerm_virtual_network.hub.id
}

output "spoke_vnet_id" {
  description = "AKS spoke VNet resource ID."
  value       = azurerm_virtual_network.spoke.id
}

output "aks_nodes_subnet_id" {
  description = "Subnet for AKS node pools."
  value       = azurerm_subnet.aks_nodes.id
}

output "private_endpoints_subnet_id" {
  description = "Subnet for private endpoints in the spoke."
  value       = azurerm_subnet.private_endpoints.id
}

output "ingress_subnet_id" {
  description = "Subnet reserved for internal ingress load balancers."
  value       = azurerm_subnet.ingress.id
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone IDs keyed by acr, key_vault and aks."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "aks_outbound_type" {
  description = "AKS outbound type matching the egress design: userDefinedRouting when the firewall is on, loadBalancer otherwise."
  value       = var.enable_firewall ? "userDefinedRouting" : "loadBalancer"
}

output "firewall_private_ip" {
  description = "Azure Firewall private IP, if deployed."
  value       = var.enable_firewall ? azurerm_firewall.this[0].ip_configuration[0].private_ip_address : null
}
