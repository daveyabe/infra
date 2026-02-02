# Firewall Rules Module

# Allow internal traffic within VPC
resource "google_compute_firewall" "allow_internal" {
  count = var.allow_internal ? 1 : 0

  name    = "${var.network_name}-allow-internal"
  project = var.project_id
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = var.internal_ranges
  priority      = 1000
}

# Allow SSH from IAP
resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.allow_iap_ssh ? 1 : 0

  name    = "${var.network_name}-allow-iap-ssh"
  project = var.project_id
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = var.ssh_target_tags
  priority      = 1000
}

# Allow health checks from Google
resource "google_compute_firewall" "allow_health_check" {
  count = var.allow_health_check ? 1 : 0

  name    = "${var.network_name}-allow-health-check"
  project = var.project_id
  network = var.network

  allow {
    protocol = "tcp"
    ports    = var.health_check_ports
  }

  # Google health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["allow-health-check"]
  priority      = 1000
}

# Allow HTTP(S) from load balancer
resource "google_compute_firewall" "allow_lb" {
  count = var.allow_load_balancer ? 1 : 0

  name    = "${var.network_name}-allow-lb"
  project = var.project_id
  network = var.network

  allow {
    protocol = "tcp"
    ports    = var.lb_ports
  }

  # Google load balancer IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = var.lb_target_tags
  priority      = 1000
}

# Custom firewall rules
resource "google_compute_firewall" "custom" {
  for_each = { for rule in var.custom_rules : rule.name => rule }

  name        = each.value.name
  project     = var.project_id
  network     = var.network
  description = lookup(each.value, "description", null)

  dynamic "allow" {
    for_each = lookup(each.value, "allow", [])
    content {
      protocol = allow.value.protocol
      ports    = lookup(allow.value, "ports", null)
    }
  }

  dynamic "deny" {
    for_each = lookup(each.value, "deny", [])
    content {
      protocol = deny.value.protocol
      ports    = lookup(deny.value, "ports", null)
    }
  }

  source_ranges      = lookup(each.value, "source_ranges", null)
  source_tags        = lookup(each.value, "source_tags", null)
  target_tags        = lookup(each.value, "target_tags", null)
  priority           = lookup(each.value, "priority", 1000)
  direction          = lookup(each.value, "direction", "INGRESS")
  destination_ranges = lookup(each.value, "destination_ranges", null)
}
