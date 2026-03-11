variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "location" {
  description = "The region for the Cloud Run service (e.g. us-central1)"
  type        = string
}

variable "name" {
  description = "The name of the Cloud Run service"
  type        = string
}

variable "image" {
  description = "The container image to deploy (e.g. us-docker.pkg.dev/project/repo/image:tag)"
  type        = string
}

variable "port" {
  description = "The port the container listens on"
  type        = number
  default     = 8080
}

variable "env" {
  description = "Environment variables for the container (key = value)"
  type        = map(string)
  default     = {}
}

variable "min_instances" {
  description = "Minimum number of instances (0 for scale-to-zero)"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "cpu" {
  description = "CPU allocation (e.g. 1, 2)"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation (e.g. 512Mi, 1Gi)"
  type        = string
  default     = "512Mi"
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access (public URL)"
  type        = bool
  default     = false
}

# Unused: service account and WIF are configured in CI/CD. Kept for API compatibility with callers (e.g. riley).
variable "service_account_email" {
  description = "Service account for the revision (unused; set in CI/CD). Kept for compatibility."
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to the service"
  type        = map(string)
  default     = {}
}

variable "timeout" {
  description = "Request timeout (string with 's' suffix, e.g. 300s, 3600s). Max 3600s."
  type        = string
  default     = "300s"
}
