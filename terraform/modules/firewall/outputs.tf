output "internal_firewall_id" {
  description = "The ID of the internal firewall rule"
  value       = var.allow_internal ? google_compute_firewall.allow_internal[0].id : null
}

output "iap_ssh_firewall_id" {
  description = "The ID of the IAP SSH firewall rule"
  value       = var.allow_iap_ssh ? google_compute_firewall.allow_iap_ssh[0].id : null
}

output "health_check_firewall_id" {
  description = "The ID of the health check firewall rule"
  value       = var.allow_health_check ? google_compute_firewall.allow_health_check[0].id : null
}

output "lb_firewall_id" {
  description = "The ID of the load balancer firewall rule"
  value       = var.allow_load_balancer ? google_compute_firewall.allow_lb[0].id : null
}
