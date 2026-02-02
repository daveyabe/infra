variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "instance_name" {
  description = "The name of the compute instance"
  type        = string
}

variable "zone" {
  description = "The zone where the instance will be created"
  type        = string
}

variable "machine_type" {
  description = "The machine type for the instance"
  type        = string
  default     = "e2-medium"
}

variable "network" {
  description = "The VPC network to attach the instance to"
  type        = string
}

variable "subnetwork" {
  description = "The subnetwork to attach the instance to"
  type        = string
}

variable "network_tags" {
  description = "Network tags to apply to the instance"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to the instance"
  type        = map(string)
  default     = {}
}

variable "boot_disk_image" {
  description = "The boot disk image"
  type        = string
  default     = "debian-cloud/debian-11"
}

variable "boot_disk_size_gb" {
  description = "The size of the boot disk in GB"
  type        = number
  default     = 20
}

variable "boot_disk_type" {
  description = "The type of the boot disk"
  type        = string
  default     = "pd-balanced"
}

variable "enable_external_ip" {
  description = "Whether to assign an external IP to the instance"
  type        = bool
  default     = false
}

variable "service_account_email" {
  description = "The service account email to attach to the instance"
  type        = string
  default     = null
}

variable "service_account_scopes" {
  description = "The service account scopes"
  type        = list(string)
  default     = ["cloud-platform"]
}

variable "metadata" {
  description = "Metadata key-value pairs to attach to the instance"
  type        = map(string)
  default     = {}
}

variable "startup_script" {
  description = "The startup script to run on instance boot"
  type        = string
  default     = null
}

variable "enable_secure_boot" {
  description = "Whether to enable secure boot on the instance"
  type        = bool
  default     = true
}

variable "allow_stopping_for_update" {
  description = "Allow the instance to be stopped for updates"
  type        = bool
  default     = true
}

variable "additional_disks" {
  description = "Additional disks to attach to the instance"
  type = list(object({
    name    = string
    size_gb = number
    type    = optional(string, "pd-standard")
  }))
  default = []
}
