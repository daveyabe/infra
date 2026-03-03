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

# --- Notion backup bucket ---

variable "backup_bucket_location" {
  description = "GCS bucket location (multi-region recommended for durability)"
  type        = string
  default     = "US"
}

variable "backup_retention_days" {
  description = "Number of days to retain backups before deletion"
  type        = number
  default     = 365
}

variable "backup_nearline_age_days" {
  description = "Days after which backups transition to Nearline storage"
  type        = number
  default     = 30
}

variable "backup_coldline_age_days" {
  description = "Days after which backups transition from Nearline to Coldline"
  type        = number
  default     = 90
}

variable "backup_writer_service_account" {
  description = "Service account email granted objectCreator on the backup bucket (the GitHub Actions SA)"
  type        = string
  default     = null
}
