#!/usr/bin/env bash
# Authorize a GitHub repository to use the reusable deploy workflow.
#
# This script adds a Workload Identity Federation binding that allows the
# specified GitHub repo to impersonate the Terraform service account.
#
# Usage:
#   ./scripts/allow-caller-repo.sh <GITHUB_ORG> <GITHUB_REPO> [options]
#
# Options:
#   --gcp-project-id ID       GCP project ID (default: from gcloud config)
#   --service-account SA      Service account ID (default: terraform-github-actions)
#   --pool-id POOL            WIF pool ID (default: github-pool)
#   --dry-run                 Show what would be done without making changes
#
# Examples:
#   ./scripts/allow-caller-repo.sh N43-Studio my-app
#   ./scripts/allow-caller-repo.sh N43-Studio my-app --dry-run
#
# Prerequisites:
#   - WIF pool and provider must already exist (run 05-workload-identity-federation-github.sh first)
#   - You must have iam.serviceAccounts.setIamPolicy permission on the service account

set -euo pipefail

# Defaults
GCP_PROJECT_ID=""
SERVICE_ACCOUNT_ID="terraform-github-actions"
WIF_POOL_ID="github-pool"
DRY_RUN=false

usage() {
  echo "Usage: $0 <GITHUB_ORG> <GITHUB_REPO> [options]"
  echo ""
  echo "Options:"
  echo "  --gcp-project-id ID       GCP project ID (default: from gcloud config)"
  echo "  --service-account SA      Service account ID (default: $SERVICE_ACCOUNT_ID)"
  echo "  --pool-id POOL            WIF pool ID (default: $WIF_POOL_ID)"
  echo "  --dry-run                 Show what would be done without making changes"
  echo ""
  echo "Example:"
  echo "  $0 N43-Studio my-app"
  exit 1
}

# Parse arguments
[[ $# -lt 2 ]] && usage

GITHUB_ORG="$1"
GITHUB_REPO="$2"
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gcp-project-id) GCP_PROJECT_ID="$2"; shift 2 ;;
    --service-account) SERVICE_ACCOUNT_ID="$2"; shift 2 ;;
    --pool-id) WIF_POOL_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Get project ID from gcloud if not provided
if [[ -z "$GCP_PROJECT_ID" ]]; then
  GCP_PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
  if [[ -z "$GCP_PROJECT_ID" ]]; then
    echo "ERROR: No GCP project ID provided and none set in gcloud config."
    echo "Use --gcp-project-id or run: gcloud config set project <PROJECT_ID>"
    exit 1
  fi
fi

# Get project number for principalSet
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || true)
if [[ -z "$PROJECT_NUMBER" ]]; then
  echo "ERROR: Could not get project number for '$GCP_PROJECT_ID'."
  echo "Ensure you have access to the project."
  exit 1
fi

# Construct the principal set and SA email
POOL_RESOURCE="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WIF_POOL_ID"
PRINCIPAL_SET="principalSet://iam.googleapis.com/$POOL_RESOURCE/attribute.repository/$GITHUB_ORG/$GITHUB_REPO"
SA_EMAIL="${SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

echo "=== Allow Caller Repo ==="
echo "  GitHub Repo:      $GITHUB_ORG/$GITHUB_REPO"
echo "  GCP Project:      $GCP_PROJECT_ID"
echo "  Project Number:   $PROJECT_NUMBER"
echo "  Service Account:  $SA_EMAIL"
echo "  WIF Pool:         $WIF_POOL_ID"
echo ""
echo "Principal Set:"
echo "  $PRINCIPAL_SET"
echo ""

if $DRY_RUN; then
  echo "[DRY RUN] Would run:"
  echo "  gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \\"
  echo "    --project=$GCP_PROJECT_ID \\"
  echo "    --role=roles/iam.workloadIdentityUser \\"
  echo "    --member=$PRINCIPAL_SET"
  echo ""
  echo "No changes made."
  exit 0
fi

# Check if binding already exists
echo "Checking existing bindings..."
EXISTING=$(gcloud iam service-accounts get-iam-policy "$SA_EMAIL" \
  --project="$GCP_PROJECT_ID" \
  --format="json" 2>/dev/null | \
  grep -F "$PRINCIPAL_SET" || true)

if [[ -n "$EXISTING" ]]; then
  echo "Binding already exists for $GITHUB_ORG/$GITHUB_REPO"
  echo "No changes needed."
  exit 0
fi

# Add the binding
echo "Adding Workload Identity User binding..."
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$GCP_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$PRINCIPAL_SET"

echo ""
echo "=== Done ==="
echo ""
echo "The repository $GITHUB_ORG/$GITHUB_REPO can now use the reusable deploy workflow."
echo ""
echo "In $GITHUB_ORG/$GITHUB_REPO, create a workflow like:"
echo ""
echo "  name: Deploy"
echo "  on:"
echo "    push:"
echo "      branches: [main]"
echo ""
echo "  jobs:"
echo "    deploy:"
echo "      uses: N43-Studio/infrastructure/.github/workflows/deploy-service.yml@main"
echo "      with:"
echo "        project: <project-name>"
echo "        environment: dev"
echo "        action: apply"
echo "        image_tag: \${{ github.sha }}"
echo "      secrets: inherit"
echo ""
echo "Ensure the caller repo has these secrets:"
echo "  - GCP_PROJECT_ID: $GCP_PROJECT_ID"
echo "  - GCP_PROJECT_NUMBER: $PROJECT_NUMBER"
echo ""
