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

cmd_init() { echo "Not implemented: init"; }
cmd_run()  { echo "Not implemented: run"; }
cmd_web()  { echo "Not implemented: web"; }
cmd_resume() { echo "Not implemented: resume"; }
cmd_create() { echo "Not implemented: create"; }
cmd_path() { echo "Not implemented: path"; }
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
