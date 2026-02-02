# Workload Identity Federation Module
# Enables keyless authentication from GitHub Actions to GCP

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions"
}

# Workload Identity Provider (GitHub OIDC)
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub Provider"
  description                        = "OIDC provider for GitHub Actions"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only allow tokens from GitHub Actions
  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service Account for Terraform
resource "google_service_account" "terraform" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Terraform GitHub Actions"
  description  = "Service account for Terraform executed via GitHub Actions"
}

# Allow GitHub Actions to impersonate the service account
resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# Grant the service account permissions to manage infrastructure
resource "google_project_iam_member" "terraform_permissions" {
  for_each = toset(var.terraform_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}
