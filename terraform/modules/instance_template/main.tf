# Instance Template Module

resource "google_compute_instance_template" "template" {
  name_prefix  = "${var.name_prefix}-"
  project      = var.project_id
  region       = var.region
  machine_type = var.machine_type

  tags = var.network_tags

  labels = var.labels

  disk {
    source_image = var.source_image
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    auto_delete  = true
    boot         = true
  }

  dynamic "disk" {
    for_each = var.additional_disks
    content {
      disk_size_gb = disk.value.size_gb
      disk_type    = lookup(disk.value, "type", "pd-standard")
      auto_delete  = lookup(disk.value, "auto_delete", true)
      boot         = false
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {
        // Ephemeral public IP
      }
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }

  metadata = merge(
    var.metadata,
    var.startup_script != null ? { startup-script = var.startup_script } : {}
  )

  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = var.automatic_restart
    on_host_maintenance = var.preemptible ? "TERMINATE" : "MIGRATE"
    preemptible         = var.preemptible
  }

  lifecycle {
    create_before_destroy = true
  }
}
