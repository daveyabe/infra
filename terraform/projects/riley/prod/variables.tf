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

# Instance Template variables
variable "machine_type" {
  description = "Machine type for instances"
  type        = string
  default     = "e2-highcpu-8"
}

variable "source_image" {
  description = "Source image for boot disk"
  type        = string
  default     = "debian-cloud/debian-11"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

# MIG variables
variable "autoscaling_enabled" {
  description = "Enable autoscaling for the MIG"
  type        = bool
  default     = true
}

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 10
}

variable "cpu_utilization_target" {
  description = "Target CPU utilization for autoscaling (0.0-1.0)"
  type        = number
  default     = 0.7
}

variable "health_check_type" {
  description = "Health check type (HTTP, HTTPS, TCP)"
  type        = string
  default     = "HTTP"
}

variable "health_check_port" {
  description = "Port for health check"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Path for HTTP/HTTPS health check"
  type        = string
  default     = "/"
}

variable "named_ports" {
  description = "Named ports for the instance group"
  type = list(object({
    name = string
    port = number
  }))
  default = [{ name = "http", port = 80 }]
}

# GitHub Actions Runner variables
variable "github_runner_url" {
  description = "GitHub repository URL for the Actions runner"
  type        = string
}

variable "github_runner_token" {
  description = "GitHub PAT for registering the Actions runner"
  type        = string
  sensitive   = true
}

variable "github_runner_labels" {
  description = "Labels to assign to the GitHub Actions runner"
  type        = string
  default     = "self-hosted,linux,x64,gcp,prod"
}
