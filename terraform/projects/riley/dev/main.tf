# Riley Backend - Development Environment
#
# High-level manifest: Artifact Registry (Docker) + Cloud Run service
# for the riley backend service.

locals {
  project        = "riley"
  env            = "dev"
  backend_name   = "riley-backend"
  labels         = merge(var.common_labels, {
    project     = local.project
    environment = local.env
    service     = local.backend_name
  })
  # Full container image: registry URL / image name : tag
  backend_image  = "${module.artifact_registry.repository_url}/${local.backend_name}:${var.riley_backend_image_tag}"
}

# Artifact Registry: Docker repository for riley backend images
module "artifact_registry" {
  source = "../../../modules/artifact-registry"

  project_id    = var.gcp_project_id
  location      = var.region
  repository_id = local.backend_name
  format        = "DOCKER"
  description   = "Docker images for Riley backend (${local.env})"
  labels        = local.labels
}

# Cloud Run: Riley backend service
module "cloud_run" {
  source = "../../../modules/cloud-run"

  project_id  = var.gcp_project_id
  location    = var.region
  name        = local.backend_name
  image       = local.backend_image

  port                   = var.riley_backend_port
  env                    = var.riley_backend_env
  min_instances          = var.riley_backend_min_instances
  max_instances          = var.riley_backend_max_instances
  cpu                    = var.riley_backend_cpu
  memory                 = var.riley_backend_memory
  allow_unauthenticated  = var.riley_backend_allow_unauthenticated
  service_account_email  = var.riley_backend_service_account_email
  labels                 = local.labels
}
