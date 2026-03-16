# Scripts

## adk-menu.sh

Bash script for managing [Google ADK](https://github.com/google/adk) agents: init venv, run CLI or web UI, resume sessions, create agents, and manage agent path.

### Config: ADK_AGENT_PATH

Agent path is resolved in this order:

1. **Environment:** `ADK_AGENT_PATH` if set and non-empty.
2. **Current directory:** `./.adk-agent-path` (first readable file wins).
3. **User config:** `~/.adk-menu.conf`.

Config file format: one line `ADK_AGENT_PATH=/path/to/agent`. Comments (`#`) and blank lines are ignored; leading/trailing whitespace is stripped.

### Subcommands

| Command | Description |
|--------|-------------|
| (none) | Interactive menu |
| `init` | Create `.venv` in agent dir and `pip install google-adk` |
| `run` | Activate venv and run `adk run` (CLI) |
| `web` | Activate venv and run `adk web --port 8000` from agent’s parent dir |
| `resume` | Discover `*.session.json` / `.session.json`, choose one, run `adk run --resume` |
| `create` | Prompt for agent name and parent dir, run `adk create`, offer to set path and init |
| `path` | Show current path; when run from menu, prompt to set and optionally save to config |
| `help` | Print usage |

### Usage

```bash
./scripts/adk-menu.sh [command]
./scripts/adk-menu.sh          # interactive menu
./scripts/adk-menu.sh help
./scripts/adk-menu.sh path
./scripts/adk-menu.sh init
```

### Design

See [ADK Bash Menu — Design](../../docs/plans/2025-03-16-adk-menu-design.md) for scope, config precedence, and error messages.
