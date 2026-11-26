# Local helpers. CI does the same via .github/workflows/terraform.yml.
ENV ?= dev
DIR := environments/$(ENV)

.PHONY: fmt validate lint scan check init plan lock audit destroy verify-destroyed destroy-bootstrap

fmt:
	terraform fmt -recursive

validate:
	for d in $(DIR) bootstrap; do terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate; done

lint:
	tflint --init --config $(CURDIR)/.tflint.hcl
	tflint --recursive --config $(CURDIR)/.tflint.hcl

scan:
	checkov -d . --framework terraform github_actions --quiet

check: fmt validate lint scan

# Pin provider hashes for every platform the team and CI use, then commit the lock files.
lock:
	for d in $(DIR) bootstrap; do terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
	  terraform -chdir=$$d providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64 -platform=windows_amd64; done

# Requires TFSTATE_RESOURCE_GROUP, TFSTATE_STORAGE_ACCOUNT, TFSTATE_CONTAINER and ARM_SUBSCRIPTION_ID, plus `az login`.
init:
	terraform -chdir=$(DIR) init \
	  -backend-config="resource_group_name=$(TFSTATE_RESOURCE_GROUP)" \
	  -backend-config="storage_account_name=$(TFSTATE_STORAGE_ACCOUNT)" \
	  -backend-config="container_name=$(TFSTATE_CONTAINER)"

plan: init
	terraform -chdir=$(DIR) plan

# Teardown. `audit` is read-only: it lists everything in the environment and flags
# resources Terraform does not manage before you destroy anything. Pass
# ALLOW_UNMANAGED=true to destroy those too, once you have read the list.
ALLOW_UNMANAGED ?= false

audit: init
	TF_DIR=$(DIR) ENVIRONMENT=$(ENV) ALLOW_UNMANAGED=$(ALLOW_UNMANAGED) scripts/teardown-audit.sh pre

destroy: audit
	TF_VAR_allow_unmanaged_resource_deletion=$(ALLOW_UNMANAGED) terraform -chdir=$(DIR) destroy
	$(MAKE) verify-destroyed

verify-destroyed:
	TF_DIR=$(DIR) ENVIRONMENT=$(ENV) scripts/teardown-audit.sh post

# Last of all, once every environment is gone: state account and GitHub identities.
destroy-bootstrap:
	scripts/destroy-bootstrap.sh
