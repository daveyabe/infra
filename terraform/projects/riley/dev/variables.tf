variable "gcp_project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The default GCP region (used for Artifact Registry and Cloud Run)"
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

# --- Riley backend: image ---
variable "riley_backend_image_tag" {
  description = "Container image tag for the riley backend (e.g. latest, or a digest)"
  type        = string
  default     = "latest"
}

# --- Riley backend: Cloud Run ---
variable "riley_backend_port" {
  description = "Port the riley backend container listens on"
  type        = number
  default     = 8080
}

variable "riley_backend_env" {
  description = "Environment variables for the riley backend container"
  type        = map(string)
  default     = {}
}

variable "riley_backend_min_instances" {
  description = "Minimum number of Cloud Run instances (0 for scale-to-zero)"
  type        = number
  default     = 0
}

variable "riley_backend_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "riley_backend_cpu" {
  description = "CPU allocation for the riley backend (e.g. 1, 2)"
  type        = string
  default     = "1"
}

variable "riley_backend_memory" {
  description = "Memory allocation for the riley backend (e.g. 512Mi, 1Gi)"
  type        = string
  default     = "512Mi"
}

variable "riley_backend_allow_unauthenticated" {
  description = "Allow unauthenticated access to the riley backend (public URL)"
  type        = bool
  default     = false
}

variable "riley_backend_service_account_email" {
  description = "Service account for the riley backend revision (null = default compute SA)"
  type        = string
  default     = null
}
