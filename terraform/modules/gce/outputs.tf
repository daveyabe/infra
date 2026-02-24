output "instance_id" {
  description = "The ID of the compute instance"
  value       = google_compute_instance.instance.id
}

output "instance_name" {
  description = "The name of the compute instance"
  value       = google_compute_instance.instance.name
}

output "instance_self_link" {
  description = "The self link of the compute instance"
  value       = google_compute_instance.instance.self_link
}

output "internal_ip" {
  description = "The internal IP address of the instance"
  value       = google_compute_instance.instance.network_interface[0].network_ip
}

output "external_ip" {
  description = "The external IP address of the instance (if enabled)"
  value       = var.enable_external_ip ? google_compute_instance.instance.network_interface[0].access_config[0].nat_ip : null
}

output "zone" {
  description = "The zone of the instance"
  value       = google_compute_instance.instance.zone
}
