# Cloud Run Service Module

locals {
  # Direct VPC egress (no Serverless VPC Access connector): private RFC1918 traffic uses the VPC.
  direct_vpc_egress_enabled = var.direct_vpc_subnetwork != ""
  # Unix socket volume and/or Direct VPC to private IP both need Cloud SQL Client on the runtime SA.
  cloud_run_needs_cloudsql_client = length(var.cloud_sql_connection_names) > 0 || local.direct_vpc_egress_enabled
}

data "google_project" "this" {
  count      = local.cloud_run_needs_cloudsql_client ? 1 : 0
  project_id = var.project_id
}

locals {
  cloud_sql_runtime_sa = local.cloud_run_needs_cloudsql_client ? "${data.google_project.this[0].number}-compute@developer.gserviceaccount.com" : null
}

# Cloud Run’s default runtime identity (default compute SA) must open Cloud SQL (unix socket and/or private IP via Direct VPC).
resource "google_project_iam_member" "cloud_run_cloudsql_client" {
  count   = local.cloud_run_needs_cloudsql_client ? 1 : 0
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

    # Direct VPC egress: reach private IPs (e.g. Cloud SQL private IP) without a VPC connector resource.
    dynamic "vpc_access" {
      for_each = local.direct_vpc_egress_enabled ? [1] : []
      content {
        egress = var.vpc_access_egress
        network_interfaces {
          network    = var.direct_vpc_network != "" ? var.direct_vpc_network : null
          subnetwork = var.direct_vpc_subnetwork
          tags       = length(var.direct_vpc_tags) > 0 ? var.direct_vpc_tags : null
        }
      }
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

  # deploy.yml owns container env vars (committed .env.cloud-run.* + GitHub Secrets).
  # Terraform still seeds env on initial apply via var.env, but subsequent changes
  # come from CI — ignore_changes prevents terraform apply from reverting them.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].env,
    ]
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
