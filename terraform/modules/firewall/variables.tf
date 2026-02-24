variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "network" {
  description = "The VPC network self_link or name"
  type        = string
}

variable "network_name" {
  description = "The VPC network name (used for rule naming)"
  type        = string
}

variable "allow_internal" {
  description = "Allow internal traffic within VPC"
  type        = bool
  default     = true
}

variable "internal_ranges" {
  description = "CIDR ranges for internal traffic"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "allow_iap_ssh" {
  description = "Allow SSH access via IAP"
  type        = bool
  default     = true
}

variable "ssh_target_tags" {
  description = "Network tags for SSH access"
  type        = list(string)
  default     = []
}

variable "allow_health_check" {
  description = "Allow Google health check traffic"
  type        = bool
  default     = true
}

variable "health_check_ports" {
  description = "Ports to allow for health checks"
  type        = list(string)
  default     = ["80", "443", "8080"]
}

variable "allow_load_balancer" {
  description = "Allow traffic from Google load balancers"
  type        = bool
  default     = false
}

variable "lb_ports" {
  description = "Ports to allow from load balancers"
  type        = list(string)
  default     = ["80", "443"]
}

variable "lb_target_tags" {
  description = "Network tags for load balancer traffic"
  type        = list(string)
  default     = []
}

variable "custom_rules" {
  description = "List of custom firewall rules"
  type = list(object({
    name               = string
    description        = optional(string)
    direction          = optional(string, "INGRESS")
    priority           = optional(number, 1000)
    source_ranges      = optional(list(string))
    source_tags        = optional(list(string))
    destination_ranges = optional(list(string))
    target_tags        = optional(list(string))
    allow = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])
    deny = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])
  }))
  default = []
}
