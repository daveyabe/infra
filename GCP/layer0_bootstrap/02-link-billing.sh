#!/usr/bin/env bash
# Link a billing account to a GCP project.
# Required for enabling APIs and using billable resources.
#
# Usage: ./02-link-billing.sh <PROJECT_ID> <BILLING_ACCOUNT_ID>
#
# PROJECT_ID         - target GCP project ID
# BILLING_ACCOUNT_ID - billing account ID (e.g. 01ABCD-23EF56-789GHI)
#   List accounts: gcloud billing accounts list

set -e

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID> <BILLING_ACCOUNT_ID>}"
BILLING_ACCOUNT_ID="${2:?Usage: $0 <PROJECT_ID> <BILLING_ACCOUNT_ID>}"

if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
  echo "Error: Project $PROJECT_ID not found."
  exit 1
fi

echo "Linking billing account $BILLING_ACCOUNT_ID to project $PROJECT_ID"
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
gcloud config set project "$PROJECT_ID"
echo "Billing linked successfully."
