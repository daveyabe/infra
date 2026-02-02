# Terraform Infrastructure

This directory contains Terraform configurations for GCP infrastructure.

## Directory Structure

```
terraform/
├── bootstrap/                    # One-time setup (state bucket, Workload Identity)
├── modules/                      # Reusable Terraform modules
│   ├── gce/                     # Compute Engine instances
│   ├── gcs/                     # Cloud Storage buckets
│   ├── vpc/                     # VPC networking
│   ├── iam/                     # IAM roles and service accounts
│   ├── firewall/                # Firewall rules
│   ├── instance_template/       # Instance templates for MIGs
│   ├── mig/                     # Managed Instance Groups
│   └── workload_identity/       # GitHub Actions OIDC authentication
├── projects/                     # Project-specific configurations
│   └── riley/                   # Riley project
│       ├── dev/
│       ├── staging/
│       └── prod/
└── README.md
```

## CIDR Allocation

Each project has a dedicated IP range block to avoid conflicts:

| Project | Environment | CIDR Range    |
|---------|-------------|---------------|
| Riley   | dev         | 10.10.0.0/24  |
| Riley   | staging     | 10.11.0.0/24  |
| Riley   | prod        | 10.12.x.0/24  |

## Getting Started

### Step 1: Bootstrap (One-time Setup)

Run the bootstrap configuration to create:
- GCS bucket for Terraform state
- Workload Identity Federation for GitHub Actions

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project ID

gcloud auth application-default login
terraform init
terraform apply
```

### Step 2: Configure GitHub Secrets

Add these secrets to your GitHub repository (Settings > Secrets > Actions):

| Secret | Value |
|--------|-------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_PROJECT_NUMBER` | Your GCP project number (from GCP Console) |

### Step 3: Enable Remote State

After bootstrap, uncomment the backend configuration in each environment's `backend.tf` and run:

```bash
cd terraform/projects/riley/dev
terraform init -migrate-state
```

### Step 4: CI/CD Workflow

The GitHub Actions workflow (`.github/workflows/terraform.yml`) will:

- **On Pull Request**: Run `terraform plan` and comment results on the PR
- **On Merge to main**: Run `terraform apply` automatically
- **Manual**: Trigger deployments via workflow_dispatch

## Local Development

For local testing (not recommended for production):

```bash
cd projects/riley/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
gcloud auth application-default login
terraform init
terraform plan
terraform apply
```

### Module Usage

Modules are consumed by project/environment configurations:

```hcl
module "vpc" {
  source = "../../../modules/vpc"
  
  project_id   = var.gcp_project_id
  network_name = "${local.project}-${local.env}-vpc"
  region       = var.region
}
```

## Best Practices

- **State Management**: Each project/environment uses a separate state prefix in GCS (e.g., `riley/dev`, `halo/prod`)
- **Variable Files**: Use `terraform.tfvars` for environment-specific values
- **Naming Convention**: Use `{project}-{env}-{resource}` naming pattern
- **Labeling**: All resources are labeled with `project` and `environment` tags
- **CIDR Planning**: Non-overlapping IP ranges per project for potential VPC peering
