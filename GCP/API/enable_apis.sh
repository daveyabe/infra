#!/usr/bin/env bash
# Enable basic GCP APIs for a given project.
# Usage: ./enable_apis.sh <PROJECT_ID> [API_NAME ...]
#
# With only PROJECT_ID, enables the default set below.
# Pass additional API names (e.g. container.googleapis.com) to enable extras.

set -e

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID> [API_NAME ...]}"
shift || true

# Default set of commonly needed APIs
DEFAULT_APIS=(
  cloudresourcemanager.googleapis.com
  serviceusage.googleapis.com
  compute.googleapis.com
  storage.googleapis.com
  storage-component.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  secretmanager.googleapis.com
  sqladmin.googleapis.com
  run.googleapis.com
  artifactregistry.googleapis.com
  certificatemanager.googleapis.com
  servicemanagement.googleapis.com
  servicenetworking.googleapis.com
  vpcaccess.googleapis.com
  dns.googleapis.com
  logging.googleapis.com
  monitoring.googleapis.com
  iap.googleapis.com
)

# APIs needed for AI across the project (Vertex AI, Gemini, etc.)
AI_APIS=(
  aiplatform.googleapis.com
  generativelanguage.googleapis.com
  ml.googleapis.com
  notebooks.googleapis.com
  discoveryengine.googleapis.com
  documentai.googleapis.com
  vision.googleapis.com
)

APIS=("${DEFAULT_APIS[@]}" "${AI_APIS[@]}" "$@")

echo "Enabling APIs for project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

for api in "${APIS[@]}"; do
  echo "  Enabling $api"
  gcloud services enable "$api" --project="$PROJECT_ID"
done

echo "Done."
