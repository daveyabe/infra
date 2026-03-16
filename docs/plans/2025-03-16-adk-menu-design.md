# ADK Bash Menu — Design

## Summary

Single bash script with subcommands and an interactive menu. Agent path from env or config; venv lives inside the agent dir. Supports init, run (CLI), run (web UI), resume from discovered session JSON, create agent, and set/show path. Relocatable to (A) later without code change.

---

## Section 1: Scope (approved)

- **Init:** Create `.venv` in agent dir; `pip install google-adk`. If agent dir missing, optionally `adk create <name>` then init.
- **Run CLI / Web:** Activate venv; `adk run` or `adk web` (from parent of agent dir for web).
- **Resume:** Discover `*.session.json` (and `.session.json`) under agent dir; pick one; `adk run --resume <file> <agent_path>`.
- **Config:** `ADK_AGENT_PATH` env wins; else config file. If unset, prompt once and optionally save.
- **Extras:** Create new agent; Set/show agent path; Exit.

---

## Section 2: Config, layout, menu flow

### Config precedence

1. `ADK_AGENT_PATH` (environment)
2. Config file (first found):
   - `./.adk-agent-path` (current directory — supports A) when script lives in agent repo)
   - `~/.adk-menu.conf`

Config file format: one line, optional `KEY=value`. We only use `ADK_AGENT_PATH=/path`. Allow comments (`#`) and strip whitespace.

### File layout

- **Repo (C):** Script in this repo, e.g. `scripts/adk-menu.sh` (or `tools/adk-menu.sh`). Config in `~/.adk-menu.conf` or user sets env.
- **Relocated (A):** Same script in agent repo root; `ADK_AGENT_PATH` set to repo root or `.adk-agent-path` in repo with that path. Venv at `$ADK_AGENT_PATH/.venv`.

### Subcommands

| Command | Behavior |
|--------|----------|
| (no args) | Interactive menu |
| `init` | Ensure agent path set → create venv in agent dir, pip install google-adk; if agent dir missing, prompt to create via `adk create` then init |
| `run` | Ensure path + venv → activate venv, `adk run "$ADK_AGENT_PATH"` |
| `web` | Ensure path + venv → activate venv, run `adk web --port 8000` from parent of `$ADK_AGENT_PATH` |
| `resume` | Ensure path + venv → discover session files → prompt to choose → `adk run --resume <file> "$ADK_AGENT_PATH"` |
| `create` | Prompt for agent name → `adk create <name>` (in cwd or a chosen dir) → offer to set path and run init |
| `path` | Show current `ADK_AGENT_PATH`; prompt to set new path and optionally write to config |
| `help` | Print usage and subcommands |

Venv activation: source `$ADK_AGENT_PATH/.venv/bin/activate` when running `adk` for run/web/resume. If `.venv` missing, tell user to run `init` first.

### Session discovery (resume)

- Look for session files under `$ADK_AGENT_PATH`: any `*.session.json` and, if present, `.session.json`.
- Sort by mtime (newest first). Display numbered list; user chooses by number or path.
- If none found, print message and return to menu (or exit if subcommand).

### Interactive menu

When run with no args, show:

```
ADK Menu (agent: $ADK_AGENT_PATH or "not set")
  1) Init venv + pip install google-adk
  2) Run session (CLI)
  3) Run session (Web UI)
  4) Resume session (choose from saved)
  5) Create new agent
  6) Set / show agent path
  7) Exit
Choice:
```

Loop until Exit. If path is not set, options 1–4 can prompt for path first (and optionally save), or show "Set agent path first (option 6)."

---

## Section 3: Error handling

- **Path unset:** Subcommands that need path (init, run, web, resume) exit with message "ADK_AGENT_PATH not set. Use 'path' or set ADK_AGENT_PATH." unless we're in interactive menu and can prompt.
- **Path set but dir missing:** init offers to run `adk create`; run/web/resume exit with "Agent path does not exist: $ADK_AGENT_PATH."
- **Venv missing for run/web/resume:** "No .venv at $ADK_AGENT_PATH/.venv. Run 'init' first."
- **adk not in PATH after venv activate:** "google-adk not found. Run 'init' and ensure venv is correct."
- **No session files for resume:** "No .session.json or *.session.json found under $ADK_AGENT_PATH."
- Use `set -e` only where we want exit on failure; for menu loop we don’t want one failure to exit the script. Prefer explicit checks and messages.

---

## Relocation to (A)

When script lives inside the agent repo: set `ADK_AGENT_PATH` to repo root (e.g. in `.adk-agent-path` or env). No script changes; same subcommands and menu.
