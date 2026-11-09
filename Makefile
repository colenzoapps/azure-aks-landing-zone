# Local helpers. CI does the same via .github/workflows/terraform.yml.
ENV ?= dev
DIR := environments/$(ENV)

.PHONY: fmt validate lint scan check init plan lock

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
