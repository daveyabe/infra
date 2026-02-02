output "network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "The self link of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "subnets" {
  description = "Map of subnet names to their attributes"
  value = {
    for k, v in google_compute_subnetwork.subnets : k => {
      id         = v.id
      name       = v.name
      self_link  = v.self_link
      region     = v.region
      ip_range   = v.ip_cidr_range
      gateway_ip = v.gateway_address
    }
  }
}

output "router_id" {
  description = "The ID of the Cloud Router (if created)"
  value       = var.create_nat_gateway ? google_compute_router.router[0].id : null
}
