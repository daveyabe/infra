#!/usr/bin/env bash
# vertex-model-garden.sh — Deploy OSS models from Vertex AI Model Garden
# and generate Gas Town + Cursor configuration.
# Convention: follows adk-menu.sh patterns (load_config, ensure_*, menu_loop).

STATE_DIR="${HOME}/.vertex-model-garden"
DEPLOYMENTS_DIR="${STATE_DIR}/deployments"
CONFIG_FILE="${STATE_DIR}/config"
LITELLM_CONFIG="${HOME}/.litellm/config.yaml"
LITELLM_PORT=4000
# Must match ~/.litellm/config.yaml general_settings.master_key (gastown_install_litellm_proxy default).
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-gastown-litellm}"

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

# Check if LiteLLM proxy is running (health endpoint requires Authorization when master_key is set)
litellm_is_running() {
  curl -sf -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    "http://127.0.0.1:${LITELLM_PORT}/health" &>/dev/null
}

# --- Subcommand dispatch (at bottom of file) ---

# show_banner() and menu_loop() follow adk-menu.sh conventions (interactive menu).

cmd_list() {
  local filter="${1:-}"
  echo "Fetching deployable models from Model Garden (project=$PROJECT)..."
  echo ""

  if [[ -n "$filter" ]]; then
    echo "Filter: $filter"
    echo ""
    gcloud ai model-garden models list \
      --project="$PROJECT" \
      --format="table(name, supportedActions.join(','))" 2>&1 \
      | grep -i "$filter" || echo "No models matching '$filter'."
  else
    echo "TIP: Pass a filter to narrow results: vertex-model-garden.sh list llama"
    echo ""
    gcloud ai model-garden models list \
      --project="$PROJECT" \
      --format="table(name, supportedActions.join(','))" 2>&1 \
      | head -80
    echo ""
    echo "(Showing first 80 results. Use a filter to narrow.)"
  fi
}

cmd_configs() {
  local model="${1:-}"
  if [[ -z "$model" ]]; then
    read -r -p "Model name (e.g. google/gemma2@gemma-2-9b): " model
    model="${model#"${model%%[![:space:]]*}"}"
    model="${model%"${model##*[![:space:]]}"}"
  fi
  if [[ -z "$model" ]]; then
    echo "ERROR: Model name required."
    return 1
  fi

  echo ""
  echo "Deployment configurations for: $model"
  echo "============================================="
  gcloud ai model-garden models list-deployment-config \
    --model="$model" \
    --project="$PROJECT" 2>&1

  echo ""
  echo "Use these machine-type and accelerator values with the 'deploy' command."
}

cmd_deploy() {
  local model="" machine_type="" accel_type="" accel_count=""
  local eula_reply eula_flag="" proceed search_term

  # --- Step 1: Model selection ---
  read -r -p "Model to deploy (e.g. google/gemma2@gemma-2-9b, or '?' to search): " model
  model="${model#"${model%%[![:space:]]*}"}"
  model="${model%"${model##*[![:space:]]}"}"
  if [[ "$model" == "?" ]]; then
    read -r -p "Search term: " search_term
    cmd_list "$search_term"
    echo ""
    read -r -p "Model to deploy: " model
    model="${model#"${model%%[![:space:]]*}"}"
    model="${model%"${model##*[![:space:]]}"}"
  fi
  if [[ -z "$model" ]]; then
    echo "ERROR: Model name required."
    return 1
  fi

  # --- Step 2: Show and select hardware config ---
  echo ""
  echo "Fetching deployment configurations for $model..."
  gcloud ai model-garden models list-deployment-config \
    --model="$model" --project="$PROJECT" 2>&1
  echo ""
  read -r -p "Machine type (e.g. g2-standard-12, or Enter for default): " machine_type
  machine_type="${machine_type#"${machine_type%%[![:space:]]*}"}"
  machine_type="${machine_type%"${machine_type##*[![:space:]]}"}"

  if [[ -n "$machine_type" ]]; then
    read -r -p "Accelerator type (e.g. NVIDIA_L4, or Enter to skip): " accel_type
    accel_type="${accel_type#"${accel_type%%[![:space:]]*}"}"
    accel_type="${accel_type%"${accel_type##*[![:space:]]}"}"
    if [[ -n "$accel_type" ]]; then
      read -r -p "Accelerator count [1]: " accel_count
      accel_count="${accel_count:-1}"
    fi
  fi

  # --- Step 3: Hugging Face token for gated models ---
  load_config
  if [[ "$model" == *llama* || "$model" == *mistral* || "$model" == *falcon* ]]; then
    if [[ -z "${HF_TOKEN:-}" ]]; then
      echo ""
      echo "This model may be gated on Hugging Face. A HF access token may be required."
      echo "Get one at: https://huggingface.co/settings/tokens"
      read -r -p "Hugging Face token (or Enter to skip): " HF_TOKEN
    fi
  fi

  # --- Step 4: EULA ---
  echo ""
  echo "WARNING: Many Model Garden models require EULA acceptance."
  read -r -p "Accept EULA? [Y/n] " eula_reply
  eula_flag=""
  if [[ ! "$eula_reply" =~ ^[nN] ]]; then
    eula_flag="--accept-eula"
  fi

  # --- Step 5: Cost warning ---
  echo ""
  echo "================================================================"
  echo "  COST WARNING: GPU endpoints bill CONTINUOUSLY while deployed."
  echo "  A single NVIDIA L4 (g2-standard-12) costs ~\$1.50/hour."
  echo "  A100 or H100 instances cost \$5-30+/hour."
  echo "  Use 'undeploy' to stop billing when done."
  echo "================================================================"
  read -r -p "Proceed with deployment? [y/N] " proceed
  if [[ ! "$proceed" =~ ^[yY] ]]; then
    echo "Cancelled."
    return 0
  fi

  # --- Step 6: Build and run deploy command ---
  local deployment_alias endpoint_name deploy_output deploy_rc
  deployment_alias=$(make_alias "$model")
  endpoint_name="gastown-${deployment_alias}"

  local -a gcloud_deploy=(ai model-garden models deploy
    --model="$model"
    --project="$PROJECT"
    --region="$REGION"
    --endpoint-display-name="$endpoint_name")
  [[ -n "$machine_type" ]] && gcloud_deploy+=(--machine-type="$machine_type")
  [[ -n "$accel_type" ]]   && gcloud_deploy+=(--accelerator-type="$accel_type")
  [[ -n "$accel_count" ]]  && gcloud_deploy+=(--accelerator-count="$accel_count")
  [[ -n "$eula_flag" ]]    && gcloud_deploy+=("$eula_flag")
  if [[ -n "${HF_TOKEN:-}" ]]; then
    gcloud_deploy+=(--hugging-face-access-token="$HF_TOKEN")
  fi

  echo ""
  echo "Running: gcloud ${gcloud_deploy[*]}"
  echo "(This may take 15-30 minutes...)"
  echo ""

  deploy_output=$(mktemp)
  gcloud "${gcloud_deploy[@]}" 2>&1 | tee "$deploy_output"
  deploy_rc=${PIPESTATUS[0]}

  if [[ $deploy_rc -ne 0 ]]; then
    echo ""
    echo "ERROR: Deployment failed (exit code $deploy_rc)."
    echo "Common causes:"
    echo "  - Insufficient GPU quota (request at: https://console.cloud.google.com/iam-admin/quotas)"
    echo "  - Model requires EULA acceptance"
    echo "  - Region does not support the requested accelerator"
    rm -f "$deploy_output"
    return 1
  fi

  # --- Step 7: Parse endpoint ID ---
  local endpoint_id=""
  endpoint_id=$(grep -oE 'endpoints/[0-9]+' "$deploy_output" | head -1 | sed 's|endpoints/||')

  if [[ -z "$endpoint_id" ]]; then
    echo "Could not parse endpoint ID from output. Searching by display name..."
    endpoint_id=$(gcloud ai endpoints list \
      --project="$PROJECT" --region="$REGION" \
      --filter="displayName=${endpoint_name}" \
      --format="value(name)" 2>/dev/null | grep -oE 'endpoints/[0-9]+' | head -1 | sed 's|endpoints/||')
  fi

  rm -f "$deploy_output"

  if [[ -z "$endpoint_id" ]]; then
    echo ""
    echo "WARNING: Could not determine endpoint ID automatically."
    echo "Run '${0##*/} status' to find your endpoint."
    return 1
  fi

  # --- Step 8: Save state and print next steps ---
  save_deployment "$deployment_alias" "$endpoint_id" "$model" "$REGION" "$PROJECT" \
    "${machine_type:-auto}" "${accel_type:-auto}" "${accel_count:-0}"

  echo ""
  echo "============================================="
  echo "  DEPLOYMENT SUCCESSFUL"
  echo "  Alias:       $deployment_alias"
  echo "  Endpoint ID: $endpoint_id"
  echo "  Region:      $REGION"
  echo "  Project:     $PROJECT"
  echo "============================================="
  echo ""
  echo "Next step: generate Gas Town + Cursor config:"
  echo "  ${0##*/} generate-config $deployment_alias"
  echo ""
  echo "To stop billing:"
  echo "  ${0##*/} undeploy $deployment_alias"
}
cmd_status() {
  echo "=== Saved deployments (local state) ==="
  list_saved_deployments
  echo ""
  echo "=== Live Vertex AI endpoints (project=$PROJECT, region=$REGION) ==="
  gcloud ai endpoints list \
    --project="$PROJECT" \
    --region="$REGION" \
    --format="table(name.basename(), displayName, deployedModels[0].id, createTime)" 2>&1
}

cmd_undeploy() {
  local alias="${1:-}"

  if [[ -z "$alias" ]]; then
    echo "Saved deployments:"
    list_saved_deployments
    echo ""
    read -r -p "Alias to undeploy (or endpoint ID): " alias
    alias="${alias#"${alias%%[![:space:]]*}"}"
    alias="${alias%"${alias##*[![:space:]]}"}"
  fi
  if [[ -z "$alias" ]]; then
    echo "ERROR: Alias or endpoint ID required."
    return 1
  fi

  local endpoint_id="" deployed_model_id=""

  if [[ -f "${DEPLOYMENTS_DIR}/${alias}.json" ]]; then
    endpoint_id=$(grep -o '"endpoint_id": *"[^"]*"' "${DEPLOYMENTS_DIR}/${alias}.json" | head -1 | cut -d'"' -f4)
  else
    endpoint_id="$alias"
  fi

  if [[ -z "$endpoint_id" ]]; then
    echo "ERROR: Could not resolve endpoint ID for '$alias'."
    return 1
  fi

  echo "Endpoint ID: $endpoint_id"
  echo ""

  deployed_model_id=$(gcloud ai endpoints describe "$endpoint_id" \
    --project="$PROJECT" --region="$REGION" \
    --format="value(deployedModels[0].id)" 2>/dev/null)

  echo "================================================================"
  echo "  WARNING: This will undeploy the model and delete the endpoint."
  echo "  Endpoint: $endpoint_id"
  echo "  Deployed model: ${deployed_model_id:-unknown}"
  echo "================================================================"
  read -r -p "Proceed? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[yY] ]]; then
    echo "Cancelled."
    return 0
  fi

  if [[ -n "$deployed_model_id" ]]; then
    echo "Undeploying model ${deployed_model_id} from endpoint ${endpoint_id}..."
    gcloud ai endpoints undeploy-model "$endpoint_id" \
      --project="$PROJECT" \
      --region="$REGION" \
      --deployed-model-id="$deployed_model_id" \
      --quiet 2>&1
    local rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "WARNING: undeploy-model failed (rc=$rc). Trying to delete endpoint anyway..."
    fi
  fi

  echo "Deleting endpoint ${endpoint_id}..."
  gcloud ai endpoints delete "$endpoint_id" \
    --project="$PROJECT" \
    --region="$REGION" \
    --quiet 2>&1

  if [[ -f "${DEPLOYMENTS_DIR}/${alias}.json" ]]; then
    rm -f "${DEPLOYMENTS_DIR}/${alias}.json"
    echo "Removed local state for '$alias'."
  fi

  echo ""
  echo "Undeploy complete. Billing for this endpoint has stopped."
}

cmd_generate_config() {
  local alias="${1:-}"

  if [[ -z "$alias" ]]; then
    echo "Saved deployments:"
    list_saved_deployments
    echo ""
    read -r -p "Alias to generate config for: " alias
    alias="${alias#"${alias%%[![:space:]]*}"}"
    alias="${alias%"${alias##*[![:space:]]}"}"
  fi
  if [[ -z "$alias" ]]; then
    echo "ERROR: Alias required. Run 'deploy' first or check 'status'."
    return 1
  fi

  local state_file="${DEPLOYMENTS_DIR}/${alias}.json"
  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: No saved deployment for '${alias}'."
    echo "If you deployed manually, create ${state_file} with endpoint_id, model, region, project."
    return 1
  fi

  local endpoint_id model region project
  endpoint_id=$(grep -o '"endpoint_id": *"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4)
  model=$(grep -o '"model": *"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4)
  region=$(grep -o '"region": *"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4)
  project=$(grep -o '"project": *"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4)

  local raw_predict_url="https://${region}-aiplatform.googleapis.com/v1/projects/${project}/locations/${region}/endpoints/${endpoint_id}"

  echo ""
  echo "============================================================"
  echo "  GAS TOWN + CURSOR CONFIGURATION"
  echo "  Model:    $model"
  echo "  Alias:    $alias"
  echo "  Endpoint: $endpoint_id"
  echo "============================================================"
  echo ""

  if litellm_is_running; then
    echo "--- OPTION A: LiteLLM Proxy (DETECTED RUNNING on :${LITELLM_PORT}) ---"
    echo ""
    echo "Step 1: Register this model with LiteLLM"
    echo ""
    echo "  Add to ~/.litellm/config.yaml under model_list:"
    echo ""
    echo "    - model_name: \"${alias}\""
    echo "      litellm_params:"
    echo "        model: \"vertex_ai/openai/${endpoint_id}\""
    echo "        vertex_project: \"${project}\""
    echo "        vertex_location: \"${region}\""
    echo ""
    echo "  Then restart LiteLLM:  systemctl --user restart litellm-proxy"
    echo ""
    echo "Step 2: Add model in Cursor IDE"
    echo ""
    echo "  Cursor Settings (Cmd+Shift+P > Cursor Settings) > Models > Add Model"
    echo "    Provider:  OpenAI Compatible"
    echo "    Name:      ${alias}"
    echo "    Base URL:  http://localhost:${LITELLM_PORT}/v1"
    echo "    API Key:   sk-gastown-litellm"
    echo ""
  else
    echo "--- OPTION A: LiteLLM Proxy (NOT RUNNING) ---"
    echo ""
    echo "  LiteLLM is not detected on port ${LITELLM_PORT}."
    echo "  To install: source the gastown_install_litellm_proxy() function"
    echo "  from /opt/gastown/data/engineering/scripts/gastown-host-tools.sh"
    echo ""
  fi

  echo "--- OPTION B: Manual Token (no proxy needed, token expires hourly) ---"
  echo ""
  echo "Step 1: Get a fresh GCP access token"
  echo ""
  echo "  gcloud auth print-access-token"
  echo ""
  echo "Step 2: Add model in Cursor IDE"
  echo ""
  echo "  Cursor Settings > Models > Add Model"
  echo "    Provider:  OpenAI Compatible"
  echo "    Name:      ${alias}"
  echo "    Base URL:  ${raw_predict_url}"
  echo "    API Key:   <paste token from step 1>"
  echo ""
  echo "  NOTE: Tokens expire after ~1 hour. Repeat step 1 and update the key."
  echo ""

  echo "--- GAS TOWN CONFIGURATION (same for both options) ---"
  echo ""
  echo "Add this to /opt/gastown/data/settings/config.json under \"agents\":"
  echo ""
  echo "    \"${alias}\": {"
  echo "      \"provider\": \"cursor\","
  echo "      \"command\": \"cursor-agent\","
  echo "      \"args\": [\"-f\", \"--model\", \"${alias}\"]"
  echo "    }"
  echo ""
  echo "To set as town default:"
  echo "  Change \"default_agent\" to \"${alias}\""
  echo ""
  echo "To assign to specific roles, add to \"role_agents\":"
  echo "  \"polecat\": \"${alias}\""
  echo "  \"crew\": \"${alias}\""
  echo ""
  echo "--- FULL config.json EXAMPLE ---"
  echo ""
  cat <<JSONEOF
{
  "type": "town-settings",
  "version": 1,
  "default_agent": "cursor-composer2",
  "agents": {
    "cursor-composer2": {
      "provider": "cursor",
      "command": "cursor-agent",
      "args": ["-f", "--model", "composer-2"]
    },
    "${alias}": {
      "provider": "cursor",
      "command": "cursor-agent",
      "args": ["-f", "--model", "${alias}"]
    }
  },
  "role_agents": {
    "mayor": "cursor-composer2",
    "deacon": "cursor-composer2",
    "witness": "${alias}",
    "refinery": "cursor-composer2",
    "polecat": "${alias}",
    "crew": "cursor-composer2"
  }
}
JSONEOF
  echo ""
  echo "============================================================"
}

show_banner() {
  echo ""
  echo "  __     __        _              _    ___   __  __           _      _   "
  echo "  \ \   / /__ _ __| |_ _____  __ / \  |_ _| |  \/  | ___  __| | ___| |  "
  echo "   \ \ / / _ \ '__| __/ _ \ \/ // _ \  | |  | |\/| |/ _ \/ _\` |/ _ \ |  "
  echo "    \ V /  __/ |  | ||  __/>  </ ___ \ | |  | |  | | (_) | (_| |  __/ |  "
  echo "     \_/ \___|_|   \__\___/_/\_/_/   \_\___| |_|  |_|\___/ \__,_|\___|_|  "
  echo "                         Gas Town Model Garden"
  echo ""
}

menu_loop() {
  local choice
  while true; do
    load_config
    show_banner
    echo "  Project: ${PROJECT:-<not set>}  Region: ${REGION:-us-central1}"
    echo ""
    echo "  1) List available models"
    echo "  2) Show deployment configs for a model"
    echo "  3) Deploy a model"
    echo "  4) Show deployed endpoints (status)"
    echo "  5) Undeploy a model"
    echo "  6) Generate Gas Town + Cursor config"
    echo "  7) Exit"
    echo ""
    read -r -p "  Choice: " choice
    choice="${choice#"${choice%%[![:space:]]*}"}"
    choice="${choice%"${choice##*[![:space:]]}"}"
    case "$choice" in
      1)
        ensure_gcloud && ensure_project && cmd_list
        read -r -p "Press Enter to continue..."
        ;;
      2)
        ensure_gcloud && ensure_project && cmd_configs
        read -r -p "Press Enter to continue..."
        ;;
      3)
        ensure_gcloud && ensure_project && ensure_region && ensure_apis && cmd_deploy
        read -r -p "Press Enter to continue..."
        ;;
      4)
        ensure_gcloud && ensure_project && ensure_region && cmd_status
        read -r -p "Press Enter to continue..."
        ;;
      5)
        ensure_gcloud && ensure_project && ensure_region && cmd_undeploy
        read -r -p "Press Enter to continue..."
        ;;
      6)
        cmd_generate_config
        read -r -p "Press Enter to continue..."
        ;;
      7)
        exit 0
        ;;
      *)
        echo "Invalid choice."
        ;;
    esac
  done
}

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
