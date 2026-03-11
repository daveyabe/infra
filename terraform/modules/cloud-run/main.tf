# Cloud Run Service Module

resource "google_cloud_run_v2_service" "service" {
  name     = var.name
  location = var.location
  project  = var.project_id
  labels   = var.labels

  template {
    timeout = var.timeout

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      ports {
        container_port = var.port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }
    }

    dynamic "service_account" {
      for_each = var.service_account_email != null ? [1] : []
      content {
        email = var.service_account_email
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = google_cloud_run_v2_service.service.project
  location = google_cloud_run_v2_service.service.location
  name     = google_cloud_run_v2_service.service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
