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

cmd_init() { echo "Not implemented: init"; }
cmd_run()  { echo "Not implemented: run"; }
cmd_web()  { echo "Not implemented: web"; }
cmd_resume() { echo "Not implemented: resume"; }
cmd_create() { echo "Not implemented: create"; }
menu_loop() { echo "Not implemented: menu"; }

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
