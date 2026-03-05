output "notion_backup_bucket_name" {
  description = "GCS bucket storing nightly Notion workspace backups"
  value       = module.notion_backup_bucket.bucket_name
}

output "notion_backup_bucket_url" {
  description = "GCS URL for the Notion backup bucket"
  value       = module.notion_backup_bucket.bucket_url
}

output "notion_backup_bucket_self_link" {
  description = "Self link for the Notion backup bucket"
  value       = module.notion_backup_bucket.bucket_self_link
}
