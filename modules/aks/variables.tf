variable "name" {
  description = "Cluster name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the cluster. Nodes go in <name>-nodes."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. 1.33. Null takes the regional default."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "Control plane tier: Free (no SLA) or Standard."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "vnet_id" {
  description = "Spoke VNet ID. The control-plane identity gets Network Contributor here."
  type        = string
}

variable "nodes_subnet_id" {
  description = "Subnet for all node pools."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the privatelink.<region>.azmk8s.io zone for the API server."
  type        = string
}

variable "outbound_type" {
  description = "loadBalancer, or userDefinedRouting when egress is forced through a firewall."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.outbound_type)
    error_message = "Unsupported outbound_type."
  }
}

variable "pod_cidr" {
  description = "Overlay pod CIDR. Must not overlap any routable network."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR. The DNS service IP is the 10th host."
  type        = string
  default     = "172.16.0.0/16"
}

variable "system_node_vm_size" {
  description = "VM size for the system pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "system_node_min_count" {
  description = "Minimum system nodes."
  type        = number
  default     = 1
}

variable "system_node_max_count" {
  description = "Maximum system nodes."
  type        = number
  default     = 3
}

variable "apps_pool_enabled" {
  description = "Create the user node pool for application workloads."
  type        = bool
  default     = true
}

variable "apps_node_vm_size" {
  description = "VM size for the apps pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "apps_node_min_count" {
  description = "Minimum apps nodes. 0 lets the pool scale to zero when idle."
  type        = number
  default     = 0
}

variable "apps_node_max_count" {
  description = "Maximum apps nodes."
  type        = number
  default     = 3
}

variable "availability_zones" {
  description = "Zones for node pools. Null for regions or SKUs without zone support."
  type        = list(string)
  default     = null
}

variable "host_encryption_enabled" {
  description = "Encrypt temp disks and caches at the host. Requires Microsoft.Compute/EncryptionAtHost registered on the subscription."
  type        = bool
  default     = false
}

variable "admin_group_object_ids" {
  description = "Entra ID groups granted cluster admin."
  type        = list(string)
  default     = []
}

variable "cluster_admin_principals" {
  description = "Principals granted Azure Kubernetes Service RBAC Cluster Admin, keyed by a stable label. type is User, Group or ServicePrincipal."
  type = map(object({
    object_id = string
    type      = string
  }))
  default = {}
}

variable "acr_id" {
  description = "Registry the kubelet identity may pull from."
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault the Secrets Store CSI driver may read from."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace for Container Insights and control-plane logs."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
