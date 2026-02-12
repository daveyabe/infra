#!/usr/bin/env bash
# Create a GCP project if it does not already exist.
# Usage: ./provision_project.sh <PROJECT_ID> [PROJECT_NAME] [ORGANIZATION_ID]
#
# PROJECT_ID      - globally unique project ID (e.g. my-org-dev-12345)
# PROJECT_NAME    - optional display name; defaults to PROJECT_ID if omitted
# ORGANIZATION_ID - optional org ID (numeric); project is created under this org if provided

set -e

PROJECT_ID="${1:?Usage: $0 <project-id-randomness> [PROJECT_NAME] [ORGANIZATION_ID (833531661158 = N43 Studio)]}"
PROJECT_NAME="${2:-$PROJECT_ID}"
ORGANIZATION_ID="${3:-}"

if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
  echo "Project $PROJECT_ID already exists."
  gcloud config set project "$PROJECT_ID"
  exit 0
fi

echo "Creating project: $PROJECT_ID ($PROJECT_NAME)"
CREATE_CMD=(gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME")
[[ -n "$ORGANIZATION_ID" ]] && CREATE_CMD+=(--organization="$ORGANIZATION_ID")
"${CREATE_CMD[@]}"
gcloud config set project "$PROJECT_ID"
echo "Project $PROJECT_ID created."
