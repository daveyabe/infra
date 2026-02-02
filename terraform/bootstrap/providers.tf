terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Bootstrap uses local state - only run once
  # After bootstrap, state for other environments is in GCS
}

provider "google" {
  project = var.gcp_project_id
  region  = var.region
}
