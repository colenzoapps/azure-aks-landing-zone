variable "project" {
  description = "Short project code used in names."
  type        = string
  default     = "lz"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region (lowercase, no spaces), e.g. uksouth."
  type        = string
  default     = "uksouth"
}

variable "location_short" {
  description = "Short region code used in names, e.g. uks."
  type        = string
  default     = "uks"
}

variable "repository" {
  description = "Source repository, recorded as a tag on every resource."
  type        = string
  default     = "unknown"
}

variable "hub_address_space" {
  description = "Hub VNet CIDR."
  type        = string
  default     = "10.0.0.0/22"
}

variable "spoke_address_space" {
  description = "AKS spoke VNet CIDR."
  type        = string
  default     = "10.1.0.0/16"
}

variable "enable_firewall" {
  description = "Deploy Azure Firewall and force AKS egress through it (about £25/day extra)."
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "AKS minor version, or null for the regional default."
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "AKS control plane tier."
  type        = string
  default     = "Free"
}

variable "system_node_vm_size" {
  description = "System pool VM size."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "apps_node_vm_size" {
  description = "Apps pool VM size."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "availability_zones" {
  description = "Node pool zones, or null."
  type        = list(string)
  default     = null
}

variable "aks_admin_group_object_ids" {
  description = "Entra ID groups with cluster admin."
  type        = list(string)
  default     = []
}

variable "pipeline_principal_object_id" {
  description = "Object ID of the GitHub apply identity (set as TF_VAR_pipeline_principal_object_id in CI)."
  type        = string
  default     = null
}

variable "extra_cluster_admins" {
  description = "Additional principals granted AKS RBAC Cluster Admin, e.g. your own user object ID."
  type = map(object({
    object_id = string
    type      = string
  }))
  default = {}
}

variable "log_daily_quota_gb" {
  description = "Log Analytics daily ingestion cap in GB."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
