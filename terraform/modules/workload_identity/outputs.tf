output "workload_identity_pool_name" {
  description = "The full name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.github_pool.name
}

output "workload_identity_provider_name" {
  description = "The full name of the Workload Identity Provider"
  value       = google_iam_workload_identity_pool_provider.github_provider.name
}

output "service_account_email" {
  description = "The email of the Terraform service account"
  value       = google_service_account.terraform.email
}

output "github_actions_config" {
  description = "Configuration values for GitHub Actions workflow"
  value = {
    workload_identity_provider = google_iam_workload_identity_pool_provider.github_provider.name
    service_account            = google_service_account.terraform.email
  }
}
