# Premium is the lowest SKU that supports private endpoints and disabling
# public network access.
resource "azurerm_container_registry" "this" {
  #checkov:skip=CKV_AZURE_165:Geo-replication is out of scope for a single-region dev landing zone.
  #checkov:skip=CKV_AZURE_233:Zone redundancy left off to keep the dev environment cheap; enable for prod.
  #checkov:skip=CKV_AZURE_164:Content trust (Notary v1) is deprecated; image signing belongs in the build pipeline (Notation).
  #checkov:skip=CKV_AZURE_166:Quarantine is a preview workflow needing a scanner integration; scanning is handled by Defender for Containers.
  #checkov:skip=CKV_AZURE_163:Vulnerability scanning is a Defender for Containers subscription setting, not a registry argument.
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  anonymous_pull_enabled        = false
  data_endpoint_enabled         = true
  network_rule_bypass_option    = "AzureServices"
  zone_redundancy_enabled       = false
  tags                          = var.tags

  retention_policy_in_days = 7
}

resource "azurerm_private_endpoint" "this" {
  name                          = "pe-${var.name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${var.name}"
  tags                          = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                           = "diag-to-law"
  target_resource_id             = azurerm_container_registry.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "audit"
  }
}
