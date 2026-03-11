# Langgraph - Development Environment
#
# Artifact Registry (Docker) + Cloud Run service for the langgraph service.

locals {
  project      = "langgraph"
  env          = "dev"
  service_name = "langgraph"
  labels = merge(var.common_labels, {
    project     = local.project
    environment = local.env
    service     = local.service_name
  })
  # Full container image: registry URL / image name : tag
  backend_image = "${module.artifact_registry.repository_url}/${local.service_name}:${var.langgraph_image_tag}"
}

# Artifact Registry: Docker repository for langgraph images
module "artifact_registry" {
  source = "../../../modules/artifact-registry"

  project_id    = var.gcp_project_id
  location      = var.region
  repository_id = local.service_name
  format        = "DOCKER"
  description   = "Docker images for Langgraph (${local.env})"
  labels        = local.labels
}

# Cloud Run: Langgraph service
module "cloud_run" {
  source = "../../../modules/cloud-run"

  project_id = var.gcp_project_id
  location   = var.region
  name       = local.service_name
  image      = local.backend_image

  port                  = var.langgraph_port
  env                   = var.langgraph_env
  min_instances         = var.langgraph_min_instances
  max_instances         = var.langgraph_max_instances
  cpu                   = var.langgraph_cpu
  memory                = var.langgraph_memory
  allow_unauthenticated = var.langgraph_allow_unauthenticated
  timeout               = var.langgraph_request_timeout
  labels                = local.labels
}
