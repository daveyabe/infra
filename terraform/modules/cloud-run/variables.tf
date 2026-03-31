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

variable "cloud_sql_connection_names" {
  description = "Cloud SQL connection names (project:region:instance). When set, mounts the proxy at /cloudsql; use DATABASE_URL with host=/cloudsql/..."
  type        = list(string)
  default     = []
}

# Direct VPC egress (recommended for private IP Cloud SQL without a Serverless VPC Access connector).
variable "direct_vpc_network" {
  description = "VPC network name or full resource name. Optional if subnetwork fully specifies the network."
  type        = string
  default     = ""
}

variable "direct_vpc_subnetwork" {
  description = "Subnet for Cloud Run to attach for outbound traffic (same region as Cloud Run). When non-empty, enables Direct VPC egress."
  type        = string
  default     = ""
}

variable "direct_vpc_tags" {
  description = "Optional VPC network tags for the Cloud Run network interface (e.g. for firewall targeting)."
  type        = list(string)
  default     = []
}

variable "vpc_access_egress" {
  description = "With Direct VPC: PRIVATE_RANGES_ONLY sends only private destinations through the VPC (default). ALL_TRAFFIC sends all egress via the VPC."
  type        = string
  default     = "PRIVATE_RANGES_ONLY"

  validation {
    condition     = contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], var.vpc_access_egress)
    error_message = "vpc_access_egress must be ALL_TRAFFIC or PRIVATE_RANGES_ONLY."
  }
}
