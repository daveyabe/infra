variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "name" {
  description = "Name of the managed instance group"
  type        = string
}

variable "zone" {
  description = "The zone for the MIG"
  type        = string
}

variable "base_instance_name" {
  description = "Base name for instances in the group"
  type        = string
}

variable "instance_template" {
  description = "The instance template self_link"
  type        = string
}

variable "target_size" {
  description = "Target number of instances (ignored if autoscaling enabled)"
  type        = number
  default     = 1
}

# Named ports
variable "named_ports" {
  description = "Named ports for the instance group"
  type = list(object({
    name = string
    port = number
  }))
  default = []
}

# Health check
variable "health_check" {
  description = "Health check self_link for auto-healing"
  type        = string
  default     = null
}

variable "health_check_initial_delay" {
  description = "Initial delay before health checking"
  type        = number
  default     = 300
}

variable "create_health_check" {
  description = "Whether to create a health check"
  type        = bool
  default     = false
}

variable "health_check_type" {
  description = "Type of health check (HTTP, HTTPS, TCP)"
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

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10
}

variable "healthy_threshold" {
  description = "Number of consecutive successes for healthy"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failures for unhealthy"
  type        = number
  default     = 2
}

# Update policy
variable "update_policy_type" {
  description = "Update policy type (PROACTIVE or OPPORTUNISTIC)"
  type        = string
  default     = "PROACTIVE"
}

variable "update_policy_minimal_action" {
  description = "Minimal action for updates (NONE, REFRESH, RESTART, REPLACE)"
  type        = string
  default     = "REPLACE"
}

variable "update_policy_most_disruptive_action" {
  description = "Most disruptive action allowed (NONE, REFRESH, RESTART, REPLACE)"
  type        = string
  default     = "REPLACE"
}

variable "max_surge_fixed" {
  description = "Max instances to create above target during update"
  type        = number
  default     = 1
}

variable "max_unavailable_fixed" {
  description = "Max instances unavailable during update"
  type        = number
  default     = 0
}

variable "replacement_method" {
  description = "Replacement method (SUBSTITUTE or RECREATE)"
  type        = string
  default     = "SUBSTITUTE"
}

# Autoscaling
variable "autoscaling_enabled" {
  description = "Enable autoscaling"
  type        = bool
  default     = false
}

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 10
}

variable "cooldown_period" {
  description = "Cooldown period in seconds"
  type        = number
  default     = 60
}

variable "cpu_utilization_target" {
  description = "Target CPU utilization (0.0 - 1.0)"
  type        = number
  default     = 0.6
}

variable "custom_metrics" {
  description = "Custom metrics for autoscaling"
  type = list(object({
    name   = string
    type   = string
    target = number
  }))
  default = []
}

variable "scale_in_control_enabled" {
  description = "Enable scale-in control"
  type        = bool
  default     = false
}

variable "scale_in_max_replicas" {
  description = "Max replicas to scale in at once"
  type        = number
  default     = 1
}

variable "scale_in_time_window" {
  description = "Time window for scale-in control"
  type        = number
  default     = 600
}
