locals {
  # Hub layout (/22): firewall /26, shared private endpoints /24. The rest is
  # headroom for Bastion, VPN/ExpressRoute gateways or DNS resolvers later.
  hub_subnets = {
    AzureFirewallSubnet = cidrsubnet(var.hub_address_space, 4, 0)
    snet-shared-pe      = cidrsubnet(var.hub_address_space, 2, 1)
  }

  # Spoke layout (/16): AKS nodes /22 (overlay CNI, so pods do not consume VNet IPs),
  # private endpoints /24, internal ingress load balancers /24.
  spoke_subnets = {
    aks_nodes         = cidrsubnet(var.spoke_address_space, 6, 0)
    private_endpoints = cidrsubnet(var.spoke_address_space, 8, 8)
    ingress           = cidrsubnet(var.spoke_address_space, 8, 9)
  }

  private_dns_zones = {
    acr       = "privatelink.azurecr.io"
    key_vault = "privatelink.vaultcore.azure.net"
    aks       = var.aks_private_dns_zone_name
  }
}

# ---------------------------------------------------------------------------
# Hub
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.name_prefix}-hub"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  address_space       = [var.hub_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "hub" {
  for_each = local.hub_subnets

  name                 = each.key
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value]
}

# ---------------------------------------------------------------------------
# Spoke (AKS)
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-${var.name_prefix}-aks"
  location            = var.location
  resource_group_name = var.spoke_resource_group_name
  address_space       = [var.spoke_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = var.spoke_resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.spoke_subnets.aks_nodes]
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = var.spoke_resource_group_name
  virtual_network_name              = azurerm_virtual_network.spoke.name
  address_prefixes                  = [local.spoke_subnets.private_endpoints]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "ingress" {
  name                 = "snet-ingress"
  resource_group_name  = var.spoke_resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.spoke_subnets.ingress]
}

# NSGs: Azure's default rules already deny inbound from the internet. These
# NSGs make the intent explicit and give a single place to add rules later.
resource "azurerm_network_security_group" "spoke" {
  for_each = {
    aks_nodes         = azurerm_subnet.aks_nodes.id
    private_endpoints = azurerm_subnet.private_endpoints.id
    ingress           = azurerm_subnet.ingress.id
  }

  name                = "nsg-${var.name_prefix}-${replace(each.key, "_", "-")}"
  location            = var.location
  resource_group_name = var.spoke_resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "spoke" {
  for_each = {
    aks_nodes         = azurerm_subnet.aks_nodes.id
    private_endpoints = azurerm_subnet.private_endpoints.id
    ingress           = azurerm_subnet.ingress.id
  }

  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.spoke[each.key].id
}

resource "azurerm_network_security_group" "hub_shared_pe" {
  name                = "nsg-${var.name_prefix}-hub-shared-pe"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "hub_shared_pe" {
  subnet_id                 = azurerm_subnet.hub["snet-shared-pe"].id
  network_security_group_id = azurerm_network_security_group.hub_shared_pe.id
}

# ---------------------------------------------------------------------------
# Peering
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-aks"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-aks-to-hub"
  resource_group_name          = var.spoke_resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}

# ---------------------------------------------------------------------------
# Private DNS (centralised in the hub, linked to both VNets)
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each = local.private_dns_zones

  name                  = "link-hub"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = local.private_dns_zones

  name                  = "link-aks"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
}

# ---------------------------------------------------------------------------
# Optional egress firewall (hub) + forced tunnelling for AKS nodes
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "firewall" {
  count = var.enable_firewall ? 1 : 0

  name                = "pip-${var.name_prefix}-afw"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  count = var.enable_firewall ? 1 : 0

  name                     = "afwp-${var.name_prefix}"
  location                 = var.location
  resource_group_name      = var.hub_resource_group_name
  sku                      = var.firewall_sku_tier
  threat_intelligence_mode = "Deny"
  tags                     = var.tags

  dns {
    proxy_enabled = true
  }
}

# Minimum egress AKS needs to function (Microsoft's documented AKS FQDN tag,
# plus NTP and the Azure service tags the nodes talk to).
resource "azurerm_firewall_policy_rule_collection_group" "aks" {
  count = var.enable_firewall ? 1 : 0

  name               = "aks-egress"
  firewall_policy_id = azurerm_firewall_policy.this[0].id
  priority           = 200

  network_rule_collection {
    name     = "aks-network"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "azure-services"
      protocols             = ["TCP"]
      source_addresses      = [local.spoke_subnets.aks_nodes]
      destination_addresses = ["AzureCloud.${var.location}", "AzureMonitor", "AzureContainerRegistry"]
      destination_ports     = ["443", "9000"]
    }

    rule {
      name                  = "ntp"
      protocols             = ["UDP"]
      source_addresses      = [local.spoke_subnets.aks_nodes]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }
  }

  application_rule_collection {
    name     = "aks-fqdn"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "aks-required"
      source_addresses      = [local.spoke_subnets.aks_nodes]
      destination_fqdn_tags = ["AzureKubernetesService"]

      protocols {
        type = "Https"
        port = 443
      }
      protocols {
        type = "Http"
        port = 80
      }
    }
  }
}

resource "azurerm_firewall" "this" {
  count = var.enable_firewall ? 1 : 0

  name                = "afw-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this[0].id
  zones               = ["1", "2", "3"]
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.hub["AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.aks]
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count = var.enable_firewall ? 1 : 0

  name                           = "diag-to-law"
  target_resource_id             = azurerm_firewall.this[0].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_route_table" "aks_egress" {
  count = var.enable_firewall ? 1 : 0

  name                          = "rt-${var.name_prefix}-aks-egress"
  location                      = var.location
  resource_group_name           = var.spoke_resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.this[0].ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "aks_nodes" {
  count = var.enable_firewall ? 1 : 0

  subnet_id      = azurerm_subnet.aks_nodes.id
  route_table_id = azurerm_route_table.aks_egress[0].id
}
