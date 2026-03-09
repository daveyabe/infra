# Terraform Backend Configuration
#
# Uncomment after running the bootstrap configuration.
# Replace PROJECT_ID with your actual GCP project ID.
# Run `terraform init` after uncommenting.

terraform {
  backend "gcs" {
    bucket = "natural-iridium-469419-f7-tfstate"
    prefix = "projects/notion-backup/prod"
  }
}
