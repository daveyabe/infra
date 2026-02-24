# Set your project ID via command line argument

set -e

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID>}"

gcloud config set project $PROJECT_ID

# Create the service account
gcloud iam service-accounts create terraform-pro \
  --display-name="Terraform Provisioning Service Account"

# Grant necessary roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform-pro@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.repoAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform-pro@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform-pro@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform-pro@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"