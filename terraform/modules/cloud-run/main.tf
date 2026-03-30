# Cloud Run Service Module

data "google_project" "this" {
  count      = length(var.cloud_sql_connection_names) > 0 ? 1 : 0
  project_id = var.project_id
}

locals {
  cloud_sql_runtime_sa = length(var.cloud_sql_connection_names) > 0 ? "${data.google_project.this[0].number}-compute@developer.gserviceaccount.com" : null
}

# Cloud Run’s default runtime identity (default compute SA) must open Cloud SQL.
resource "google_project_iam_member" "cloud_run_cloudsql_client" {
  count   = length(var.cloud_sql_connection_names) > 0 ? 1 : 0
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.cloud_sql_runtime_sa}"
}

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

    dynamic "volumes" {
      for_each = length(var.cloud_sql_connection_names) > 0 ? [1] : []
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = var.cloud_sql_connection_names
        }
      }
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

      dynamic "volume_mounts" {
        for_each = length(var.cloud_sql_connection_names) > 0 ? [1] : []
        content {
          name       = "cloudsql"
          mount_path = "/cloudsql"
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
  }

  depends_on = [google_project_iam_member.cloud_run_cloudsql_client]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = google_cloud_run_v2_service.service.project
  location = google_cloud_run_v2_service.service.location
  name     = google_cloud_run_v2_service.service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
