# Set your project ID via command line argument

set -e

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID>}"
SA_EMAIL="terraform-pro@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud config set project "$PROJECT_ID"

# Create the service account only if it doesn't exist (idempotent)
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
  echo "Creating service account terraform-pro..."
  gcloud iam service-accounts create terraform-pro \
    --display-name="Terraform Provisioning Service Account" \
    --project="$PROJECT_ID"
  echo "Waiting a few seconds for IAM propagation..."
  sleep 10
else
  echo "Service account terraform-pro already exists."
fi

# Grant necessary roles
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.repoAdmin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/iam.serviceAccountAdmin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.admin"