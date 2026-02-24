variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "network_name" {
  description = "The name of the VPC network"
  type        = string
}

variable "region" {
  description = "The default region for resources"
  type        = string
}

variable "routing_mode" {
  description = "The network routing mode (GLOBAL or REGIONAL)"
  type        = string
  default     = "GLOBAL"
}

variable "subnets" {
  description = "List of subnets to create"
  type = list(object({
    name                     = string
    region                   = string
    ip_cidr_range            = string
    private_ip_google_access = optional(bool, true)
    secondary_ip_ranges = optional(list(object({
      range_name    = string
      ip_cidr_range = string
    })), [])
  }))
  default = []
}

variable "create_nat_gateway" {
  description = "Whether to create a Cloud NAT gateway"
  type        = bool
  default     = false
}
