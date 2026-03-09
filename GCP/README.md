# GCP Bootstrap — Full Project Provisioning

This directory contains scripts and a Makefile to provision a new GCP project end-to-end: create the project, link billing, enable APIs, create the Terraform service account used by GitHub Actions (via WIF), and set up Workload Identity Federation.

## Overview

The bootstrap runs **five steps** in order. Each step is idempotent where possible, so you can re-run safely.

| Step | Script | Purpose |
|------|--------|---------|
| 1 | `01-provision-project.sh` | Create the GCP project (or no-op if it exists) and set default labels. |
| 2 | `02-link-billing.sh` | Link a billing account (required for APIs and paid resources). |
| 3 | `03-enable-apis.sh` | Enable default + AI APIs (and optional extras). |
| 4 | `05-workload-identity-federation-github.sh` | Create WIF SA (`terraform-github-actions`), grant Terraform roles, set up WIF for GitHub Actions (no SA keys). |
| 5 | `06-increase-service-quotas.sh` | Request common quota increases (Compute CPUs, instances, IPs). |

---

## Prerequisites

- **gcloud CLI** installed and on your `PATH`.
- **Authentication:** `gcloud auth login` (or a service account with sufficient permissions).
- **Permissions:** Ability to create projects, link billing, enable APIs, and manage IAM in the project (and org, if using `ORGANIZATION_ID`).

---

## Variables

Pass these to `make` on the command line or set them in the environment.

### Required (for full provisioning)

| Variable | Description | Example |
|----------|-------------|---------|
| `PROJECT_ID` | GCP project ID (globally unique). | `my-org-dev-12345` |
| `BILLING_ACCOUNT_ID` | Billing account to link to the project. | `01ABCD-23EF56-789GHI` |

List billing accounts: `gcloud billing accounts list`

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_NAME` | Display name for the project. | `PROJECT_ID` |
| `ORGANIZATION_ID` | Organization ID; project is created under this org if set. | (none) |
| `PROJECT_LABELS` | Project labels (comma-separated `key=value`). | `team=devops,environment=dev` |
| `GITHUB_ORG` | GitHub organization for Workload Identity Federation. | `N43-Studio` |
| `GITHUB_REPO` | GitHub repository for WIF. | `infrastructure` |
| `SERVICE_ACCOUNT_ID` | Service account used by GitHub Actions via WIF. | `terraform-github-actions` |
| `EXTRA_APIS` | Additional APIs to enable (space-separated). | (none) |
| `QUOTA_REGIONS` | Regions for quota increase requests (space-separated). | `us-central1 us-east1 northamerica-northeast2` |

---

## Makefile Targets

Run from this directory (`GCP/bootstrap/`):

```bash
make help   # Show usage (default)
make all    # Run all five steps in order
```

### Pipeline and dependencies

- **`all`** — Runs: `provision` → `link-billing` → `enable-apis` → `workload-identity` → `increase-quotas`.
- Each target depends on the previous one. Running e.g. `make workload-identity` will run `provision`, `link-billing`, and `enable-apis` first.

| Target | What it runs |
|--------|----------------|
| `provision` | `01-provision-project.sh` — create project |
| `link-billing` | `02-link-billing.sh` — link billing account |
| `enable-apis` | `03-enable-apis.sh` — enable APIs |
| `workload-identity` | `05-workload-identity-federation-github.sh` — WIF + Terraform SA and roles |
| `increase-quotas` | `06-increase-service-quotas.sh` — request common quota increases |

The Makefile checks that `PROJECT_ID` (and `BILLING_ACCOUNT_ID` where needed) are set and prints a short error if not.

---

## Examples

### Full provisioning

```bash
cd GCP/bootstrap

make all PROJECT_ID=my-proj BILLING_ACCOUNT_ID=01ABCD-23EF56-789GHI
```

### With organization and display name

```bash
make all PROJECT_ID=my-proj BILLING_ACCOUNT_ID=01ABCD-23EF56-789GHI \
  ORGANIZATION_ID=833531661158 \
  PROJECT_NAME="My Project"
```

### Single steps (dependencies still run)

```bash
make provision PROJECT_ID=my-proj
make link-billing PROJECT_ID=my-proj BILLING_ACCOUNT_ID=01ABCD-23EF56-789GHI
make enable-apis PROJECT_ID=my-proj
make workload-identity PROJECT_ID=my-proj GITHUB_ORG=my-org GITHUB_REPO=my-repo
make increase-quotas PROJECT_ID=my-proj QUOTA_REGIONS="us-central1 northamerica-northeast2"
```

### Extra APIs

```bash
make enable-apis PROJECT_ID=my-proj EXTRA_APIS=container.googleapis.com
# or multiple:
make enable-apis PROJECT_ID=my-proj EXTRA_APIS=container.googleapis.com bigquery.googleapis.com
```

### From repository root

```bash
make -C GCP/bootstrap all PROJECT_ID=my-proj BILLING_ACCOUNT_ID=01ABCD-23EF56-789GHI
```

---

## Running the scripts without Make

You can call the scripts directly if you prefer.

1. **Provision project**  
   `./01-provision-project.sh <PROJECT_ID> [PROJECT_NAME] [ORGANIZATION_ID]`

2. **Link billing**  
   `./02-link-billing.sh <PROJECT_ID> <BILLING_ACCOUNT_ID>`

3. **Enable APIs**  
   `./03-enable-apis.sh <PROJECT_ID> [API_NAME ...]`

4. **Workload Identity Federation (and Terraform SA + roles)**  
   `./05-workload-identity-federation-github.sh <PROJECT_ID> <GITHUB_ORG> <GITHUB_REPO> [SERVICE_ACCOUNT_ID]`

5. **Increase service quotas**  
   `./06-increase-service-quotas.sh <PROJECT_ID> [REGION ...]`  
   Submits quota increase requests for Compute (CPUs, instances, in-use IPs per region). Requires `gcloud components install beta`. Requests are reviewed by Google (typically 1–2 business days).

Run them in this order. Steps 1–3 are idempotent where applicable; step 4 creates the WIF pool/provider and SA if they don’t exist and grants Terraform roles; step 5 is idempotent (create/update preferences).

---

## After bootstrap

- **GitHub Actions:** Step 4 (05 script) prints `WORKLOAD_IDENTITY_PROVIDER` and `SERVICE_ACCOUNT`. Use them in your workflow with `google-github-actions/auth` and `workload_identity_provider` / `service_account` (see the script output for an example job snippet). The same SA is used for Terraform runs from GitHub (no keys).
- **Optional — local Terraform:** If you need a separate key-based SA for local runs, use `04-SA-account-TF.sh` (creates `terraform-pro` and grants the same roles). Not required for the default GitHub-based flow.

---

## Troubleshooting

- **"Service account ... doesn't exist"** — Ensure step 3 (enable-apis) has run so the IAM API is enabled, then run step 4 (05 script) again. The script creates the SA if missing.
- **“Project not found”** — Run step 1 (provision) first and use the same `PROJECT_ID` in later steps.
- **Billing or API errors** — Confirm the billing account ID and that you have permission to link it and to enable APIs on the project.
