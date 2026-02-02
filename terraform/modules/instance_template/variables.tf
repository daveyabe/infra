variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for the instance template name"
  type        = string
}

variable "region" {
  description = "The region for the instance template"
  type        = string
}

variable "machine_type" {
  description = "The machine type for instances"
  type        = string
  default     = "e2-medium"
}

variable "network" {
  description = "The VPC network"
  type        = string
}

variable "subnetwork" {
  description = "The subnetwork"
  type        = string
}

variable "network_tags" {
  description = "Network tags for instances"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to instances"
  type        = map(string)
  default     = {}
}

variable "source_image" {
  description = "The source image for the boot disk"
  type        = string
  default     = "debian-cloud/debian-11"
}

variable "disk_size_gb" {
  description = "The size of the boot disk in GB"
  type        = number
  default     = 20
}

variable "disk_type" {
  description = "The type of the boot disk"
  type        = string
  default     = "pd-balanced"
}

variable "additional_disks" {
  description = "Additional disks to attach"
  type = list(object({
    size_gb     = number
    type        = optional(string, "pd-standard")
    auto_delete = optional(bool, true)
  }))
  default = []
}

variable "enable_external_ip" {
  description = "Whether to enable external IP"
  type        = bool
  default     = false
}

variable "service_account_email" {
  description = "Service account email for instances"
  type        = string
  default     = null
}

variable "service_account_scopes" {
  description = "Service account scopes"
  type        = list(string)
  default     = ["cloud-platform"]
}

variable "metadata" {
  description = "Metadata key-value pairs"
  type        = map(string)
  default     = {}
}

variable "startup_script" {
  description = "Startup script content"
  type        = string
  default     = null
}

variable "enable_secure_boot" {
  description = "Enable secure boot"
  type        = bool
  default     = true
}

variable "automatic_restart" {
  description = "Enable automatic restart on failure"
  type        = bool
  default     = true
}

variable "preemptible" {
  description = "Use preemptible instances"
  type        = bool
  default     = false
}
