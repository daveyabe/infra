output "id" {
  description = "The fully qualified resource name of the repository"
  value       = google_artifact_registry_repository.repo.id
}

output "name" {
  description = "The name of the repository"
  value       = google_artifact_registry_repository.repo.name
}

output "repository_url" {
  description = "Docker registry URL; use as registry host for docker push/pull when format is DOCKER"
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}"
}
