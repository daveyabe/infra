#!/usr/bin/env bash
# Request increases for common GCP service quotas that engineers often hit.
# Uses the Cloud Quotas API to submit preference requests (approval is async, ~1–2 business days).
#
# Usage:
#   $0 <PROJECT_ID> [REGION ...]
#
# Examples:
#   $0 my-gcp-project
#   $0 my-gcp-project us-central1 us-east1 northamerica-northeast2
#
# Optional env vars:
#   QUOTA_REGIONS   Space-separated regions to request regional quotas for (default: us-central1 us-east1 northamerica-northeast2)
#   QUOTA_JUSTIFICATION  Short justification for increase requests (default: "Bootstrap: raise defaults for dev/workloads")
#
# Prerequisites:
#   gcloud components install beta
#   Permissions: roles/cloudquotas.admin or serviceusage.quotas.update on the project

set -e

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID> [REGION ...]}"
shift || true

# Regions to request regional quota increases for (default if none passed)
QUOTA_REGIONS="${QUOTA_REGIONS:-us-central1 us-east1 northamerica-northeast2}"
if [[ $# -gt 0 ]]; then
  QUOTA_REGIONS=("$@")
else
  QUOTA_REGIONS=($QUOTA_REGIONS)
fi

QUOTA_JUSTIFICATION="${QUOTA_JUSTIFICATION:-Bootstrap: raise defaults for dev/workloads}"

echo "=== Increase common GCP service quotas ==="
echo "  Project:       $PROJECT_ID"
echo "  Regions:       ${QUOTA_REGIONS[*]}"
echo "  Justification: $QUOTA_JUSTIFICATION"
echo ""

gcloud config set project "$PROJECT_ID"

# Cloud Quotas API is required for gcloud beta quotas preferences
echo "Enabling Cloud Quotas API..."
gcloud services enable cloudquotas.googleapis.com --project="$PROJECT_ID"

# Request a quota increase. Idempotent: create with deterministic preference-id; if it exists, update.
# For global quotas pass dimensions as "" (--dimensions is omitted).
request_quota() {
  local service="$1"
  local quota_id="$2"
  local dimensions="$3"
  local preferred_value="$4"
  local dim_slug="${dimensions:-global}"
  local pref_id="bootstrap-${quota_id}-${dim_slug//[^a-z0-9-]/_}"

  local create_cmd=(gcloud beta quotas preferences create
    --project="$PROJECT_ID"
    --billing-project="$PROJECT_ID"
    --service="$service"
    --quota-id="$quota_id"
    --preferred-value="$preferred_value"
    --justification="$QUOTA_JUSTIFICATION"
    --preference-id="$pref_id"
    --quiet)
  [[ -n "$dimensions" ]] && create_cmd+=(--dimensions="$dimensions")

  if "${create_cmd[@]}" 2>/dev/null; then
    echo "  Requested: $quota_id ($dim_slug) = $preferred_value"
    return 0
  fi
  if gcloud beta quotas preferences update "$pref_id" \
    --project="$PROJECT_ID" \
    --billing-project="$PROJECT_ID" \
    --quota-id="$quota_id" \
    --service="$service" \
    --preferred-value="$preferred_value" \
    --justification="$QUOTA_JUSTIFICATION" \
    --quiet 2>/dev/null; then
    echo "  Updated:   $quota_id ($dim_slug) = $preferred_value"
    return 0
  fi
  echo "  Skipped:   $quota_id ($dim_slug) (create/update failed; may need manual request)"
  return 0
}

# --- Compute Engine: regional quotas (per region) ---
# These are the ones engineers hit most: CPUs, VM count, external IPs, disks.
for region in "${QUOTA_REGIONS[@]}"; do
  request_quota "compute.googleapis.com" "CPUS-per-project-region" "region=$region" "96"
  request_quota "compute.googleapis.com" "INSTANCES-per-project-region" "region=$region" "24"
  request_quota "compute.googleapis.com" "IN_USE_ADDRESSES-per-project-region" "region=$region" "24"
  # Persistent disk: SSD and standard (GB). Defaults are often 500–1000 GB per region.
  request_quota "compute.googleapis.com" "SSD-TOTAL-GB" "region=$region" "2000"
  request_quota "compute.googleapis.com" "DISKS-TOTAL-GB" "region=$region" "5000"
  # GPUs: 0 → 2 per region (T4 is widely available; other types have separate quota IDs).
  request_quota "compute.googleapis.com" "NVIDIA_T4_GPUS" "region=$region" "2"
done

# --- Compute: global quotas (load balancing, IPs) ---
# In-use IP addresses (often 8 by default; quota ID may vary)
request_quota "compute.googleapis.com" "IN_USE_ADDRESSES" "" "32" || true

# Forwarding rules (classic ALB/NLB). Default often 10; needed for load balancers.
request_quota "compute.googleapis.com" "FORWARDING_RULES" "" "30" || true

# Health checks. Default often 10; each backend/URL map can need several.
request_quota "compute.googleapis.com" "HEALTH_CHECKS" "" "30" || true

# Global external managed forwarding rules (global HTTP(S) LB). Default often 10.
request_quota "compute.googleapis.com" "GLOBAL_EXTERNAL_MANAGED_FORWARDING_RULES" "" "20" || true

echo ""
echo "=== Quota increase requests submitted ==="
echo "  Check status: gcloud beta quotas preferences list --project=$PROJECT_ID"
echo "  Requests are reviewed by Google (typically 1–2 business days)."
echo "  To list quota IDs for a service: gcloud beta quotas info list --service=compute.googleapis.com --project=$PROJECT_ID"
echo ""
