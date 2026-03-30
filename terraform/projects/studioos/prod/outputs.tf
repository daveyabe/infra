output "artifact_registry_repository_url" {
  description = "Docker registry URL for pushing/pulling images"
  value       = module.artifact_registry.repository_url
}

output "artifact_registry_repository_name" {
  description = "Artifact Registry repository name"
  value       = module.artifact_registry.name
}

output "studioos_service_url" {
  description = "HTTPS URL of the Cloud Run service"
  value       = module.cloud_run.service_url
}

output "studioos_service_name" {
  description = "Name of the Cloud Run service"
  value       = module.cloud_run.name
}
