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
  description = "Existing Cloud SQL instances to attach (project:region:instance). Empty skips attachment. Use DATABASE_URL unix-socket form in studioos_env (see tfvars comment). Private-IP-only DBs need a VPC connector outside this module."
  type        = list(string)
  default     = []
}
