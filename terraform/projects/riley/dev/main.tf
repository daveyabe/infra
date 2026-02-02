# Riley - Development Environment

locals {
  project = "riley"
  env     = "dev"
  labels  = merge(var.common_labels, {
    project     = local.project
    environment = local.env
  })
}

# VPC Network
module "vpc" {
  source = "../../../modules/vpc"

  project_id   = var.gcp_project_id
  network_name = "${local.project}-${local.env}-vpc"
  region       = var.region

  subnets = [
    {
      name          = "${local.project}-${local.env}-subnet-01"
      region        = var.region
      ip_cidr_range = "10.10.0.0/24"
    }
  ]

  create_nat_gateway = false
}

# Service Account for compute instances
module "compute_sa" {
  source = "../../../modules/iam"

  project_id = var.gcp_project_id

  create_service_account       = true
  service_account_id           = "${local.project}-${local.env}-compute"
  service_account_display_name = "Compute Service Account (${local.project}-${local.env})"
}

# IAM bindings for the service account (separate to avoid circular reference)
module "compute_sa_bindings" {
  source = "../../../modules/iam"

  project_id = var.gcp_project_id

  project_iam_bindings = [
    {
      role   = "roles/logging.logWriter"
      member = "serviceAccount:${module.compute_sa.service_account_email}"
    },
    {
      role   = "roles/monitoring.metricWriter"
      member = "serviceAccount:${module.compute_sa.service_account_email}"
    }
  ]
}

# Firewall rules
module "firewall" {
  source = "../../../modules/firewall"

  project_id   = var.gcp_project_id
  network      = module.vpc.network_self_link
  network_name = module.vpc.network_name

  allow_internal     = true
  internal_ranges    = ["10.10.0.0/16"]
  allow_iap_ssh      = true
  ssh_target_tags    = ["${local.project}-${local.env}"]
  allow_health_check = true
  health_check_ports = [tostring(var.health_check_port)]
}

# Instance Template
module "app_template" {
  source = "../../../modules/instance_template"

  project_id   = var.gcp_project_id
  name_prefix  = "${local.project}-${local.env}-app"
  region       = var.region
  machine_type = var.machine_type

  network    = module.vpc.network_name
  subnetwork = module.vpc.subnets["${local.project}-${local.env}-subnet-01"].name

  source_image          = var.source_image
  disk_size_gb          = var.disk_size_gb
  service_account_email = module.compute_sa.service_account_email
  network_tags          = ["${local.project}-${local.env}", "allow-health-check"]
  enable_external_ip    = true
  startup_script        = file("${path.module}/../../../../GCP/GCE/instance_metadata/Riley/startup-script.sh")

  metadata = {
    gh-url   = var.github_runner_url
    gh-token = var.github_runner_token
    labels   = var.github_runner_labels
  }

  labels = local.labels
}

# Managed Instance Group
module "app_mig" {
  source = "../../../modules/mig"

  project_id         = var.gcp_project_id
  name               = "${local.project}-${local.env}-app-mig"
  zone               = "${var.region}-a"
  base_instance_name = "${local.project}-${local.env}-app"
  instance_template  = module.app_template.self_link

  target_size = var.mig_target_size

  create_health_check = true
  health_check_type   = var.health_check_type
  health_check_port   = var.health_check_port
  health_check_path   = var.health_check_path

  named_ports = var.named_ports
}
