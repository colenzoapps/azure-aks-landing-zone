variable "name_prefix" {
  description = "Prefix applied to resource names."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the workspace."
  type        = string
}

variable "retention_in_days" {
  description = "Log retention. 30 is the free-retention floor."
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB; -1 for unlimited. A cap protects a demo subscription from runaway log costs."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
