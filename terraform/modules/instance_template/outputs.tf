output "id" {
  description = "The ID of the instance template"
  value       = google_compute_instance_template.template.id
}

output "name" {
  description = "The name of the instance template"
  value       = google_compute_instance_template.template.name
}

output "self_link" {
  description = "The self link of the instance template"
  value       = google_compute_instance_template.template.self_link
}
