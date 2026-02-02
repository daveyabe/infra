variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

# Service Account variables
variable "create_service_account" {
  description = "Whether to create a service account"
  type        = bool
  default     = false
}

variable "service_account_id" {
  description = "The service account ID (email prefix)"
  type        = string
  default     = null
}

variable "service_account_display_name" {
  description = "The display name of the service account"
  type        = string
  default     = null
}

variable "service_account_description" {
  description = "The description of the service account"
  type        = string
  default     = null
}

variable "service_account_iam" {
  description = "IAM bindings for who can use/manage the service account"
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}

variable "create_sa_key" {
  description = "Whether to create a service account key (use sparingly)"
  type        = bool
  default     = false
}

# Project IAM variables
variable "project_iam_bindings" {
  description = "Project-level IAM bindings"
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}

# Custom Role variables
variable "create_custom_role" {
  description = "Whether to create a custom IAM role"
  type        = bool
  default     = false
}

variable "custom_role_id" {
  description = "The ID of the custom role"
  type        = string
  default     = null
}

variable "custom_role_title" {
  description = "The title of the custom role"
  type        = string
  default     = null
}

variable "custom_role_description" {
  description = "The description of the custom role"
  type        = string
  default     = null
}

variable "custom_role_permissions" {
  description = "The permissions for the custom role"
  type        = list(string)
  default     = []
}

variable "custom_role_stage" {
  description = "The stage of the custom role (ALPHA, BETA, GA)"
  type        = string
  default     = "GA"
}
