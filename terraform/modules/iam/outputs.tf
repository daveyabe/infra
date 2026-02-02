output "service_account_email" {
  description = "The email of the service account"
  value       = var.create_service_account ? google_service_account.service_account[0].email : null
}

output "service_account_id" {
  description = "The ID of the service account"
  value       = var.create_service_account ? google_service_account.service_account[0].id : null
}

output "service_account_name" {
  description = "The fully-qualified name of the service account"
  value       = var.create_service_account ? google_service_account.service_account[0].name : null
}

output "service_account_key" {
  description = "The private key of the service account (base64 encoded)"
  value       = var.create_service_account && var.create_sa_key ? google_service_account_key.key[0].private_key : null
  sensitive   = true
}

output "custom_role_id" {
  description = "The ID of the custom role"
  value       = var.create_custom_role ? google_project_iam_custom_role.custom_role[0].id : null
}

output "custom_role_name" {
  description = "The name of the custom role"
  value       = var.create_custom_role ? google_project_iam_custom_role.custom_role[0].name : null
}
