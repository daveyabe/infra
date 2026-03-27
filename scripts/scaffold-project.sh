#!/usr/bin/env bash
# Scaffold a new Terraform project for Cloud Run + Artifact Registry deployment.
#
# Creates a new project root under terraform/projects/{name}/{env}/ with the
# standard 5 files (main.tf, variables.tf, outputs.tf, providers.tf, backend.tf).
#
# Usage:
#   ./scripts/scaffold-project.sh <project-name> <environment> [options]
#
# Options:
#   --gcp-project-id ID    GCP project ID (default: n43-studio-sandbox-dev)
#   --region REGION        GCP region (default: northamerica-northeast2)
#   --bucket BUCKET        GCS bucket for Terraform state (default: n43-studio-sandbox-dev-tfstate)
#
# Examples:
#   ./scripts/scaffold-project.sh my-app dev
#   ./scripts/scaffold-project.sh my-app prod --gcp-project-id my-prod-project
#
# After scaffolding:
#   1. Review and customize the generated files
#   2. Commit and PR to the infrastructure repo
#   3. Run allow-caller-repo.sh to authorize external repos to deploy

set -euo pipefail

# Defaults
GCP_PROJECT_ID="n43-studio-sandbox-dev"
REGION="northamerica-northeast2"
STATE_BUCKET="n43-studio-sandbox-dev-tfstate"

usage() {
  echo "Usage: $0 <project-name> <environment> [options]"
  echo ""
  echo "Options:"
  echo "  --gcp-project-id ID    GCP project ID (default: $GCP_PROJECT_ID)"
  echo "  --region REGION        GCP region (default: $REGION)"
  echo "  --bucket BUCKET        GCS bucket for state (default: $STATE_BUCKET)"
  echo ""
  echo "Example:"
  echo "  $0 my-app dev"
  echo "  $0 my-app prod --gcp-project-id my-prod-project"
  exit 1
}

# Parse arguments
[[ $# -lt 2 ]] && usage

PROJECT_NAME="$1"
ENVIRONMENT="$2"
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gcp-project-id) GCP_PROJECT_ID="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --bucket) STATE_BUCKET="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Validate project name (alphanumeric and hyphens only)
if [[ ! "$PROJECT_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "ERROR: Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  echo "WARNING: Environment '$ENVIRONMENT' is not one of: dev, staging, prod"
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Determine repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$REPO_ROOT/terraform/projects/$PROJECT_NAME/$ENVIRONMENT"

if [[ -d "$TARGET_DIR" ]]; then
  echo "ERROR: Directory already exists: $TARGET_DIR"
  exit 1
fi

echo "=== Scaffold Terraform Project ==="
echo "  Project:     $PROJECT_NAME"
echo "  Environment: $ENVIRONMENT"
echo "  GCP Project: $GCP_PROJECT_ID"
echo "  Region:      $REGION"
echo "  State:       gs://$STATE_BUCKET/projects/$PROJECT_NAME/$ENVIRONMENT"
echo "  Target:      $TARGET_DIR"
echo ""

mkdir -p "$TARGET_DIR"

# Generate main.tf
cat > "$TARGET_DIR/main.tf" << EOF
# $PROJECT_NAME - ${ENVIRONMENT^} Environment
#
# Artifact Registry (Docker) + Cloud Run service.

locals {
  project      = "$PROJECT_NAME"
  env          = "$ENVIRONMENT"
  service_name = "$PROJECT_NAME"
  labels = merge(var.common_labels, {
    project     = local.project
    environment = local.env
    service     = local.service_name
  })
  # Full container image: registry URL / image name : tag
  backend_image = "\${module.artifact_registry.repository_url}/\${local.service_name}:\${var.${PROJECT_NAME//-/_}_image_tag}"
}

# Artifact Registry: Docker repository
module "artifact_registry" {
  source = "../../../modules/artifact-registry"

  project_id    = var.gcp_project_id
  location      = var.region
  repository_id = local.service_name
  format        = "DOCKER"
  description   = "Docker images for $PROJECT_NAME (\${local.env})"
  labels        = local.labels
}

# Cloud Run service
module "cloud_run" {
  source = "../../../modules/cloud-run"

  project_id = var.gcp_project_id
  location   = var.region
  name       = local.service_name
  image      = local.backend_image

  port                  = var.${PROJECT_NAME//-/_}_port
  env                   = var.${PROJECT_NAME//-/_}_env
  min_instances         = var.${PROJECT_NAME//-/_}_min_instances
  max_instances         = var.${PROJECT_NAME//-/_}_max_instances
  cpu                   = var.${PROJECT_NAME//-/_}_cpu
  memory                = var.${PROJECT_NAME//-/_}_memory
  allow_unauthenticated = var.${PROJECT_NAME//-/_}_allow_unauthenticated
  timeout               = var.${PROJECT_NAME//-/_}_request_timeout
  labels                = local.labels
}
EOF

# Generate variables.tf
VAR_PREFIX="${PROJECT_NAME//-/_}"
cat > "$TARGET_DIR/variables.tf" << EOF
variable "gcp_project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The default GCP region"
  type        = string
  default     = "$REGION"
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
  }
}

# --- $PROJECT_NAME: image ---
variable "${VAR_PREFIX}_image_tag" {
  description = "Container image tag (e.g. latest, sha-abc123)"
  type        = string
  default     = "latest"
}

# --- $PROJECT_NAME: Cloud Run ---
variable "${VAR_PREFIX}_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "${VAR_PREFIX}_env" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "${VAR_PREFIX}_min_instances" {
  description = "Minimum number of Cloud Run instances (0 for scale-to-zero)"
  type        = number
  default     = 0
}

variable "${VAR_PREFIX}_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "${VAR_PREFIX}_cpu" {
  description = "CPU allocation (e.g. 1, 2)"
  type        = string
  default     = "1"
}

variable "${VAR_PREFIX}_memory" {
  description = "Memory allocation (e.g. 512Mi, 1Gi)"
  type        = string
  default     = "512Mi"
}

variable "${VAR_PREFIX}_allow_unauthenticated" {
  description = "Allow unauthenticated access (public URL)"
  type        = bool
  default     = false
}

variable "${VAR_PREFIX}_request_timeout" {
  description = "Cloud Run request timeout (e.g. 300s)"
  type        = string
  default     = "300s"
}
EOF

# Generate outputs.tf
cat > "$TARGET_DIR/outputs.tf" << EOF
output "artifact_registry_repository_url" {
  description = "Docker registry URL for pushing/pulling images"
  value       = module.artifact_registry.repository_url
}

output "artifact_registry_repository_name" {
  description = "Artifact Registry repository name"
  value       = module.artifact_registry.name
}

output "${VAR_PREFIX}_service_url" {
  description = "HTTPS URL of the Cloud Run service"
  value       = module.cloud_run.service_url
}

output "${VAR_PREFIX}_service_name" {
  description = "Name of the Cloud Run service"
  value       = module.cloud_run.name
}
EOF

# Generate providers.tf
cat > "$TARGET_DIR/providers.tf" << EOF
terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.region
}
EOF

# Generate backend.tf
cat > "$TARGET_DIR/backend.tf" << EOF
# Terraform Backend Configuration
#
# Uses GCS for remote state storage.

terraform {
  backend "gcs" {
    bucket = "$STATE_BUCKET"
    prefix = "projects/$PROJECT_NAME/$ENVIRONMENT"
  }
}
EOF

# Generate terraform.tfvars.example
cat > "$TARGET_DIR/terraform.tfvars.example" << EOF
# Example terraform.tfvars for $PROJECT_NAME/$ENVIRONMENT
#
# Copy to terraform.tfvars and customize values.
# Do NOT commit terraform.tfvars (contains sensitive data).

gcp_project_id = "$GCP_PROJECT_ID"
region         = "$REGION"

# Uncomment and customize as needed:
# ${VAR_PREFIX}_image_tag              = "latest"
# ${VAR_PREFIX}_port                   = 8080
# ${VAR_PREFIX}_min_instances          = 0
# ${VAR_PREFIX}_max_instances          = 10
# ${VAR_PREFIX}_cpu                    = "1"
# ${VAR_PREFIX}_memory                 = "512Mi"
# ${VAR_PREFIX}_allow_unauthenticated  = false
# ${VAR_PREFIX}_request_timeout        = "300s"
# ${VAR_PREFIX}_env = {
#   LOG_LEVEL = "info"
# }
EOF

echo "Created:"
ls -la "$TARGET_DIR"

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Review and customize the generated files in:"
echo "   $TARGET_DIR"
echo ""
echo "2. Test locally:"
echo "   cd $TARGET_DIR"
echo "   terraform init"
echo "   terraform plan -var='gcp_project_id=$GCP_PROJECT_ID'"
echo ""
echo "3. Commit and create a PR to the infrastructure repo"
echo ""
echo "4. After merge, authorize caller repos to deploy:"
echo "   ./scripts/allow-caller-repo.sh <GITHUB_ORG> <GITHUB_REPO>"
echo ""
echo "5. In the caller repo, create a workflow that uses:"
echo "   uses: N43-Studio/infrastructure/.github/workflows/deploy-service.yml@main"
echo "   with:"
echo "     project: $PROJECT_NAME"
echo "     environment: $ENVIRONMENT"
echo "     action: apply"
echo "     image_tag: \${{ github.sha }}"
echo ""
