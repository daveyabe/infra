# Notion Backup — Production
#
# GCS bucket for nightly Notion workspace exports.
# Multi-region for high availability with lifecycle policies that
# transition older backups to cheaper storage classes automatically:
#   STANDARD → NEARLINE → COLDLINE → delete

locals {
  project = "notion"
  env     = "prod"
  labels = merge(var.common_labels, {
    project     = local.project
    environment = local.env
    purpose     = "notion-backup"
  })
  writer_sa = coalesce(
    var.backup_writer_service_account,
    "terraform-github-actions@${var.gcp_project_id}.iam.gserviceaccount.com"
  )
}

module "notion_backup_bucket" {
  source = "../../../modules/gcs"

  project_id  = var.gcp_project_id
  bucket_name = "${var.gcp_project_id}-notion-backups"
  location    = var.backup_bucket_location

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = false
  versioning_enabled          = true

  labels = local.labels

  lifecycle_rules = [
    {
      action    = { type = "SetStorageClass", storage_class = "NEARLINE" }
      condition = { age = var.backup_nearline_age_days }
    },
    {
      action    = { type = "SetStorageClass", storage_class = "COLDLINE" }
      condition = { age = var.backup_coldline_age_days, matches_storage_class = ["NEARLINE"] }
    },
    {
      action    = { type = "Delete" }
      condition = { age = var.backup_retention_days }
    },
    {
      action    = { type = "Delete" }
      condition = { num_newer_versions = 3, with_state = "ARCHIVED" }
    },
  ]

  iam_bindings = [
    {
      role   = "roles/storage.objectCreator"
      member = "serviceAccount:${local.writer_sa}"
    },
  ]
}
