#!/usr/bin/env bash
# ADK bash menu: init venv, run ADK CLI/web, resume session, create agent, manage path.
# No set -e so menu loop does not exit on one failure.

usage() {
  echo "adk-menu.sh — ADK agent venv and run helper (init, run, web, resume, create, path)."
  echo "Usage: adk-menu.sh [command]"
  echo "Commands: init, run, web, resume, create, path, help."
  echo "With no command, runs interactive menu."
  echo "Config: ADK_AGENT_PATH env, or ./.adk-agent-path, or ~/.adk-menu.conf (line: ADK_AGENT_PATH=/path)."
}

load_config() {
  if [[ -n "${ADK_AGENT_PATH:-}" ]]; then
    export ADK_AGENT_PATH
    return
  fi
  local conf
  if [[ -r ./.adk-agent-path ]]; then
    conf=./.adk-agent-path
  elif [[ -r ~/.adk-menu.conf ]]; then
    conf=~/.adk-menu.conf
  else
    export ADK_AGENT_PATH
    return
  fi
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ "$line" =~ ^ADK_AGENT_PATH=(.+)$ ]]; then
      ADK_AGENT_PATH="${BASH_REMATCH[1]}"
      break
    fi
  done < "$conf"
  export ADK_AGENT_PATH
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

# Path subcommand: show path; when PATH_INTERACTIVE=1 (from menu) and path unset, prompt to set and optionally save.
cmd_path() {
  load_config
  echo "ADK_AGENT_PATH=${ADK_AGENT_PATH:-<not set>}"
  if [[ -z "${ADK_AGENT_PATH:-}" && "${PATH_INTERACTIVE:-0}" = "1" ]]; then
    read -r -p "Set path? [y/N] " reply
    if [[ "$reply" =~ ^[yY] ]]; then
      read -r -p "Path: " ADK_AGENT_PATH
      ADK_AGENT_PATH="${ADK_AGENT_PATH%"${ADK_AGENT_PATH##*[![:space:]]}"}"
      ADK_AGENT_PATH="${ADK_AGENT_PATH#"${ADK_AGENT_PATH%%[![:space:]]*}"}"
      if [[ -n "$ADK_AGENT_PATH" ]]; then
        export ADK_AGENT_PATH
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
  # shellcheck source=/dev/null
  source "$ADK_AGENT_PATH/.venv/bin/activate"
  adk run "$ADK_AGENT_PATH"
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
  # shellcheck source=/dev/null
  source "$ADK_AGENT_PATH/.venv/bin/activate"
  AGENT_PARENT=$(dirname "$ADK_AGENT_PATH")
  cd "$AGENT_PARENT" || exit 1
  exec adk web --port 8000
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
  # shellcheck source=/dev/null
  source "$ADK_AGENT_PATH/.venv/bin/activate"
  adk run --resume "$CHOSEN_FILE" "$ADK_AGENT_PATH"
}
cmd_create() {
  local name parent agent_path
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
  (cd "$parent" && adk create "$name") || exit 1
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
menu_loop() {
  local choice
  while true; do
    load_config
    echo ""
    echo "ADK Menu (agent: ${ADK_AGENT_PATH:-<not set>})"
    echo "  1) Init venv + pip install google-adk"
    echo "  2) Run session (CLI)"
    echo "  3) Run session (Web UI)"
    echo "  4) Resume session (choose from saved)"
    echo "  5) Create new agent"
    echo "  6) Set / show agent path"
    echo "  7) Exit"
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
  help)   usage; exit 0 ;;
  menu)   menu_loop ;;
  *)      usage; exit 1 ;;
esac
