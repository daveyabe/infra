variable "gcp_project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "northamerica-northeast2"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "N43-Studio"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "infrastructure"
}
