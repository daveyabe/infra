# Terraform Backend Configuration
#
# Uses GCS for remote state storage.

terraform {
  backend "gcs" {
    bucket = "n43-studio-sandbox-dev-tfstate"
    prefix = "projects/studioos/dev"
  }
}
