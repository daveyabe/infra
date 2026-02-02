# Managed Instance Group Module

resource "google_compute_instance_group_manager" "mig" {
  name    = var.name
  project = var.project_id
  zone    = var.zone

  base_instance_name = var.base_instance_name

  version {
    instance_template = var.instance_template
    name              = "primary"
  }

  target_size = var.autoscaling_enabled ? null : var.target_size

  dynamic "named_port" {
    for_each = var.named_ports
    content {
      name = named_port.value.name
      port = named_port.value.port
    }
  }

  dynamic "auto_healing_policies" {
    for_each = var.create_health_check || var.health_check != null ? [1] : []
    content {
      health_check      = var.create_health_check ? google_compute_health_check.health_check[0].self_link : var.health_check
      initial_delay_sec = var.health_check_initial_delay
    }
  }

  update_policy {
    type                           = var.update_policy_type
    minimal_action                 = var.update_policy_minimal_action
    most_disruptive_allowed_action = var.update_policy_most_disruptive_action
    max_surge_fixed                = var.max_surge_fixed
    max_unavailable_fixed          = var.max_unavailable_fixed
    replacement_method             = var.replacement_method
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Autoscaler (optional)
resource "google_compute_autoscaler" "autoscaler" {
  count = var.autoscaling_enabled ? 1 : 0

  name    = "${var.name}-autoscaler"
  project = var.project_id
  zone    = var.zone
  target  = google_compute_instance_group_manager.mig.id

  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = var.cooldown_period

    dynamic "cpu_utilization" {
      for_each = var.cpu_utilization_target != null ? [1] : []
      content {
        target = var.cpu_utilization_target
      }
    }

    dynamic "metric" {
      for_each = var.custom_metrics
      content {
        name   = metric.value.name
        type   = metric.value.type
        target = metric.value.target
      }
    }

    dynamic "scale_in_control" {
      for_each = var.scale_in_control_enabled ? [1] : []
      content {
        max_scaled_in_replicas {
          fixed = var.scale_in_max_replicas
        }
        time_window_sec = var.scale_in_time_window
      }
    }
  }
}

# Health Check (optional)
resource "google_compute_health_check" "health_check" {
  count = var.create_health_check ? 1 : 0

  name    = "${var.name}-health-check"
  project = var.project_id

  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = var.health_check_type == "HTTP" ? [1] : []
    content {
      port         = var.health_check_port
      request_path = var.health_check_path
    }
  }

  dynamic "https_health_check" {
    for_each = var.health_check_type == "HTTPS" ? [1] : []
    content {
      port         = var.health_check_port
      request_path = var.health_check_path
    }
  }

  dynamic "tcp_health_check" {
    for_each = var.health_check_type == "TCP" ? [1] : []
    content {
      port = var.health_check_port
    }
  }
}
