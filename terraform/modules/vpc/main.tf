# VPC Network Module

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = var.routing_mode
}

resource "google_compute_subnetwork" "subnets" {
  for_each = { for subnet in var.subnets : subnet.name => subnet }

  name                     = each.value.name
  project                  = var.project_id
  region                   = each.value.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = each.value.ip_cidr_range
  private_ip_google_access = lookup(each.value, "private_ip_google_access", true)

  dynamic "secondary_ip_range" {
    for_each = lookup(each.value, "secondary_ip_ranges", [])
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }
}

resource "google_compute_router" "router" {
  count = var.create_nat_gateway ? 1 : 0

  name    = "${var.network_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count = var.create_nat_gateway ? 1 : 0

  name                               = "${var.network_name}-nat"
  project                            = var.project_id
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
