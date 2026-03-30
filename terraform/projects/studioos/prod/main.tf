# studioos - Dev Environment
#
# Artifact Registry (Docker) + Cloud Run service.

locals {
  project      = "studioos"
  env          = "prod"
  service_name = "prodstudioos"
  labels = merge(var.common_labels, {
    project     = local.project
    environment = local.env
    service     = local.service_name
  })
  # Full container image: registry URL / image name : tag
  backend_image = "${module.artifact_registry.repository_url}/${local.service_name}:${var.studioos_image_tag}"
}

# Artifact Registry: Docker repository
module "artifact_registry" {
  source = "../../../modules/artifact-registry"

  project_id    = var.gcp_project_id
  location      = var.region
  repository_id = local.service_name
  format        = "DOCKER"
  description   = "Docker images for studioos (${local.env})"
  labels        = local.labels
}

# Cloud Run service
module "cloud_run" {
  source = "../../../modules/cloud-run"

  project_id = var.gcp_project_id
  location   = var.region
  name       = local.service_name
  image      = local.backend_image

  port                  = var.studioos_port
  env                   = var.studioos_env
  min_instances         = var.studioos_min_instances
  max_instances         = var.studioos_max_instances
  cpu                   = var.studioos_cpu
  memory                = var.studioos_memory
  allow_unauthenticated = var.studioos_allow_unauthenticated
  timeout               = var.studioos_request_timeout
  labels                = local.labels
}
