#!/usr/bin/env bash
# vertex-model-garden.sh — Deploy OSS models from Vertex AI Model Garden
# and generate Gas Town + Cursor configuration.
# Convention: follows adk-menu.sh patterns (load_config, ensure_*, menu_loop).

STATE_DIR="${HOME}/.vertex-model-garden"
DEPLOYMENTS_DIR="${STATE_DIR}/deployments"
CONFIG_FILE="${STATE_DIR}/config"
LITELLM_CONFIG="${HOME}/.litellm/config.yaml"
LITELLM_PORT=4000

usage() {
  cat <<'EOF'
vertex-model-garden.sh — Deploy Vertex AI Model Garden models for Gas Town

Usage: vertex-model-garden.sh [command]
Commands:
  list              List deployable models (filterable)
  configs           Show hardware configs for a model
  deploy            Deploy a model to a Vertex AI endpoint
  status            List active deployments
  undeploy          Undeploy a model and delete endpoint
  generate-config   Generate Gas Town + Cursor config
  help              Show this help
  (no command)      Interactive menu

Config: ~/.vertex-model-garden/config
  PROJECT=my-gcp-project
  REGION=us-central1
  HF_TOKEN=hf_...            (optional, for gated models like Llama)
EOF
}

# --- Config loading ---

load_config() {
  if [[ -r "$CONFIG_FILE" ]]; then
    local line
    while IFS= read -r line; do
      line="${line%%#*}"                              # strip comments
      line="${line#"${line%%[![:space:]]*}"}"          # trim leading
      line="${line%"${line##*[![:space:]]}"}"          # trim trailing
      [[ -z "$line" ]] && continue
      case "$line" in
        PROJECT=*)  [[ -z "${PROJECT:-}" ]]  && PROJECT="${line#PROJECT=}" ;;
        REGION=*)   [[ -z "${REGION:-}" ]]   && REGION="${line#REGION=}" ;;
        HF_TOKEN=*) [[ -z "${HF_TOKEN:-}" ]] && HF_TOKEN="${line#HF_TOKEN=}" ;;
      esac
    done < "$CONFIG_FILE"
  fi
}

# --- Prerequisite checks ---

ensure_gcloud() {
  if ! command -v gcloud &>/dev/null; then
    echo "ERROR: gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
    return 1
  fi
  local account
  account=$(gcloud config get-value account 2>/dev/null)
  if [[ -z "$account" || "$account" == "(unset)" ]]; then
    echo "ERROR: Not authenticated. Run: gcloud auth login"
    return 1
  fi
  return 0
}

ensure_project() {
  load_config
  if [[ -z "${PROJECT:-}" ]]; then
    PROJECT=$(gcloud config get-value project 2>/dev/null)
  fi
  if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
    read -r -p "GCP project ID: " PROJECT
    PROJECT="${PROJECT#"${PROJECT%%[![:space:]]*}"}"
    PROJECT="${PROJECT%"${PROJECT##*[![:space:]]}"}"
  fi
  if [[ -z "$PROJECT" ]]; then
    echo "ERROR: Project ID required."
    return 1
  fi
  export PROJECT
}

ensure_region() {
  load_config
  if [[ -z "${REGION:-}" ]]; then
    REGION=$(gcloud config get-value ai/region 2>/dev/null)
  fi
  if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
    REGION="us-central1"
    echo "Using default region: $REGION"
  fi
  export REGION
}

ensure_apis() {
  echo "Checking Vertex AI API is enabled..."
  local enabled
  enabled=$(gcloud services list --project="$PROJECT" --filter="name:aiplatform.googleapis.com" --format="value(name)" 2>/dev/null)
  if [[ -z "$enabled" ]]; then
    echo "Enabling aiplatform.googleapis.com..."
    gcloud services enable aiplatform.googleapis.com --project="$PROJECT" || {
      echo "ERROR: Failed to enable Vertex AI API. Check permissions."
      return 1
    }
  fi
}

# --- State management ---

init_state_dir() {
  mkdir -p "$DEPLOYMENTS_DIR"
}

save_deployment() {
  local alias="$1" endpoint_id="$2" model="$3" region="$4" project="$5"
  local machine_type="${6:-}" accelerator_type="${7:-}" accelerator_count="${8:-0}"
  cat > "${DEPLOYMENTS_DIR}/${alias}.json" <<EOF
{
  "alias": "${alias}",
  "endpoint_id": "${endpoint_id}",
  "model": "${model}",
  "region": "${region}",
  "project": "${project}",
  "machine_type": "${machine_type}",
  "accelerator_type": "${accelerator_type}",
  "accelerator_count": ${accelerator_count},
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  echo "Saved deployment state to ${DEPLOYMENTS_DIR}/${alias}.json"
}

load_deployment() {
  local alias="$1"
  local file="${DEPLOYMENTS_DIR}/${alias}.json"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: No saved deployment for '${alias}'. Run 'status' to see deployments."
    return 1
  fi
  cat "$file"
}

list_saved_deployments() {
  local f
  for f in "${DEPLOYMENTS_DIR}"/*.json; do
    [[ -e "$f" ]] || { echo "(none)"; return; }
    local alias endpoint_id model
    alias=$(basename "$f" .json)
    endpoint_id=$(grep -o '"endpoint_id": *"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    model=$(grep -o '"model": *"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    printf "  %-25s endpoint=%-25s model=%s\n" "$alias" "$endpoint_id" "$model"
  done
}

# --- Utility ---

# Derive a short alias from a model name: google/gemma2@gemma-2-9b -> vertex-gemma-2-9b
make_alias() {
  local model="$1"
  local short
  # If model has @version, use the version part; otherwise use the model name after /
  if [[ "$model" == *@* ]]; then
    short="${model##*@}"
  elif [[ "$model" == */* ]]; then
    short="${model##*/}"
  else
    short="$model"
  fi
  # Lowercase, replace non-alphanumeric with hyphens
  short=$(echo "$short" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '-' | sed 's/--*/-/g; s/^-//; s/-$//')
  echo "vertex-${short}"
}

# Check if LiteLLM proxy is running
litellm_is_running() {
  curl -sf "http://localhost:${LITELLM_PORT}/health" &>/dev/null
}

# --- Subcommand dispatch (at bottom of file) ---

# cmd_list(), cmd_configs(), cmd_deploy(), cmd_status(), cmd_undeploy(),
# cmd_generate_config(), show_banner(), menu_loop() are defined in subsequent tasks.
# Stub them here so the script doesn't error:

cmd_list()            { echo "Not yet implemented. See Task 2."; }
cmd_configs()         { echo "Not yet implemented. See Task 2."; }
cmd_deploy()          { echo "Not yet implemented. See Task 3."; }
cmd_status()          { echo "Not yet implemented. See Task 4."; }
cmd_undeploy()        { echo "Not yet implemented. See Task 4."; }
cmd_generate_config() { echo "Not yet implemented. See Task 5."; }
show_banner()         { echo "  Vertex AI Model Garden -- Gas Town"; echo ""; }
menu_loop()           { echo "Not yet implemented. See Task 7."; }

# --- Main dispatch ---
init_state_dir

subcommand="${1:-menu}"
case "$subcommand" in
  list)            ensure_gcloud && ensure_project && cmd_list "${@:2}" ;;
  configs)         ensure_gcloud && ensure_project && cmd_configs "${@:2}" ;;
  deploy)          ensure_gcloud && ensure_project && ensure_region && ensure_apis && cmd_deploy "${@:2}" ;;
  status)          ensure_gcloud && ensure_project && ensure_region && cmd_status ;;
  undeploy)        ensure_gcloud && ensure_project && ensure_region && cmd_undeploy "${@:2}" ;;
  generate-config) cmd_generate_config "${@:2}" ;;
  help)            usage; exit 0 ;;
  menu)            menu_loop ;;
  *)               usage; exit 1 ;;
esac
