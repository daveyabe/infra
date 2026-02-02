# IAM Module

# Service Account
resource "google_service_account" "service_account" {
  count = var.create_service_account ? 1 : 0

  account_id   = var.service_account_id
  project      = var.project_id
  display_name = var.service_account_display_name
  description  = var.service_account_description
}

# Service Account IAM bindings (who can use/manage the SA)
resource "google_service_account_iam_member" "service_account_iam" {
  for_each = var.create_service_account ? { for binding in var.service_account_iam : "${binding.role}-${binding.member}" => binding } : {}

  service_account_id = google_service_account.service_account[0].name
  role               = each.value.role
  member             = each.value.member
}

# Project IAM bindings for the service account
resource "google_project_iam_member" "project_iam" {
  for_each = { for binding in var.project_iam_bindings : "${binding.role}-${binding.member}" => binding }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

# Custom IAM Role
resource "google_project_iam_custom_role" "custom_role" {
  count = var.create_custom_role ? 1 : 0

  role_id     = var.custom_role_id
  project     = var.project_id
  title       = var.custom_role_title
  description = var.custom_role_description
  permissions = var.custom_role_permissions
  stage       = var.custom_role_stage
}

# Service Account Key (use sparingly - prefer workload identity)
resource "google_service_account_key" "key" {
  count = var.create_service_account && var.create_sa_key ? 1 : 0

  service_account_id = google_service_account.service_account[0].name
  key_algorithm      = "KEY_ALG_RSA_2048"
}
