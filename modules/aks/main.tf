data "azurerm_client_config" "current" {}

# Control-plane identity. A user-assigned identity is required for a private
# cluster with a custom private DNS zone, because the role assignments below
# must exist before the cluster is created.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name}-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "dns_zone_contributor" {
  scope                = var.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "network_contributor" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "this" {
  #checkov:skip=CKV_AZURE_170:Free tier (no uptime SLA) is deliberate for dev; set sku_tier = "Standard" for prod.
  #checkov:skip=CKV_AZURE_117:Customer-managed disk encryption keys add a Disk Encryption Set and key lifecycle; out of scope for dev.
  #checkov:skip=CKV_AZURE_226:Ephemeral OS disks need a VM size with a cache/temp disk; the default D2s_v5 has none.
  #checkov:skip=CKV_AZURE_227:Host encryption requires the EncryptionAtHost feature registered on the subscription; toggle via var.host_encryption_enabled.
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  node_resource_group = "${var.resource_group_name}-nodes"
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  # Private API server, resolved through the hub-owned private DNS zone.
  private_cluster_enabled             = true
  private_dns_zone_id                 = var.private_dns_zone_id
  private_cluster_public_fqdn_enabled = false

  # Identity and access: Entra ID only, Azure RBAC for Kubernetes authorisation.
  local_account_disabled    = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true
  run_command_enabled       = true # Lets CI reach the private API via `az aks command invoke`.

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = var.admin_group_object_ids
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_vm_size
    vnet_subnet_id               = var.nodes_subnet_id
    auto_scaling_enabled         = true
    min_count                    = var.system_node_min_count
    max_count                    = var.system_node_max_count
    max_pods                     = 110
    os_sku                       = "AzureLinux"
    only_critical_addons_enabled = true
    host_encryption_enabled      = var.host_encryption_enabled
    zones                        = var.availability_zones
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # Azure CNI Overlay with the Cilium dataplane: pods get IPs from a private
  # overlay range, so the node subnet only needs to size for nodes.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = var.outbound_type
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = cidrhost(var.service_cidr, 10)
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  lifecycle {
    ignore_changes = [
      # The autoscaler owns node counts.
      default_node_pool[0].node_count,
      # Patch upgrades are applied by AKS on the auto-upgrade channel.
      kubernetes_version,
    ]
  }

  depends_on = [
    azurerm_role_assignment.dns_zone_contributor,
    azurerm_role_assignment.network_contributor,
  ]
}

# Workloads run on a separate user pool that can scale to zero, keeping
# application pods off the system pool.
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  #checkov:skip=CKV_AZURE_227:See host_encryption_enabled note on the cluster.
  #checkov:skip=CKV_AZURE_226:See ephemeral OS disk note on the cluster.
  count = var.apps_pool_enabled ? 1 : 0

  name                    = "apps"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  mode                    = "User"
  vm_size                 = var.apps_node_vm_size
  vnet_subnet_id          = var.nodes_subnet_id
  auto_scaling_enabled    = true
  min_count               = var.apps_node_min_count
  max_count               = var.apps_node_max_count
  max_pods                = 110
  os_sku                  = "AzureLinux"
  host_encryption_enabled = var.host_encryption_enabled
  zones                   = var.availability_zones
  tags                    = var.tags

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# ---------------------------------------------------------------------------
# Least-privilege wiring between the cluster and its dependencies
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "csi_kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cluster_admins" {
  for_each = var.cluster_admin_principals

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value.object_id
  principal_type       = each.value.type
}

# ---------------------------------------------------------------------------
# Observability: Container Insights (managed identity auth needs an explicit
# data collection rule) and control-plane audit logs.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "MSCI-${var.location}-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Exclude"
          namespaces             = ["kube-system", "gatekeeper-system"]
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
}

resource "azurerm_monitor_diagnostic_setting" "control_plane" {
  name                           = "diag-to-law"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  # kube-audit-admin excludes read-only (get/list) events, which keeps volume
  # and cost down while retaining every mutating API call.
  dynamic "enabled_log" {
    for_each = ["kube-audit-admin", "guard", "kube-apiserver", "cluster-autoscaler"]
    content {
      category = enabled_log.value
    }
  }
}
