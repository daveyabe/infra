#!/usr/bin/env bash
# Create a basic sandbox Cloud SQL instance on GCP.
# Root password is stored in Secret Manager (no echo to stdout).
# Usage: ./create_sandbox_cloudsql.sh <PROJECT_ID> [INSTANCE_NAME]

set -e

PROJECT_ID="${1:?Usage: $0 PROJECT_ID [INSTANCE_NAME]}"
INSTANCE_NAME="${2:-sandbox-sql}"
REGION="${CLOUDSQL_REGION:-us-central1}"
TIER="db-f1-micro"          # smallest shared-core tier (sandbox)
DATABASE_VERSION="POSTGRES_15"
SECRET_NAME="cloudsql-${INSTANCE_NAME}-root-password"

echo "Creating Cloud SQL instance: $INSTANCE_NAME (project: $PROJECT_ID)"
gcloud config set project "$PROJECT_ID"

# Ensure Secret Manager API is enabled
gcloud services enable secretmanager.googleapis.com --quiet 2>/dev/null || true

ROOT_PASSWORD=$(openssl rand -base64 24)
gcloud sql instances create "$INSTANCE_NAME" \
  --database-version="$DATABASE_VERSION" \
  --tier="$TIER" \
  --region="$REGION" \
  --root-password="$ROOT_PASSWORD" \
  --storage-type=HDD \
  --storage-size=10GB

# Store root password in Secret Manager
if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
  gcloud secrets create "$SECRET_NAME" \
    --replication-policy="automatic" \
    --project="$PROJECT_ID"
fi
echo -n "$ROOT_PASSWORD" | gcloud secrets versions add "$SECRET_NAME" \
  --data-file=- \
  --project="$PROJECT_ID"

# Clear from shell history
unset ROOT_PASSWORD

echo ""
echo "Instance $INSTANCE_NAME created."
echo "Connect: gcloud sql connect $INSTANCE_NAME --user=postgres"
echo "Root password secret: $SECRET_NAME (access: gcloud secrets versions access latest --secret=$SECRET_NAME)"
