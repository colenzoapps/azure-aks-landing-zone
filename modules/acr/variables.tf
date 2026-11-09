variable "name" {
  description = "Globally unique registry name (alphanumeric, 5-50 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "ACR names must be 5-50 alphanumeric characters."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the registry and its private endpoint."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet the private endpoint is placed in."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the privatelink.azurecr.io zone."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace receiving registry audit logs."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
