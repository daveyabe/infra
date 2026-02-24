# GCE Instance Module

resource "google_compute_instance" "instance" {
  name         = var.instance_name
  project      = var.project_id
  zone         = var.zone
  machine_type = var.machine_type

  tags = var.network_tags

  labels = var.labels

  boot_disk {
    initialize_params {
      image = var.boot_disk_image
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
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

  allow_stopping_for_update = var.allow_stopping_for_update

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }
}

resource "google_compute_disk" "additional_disks" {
  for_each = { for disk in var.additional_disks : disk.name => disk }

  name    = each.value.name
  project = var.project_id
  zone    = var.zone
  type    = lookup(each.value, "type", "pd-standard")
  size    = each.value.size_gb

  labels = var.labels
}

resource "google_compute_attached_disk" "attached_disks" {
  for_each = { for disk in var.additional_disks : disk.name => disk }

  disk     = google_compute_disk.additional_disks[each.key].id
  instance = google_compute_instance.instance.id
}
