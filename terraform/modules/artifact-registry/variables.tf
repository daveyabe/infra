variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "repository_id" {
  description = "The ID of the Artifact Registry repository (e.g. my-repo)"
  type        = string
}

variable "location" {
  description = "The location of the repository (region or multi-region, e.g. us-central1)"
  type        = string
}

variable "format" {
  description = "The format of the repository (DOCKER, MAVEN, NPM, PYTHON, etc.)"
  type        = string
  default     = "DOCKER"
}

variable "description" {
  description = "Optional description of the repository"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to the repository"
  type        = map(string)
  default     = {}
}
