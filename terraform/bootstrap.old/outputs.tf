output "tfstate_bucket" {
  description = "The name of the Terraform state bucket"
  value       = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "The Workload Identity Provider name (use in GitHub Actions)"
  value       = module.workload_identity.workload_identity_provider_name
}

output "service_account_email" {
  description = "The Terraform service account email (use in GitHub Actions)"
  value       = module.workload_identity.service_account_email
}

output "github_secrets_instructions" {
  description = "Instructions for setting up GitHub secrets"
  value       = <<-EOT
    
    Add these secrets to your GitHub repository:
    
    1. GCP_PROJECT_ID: ${var.gcp_project_id}
    2. GCP_PROJECT_NUMBER: (find in GCP Console > Project Settings)
    
    The workflow will use these values:
    - Workload Identity Provider: ${module.workload_identity.workload_identity_provider_name}
    - Service Account: ${module.workload_identity.service_account_email}
    
  EOT
}
