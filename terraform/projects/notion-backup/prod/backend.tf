# Terraform Backend Configuration
#
# Uncomment after running the bootstrap configuration.
# Replace PROJECT_ID with your actual GCP project ID.
# Run `terraform init` after uncommenting.

terraform {
  backend "gcs" {
    bucket = "n43-studio-sandbox-dev-tfstate"
    prefix = "projects/notion-backup/prod"
  }
}
