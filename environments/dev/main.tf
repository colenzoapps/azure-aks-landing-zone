data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  name_prefix = "${var.project}-${var.environment}-${var.location_short}"
  # Globally unique names (ACR, Key Vault) need a suffix and no hyphens for ACR.
  unique = "${var.project}${var.environment}${var.location_short}${random_string.suffix.result}"

  tags = merge(var.tags, {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
    repository  = var.repository
  })

  # The GitHub apply identity is made a cluster admin so the pipeline can
  # smoke-test the private API server. It is passed in explicitly rather than
  # read from azurerm_client_config, because plan and apply run as different
  # identities and the plan must describe what apply will do.
  cluster_admin_principals = merge(
    {
      for label, id in { pipeline = var.pipeline_principal_object_id } :
      label => { object_id = id, type = "ServicePrincipal" } if id != null
    },
    var.extra_cluster_admins,
  )
}

# ---------------------------------------------------------------------------
# Resource groups: one per lifecycle / ownership boundary
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  for_each = toset(["hub", "aks", "shared", "monitoring"])

  name     = "rg-${local.name_prefix}-${each.key}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Platform modules
# ---------------------------------------------------------------------------

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this["monitoring"].name
  retention_in_days   = 30
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

module "network" {
  source = "../../modules/network"

  name_prefix                = local.name_prefix
  location                   = var.location
  hub_resource_group_name    = azurerm_resource_group.this["hub"].name
  spoke_resource_group_name  = azurerm_resource_group.this["aks"].name
  hub_address_space          = var.hub_address_space
  spoke_address_space        = var.spoke_address_space
  enable_firewall            = var.enable_firewall
  aks_private_dns_zone_name  = "privatelink.${var.location}.azmk8s.io"
  log_analytics_workspace_id = module.monitoring.workspace_id
  tags                       = local.tags
}

module "acr" {
  source = "../../modules/acr"

  name                       = "acr${local.unique}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this["shared"].name
  private_endpoint_subnet_id = module.network.private_endpoints_subnet_id
  private_dns_zone_id        = module.network.private_dns_zone_ids["acr"]
  log_analytics_workspace_id = module.monitoring.workspace_id
  tags                       = local.tags
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                       = "kv-${local.unique}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this["shared"].name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  private_endpoint_subnet_id = module.network.private_endpoints_subnet_id
  private_dns_zone_id        = module.network.private_dns_zone_ids["key_vault"]
  log_analytics_workspace_id = module.monitoring.workspace_id
  tags                       = local.tags
}

module "aks" {
  source = "../../modules/aks"

  name                = "aks-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this["aks"].name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.aks_sku_tier

  vnet_id             = module.network.spoke_vnet_id
  nodes_subnet_id     = module.network.aks_nodes_subnet_id
  private_dns_zone_id = module.network.private_dns_zone_ids["aks"]
  outbound_type       = module.network.aks_outbound_type

  system_node_vm_size   = var.system_node_vm_size
  system_node_min_count = 1
  system_node_max_count = 3
  apps_pool_enabled     = true
  apps_node_vm_size     = var.apps_node_vm_size
  apps_node_min_count   = 0
  apps_node_max_count   = 3
  availability_zones    = var.availability_zones

  admin_group_object_ids   = var.aks_admin_group_object_ids
  cluster_admin_principals = local.cluster_admin_principals

  acr_id                     = module.acr.id
  key_vault_id               = module.keyvault.id
  log_analytics_workspace_id = module.monitoring.workspace_id
  tags                       = local.tags

  # With the firewall on, the UDR must exist before AKS validates egress.
  depends_on = [module.network]
}
