# Non-secret settings for the dev landing zone. Credentials and the
# subscription ID come from the pipeline environment, never from this file.
project        = "lz"
environment    = "dev"
location       = "uksouth"
location_short = "uks"

enable_firewall     = false
aks_sku_tier        = "Free"
system_node_vm_size = "Standard_D2s_v5"
apps_node_vm_size   = "Standard_D2s_v5"
availability_zones  = ["1", "2", "3"]

# Add yourself so you can run `az aks command invoke` and kubectl via a jump host:
# extra_cluster_admins = {
#   me = { object_id = "<az ad signed-in-user show --query id -o tsv>", type = "User" }
# }
