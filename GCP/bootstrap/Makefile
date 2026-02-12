# GCP Bootstrap — full project provisioning
#
# Required: PROJECT_ID, BILLING_ACCOUNT_ID (for full provisioning)
# Optional: PROJECT_NAME, ORGANIZATION_ID, GITHUB_ORG, GITHUB_REPO, EXTRA_APIS
#
# Quick start (full run):
#   make all PROJECT_ID=my-project BILLING_ACCOUNT_ID=01ABCD-23EF56-789GHI
#
# Or run steps individually (see targets below).

SHELL := /bin/bash
BOOTSTRAP_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# --- Required (set on command line or in env) ---
PROJECT_ID        ?=
BILLING_ACCOUNT_ID ?=

# --- Optional (with defaults matching the scripts) ---
PROJECT_NAME      ?= $(PROJECT_ID)
ORGANIZATION_ID   ?=
GITHUB_ORG        ?= N43-Studio
GITHUB_REPO       ?= infrastructure
SERVICE_ACCOUNT_ID ?= terraform-github-actions
EXTRA_APIS        ?=

# Ensure PROJECT_ID is set for targets that need it
define require_project
  @[[ -n "$(PROJECT_ID)" ]] || { echo "Error: PROJECT_ID is required. Example: make $1 PROJECT_ID=my-project"; exit 1; }
endef

define require_billing
  @[[ -n "$(BILLING_ACCOUNT_ID)" ]] || { echo "Error: BILLING_ACCOUNT_ID is required. Example: make $1 PROJECT_ID=my-project BILLING_ACCOUNT_ID=01ABCD-23EF56-789GHI"; exit 1; }
endef

.DEFAULT_GOAL := help
.PHONY: help all provision link-billing enable-apis sa-account workload-identity

help:
	@echo "GCP Bootstrap — full project provisioning"
	@echo ""
	@echo "Required (command line or env):"
	@echo "  PROJECT_ID             GCP project ID (e.g. my-org-dev-12345)"
	@echo "  BILLING_ACCOUNT_ID      Billing account ID for link-billing / all (e.g. 01ABCD-23EF56-789GHI)"
	@echo ""
	@echo "Optional:"
	@echo "  PROJECT_NAME           Display name (default: PROJECT_ID)"
	@echo "  ORGANIZATION_ID        Org ID for project create (e.g. 833531661158)"
	@echo "  GITHUB_ORG             GitHub org for WIF (default: N43-Studio)"
	@echo "  GITHUB_REPO            GitHub repo for WIF (default: infrastructure)"
	@echo "  SERVICE_ACCOUNT_ID     WIF service account (default: terraform-github-actions)"
	@echo "  EXTRA_APIS             Extra APIs for enable-apis (space-separated)"
	@echo ""
	@echo "Targets (run in order for fresh project):"
	@echo "  all                    Run all steps: provision -> link-billing -> enable-apis -> sa-account -> workload-identity"
	@echo "  provision              Create project (01-provision-project.sh)"
	@echo "  link-billing           Link billing account (02-link-billing.sh)"
	@echo "  enable-apis            Enable default + AI APIs (03-enable-apis.sh)"
	@echo "  sa-account             Create Terraform SA and roles (04-SA-account-TF.sh)"
	@echo "  workload-identity      Set up WIF for GitHub Actions (05-workload-identity-federation-github.sh)"
	@echo ""
	@echo "Examples:"
	@echo "  make all PROJECT_ID=my-proj BILLING_ACCOUNT_ID=01ABCD-23EF56-789GHI"
	@echo "  make provision PROJECT_ID=my-proj ORGANIZATION_ID=833531661158"
	@echo "  make enable-apis PROJECT_ID=my-proj EXTRA_APIS=container.googleapis.com"

# Full pipeline: all steps in order
all: provision link-billing enable-apis sa-account workload-identity
	@echo ""
	@echo "=== Bootstrap complete for project: $(PROJECT_ID) ==="

# 01 — Create project (idempotent)
provision:
	$(call require_project,provision)
	$(BOOTSTRAP_DIR)01-provision-project.sh "$(PROJECT_ID)" "$(PROJECT_NAME)" "$(ORGANIZATION_ID)"

# 02 — Link billing (required for APIs and paid resources)
link-billing: provision
	$(call require_project,link-billing)
	$(call require_billing,link-billing)
	$(BOOTSTRAP_DIR)02-link-billing.sh "$(PROJECT_ID)" "$(BILLING_ACCOUNT_ID)"

# 03 — Enable APIs
enable-apis: link-billing
	$(call require_project,enable-apis)
	$(BOOTSTRAP_DIR)03-enable-apis.sh "$(PROJECT_ID)" $(if $(EXTRA_APIS),$(EXTRA_APIS))

# 04 — Terraform service account and IAM roles
sa-account: enable-apis
	$(call require_project,sa-account)
	$(BOOTSTRAP_DIR)04-SA-account-TF.sh "$(PROJECT_ID)"

# 05 — Workload Identity Federation for GitHub Actions
workload-identity: sa-account
	$(call require_project,workload-identity)
	$(BOOTSTRAP_DIR)05-workload-identity-federation-github.sh "$(PROJECT_ID)" "$(GITHUB_ORG)" "$(GITHUB_REPO)" "$(SERVICE_ACCOUNT_ID)"
