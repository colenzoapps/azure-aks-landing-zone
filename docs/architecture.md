# Architecture and design decisions

## Address plan

| Network | CIDR | Purpose |
|---|---|---|
| Hub VNet | 10.0.0.0/22 | Shared connectivity and DNS |
| `AzureFirewallSubnet` | 10.0.0.0/26 | Azure Firewall (when enabled) |
| `snet-shared-pe` | 10.0.1.0/24 | Private endpoints for shared services |
| *(free)* | 10.0.0.64/26 to 10.0.0.255, 10.0.2.0/23 | Headroom for Bastion, VPN/ExpressRoute gateway, DNS resolver |
| AKS spoke VNet | 10.1.0.0/16 | Workload network |
| `snet-aks-nodes` | 10.1.0.0/22 | Node NICs only (about 1,000 nodes) |
| `snet-private-endpoints` | 10.1.8.0/24 | ACR and Key Vault private endpoints |
| `snet-ingress` | 10.1.9.0/24 | Internal load balancers for ingress controllers |
| Pod CIDR (overlay) | 192.168.0.0/16 | Not routable on the VNet |
| Service CIDR | 172.16.0.0/16 | Kubernetes services; DNS at 172.16.0.10 |

Pod and service ranges are chosen to stay clear of RFC 1918 space likely to be used on-premises or in other spokes.

## Trust model

| Principal | Federated subject(s) | Azure roles | Why |
|---|---|---|---|
| `gh-<repo>-plan` | `pull_request`, `ref:refs/heads/main` | Reader, AKS Cluster User (subscription); Blob Data Contributor (state) | PRs from any branch can plan but cannot change anything. State write is only needed for the lock. |
| `gh-<repo>-apply` | `environment:dev` | Contributor; RBAC Administrator with ABAC condition (subscription); Blob Data Contributor (state) | Only jobs that passed the `dev` environment's reviewer gate get a token. The ABAC condition limits role assignments to Network Contributor, Private DNS Zone Contributor, AcrPull, Key Vault Secrets User and AKS RBAC Cluster Admin, so the pipeline cannot escalate itself to Owner. |
| AKS control-plane UAI | n/a | Private DNS Zone Contributor (AKS zone), Network Contributor (spoke VNet) | Required for a private cluster with a bring-your-own DNS zone. Assigned before cluster creation. |
| Kubelet identity | n/a | AcrPull (registry) | Image pulls without registry credentials. |
| Key Vault CSI identity | n/a | Key Vault Secrets User (vault) | Mount secrets into pods; read-only. |

## Key decisions

**Private cluster with hub-owned DNS zone rather than `System`.** The zone lives in the hub and is linked to every VNet that needs to resolve the API server, which is how it works in an enterprise landing zone with central DNS. The cost is the extra identity and role assignments, and that is the part most teams get wrong.

**Azure CNI Overlay with Cilium.** Pods take addresses from a private overlay, so the node subnet is sized for nodes, not pods × nodes. Cilium provides eBPF dataplane performance and network policy without running a separate Calico install.

**`run_command_enabled = true`.** GitHub-hosted runners cannot reach a private API server. `az aks command invoke` gives CI a controlled, audited path (via ARM, governed by Azure RBAC) for smoke tests without a jump host. Production would add self-hosted runners in the spoke.

**Firewall optional, off by default.** Forced tunnelling through Azure Firewall is the correct production egress pattern, but it costs more per day than the rest of the environment combined. A single variable switches it on and moves the cluster to `userDefinedRouting`; the network module is applied first via `depends_on` so the route exists before AKS validates egress.

**Saved plan is what gets applied.** The `plan` job uploads the binary plan and the provider lock file; the `apply` job applies exactly that artifact. If state moved in between, Terraform refuses the stale plan instead of applying something nobody reviewed.

**Pipeline principal passed explicitly.** The cluster-admin grant for the pipeline uses `TF_VAR_pipeline_principal_object_id` instead of `azurerm_client_config`. Plan and apply run as different identities, and reading the current principal would make the plan describe a different role assignment from the one apply makes.

**Container Insights via an explicit data collection rule.** With managed-identity auth, the monitoring agent is driven by a data collection rule (DCR) and its association. The Azure CLI and portal create these for you; here they are declared in code so collection settings (interval, namespace filtering, ContainerLogV2) are versioned and reviewable, not left to defaults.

**State storage with shared keys disabled.** Everything, including the Terraform backend, authenticates with Entra ID (`use_azuread_auth`). A leaked storage key cannot be used because there is none.
