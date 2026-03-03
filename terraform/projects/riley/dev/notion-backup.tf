# Notion Backup — GCS bucket for nightly workspace exports
#
# Multi-region (US) for high availability with lifecycle policies that
# transition older backups to cheaper storage classes automatically:
#   STANDARD → NEARLINE (30 d) → COLDLINE (90 d) → delete (365 d)
# Object versioning keeps prior copies recoverable even if overwritten.

module "notion_backup_bucket" {
  source = "../../../modules/gcs"

  project_id  = var.gcp_project_id
  bucket_name = "${var.gcp_project_id}-notion-backups"
  location    = "US"

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = false
  versioning_enabled          = true

  labels = merge(var.common_labels, {
    purpose = "notion-backup"
    service = "notion"
  })

  lifecycle_rules = [
    {
      action = { type = "SetStorageClass", storage_class = "NEARLINE" }
      condition = { age = 30 }
    },
    {
      action = { type = "SetStorageClass", storage_class = "COLDLINE" }
      condition = { age = 90, matches_storage_class = ["NEARLINE"] }
    },
    {
      action = { type = "Delete" }
      condition = { age = 365 }
    },
    {
      action = { type = "Delete" }
      condition = { num_newer_versions = 3, with_state = "ARCHIVED" }
    },
  ]

  iam_bindings = [
    {
      role   = "roles/storage.objectCreator"
      member = "serviceAccount:${var.gcp_project_id}@${var.gcp_project_id}.iam.gserviceaccount.com"
    },
  ]
}
