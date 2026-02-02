variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "bucket_name" {
  description = "The name of the GCS bucket (must be globally unique)"
  type        = string
}

variable "location" {
  description = "The location of the bucket (region or multi-region)"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "The storage class of the bucket"
  type        = string
  default     = "STANDARD"
}

variable "uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow bucket to be destroyed even if it contains objects"
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Enable object versioning"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to the bucket"
  type        = map(string)
  default     = {}
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for the bucket"
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age                   = optional(number)
      num_newer_versions    = optional(number)
      with_state            = optional(string)
      matches_storage_class = optional(list(string))
    })
  }))
  default = []
}

variable "kms_key_name" {
  description = "The Cloud KMS key name for bucket encryption"
  type        = string
  default     = null
}

variable "log_bucket" {
  description = "The bucket to store access logs"
  type        = string
  default     = null
}

variable "log_object_prefix" {
  description = "The prefix for log objects"
  type        = string
  default     = "logs/"
}

variable "iam_bindings" {
  description = "IAM bindings for the bucket"
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}
