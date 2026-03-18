#!/usr/bin/env bash
# ADK bash menu: init venv, run ADK CLI/web, resume session, create agent, manage path.
# No set -e so menu loop does not exit on one failure.

usage() {
  echo "adk-menu.sh — ADK agent venv and run helper (init, run, web, resume, create, path)."
  echo "Usage: adk-menu.sh [command]"
  echo "Commands: init, run, web, resume, create, path, deploy, query-vertex, help."
  echo "With no command, runs interactive menu."
  echo "Config: ADK_AGENT_PATH env, or ./.adk-agent-path, or ~/.adk-menu.conf (ADK_AGENT_PATH=/path, optional ADK_WEB_PORT=8000)."
}

load_config() {
  local conf line
  if [[ -r ./.adk-agent-path ]]; then
    conf=./.adk-agent-path
  elif [[ -r ~/.adk-menu.conf ]]; then
    conf=~/.adk-menu.conf
  else
    conf=
  fi
  if [[ -n "$conf" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      if [[ -z "${ADK_AGENT_PATH:-}" && "$line" =~ ^ADK_AGENT_PATH=(.+)$ ]]; then
        ADK_AGENT_PATH="${BASH_REMATCH[1]}"
      elif [[ -z "${ADK_WEB_PORT:-}" && "$line" =~ ^ADK_WEB_PORT=([0-9]+)$ ]]; then
        ADK_WEB_PORT="${BASH_REMATCH[1]}"
      elif [[ -z "${ADK_DEPLOY_STAGING_BUCKET:-}" && "$line" =~ ^ADK_DEPLOY_STAGING_BUCKET=(.+)$ ]]; then
        ADK_DEPLOY_STAGING_BUCKET="${BASH_REMATCH[1]}"
      fi
    done < "$conf"
  fi
  export ADK_AGENT_PATH
  ADK_WEB_PORT="${ADK_WEB_PORT:-8000}"
}

# Ensure ADK_AGENT_PATH is set. Print message and return 1 if not. Used by init, run, web, resume.
ensure_path() {
  load_config
  if [[ -z "${ADK_AGENT_PATH:-}" ]]; then
    echo "ADK_AGENT_PATH not set. Use 'path' or set ADK_AGENT_PATH."
    return 1
  fi
  return 0
}

# Activate venv at ADK_AGENT_PATH/.venv so current shell and child processes use it. Return 1 if no venv.
activate_venv() {
  if [[ -z "${ADK_AGENT_PATH:-}" || ! -f "$ADK_AGENT_PATH/.venv/bin/activate" ]]; then
    return 1
  fi
  # shellcheck source=/dev/null
  source "$ADK_AGENT_PATH/.venv/bin/activate"
  export VIRTUAL_ENV
  export PATH
  return 0
}

# Ensure ADK_AGENT_PATH is an ADK agent dir (has agent.py or root_agent.yaml). Exit 1 with clear message if not.
ensure_agent_dir() {
  if [[ -f "$ADK_AGENT_PATH/agent.py" || -f "$ADK_AGENT_PATH/root_agent.yaml" ]]; then
    return 0
  fi
  echo "Not an ADK agent directory: $ADK_AGENT_PATH"
  echo "ADK expects a folder that contains agent.py (with root_agent) or root_agent.yaml."
  if [[ -f "$ADK_AGENT_PATH/adk-menu.sh" ]]; then
    echo "This path is the menu script directory. Set ADK_AGENT_PATH to your agent folder (e.g. the one from 'adk create <name>', or a subfolder that has agent.py)."
  else
    echo "Set ADK_AGENT_PATH to your agent folder (e.g. /path/to/my_agent where my_agent contains agent.py or root_agent.yaml)."
  fi
  exit 1
}

# True if the agent is configured to use Vertex AI (needs GCP auth).
agent_uses_vertex() {
  [[ -f "$ADK_AGENT_PATH/.env" ]] && grep -q 'GOOGLE_GENAI_USE_VERTEXAI=1' "$ADK_AGENT_PATH/.env" 2>/dev/null
}

# Ensure GOOGLE_API_KEY (Gemini / AI Studio) is available via env or agent .env. Prompt if missing.
ensure_api_key() {
  if [[ -n "${GOOGLE_API_KEY:-}" ]]; then
    return 0
  fi
  local key_from_env
  key_from_env=$(read_agent_env GOOGLE_API_KEY)
  if [[ -n "$key_from_env" ]]; then
    export GOOGLE_API_KEY="$key_from_env"
    return 0
  fi
  echo "GOOGLE_API_KEY not found (needed for Gemini / AI Studio)."
  echo "Get one at: https://aistudio.google.com/apikey"
  read -r -p "Enter API key (or leave empty to skip): " reply
  reply="${reply%"${reply##*[![:space:]]}"}"
  reply="${reply#"${reply%%[![:space:]]*}"}"
  if [[ -z "$reply" ]]; then
    echo "No API key set. adk may fail without it."
    return 1
  fi
  export GOOGLE_API_KEY="$reply"
  if [[ -n "${ADK_AGENT_PATH:-}" ]]; then
    read -r -p "Save to $ADK_AGENT_PATH/.env? [Y/n] " save_reply
    if [[ ! "$save_reply" =~ ^[nN] ]]; then
      echo "GOOGLE_API_KEY=$reply" >> "$ADK_AGENT_PATH/.env"
      echo "Saved to .env."
    fi
  fi
  return 0
}

# Ensure Google Cloud / Vertex AI credentials are available. Exit 1 with message if not.
# When AUTH_INTERACTIVE=1 (e.g. from menu), offer to run gcloud auth application-default login.
ensure_gcp_auth() {
  if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -r "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    return 0
  fi
  local adc_default="$HOME/.config/gcloud/application_default_credentials.json"
  if [[ -r "$adc_default" ]]; then
    return 0
  fi
  if command -v gcloud >/dev/null 2>&1 && gcloud auth application-default print-access-token >/dev/null 2>&1; then
    return 0
  fi
  echo "Vertex AI / Google Cloud credentials not found."
  echo "Run: gcloud auth application-default login"
  echo "Or set GOOGLE_APPLICATION_CREDENTIALS to a service account key JSON path."
  if [[ "${AUTH_INTERACTIVE:-0}" = "1" ]]; then
    read -r -p "Run 'gcloud auth application-default login' now? [y/N] " reply
    if [[ "$reply" =~ ^[yY] ]]; then
      gcloud auth application-default login
      return 0
    fi
  fi
  exit 1
}

# Path subcommand: show path; when PATH_INTERACTIVE=1 (from menu), always offer to set/change path and optionally save.
cmd_path() {
  load_config
  echo "ADK_AGENT_PATH=${ADK_AGENT_PATH:-<not set>}"
  if [[ "${PATH_INTERACTIVE:-0}" = "1" ]]; then
    if [[ -n "${ADK_AGENT_PATH:-}" ]]; then
      read -r -p "Change path? [y/N] " reply
    else
      read -r -p "Set path? [y/N] " reply
    fi
    if [[ "$reply" =~ ^[yY] ]]; then
      read -r -p "Path: " ADK_AGENT_PATH
      ADK_AGENT_PATH="${ADK_AGENT_PATH%"${ADK_AGENT_PATH##*[![:space:]]}"}"
      ADK_AGENT_PATH="${ADK_AGENT_PATH#"${ADK_AGENT_PATH%%[![:space:]]*}"}"
      if [[ -n "$ADK_AGENT_PATH" ]]; then
        export ADK_AGENT_PATH
        echo "ADK_AGENT_PATH=$ADK_AGENT_PATH"
        read -r -p "Save to config? [y/N] " reply2
        if [[ "$reply2" =~ ^[yY] ]]; then
          echo "ADK_AGENT_PATH=$ADK_AGENT_PATH" > ~/.adk-menu.conf
        fi
      fi
    fi
  fi
}

cmd_init() {
  ensure_path || exit 1
  if [[ ! -d "$ADK_AGENT_PATH" ]]; then
    echo "Agent path does not exist. Create with 'adk create <name>' (use subcommand 'create') or set path to an existing agent."
    exit 1
  fi
  if [[ -d "$ADK_AGENT_PATH/.venv" ]]; then
    "$ADK_AGENT_PATH/.venv/bin/pip" install google-adk
  else
    python3 -m venv "$ADK_AGENT_PATH/.venv"
    "$ADK_AGENT_PATH/.venv/bin/pip" install google-adk
  fi
  echo "Init done. Venv at $ADK_AGENT_PATH/.venv"
}
cmd_run() {
  ensure_path || exit 1
  if [[ ! -d "$ADK_AGENT_PATH" ]]; then
    echo "Agent path does not exist: $ADK_AGENT_PATH"
    exit 1
  fi
  if [[ ! -f "$ADK_AGENT_PATH/.venv/bin/activate" ]]; then
    echo "No .venv at $ADK_AGENT_PATH/.venv. Run 'init' first."
    exit 1
  fi
  activate_venv || exit 1
  if [[ ! -x "$ADK_AGENT_PATH/.venv/bin/adk" ]]; then
    echo "google-adk not found. Run 'init' and ensure venv is correct."
    exit 1
  fi
  ensure_agent_dir
  if agent_uses_vertex; then
    ensure_gcp_auth || exit 1
  else
    ensure_api_key
  fi
  "$ADK_AGENT_PATH/.venv/bin/adk" run "$ADK_AGENT_PATH"
}
cmd_web() {
  ensure_path || exit 1
  if [[ ! -d "$ADK_AGENT_PATH" ]]; then
    echo "Agent path does not exist: $ADK_AGENT_PATH"
    exit 1
  fi
  if [[ ! -f "$ADK_AGENT_PATH/.venv/bin/activate" ]]; then
    echo "No .venv at $ADK_AGENT_PATH/.venv. Run 'init' first."
    exit 1
  fi
  activate_venv || exit 1
  if [[ ! -x "$ADK_AGENT_PATH/.venv/bin/adk" ]]; then
    echo "google-adk not found. Run 'init' and ensure venv is correct."
    exit 1
  fi
  ensure_agent_dir
  if agent_uses_vertex; then
    ensure_gcp_auth || exit 1
  else
    ensure_api_key
  fi
  AGENT_PARENT=$(dirname "$ADK_AGENT_PATH")
  cd "$AGENT_PARENT" || exit 1
  # If default port 8000 is in use (or reserved e.g. TIME_WAIT), try 8001, 8002, ...
  web_port=$ADK_WEB_PORT
  if [[ "$web_port" = "8000" ]]; then
    while true; do
      if "$ADK_AGENT_PATH/.venv/bin/python" -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(0.5)
try:
  s.bind(('127.0.0.1', $web_port))
  s.close()
except OSError:
  exit(1)
" 2>/dev/null; then
        break
      fi
      if [[ "$web_port" = "8000" ]]; then
        echo "Port 8000 in use or reserved; trying next port..."
      fi
      web_port=$((web_port + 1))
      [[ $web_port -lt 65535 ]] || { echo "Could not find an available port."; exit 1; }
    done
    if [[ "$web_port" != "8000" ]]; then
      echo "Using port $web_port instead of 8000."
    fi
  fi
  export PORT="$web_port"
  echo "Starting web server on port ${web_port}."
  exec "$ADK_AGENT_PATH/.venv/bin/adk" web --port "$web_port"
}
# Discover session files under ADK_AGENT_PATH: .session.json and *.session.json, newest first. Return 1 if none.
discover_sessions() {
  local sessions=()
  if [[ -f "$ADK_AGENT_PATH/.session.json" ]]; then
    sessions+=("$ADK_AGENT_PATH/.session.json")
  fi
  local f
  for f in "$ADK_AGENT_PATH"/*.session.json; do
    [[ -e "$f" ]] && sessions+=("$f")
  done
  if ((${#sessions[@]} == 0)); then
    echo "No .session.json or *.session.json found under $ADK_AGENT_PATH."
    return 1
  fi
  # Sort by mtime newest first
  SESSION_FILES=()
  while IFS= read -r line; do
    SESSION_FILES+=("$line")
  done < <(ls -td "${sessions[@]}" 2>/dev/null)
  return 0
}

cmd_resume() {
  ensure_path || exit 1
  if [[ ! -d "$ADK_AGENT_PATH" ]]; then
    echo "Agent path does not exist: $ADK_AGENT_PATH"
    exit 1
  fi
  if [[ ! -f "$ADK_AGENT_PATH/.venv/bin/activate" ]]; then
    echo "No .venv at $ADK_AGENT_PATH/.venv. Run 'init' first."
    exit 1
  fi
  ensure_agent_dir
  if agent_uses_vertex; then
    ensure_gcp_auth || exit 1
  else
    ensure_api_key
  fi
  discover_sessions || exit 1
  local i=1 chosen path_reply
  for path_reply in "${SESSION_FILES[@]}"; do
    echo "  ($i) $path_reply"
    ((i++)) || true
  done
  read -r -p "Choose number or path: " reply
  reply="${reply%"${reply##*[![:space:]]}"}"
  reply="${reply#"${reply%%[![:space:]]*}"}"
  if [[ -z "$reply" ]]; then
    echo "No choice."
    exit 1
  fi
  if [[ "$reply" =~ ^[0-9]+$ ]]; then
    if (( reply >= 1 && reply <= ${#SESSION_FILES[@]} )); then
      CHOSEN_FILE="${SESSION_FILES[reply-1]}"
    else
      echo "Invalid number."
      exit 1
    fi
  else
    # Allow full path or basename
    CHOSEN_FILE=""
    for path_reply in "${SESSION_FILES[@]}"; do
      if [[ "$path_reply" == "$reply" || $(basename "$path_reply") == "$reply" ]]; then
        CHOSEN_FILE="$path_reply"
        break
      fi
    done
    if [[ -z "$CHOSEN_FILE" ]]; then
      echo "Not found: $reply"
      exit 1
    fi
  fi
  activate_venv || exit 1
  if [[ ! -x "$ADK_AGENT_PATH/.venv/bin/adk" ]]; then
    echo "google-adk not found. Run 'init' and ensure venv is correct."
    exit 1
  fi
  "$ADK_AGENT_PATH/.venv/bin/adk" run --resume "$CHOSEN_FILE" "$ADK_AGENT_PATH"
}
cmd_create() {
  local name parent agent_path adk_bin
  load_config
  # Use current agent's venv for adk create if available
  if [[ -n "${ADK_AGENT_PATH:-}" && -x "$ADK_AGENT_PATH/.venv/bin/adk" ]]; then
    activate_venv
    adk_bin="$ADK_AGENT_PATH/.venv/bin/adk"
  elif command -v adk >/dev/null 2>&1; then
    adk_bin=adk
  else
    echo "No adk in PATH and no agent venv set. Use 'path' to set an agent, run 'init', then create; or install google-adk (pip install google-adk)."
    exit 1
  fi
  read -r -p "Agent name (directory to create): " name
  name="${name%"${name##*[![:space:]]}"}"
  name="${name#"${name%%[![:space:]]*}"}"
  if [[ -z "$name" ]]; then
    echo "Agent name cannot be empty."
    exit 1
  fi
  read -r -p "Parent directory [$(pwd)]: " parent
  parent="${parent%"${parent##*[![:space:]]}"}"
  parent="${parent#"${parent%%[![:space:]]*}"}"
  if [[ -z "$parent" ]]; then
    parent=$(pwd)
  fi
  (cd "$parent" && "$adk_bin" create "$name") || exit 1
  agent_path="$parent/$name"
  echo "Created. Set path and run init? Set ADK_AGENT_PATH to $agent_path and run init, or use 'path' to set and then 'init'."
  read -r -p "Set ADK_AGENT_PATH to $agent_path now? [y/N] " reply
  if [[ "$reply" =~ ^[yY] ]]; then
    export ADK_AGENT_PATH="$agent_path"
    read -r -p "Run init now? [y/N] " reply2
    if [[ "$reply2" =~ ^[yY] ]]; then
      cmd_init
    fi
  fi
}

# Read optional VAR from agent .env (KEY=value, no export).
read_agent_env() {
  local key="$1"
  if [[ -f "$ADK_AGENT_PATH/.env" ]]; then
    local line
    while IFS= read -r line; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      if [[ "$line" =~ ^${key}=(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
      fi
    done < "$ADK_AGENT_PATH/.env"
  fi
  echo ""
}

# Deploy current agent to Vertex AI Agent Engine. Requires GCP auth, project, region, display_name.
cmd_deploy() {
  ensure_path || exit 1
  if [[ ! -d "$ADK_AGENT_PATH" ]]; then
    echo "Agent path does not exist: $ADK_AGENT_PATH"
    exit 1
  fi
  if [[ ! -f "$ADK_AGENT_PATH/.venv/bin/activate" ]]; then
    echo "No .venv at $ADK_AGENT_PATH/.venv. Run 'init' first."
    exit 1
  fi
  activate_venv || exit 1
  if [[ ! -x "$ADK_AGENT_PATH/.venv/bin/adk" ]]; then
    echo "google-adk not found. Run 'init' and ensure venv is correct."
    exit 1
  fi
  ensure_agent_dir || exit 1
  ensure_gcp_auth || exit 1
  local project region display_name
  project=$(read_agent_env GOOGLE_CLOUD_PROJECT)
  region=$(read_agent_env GOOGLE_CLOUD_LOCATION)
  display_name=$(basename "$ADK_AGENT_PATH")
  if [[ -z "$project" ]]; then
    read -r -p "GCP project ID: " project
    project="${project%"${project##*[![:space:]]}"}"
    project="${project#"${project%%[![:space:]]*}"}"
  fi
  if [[ -z "$region" ]]; then
    read -r -p "Region [us-central1]: " region
    region="${region%"${region##*[![:space:]]}"}"
    region="${region#"${region%%[![:space:]]*}"}"
    [[ -z "$region" ]] && region=us-central1
  fi
  read -r -p "Display name for Agent Engine [$display_name]: " reply
  reply="${reply%"${reply##*[![:space:]]}"}"
  reply="${reply#"${reply%%[![:space:]]*}"}"
  [[ -n "$reply" ]] && display_name="$reply"
  if [[ -z "$project" ]]; then
    echo "Project ID is required."
    exit 1
  fi
  load_config
  local staging_bucket="${ADK_DEPLOY_STAGING_BUCKET:-}"
  if [[ -z "$staging_bucket" ]]; then
    staging_bucket=$(read_agent_env ADK_DEPLOY_STAGING_BUCKET)
  fi
  if [[ -z "$staging_bucket" ]]; then
    echo "Staging bucket (gs://...) is required to avoid the 8MB request payload limit."
    echo "Create one with: gsutil mb -p $project -l $region gs://YOUR-BUCKET-NAME"
    read -r -p "GCS staging bucket (gs://...): " staging_bucket
    staging_bucket="${staging_bucket%"${staging_bucket##*[![:space:]]}"}"
    staging_bucket="${staging_bucket#"${staging_bucket%%[![:space:]]*}"}"
  fi
  if [[ -z "$staging_bucket" ]]; then
    echo "Staging bucket is required. Add ADK_DEPLOY_STAGING_BUCKET=gs://your-bucket to ~/.adk-menu.conf or agent .env."
    exit 1
  fi
  # Deploy from a minimal copy (no .venv, __pycache__, .adk) to stay under the 8MB request payload limit.
  local tmp_deploy
  tmp_deploy=$(mktemp -d "${TMPDIR:-/tmp}/adk_deploy_XXXXXX")
  trap 'rm -rf "$tmp_deploy"' RETURN
  local f base
  for f in "$ADK_AGENT_PATH"/* "$ADK_AGENT_PATH"/.*; do
    [[ -e "$f" ]] || continue
    base=$(basename "$f")
    case "$base" in
      .|..) continue ;;
      .venv|.git|.adk|__pycache__) continue ;;
      *.session.json) continue ;;
      *) cp -R "$f" "$tmp_deploy/" 2>/dev/null || true ;;
    esac
  done
  # Rewrite .env for Vertex: remove GOOGLE_API_KEY (conflicts with project auth) and ensure Vertex AI is enabled.
  if [[ -f "$tmp_deploy/.env" ]]; then
    grep -v '^GOOGLE_API_KEY=' "$tmp_deploy/.env" > "$tmp_deploy/.env.tmp" && mv "$tmp_deploy/.env.tmp" "$tmp_deploy/.env"
  fi
  if ! grep -q '^GOOGLE_GENAI_USE_VERTEXAI=' "$tmp_deploy/.env" 2>/dev/null; then
    echo "GOOGLE_GENAI_USE_VERTEXAI=TRUE" >> "$tmp_deploy/.env"
  fi
  if ! grep -q '^GOOGLE_CLOUD_PROJECT=' "$tmp_deploy/.env" 2>/dev/null; then
    echo "GOOGLE_CLOUD_PROJECT=$project" >> "$tmp_deploy/.env"
  fi
  if ! grep -q '^GOOGLE_CLOUD_LOCATION=' "$tmp_deploy/.env" 2>/dev/null; then
    echo "GOOGLE_CLOUD_LOCATION=$region" >> "$tmp_deploy/.env"
  fi
  # Ensure requirements.txt exists (ADK may generate, but some versions expect it)
  if [[ ! -f "$tmp_deploy/requirements.txt" ]]; then
    "$ADK_AGENT_PATH/.venv/bin/pip" freeze > "$tmp_deploy/requirements.txt" 2>/dev/null || echo "google-adk" > "$tmp_deploy/requirements.txt"
  fi
  echo "Deploying to Vertex AI Agent Engine (project=$project, region=$region, display_name=$display_name, staging=$staging_bucket)..."
  echo "(Deploy can take several minutes; output streams below.)"
  local deploy_out deploy_rc resource_name
  deploy_out=$(mktemp)
  "$ADK_AGENT_PATH/.venv/bin/adk" deploy agent_engine \
    --project="$project" \
    --region="$region" \
    --staging_bucket="$staging_bucket" \
    --display_name="$display_name" \
    "$tmp_deploy" 2>&1 | tee "$deploy_out"
  deploy_rc=${PIPESTATUS[0]}
  if [[ $deploy_rc -ne 0 ]]; then
    rm -f "$deploy_out"
    exit 1
  fi
  resource_name=$(grep -o 'projects/[0-9][0-9]*/locations/[^/]*/reasoningEngines/[0-9][0-9]*' "$deploy_out" | head -1)
  rm -f "$deploy_out"
  echo "Deploy complete. Check Agent Engine in Cloud Console or use the returned resource name to query the agent."
  if [[ -n "$resource_name" ]]; then
    read -r -p "Query the deployed agent now? [y/N] " reply
    if [[ "$reply" =~ ^[yY] ]]; then
      query_deployed_agent "$project" "$region" "$resource_name"
    fi
  fi
}

# List existing Vertex AI Agent Engines in project/region, let user select one, then run query loop.
cmd_query_vertex() {
  ensure_path || exit 1
  [[ -x "$ADK_AGENT_PATH/.venv/bin/python" ]] || { echo "No venv at $ADK_AGENT_PATH/.venv. Run 'init' first."; return 1; }
  ensure_gcp_auth || return 1
  local project region
  project=$(read_agent_env GOOGLE_CLOUD_PROJECT)
  region=$(read_agent_env GOOGLE_CLOUD_LOCATION)
  if [[ -z "$project" ]]; then
    read -r -p "GCP project ID: " project
    project="${project%"${project##*[![:space:]]}"}"
    project="${project#"${project%%[![:space:]]*}"}"
  fi
  if [[ -z "$region" ]]; then
    read -r -p "Region [us-central1]: " region
    region="${region%"${region##*[![:space:]]}"}"
    region="${region#"${region%%[![:space:]]*}"}"
    [[ -z "$region" ]] && region=us-central1
  fi
  if [[ -z "$project" ]]; then
    echo "Project ID is required."
    return 1
  fi
  local py_script
  py_script=$(mktemp)
  cat << 'PYEOF2' > "$py_script"
import asyncio
import sys
import vertexai
from vertexai.preview import reasoning_engines

def _read_input():
    return input("You: ").strip()

async def async_main():
    project = sys.argv[1]
    location = sys.argv[2]
    vertexai.init(project=project, location=location)
    engines = reasoning_engines.ReasoningEngine.list()
    if not engines:
        print("No Agent Engines (reasoning engines) found in this project/region.", file=sys.stderr)
        return 1
    for i, eng in enumerate(engines, 1):
        name = getattr(eng, "name", None) or getattr(eng, "resource_name", None) or str(eng)
        resource_id = name.split("/")[-1] if "/" in name else name
        display = getattr(eng, "display_name", None)
        if not display and getattr(eng, "gca_resource", None):
            display = getattr(eng.gca_resource, "display_name", None)
        if not display:
            display = resource_id
        if display != resource_id:
            print(f"  ({i}) {display} - {resource_id}")
        else:
            print(f"  ({i}) {resource_id}")
    try:
        choice = input("Select number (or Enter to cancel): ").strip()
    except (EOFError, KeyboardInterrupt):
        return 0
    if not choice:
        return 0
    try:
        idx = int(choice)
        if idx < 1 or idx > len(engines):
            print("Invalid number.", file=sys.stderr)
            return 1
    except ValueError:
        print("Enter a number.", file=sys.stderr)
        return 1
    eng = engines[idx - 1]
    resource_name = getattr(eng, "name", None) or getattr(eng, "resource_name", None)
    if not resource_name:
        print("Could not get resource name.", file=sys.stderr)
        return 1
    # agent_engines.get() requires full path: projects/.../locations/.../reasoningEngines/{id}
    if "/" not in resource_name or "reasoningEngines" not in resource_name:
        resource_id = resource_name.split("/")[-1] if "/" in resource_name else resource_name
        resource_name = f"projects/{project}/locations/{location}/reasoningEngines/{resource_id}"
    client = vertexai.Client(project=project, location=location)
    app = client.agent_engines.get(name=resource_name)
    user_id = "adk-menu-user"
    loop = asyncio.get_event_loop()

    # Create session through the deployed agent so it lives in the agent's own session store.
    try:
        session = await app.async_create_session(user_id=user_id)
        # Response is the dict form of an ADK session: {'id': '...', 'userId': '...', ...}
        if isinstance(session, dict):
            session_id = session.get("id")
        else:
            session_id = getattr(session, "id", None)
        if not session_id:
            print(f"[vertex session] unexpected create_session response: {session!r}", file=sys.stderr)
            print("Could not get session ID.", file=sys.stderr)
            return 1
        session_id = str(session_id)
        print(f"[vertex session] session_id={session_id!r}", file=sys.stderr)
    except Exception as e:
        print(f"Could not create session: {e}", file=sys.stderr)
        return 1

    print("Connected (single session). Type a message and press Enter (empty or 'exit' to quit).")
    while True:
        try:
            msg = await loop.run_in_executor(None, _read_input)
        except (EOFError, KeyboardInterrupt):
            break
        if not msg or msg.lower() in ("exit", "quit", "q"):
            break
        print("Agent: ", end="", flush=True)
        try:
            async for event in app.async_stream_query(user_id=user_id, session_id=session_id, message=msg):
                if isinstance(event, dict):
                    content = event.get("content") or {}
                    parts = content.get("parts", []) if isinstance(content, dict) else []
                    if not parts and isinstance(content, dict) and "text" in content:
                        print(content["text"], end="", flush=True)
                    for part in parts if isinstance(parts, list) else []:
                        if isinstance(part, dict) and "text" in part:
                            print(part["text"], end="", flush=True)
            print()
        except Exception as e:
            print(f"\nError: {e}")
    print("Done.")
    return 0

if __name__ == "__main__":
    sys.exit(asyncio.run(async_main()) if len(sys.argv) >= 3 else 1)
PYEOF2
  "$ADK_AGENT_PATH/.venv/bin/python" "$py_script" "$project" "$region"
  local r=$?
  rm -f "$py_script"
  return $r
}

# Interactive query loop for a deployed Vertex AI Agent Engine (resource name from deploy output).
query_deployed_agent() {
  local project="$1" region="$2" resource_name="$3"
  if [[ -z "$project" || -z "$region" || -z "$resource_name" ]]; then
    echo "Missing project, region, or resource name."
    return 1
  fi
  ensure_path || return 1
  [[ -x "$ADK_AGENT_PATH/.venv/bin/python" ]] || { echo "No venv at $ADK_AGENT_PATH/.venv"; return 1; }
  local py_script
  py_script=$(mktemp)
  cat << 'PYEOF' > "$py_script"
import asyncio
import sys
import vertexai

def _read_input():
    return input("You: ").strip()

async def async_main():
    project = sys.argv[1]
    location = sys.argv[2]
    resource_name = sys.argv[3]
    vertexai.init(project=project, location=location)
    client = vertexai.Client(project=project, location=location)
    app = client.agent_engines.get(name=resource_name)
    user_id = "adk-menu-user"
    loop = asyncio.get_event_loop()

    # Create session through the deployed agent so it lives in the agent's own session store.
    try:
        session = await app.async_create_session(user_id=user_id)
        # Response is the dict form of an ADK session: {'id': '...', 'userId': '...', ...}
        if isinstance(session, dict):
            session_id = session.get("id")
        else:
            session_id = getattr(session, "id", None)
        if not session_id:
            print(f"[vertex session] unexpected create_session response: {session!r}", file=sys.stderr)
            print("Could not get session ID.", file=sys.stderr)
            return 1
        session_id = str(session_id)
        print(f"[vertex session] session_id={session_id!r}", file=sys.stderr)
    except Exception as e:
        print(f"Could not create session: {e}", file=sys.stderr)
        return 1

    print("Connected to deployed agent (single session). Type a message and press Enter (empty or 'exit' to quit).")
    while True:
        try:
            msg = await loop.run_in_executor(None, _read_input)
        except (EOFError, KeyboardInterrupt):
            break
        if not msg or msg.lower() in ("exit", "quit", "q"):
            break
        print("Agent: ", end="", flush=True)
        try:
            async for event in app.async_stream_query(user_id=user_id, session_id=session_id, message=msg):
                if isinstance(event, dict):
                    content = event.get("content") or {}
                    parts = content.get("parts", []) if isinstance(content, dict) else []
                    if not parts and isinstance(content, dict) and "text" in content:
                        print(content["text"], end="", flush=True)
                    for part in parts if isinstance(parts, list) else []:
                        if isinstance(part, dict) and "text" in part:
                            print(part["text"], end="", flush=True)
            print()
        except Exception as e:
            print(f"\nError: {e}")
    print("Done.")

if __name__ == "__main__":
    asyncio.run(async_main())
PYEOF
  "$ADK_AGENT_PATH/.venv/bin/python" "$py_script" "$project" "$region" "$resource_name"
  local r=$?
  rm -f "$py_script"
  return $r
}

show_banner() {
  echo ""
  echo "  _   _  _   _____      _    ____ _____ _   _ _____ ____  "
  echo " | \ | || | |___ /     / \  / ___| ____| \ | |_   _/ ___| "
  echo " |  \| || |_  |_ \    / _ \| |  _|  _| |  \| | | | \___ \ "
  echo " | |\  |__  _|__) |  / ___ \ |_| | |___| |\  | | |  ___) |"
  echo " |_| \_|  |_||____/ /_/   \_\____|_____|_| \_| |_| |____/ "
  echo ""
}

menu_loop() {
  local choice
  AUTH_INTERACTIVE=1
  while true; do
    load_config
    show_banner
    echo "ADK Menu (agent: ${ADK_AGENT_PATH:-<not set>})"
    echo "  1) Init venv + pip install google-adk"
    echo "  2) Run session (CLI)"
    echo "  3) Run session (Web UI)"
    echo "  4) Resume session (choose from saved)"
    echo "  5) Create new agent"
    echo "  6) Set / show agent path"
    echo "  7) Deploy to Vertex AI Agent Engine"
    echo "  8) Query existing Vertex AI Agent Engine"
    echo "  9) Exit"
    read -r -p "Choice: " choice
    choice="${choice%"${choice##*[![:space:]]}"}"
    choice="${choice#"${choice%%[![:space:]]*}"}"
    case "$choice" in
      1)
        if ! ensure_path; then
          PATH_INTERACTIVE=1 cmd_path
          if ! ensure_path; then
            echo "Set agent path first (option 6)."
          else
            cmd_init
          fi
        else
          cmd_init
        fi
        read -r -p "Press Enter to continue..."
        ;;
      2)
        if ! ensure_path; then
          echo "Set agent path first (option 6)."
        else
          cmd_run
        fi
        read -r -p "Press Enter to continue..."
        ;;
      3)
        if ! ensure_path; then
          echo "Set agent path first (option 6)."
        else
          cmd_web
        fi
        read -r -p "Press Enter to continue..."
        ;;
      4)
        if ! ensure_path; then
          echo "Set agent path first (option 6)."
        else
          cmd_resume
        fi
        read -r -p "Press Enter to continue..."
        ;;
      5)
        cmd_create
        read -r -p "Press Enter to continue..."
        ;;
      6)
        PATH_INTERACTIVE=1 cmd_path
        read -r -p "Press Enter to continue..."
        ;;
      7)
        if ! ensure_path; then
          echo "Set agent path first (option 6)."
        else
          cmd_deploy
        fi
        read -r -p "Press Enter to continue..."
        ;;
      8)
        if ! ensure_path; then
          echo "Set agent path first (option 6)."
        else
          cmd_query_vertex
        fi
        read -r -p "Press Enter to continue..."
        ;;
      9)
        exit 0
        ;;
      *)
        echo "Invalid choice."
        ;;
    esac
  done
}

subcommand="${1:-menu}"
case "$subcommand" in
  init)   cmd_init ;;
  run)    cmd_run ;;
  web)    cmd_web ;;
  resume) cmd_resume ;;
  create) cmd_create ;;
  path)   cmd_path ;;
  deploy) cmd_deploy ;;
  query-vertex) cmd_query_vertex ;;
  help)   usage; exit 0 ;;
  menu)   menu_loop ;;
  *)      usage; exit 1 ;;
esac
