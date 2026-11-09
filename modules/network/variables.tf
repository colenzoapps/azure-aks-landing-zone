variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. lz-dev-uks."
  type        = string
}

variable "location" {
  description = "Azure region for all network resources."
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group holding the hub VNet, firewall and private DNS zones."
  type        = string
}

variable "spoke_resource_group_name" {
  description = "Resource group holding the AKS spoke VNet."
  type        = string
}

variable "hub_address_space" {
  description = "Address space for the hub VNet."
  type        = string
  default     = "10.0.0.0/22"
}

variable "spoke_address_space" {
  description = "Address space for the AKS spoke VNet."
  type        = string
  default     = "10.1.0.0/16"
}

variable "enable_firewall" {
  description = "Deploy Azure Firewall in the hub and force-tunnel AKS egress through it. Adds roughly £25/day; leave off for cost-controlled demos."
  type        = bool
  default     = false
}

variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier when enabled."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Basic, Standard or Premium."
  }
}

variable "aks_private_dns_zone_name" {
  description = "Private DNS zone for the private AKS API server, e.g. privatelink.uksouth.azmk8s.io."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace receiving firewall diagnostics."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
