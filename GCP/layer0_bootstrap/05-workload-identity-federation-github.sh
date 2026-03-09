#!/usr/bin/env bash
# Provision Workload Identity Federation for GitHub OIDC on a GCP project.
# This allows GitHub Actions to authenticate to GCP without service account keys.
#
# Usage:
#   $0 <PROJECT_ID> <GITHUB_ORG> <GITHUB_REPO> [SERVICE_ACCOUNT_ID]
#
# Examples:
#   $0 my-gcp-project my-org my-repo
#   $0 my-gcp-project my-org my-repo terraform-github-actions
#
# Optional env vars (defaults shown):
#   WIF_POOL_ID=github-pool
#   WIF_PROVIDER_ID=github-provider

set -e

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID> <GITHUB_ORG> <GITHUB_REPO> [SERVICE_ACCOUNT_ID]}"
#GITHUB_ORG="${2:?Usage: $0 <PROJECT_ID> <GITHUB_ORG> <GITHUB_REPO> [SERVICE_ACCOUNT_ID]}"
GITHUB_ORG="${2:-N43-Studio}"
#GITHUB_REPO="${3:?Usage: $0 <PROJECT_ID> <GITHUB_ORG> <GITHUB_REPO> [SERVICE_ACCOUNT_ID]}"
GITHUB_REPO="${3:-infrastructure}"
SERVICE_ACCOUNT_ID="${4:-terraform-github-actions}"

# Optional overrides
WIF_POOL_ID="${WIF_POOL_ID:-github-pool}"
WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-github-provider}"

echo "=== Workload Identity Federation (GitHub OIDC) ==="
echo "  Project:       $PROJECT_ID"
echo "  GitHub:        $GITHUB_ORG/$GITHUB_REPO"
echo "  Pool:          $WIF_POOL_ID"
echo "  Provider:      $WIF_PROVIDER_ID"
echo "  Service Acct:  $SERVICE_ACCOUNT_ID"
echo ""

gcloud config set project "$PROJECT_ID"

# Project number is required for principalSet
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
POOL_RESOURCE="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WIF_POOL_ID"
POOL_FULL_NAME="projects/$PROJECT_ID/locations/global/workloadIdentityPools/$WIF_POOL_ID"
PROVIDER_FULL_NAME="$POOL_FULL_NAME/providers/$WIF_PROVIDER_ID"

# Create Workload Identity Pool
echo "Creating Workload Identity Pool: $WIF_POOL_ID"
if gcloud iam workload-identity-pools describe "$WIF_POOL_ID" \
  --location=global \
  --project="$PROJECT_ID" &>/dev/null; then
  echo "  Pool already exists, skipping."
else
  gcloud iam workload-identity-pools create "$WIF_POOL_ID" \
    --location=global \
    --project="$PROJECT_ID" \
    --display-name="GitHub Actions Pool" \
    --description="Workload Identity Pool for GitHub Actions"
fi

# Create OIDC Provider (GitHub Actions)
echo "Creating OIDC Provider: $WIF_PROVIDER_ID (GitHub)"
if gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER_ID" \
  --workload-identity-pool="$WIF_POOL_ID" \
  --location=global \
  --project="$PROJECT_ID" &>/dev/null; then
  echo "  Provider already exists, skipping."
else
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER_ID" \
    --location=global \
    --workload-identity-pool="$WIF_POOL_ID" \
    --project="$PROJECT_ID" \
    --display-name="GitHub Provider" \
    --description="OIDC provider for GitHub Actions" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository_owner == '$GITHUB_ORG'"
fi

# Create service account for GitHub Actions to impersonate
echo "Creating Service Account: $SERVICE_ACCOUNT_ID"
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" &>/dev/null; then
  echo "  Service account already exists, skipping."
else
  gcloud iam service-accounts create "$SERVICE_ACCOUNT_ID" \
    --project="$PROJECT_ID" \
    --display-name="GitHub Actions (WIF)" \
    --description="Service account for GitHub Actions via Workload Identity Federation"
fi

# Grant project roles needed for Terraform (Artifact Registry, Cloud Run, IAM)
# These were previously in 04-SA-account-TF.sh for terraform-pro; now applied to the WIF SA.
echo "Granting Terraform provisioning roles to $SERVICE_ACCOUNT_ID..."
for role in roles/artifactregistry.repoAdmin roles/run.admin roles/iam.serviceAccountAdmin roles/artifactregistry.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="$role" \
    --quiet
done

# Allow the specific GitHub repo to impersonate this service account
# principalSet restricts to attribute.repository = org/repo
PRINCIPAL_SET="principalSet://iam.googleapis.com/$POOL_RESOURCE/attribute.repository/$GITHUB_ORG/$GITHUB_REPO"
SA_EMAIL="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Binding Workload Identity User (repo: $GITHUB_ORG/$GITHUB_REPO) -> $SA_EMAIL"
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$PRINCIPAL_SET"

echo ""
echo "=== Done ==="
echo ""
echo "Use these values in your GitHub Actions workflow:"
echo "  WORKLOAD_IDENTITY_PROVIDER: $PROVIDER_FULL_NAME"
echo "  SERVICE_ACCOUNT:           $SA_EMAIL"
echo ""
echo "Example job config:"
echo "  jobs:"
echo "    deploy:"
echo "      permissions:"
echo "        id-token: write"
echo "        contents: read"
echo "      steps:"
echo "        - uses: google-github-actions/auth@v2"
echo "          with:"
echo "            workload_identity_provider: '$PROVIDER_FULL_NAME'"
echo "            service_account: '$SA_EMAIL'"
echo ""
