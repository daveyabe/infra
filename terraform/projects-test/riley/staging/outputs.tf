output "vpc_network_name" {
  description = "The name of the VPC network"
  value       = module.vpc.network_name
}

output "vpc_subnets" {
  description = "The subnets in the VPC"
  value       = module.vpc.subnets
}

output "compute_service_account_email" {
  description = "The email of the compute service account"
  value       = module.compute_sa.service_account_email
}

output "instance_template_name" {
  description = "The name of the instance template"
  value       = module.app_template.name
}

output "mig_name" {
  description = "The name of the managed instance group"
  value       = module.app_mig.name
}

output "mig_instance_group" {
  description = "The instance group URL"
  value       = module.app_mig.instance_group
}
