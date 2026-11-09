variable "name" {
  description = "Globally unique Key Vault name (3-24 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault names must be 3-24 characters: letters, digits and hyphens, starting with a letter."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the vault and its private endpoint."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant for the vault."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet the private endpoint is placed in."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the privatelink.vaultcore.azure.net zone."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace receiving vault audit logs."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
