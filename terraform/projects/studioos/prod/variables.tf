variable "gcp_project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The default GCP region"
  type        = string
  default     = "northamerica-northeast2"
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
  }
}

# --- studioos: image ---
variable "studioos_image_tag" {
  description = "Container image tag (e.g. latest, sha-abc123)"
  type        = string
  default     = "latest"
}

# --- studioos: Cloud Run ---
variable "studioos_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "studioos_env" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "studioos_min_instances" {
  description = "Minimum number of Cloud Run instances (0 for scale-to-zero)"
  type        = number
  default     = 0
}

variable "studioos_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "studioos_cpu" {
  description = "CPU allocation (e.g. 1, 2)"
  type        = string
  default     = "1"
}

variable "studioos_memory" {
  description = "Memory allocation (e.g. 512Mi, 1Gi)"
  type        = string
  default     = "512Mi"
}

variable "studioos_allow_unauthenticated" {
  description = "Allow unauthenticated access (public URL)"
  type        = bool
  default     = false
}

variable "studioos_request_timeout" {
  description = "Cloud Run request timeout (e.g. 300s)"
  type        = string
  default     = "300s"
}

# --- studioos: Cloud SQL (existing instance) ---
variable "studioos_cloud_sql_connection_names" {
  description = "Existing Cloud SQL instances to attach (project:region:instance). When set, mounts the proxy at /cloudsql; use DATABASE_URL unix-socket form. For private IP only, leave empty and use Direct VPC variables instead."
  type        = list(string)
  default     = []
}

# --- studioos: Direct VPC egress (private IP Cloud SQL; no Serverless VPC Access connector) ---
# Subnetwork is fixed in main.tf: projects/{gcp_project_id}/regions/{region}/subnetworks/default
variable "studioos_direct_vpc_network" {
  description = "VPC network name or full resource name. Optional; network is inferred from the default subnet when empty."
  type        = string
  default     = ""
}

variable "studioos_direct_vpc_tags" {
  description = "Optional network tags on the Cloud Run NIC (for firewall rules)."
  type        = list(string)
  default     = []
}

variable "studioos_vpc_access_egress" {
  description = "PRIVATE_RANGES_ONLY (default): only private destinations use the VPC. ALL_TRAFFIC: all outbound via VPC."
  type        = string
  default     = "PRIVATE_RANGES_ONLY"
}
