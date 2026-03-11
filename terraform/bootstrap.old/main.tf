# Bootstrap Configuration
# Run this ONCE manually to set up:
# 1. Terraform state bucket
# 2. Workload Identity Federation for GitHub Actions
#
# Usage:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply

locals {
  project_id = var.gcp_project_id
  region     = var.region
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = local.project_id
  service            = each.value
  disable_on_destroy = false
}

# Terraform state bucket
resource "google_storage_bucket" "tfstate" {
  name     = "${local.project_id}-tfstate"
  project  = local.project_id
  location = local.region

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 5
    }
  }

  labels = {
    managed_by = "terraform"
    purpose    = "tfstate"
  }
}

# Workload Identity Federation for GitHub Actions
module "workload_identity" {
  source = "../modules/workload_identity"

  project_id = local.project_id
  github_org = var.github_org
  github_repo = var.github_repo

  terraform_roles = [
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.roleAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/storage.admin",
    "roles/resourcemanager.projectIamAdmin",
  ]

  depends_on = [google_project_service.apis]
}
