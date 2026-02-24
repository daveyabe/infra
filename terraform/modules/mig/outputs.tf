output "instance_group" {
  description = "The instance group URL"
  value       = google_compute_instance_group_manager.mig.instance_group
}

output "id" {
  description = "The ID of the managed instance group"
  value       = google_compute_instance_group_manager.mig.id
}

output "name" {
  description = "The name of the managed instance group"
  value       = google_compute_instance_group_manager.mig.name
}

output "self_link" {
  description = "The self link of the managed instance group"
  value       = google_compute_instance_group_manager.mig.self_link
}

output "health_check_id" {
  description = "The ID of the health check (if created)"
  value       = var.create_health_check ? google_compute_health_check.health_check[0].id : null
}

output "health_check_self_link" {
  description = "The self link of the health check (if created)"
  value       = var.create_health_check ? google_compute_health_check.health_check[0].self_link : null
}
