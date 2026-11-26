#!/usr/bin/env bash
# Teardown audit for one landing-zone environment. Read-only: it never deletes.
#
#   teardown-audit.sh pre    Before destroy. Lists every resource in the
#                            environment's resource groups and sorts it into:
#                              managed      in Terraform state, destroyed by Terraform
#                              aks-managed  in the AKS node resource group, removed with the cluster
#                              pe-nic       private endpoint NIC, removed with its endpoint
#                              UNMANAGED    created outside Terraform (portal, CLI, a workload)
#                              OUTSIDE      tagged for this environment but in another resource
#                                           group, so the destroy will NOT remove it
#                            Needs an initialised root module (TF_DIR) to read state.
#
#   teardown-audit.sh post   After destroy. Fails if any resource group or tagged
#                            resource for the environment still exists, and reports
#                            free leftovers (Network Watcher, soft-deleted Key Vaults).
#
# Exit codes: 0 clean, 1 error, 2 findings that need attention.
#
# Settings (environment variables):
#   PROJECT, ENVIRONMENT, LOCATION_SHORT  naming inputs (default lz / dev / uks)
#   TF_DIR                                root module (default environments/$ENVIRONMENT)
#   ARM_SUBSCRIPTION_ID                   subscription (default: the az CLI's current one)
#   ALLOW_UNMANAGED=true                  pre: report UNMANAGED resources without failing,
#                                         because the destroy is set to delete them too
#   POST_WAIT_SECONDS                     post: how long to wait for groups still deleting (default 900)

set -euo pipefail

MODE="${1:-}"
PROJECT="${PROJECT:-lz}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOCATION_SHORT="${LOCATION_SHORT:-uks}"
PREFIX="rg-${PROJECT}-${ENVIRONMENT}-${LOCATION_SHORT}-"
TF_DIR="${TF_DIR:-environments/${ENVIRONMENT}}"
ALLOW_UNMANAGED="${ALLOW_UNMANAGED:-false}"
POST_WAIT_SECONDS="${POST_WAIT_SECONDS:-900}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

SUB_ARGS=()
if [ -n "${ARM_SUBSCRIPTION_ID:-}" ]; then SUB_ARGS=(--subscription "$ARM_SUBSCRIPTION_ID"); fi

die() { echo "error: $*" >&2; exit 1; }
say() { printf '%s\n' "$*"; printf '%s\n' "$*" >>"$SUMMARY"; }
azq() { az "$@" "${SUB_ARGS[@]+"${SUB_ARGS[@]}"}" --only-show-errors -o json; }

command -v az >/dev/null || die "the Azure CLI (az) is required"
command -v jq >/dev/null || die "jq is required"
az account show >/dev/null 2>&1 || die "not logged in to Azure (run az login)"

# Resource groups that belong to the environment: by naming convention, or by tags.
landing_zone_groups() {
  azq group list | jq --arg p "$PREFIX" --arg proj "$PROJECT" --arg env "$ENVIRONMENT" '
    [ .[]
      | select((.name | ascii_downcase | startswith($p))
               or (.tags.project == $proj and .tags.environment == $env))
      | { name, managedBy: (.managedBy // ""), state: (.properties.provisioningState // "") } ]'
}

# Every resource in the subscription tagged for this environment.
tagged_resources() {
  azq resource list --tag "environment=${ENVIRONMENT}" | jq --arg proj "$PROJECT" '
    [ .[] | select(.tags.project == $proj) | { id: (.id | ascii_downcase), name, type, resourceGroup } ]'
}

print_table() { # stdin: TSV of status, type, name, resource group
  say ""
  say "| Status | Type | Name | Resource group |"
  say "|---|---|---|---|"
  while IFS=$'\t' read -r status type name rg; do
    say "| ${status} | ${type} | ${name} | ${rg} |"
  done
}

report_free_leftovers() {
  if [ "$(azq group exists -n NetworkWatcherRG)" = "true" ]; then
    local watchers
    watchers=$(azq resource list -g NetworkWatcherRG | jq -r '[.[] | "\(.type)/\(.name)"] | join(", ")')
    say "- **NetworkWatcherRG** exists (${watchers:-empty}). Azure creates it automatically when a VNet is created and it is free unless flow logs are on. It may be shared with other workloads in this subscription, so it is left alone. Delete it yourself if nothing else uses it: \`az group delete -n NetworkWatcherRG\`."
  fi
  { azq keyvault list-deleted --resource-type vault 2>/dev/null || echo '[]'; } \
    | jq -r --arg proj "$PROJECT" --arg env "$ENVIRONMENT" '
        .[] | select(.properties.tags.project == $proj and .properties.tags.environment == $env)
        | "- **Soft-deleted Key Vault** `\(.name)`: free, and purge protection keeps it until \(.properties.scheduledPurgeDate). Its name stays reserved until then; the next deploy uses a new random suffix, so this does not block a redeploy."' \
    | while IFS= read -r line; do say "$line"; done
}

pre() {
  [ -d "${TF_DIR}/.terraform" ] || die "${TF_DIR} is not initialised (run terraform init first)"

  local state_ids groups tagged rows
  state_ids=$(terraform -chdir="$TF_DIR" show -json \
    | jq '[ .. | objects | select(has("address") and has("values")) | .values.id? | strings | ascii_downcase ] | unique')
  groups=$(landing_zone_groups)
  tagged=$(tagged_resources)

  say "## Teardown audit (before destroy): ${PROJECT}-${ENVIRONMENT}"
  say ""
  say "Resource groups: $(jq -r '[.[].name] | if length == 0 then "none" else join(", ") end' <<<"$groups")"

  rows=""
  while IFS=$'\t' read -r rg managed_by; do
    [ -n "$rg" ] || continue
    local resources pe_nics
    resources=$(azq resource list -g "$rg")
    pe_nics=$(azq network nic list -g "$rg" --query "[?privateEndpoint != null].id" | jq '[.[] | ascii_downcase]')
    rows+=$(jq -r --argjson state "$state_ids" --argjson nics "$pe_nics" --arg aks "$managed_by" --arg rg "$rg" '
      .[] | (.id | ascii_downcase) as $id
      | [ (if $aks != "" then "aks-managed"
           elif ($state | index($id)) then "managed"
           elif ($nics | index($id)) then "pe-nic"
           else "UNMANAGED" end),
          .type, .name, $rg ] | @tsv' <<<"$resources")$'\n'
  done < <(jq -r '.[] | [.name, .managedBy] | @tsv' <<<"$groups")

  # Tagged resources living outside the environment's groups.
  rows+=$(jq -r --argjson groups "$groups" --argjson state "$state_ids" '
    ($groups | map(.name | ascii_downcase)) as $g
    | .[] | select((.resourceGroup | ascii_downcase) as $r | ($g | index($r)) | not)
    | [ (if ($state | index(.id)) then "managed" else "OUTSIDE" end), .type, .name, .resourceGroup ] | @tsv' <<<"$tagged")

  rows=$(sed '/^$/d' <<<"$rows" | sort)
  if [ -z "$rows" ]; then
    say ""
    say "Nothing is deployed for this environment."
    return 0
  fi
  print_table <<<"$rows"

  local unmanaged outside
  unmanaged=$(grep -c '^UNMANAGED' <<<"$rows" || true)
  outside=$(grep -c '^OUTSIDE' <<<"$rows" || true)
  say ""
  say "Totals: $(cut -f1 <<<"$rows" | sort | uniq -c | awk '{printf "%s%s %s", sep, $1, $2; sep=", "}')"
  say ""

  local status=0
  if [ "$outside" -gt 0 ]; then
    say "> **${outside} OUTSIDE resource(s)** carry this environment's tags but sit in other resource groups. The destroy will not remove them and they will keep billing. Delete them yourself, or move them into the landing zone's groups."
    status=2
  fi
  if [ "$unmanaged" -gt 0 ]; then
    if [ "$ALLOW_UNMANAGED" = "true" ]; then
      say "> **${unmanaged} UNMANAGED resource(s)** will be deleted along with their resource groups (deletion of unmanaged resources is allowed for this run)."
    else
      say "> **${unmanaged} UNMANAGED resource(s)** are not in Terraform state. The provider refuses to delete a resource group that still holds them, so the destroy would stop partway. Delete or import them, or rerun with deletion of unmanaged resources allowed."
      status=2
    fi
  fi
  [ "$status" -eq 0 ] && say "Everything listed above will be removed by the destroy."
  return "$status"
}

post() {
  local deadline=$(( $(date +%s) + POST_WAIT_SECONDS ))
  local groups tagged
  while :; do
    groups=$(landing_zone_groups)
    tagged=$(tagged_resources)
    # Wait only while Azure is still deleting something; anything else is a real leftover.
    if jq -e 'any(.[]; .state == "Deleting")' <<<"$groups" >/dev/null && [ "$(date +%s)" -lt "$deadline" ]; then
      echo "Waiting for resource groups still deleting: $(jq -r '[.[] | select(.state == "Deleting") | .name] | join(", ")' <<<"$groups")"
      sleep 30
      continue
    fi
    break
  done

  say "## Teardown audit (after destroy): ${PROJECT}-${ENVIRONMENT}"
  say ""

  local status=0
  if [ "$(jq length <<<"$groups")" -gt 0 ]; then
    say "**Resource groups still present:**"
    jq -r '.[] | "- \(.name) (\(.state))"' <<<"$groups" | while IFS= read -r l; do say "$l"; done
    status=2
  fi
  if [ "$(jq length <<<"$tagged")" -gt 0 ]; then
    say "**Tagged resources still present:**"
    jq -r '.[] | "\(.type)\t\(.name)\t\(.resourceGroup)"' <<<"$tagged" \
      | sed 's/^/LEFTOVER\t/' | print_table
    status=2
  fi
  if [ -d "${TF_DIR}/.terraform" ]; then
    local shown left
    # `show -json` succeeds with an empty document when no state exists, and
    # fails when state exists but cannot be read. Never report the latter as clean.
    if ! shown=$(terraform -chdir="$TF_DIR" show -json 2>&1); then
      say "**Could not read Terraform state** in \`${TF_DIR}\`, so it is unverified:"
      say '```'
      say "$shown"
      say '```'
      status=2
    elif left=$(jq -r '.. | objects | select(has("address") and has("mode")) | .address' <<<"$shown") \
        && [ -n "$left" ]; then
      say "**Terraform state still tracks:**"
      while IFS= read -r a; do say "- \`$a\`"; done <<<"$left"
      status=2
    fi
  fi

  if [ "$status" -eq 0 ]; then
    say "No resource groups, tagged resources or state entries remain. Nothing from this environment is billing."
  fi
  say ""
  say "Free leftovers (no action needed):"
  report_free_leftovers
  return "$status"
}

case "$MODE" in
  pre) pre ;;
  post) post ;;
  *) echo "usage: $0 pre|post" >&2; exit 1 ;;
esac
