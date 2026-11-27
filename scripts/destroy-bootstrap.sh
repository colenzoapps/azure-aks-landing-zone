#!/usr/bin/env bash
# Final teardown: removes what bootstrap/ created, after every environment is gone.
# Run locally with your own az login (Owner), from the repo root:
#
#   scripts/destroy-bootstrap.sh
#
# It removes, in order:
#   1. Subscription-scope role assignments held by the two GitHub identities.
#   2. The two Entra ID app registrations (and their service principals and
#      federated credentials). Entra keeps deleted apps in its recycle bin for
#      30 days at no cost.
#   3. The delete lock on the state storage account, then the state resource group.
#
# It does not use `terraform destroy`, because the state account is deliberately
# protected by prevent_destroy and a CanNotDelete lock. It reads the names from
# bootstrap's local state, or from these variables if that state is gone:
#   TFSTATE_RESOURCE_GROUP, PLAN_CLIENT_ID, APPLY_CLIENT_ID, ARM_SUBSCRIPTION_ID

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
command -v az >/dev/null || die "the Azure CLI (az) is required"
command -v jq >/dev/null || die "jq is required"
az account show >/dev/null 2>&1 || die "not logged in to Azure (run az login)"

repo_root=$(cd "$(dirname "$0")/.." && pwd)

tf_output() {
  command -v terraform >/dev/null || return 0
  [ -f "${repo_root}/bootstrap/terraform.tfstate" ] || return 0
  terraform -chdir="${repo_root}/bootstrap" output -raw "$1" 2>/dev/null || true
}

RG="${TFSTATE_RESOURCE_GROUP:-$(tf_output tfstate_resource_group)}"
PLAN_ID="${PLAN_CLIENT_ID:-$(tf_output plan_client_id)}"
APPLY_ID="${APPLY_CLIENT_ID:-$(tf_output apply_client_id)}"
SUB="${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

[ -n "$RG" ] || die "state resource group unknown: set TFSTATE_RESOURCE_GROUP"
[ -n "$PLAN_ID" ] && [ -n "$APPLY_ID" ] || die "identity client IDs unknown: set PLAN_CLIENT_ID and APPLY_CLIENT_ID"

echo "Checking that every environment is already destroyed..."
for env_dir in "${repo_root}"/environments/*/; do
  env=$(basename "$env_dir")
  if ! ENVIRONMENT="$env" TF_DIR="$env_dir" POST_WAIT_SECONDS=0 \
      ARM_SUBSCRIPTION_ID="$SUB" "${repo_root}/scripts/teardown-audit.sh" post; then
    die "environment '${env}' still has resources. Run the destroy workflow first; its Terraform state lives in the account this script deletes."
  fi
done

echo
echo "Subscription: $(az account show --subscription "$SUB" --query name -o tsv) ($SUB)"
echo "This will permanently delete:"
echo "  - resource group ${RG} (Terraform state for every environment)"
for id in "$PLAN_ID" "$APPLY_ID"; do
  name=$(az ad app show --id "$id" --query displayName -o tsv 2>/dev/null || echo "already deleted")
  echo "  - Entra app ${name} (${id}) and its role assignments"
done
echo
read -r -p "Type the resource group name to confirm: " answer
[ "$answer" = "$RG" ] || die "confirmation did not match; nothing was deleted"

for id in "$PLAN_ID" "$APPLY_ID"; do
  sp=$(az ad sp show --id "$id" --query id -o tsv 2>/dev/null || true)
  if [ -n "$sp" ]; then
    ids=$(az role assignment list --assignee "$sp" --all --subscription "$SUB" -o json | jq -r '.[].id')
    if [ -n "$ids" ]; then
      echo "Removing role assignments for ${id}"
      # shellcheck disable=SC2086 # one ID per word is intended
      az role assignment delete --ids $ids --subscription "$SUB" --only-show-errors
    fi
  fi
  if az ad app show --id "$id" >/dev/null 2>&1; then
    echo "Deleting Entra app ${id}"
    az ad app delete --id "$id"
  fi
done

if [ "$(az group exists -n "$RG" --subscription "$SUB")" = "true" ]; then
  locks=$(az lock list -g "$RG" --subscription "$SUB" -o json | jq -r '.[].id')
  if [ -n "$locks" ]; then
    echo "Removing delete locks in ${RG}"
    # shellcheck disable=SC2086
    az lock delete --ids $locks --subscription "$SUB"
  fi
  echo "Deleting resource group ${RG} (takes a minute or two)"
  az group delete -n "$RG" --subscription "$SUB" --yes
fi

echo
echo "Azure side is clean. Remaining local and GitHub clean-up:"
echo "  rm bootstrap/terraform.tfstate bootstrap/terraform.tfstate.backup"
echo "  gh api -X DELETE \"repos/{owner}/{repo}/environments/dev\""
echo "  for v in AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID AZURE_CLIENT_ID_PLAN AZURE_CLIENT_ID_APPLY AZURE_APPLY_OBJECT_ID TFSTATE_RESOURCE_GROUP TFSTATE_STORAGE_ACCOUNT TFSTATE_CONTAINER; do gh variable delete \$v; done"
