output "artifact_registry_repository_url" {
  description = "Docker registry URL for pushing/pulling riley backend images"
  value       = module.artifact_registry.repository_url
}

output "artifact_registry_repository_name" {
  description = "Artifact Registry repository name"
  value       = module.artifact_registry.name
}

output "riley_backend_service_url" {
  description = "HTTPS URL of the riley backend Cloud Run service"
  value       = module.cloud_run.service_url
}

output "riley_backend_service_name" {
  description = "Name of the Cloud Run service"
  value       = module.cloud_run.name
}

output "notion_backup_bucket_name" {
  description = "GCS bucket storing nightly Notion workspace backups"
  value       = module.notion_backup_bucket.bucket_name
}

output "notion_backup_bucket_url" {
  description = "GCS URL for the Notion backup bucket"
  value       = module.notion_backup_bucket.bucket_url
}
