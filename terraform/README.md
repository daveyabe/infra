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

## Cross-Repo Deployment (Reusable Workflow)

External repositories can deploy Cloud Run services by calling the reusable workflow in this repo. This centralizes Terraform configuration and state while allowing each app repo to trigger its own deployments.

### How It Works

```
┌─────────────────────┐     workflow_call     ┌──────────────────────────────────┐
│   Caller Repo CI    │ ─────────────────────>│ infrastructure/deploy-service.yml│
│  (builds image,     │   project, env,       │  (checks out this repo,          │
│   pushes to AR)     │   image_tag, action   │   runs terraform plan/apply)     │
└─────────────────────┘                       └──────────────────────────────────┘
```

1. **Caller repo** builds and pushes a Docker image to Artifact Registry
2. **Caller repo** calls the reusable workflow with the image tag
3. **Reusable workflow** checks out this infrastructure repo
4. **Reusable workflow** runs Terraform with the new image tag
5. **Cloud Run** deploys the new image

### One-Time Onboarding (New Project)

1. **Scaffold the project** (creates Terraform files):
   ```bash
   ./scripts/scaffold-project.sh my-app dev
   ```

2. **Review and customize** the generated files in `terraform/projects/my-app/dev/`

3. **Create a PR** to this infrastructure repo and get it merged

4. **Apply the initial Terraform** (creates Artifact Registry + Cloud Run):
   ```bash
   cd terraform/projects/my-app/dev
   terraform init
   terraform apply -var="gcp_project_id=YOUR_PROJECT"
   ```

5. **Authorize the caller repo** to use the reusable workflow:
   ```bash
   ./scripts/allow-caller-repo.sh N43-Studio my-app
   ```

6. **Add secrets** to the caller repo (or use org-level secrets):
   - `GCP_PROJECT_ID`: Your GCP project ID
   - `GCP_PROJECT_NUMBER`: Your GCP project number

### Caller Workflow Example

In your application repo, create `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.meta.outputs.tags }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/${{ secrets.GCP_PROJECT_NUMBER }}/locations/global/workloadIdentityPools/github-pool/providers/github-provider
          service_account: terraform-github-actions@${{ secrets.GCP_PROJECT_ID }}.iam.gserviceaccount.com
      
      - name: Configure Docker
        run: gcloud auth configure-docker northamerica-northeast2-docker.pkg.dev
      
      - name: Build and push
        id: meta
        run: |
          IMAGE="northamerica-northeast2-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/my-app/my-app:${{ github.sha }}"
          docker build -t $IMAGE .
          docker push $IMAGE
          echo "tags=${{ github.sha }}" >> $GITHUB_OUTPUT

  deploy:
    needs: build
    uses: N43-Studio/infrastructure/.github/workflows/deploy-service.yml@main
    with:
      project: my-app
      environment: dev
      action: apply
      image_tag: ${{ needs.build.outputs.image_tag }}
    secrets: inherit
```

### What the Reusable Workflow Does (and Doesn't)

**Does:**
- Runs `terraform plan` or `terraform apply` for the specified project/environment
- Passes the `image_tag` as a Terraform variable (`-var="project_image_tag=..."`)
- Returns outputs: `service_url` and `registry_url`

**Doesn't:**
- Build Docker images (caller repo does this)
- Push images to Artifact Registry (caller repo does this)
- Create new project roots (use `scaffold-project.sh` for that)

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/scaffold-project.sh` | Generate a new `terraform/projects/{name}/{env}/` root |
| `scripts/allow-caller-repo.sh` | Authorize a repo to call the reusable workflow (WIF binding) |

## Best Practices

- **State Management**: Each project/environment uses a separate state prefix in GCS (e.g., `riley/dev`, `halo/prod`)
- **Variable Files**: Use `terraform.tfvars` for environment-specific values
- **Naming Convention**: Use `{project}-{env}-{resource}` naming pattern
- **Labeling**: All resources are labeled with `project` and `environment` tags
- **CIDR Planning**: Non-overlapping IP ranges per project for potential VPC peering
