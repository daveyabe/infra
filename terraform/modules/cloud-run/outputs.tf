output "id" {
  description = "The fully qualified resource name of the service"
  value       = google_cloud_run_v2_service.service.id
}

output "name" {
  description = "The name of the Cloud Run service"
  value       = google_cloud_run_v2_service.service.name
}

output "uri" {
  description = "The URI of the deployed service"
  value       = google_cloud_run_v2_service.service.uri
}

output "service_url" {
  description = "The HTTPS URL of the service"
  value       = google_cloud_run_v2_service.service.uri
}
