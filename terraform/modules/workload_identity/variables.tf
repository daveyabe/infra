variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "pool_id" {
  description = "Workload Identity Pool ID"
  type        = string
  default     = "github-pool"
}

variable "provider_id" {
  description = "Workload Identity Provider ID"
  type        = string
  default     = "github-provider"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "service_account_id" {
  description = "Service account ID for Terraform"
  type        = string
  default     = "terraform-github-actions"
}

variable "terraform_roles" {
  description = "IAM roles to grant to the Terraform service account"
  type        = list(string)
  default = [
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.roleAdmin",
    "roles/storage.admin",
    "roles/resourcemanager.projectIamAdmin",
  ]
}
