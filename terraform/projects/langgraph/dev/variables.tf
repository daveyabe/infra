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

# --- Langgraph: image ---
variable "langgraph_image_tag" {
  description = "Container image tag for the langgraph service (e.g. latest, or a digest)"
  type        = string
  default     = "latest"
}

# --- Langgraph: Cloud Run ---
variable "langgraph_port" {
  description = "Port the langgraph container listens on"
  type        = number
  default     = 8080
}

variable "langgraph_env" {
  description = "Environment variables for the langgraph container"
  type        = map(string)
  default     = {}
}

variable "langgraph_min_instances" {
  description = "Minimum number of Cloud Run instances (0 for scale-to-zero)"
  type        = number
  default     = 0
}

variable "langgraph_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "langgraph_cpu" {
  description = "CPU allocation for the langgraph service (e.g. 1, 2)"
  type        = string
  default     = "1"
}

variable "langgraph_memory" {
  description = "Memory allocation for the langgraph service (e.g. 512Mi, 1Gi)"
  type        = string
  default     = "512Mi"
}

variable "langgraph_allow_unauthenticated" {
  description = "Allow unauthenticated access to the langgraph service (public URL)"
  type        = bool
  default     = false
}

variable "langgraph_request_timeout" {
  description = "Cloud Run request timeout (e.g. 300s, 3600s). LangGraph runs can be long; 3600s allows up to 1h."
  type        = string
  default     = "3600s"
}
