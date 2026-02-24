# GCS Bucket Module

resource "google_storage_bucket" "bucket" {
  name     = var.bucket_name
  project  = var.project_id
  location = var.location

  storage_class               = var.storage_class
  uniform_bucket_level_access = var.uniform_bucket_level_access
  force_destroy               = var.force_destroy

  labels = var.labels

  dynamic "versioning" {
    for_each = var.versioning_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lookup(lifecycle_rule.value.action, "storage_class", null)
      }
      condition {
        age                   = lookup(lifecycle_rule.value.condition, "age", null)
        num_newer_versions    = lookup(lifecycle_rule.value.condition, "num_newer_versions", null)
        with_state            = lookup(lifecycle_rule.value.condition, "with_state", null)
        matches_storage_class = lookup(lifecycle_rule.value.condition, "matches_storage_class", null)
      }
    }
  }

  dynamic "encryption" {
    for_each = var.kms_key_name != null ? [1] : []
    content {
      default_kms_key_name = var.kms_key_name
    }
  }

  dynamic "logging" {
    for_each = var.log_bucket != null ? [1] : []
    content {
      log_bucket        = var.log_bucket
      log_object_prefix = var.log_object_prefix
    }
  }
}

resource "google_storage_bucket_iam_member" "members" {
  for_each = { for binding in var.iam_bindings : "${binding.role}-${binding.member}" => binding }

  bucket = google_storage_bucket.bucket.name
  role   = each.value.role
  member = each.value.member
}
