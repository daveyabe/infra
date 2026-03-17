# Scripts

## adk-menu.sh

Bash script for managing [Google ADK](https://github.com/google/adk) agents: init venv, run CLI or web UI, resume sessions, create agents, and manage agent path.

### Config: ADK_AGENT_PATH

Agent path is resolved in this order:

1. **Environment:** `ADK_AGENT_PATH` if set and non-empty.
2. **Current directory:** `./.adk-agent-path` (first readable file wins).
3. **User config:** `~/.adk-menu.conf`.

Config file format: one line `ADK_AGENT_PATH=/path/to/agent`; optional `ADK_WEB_PORT=8000` (default 8000). Comments (`#`) and blank lines are ignored; leading/trailing whitespace is stripped. If port 8000 is already in use, set `ADK_WEB_PORT=8001` (or another port) in `~/.adk-menu.conf` or in the environment.

**Important:** `ADK_AGENT_PATH` must point at a **single agent folder** (the one that contains `agent.py` or `root_agent.yaml`), e.g. the directory created by `adk create my_agent`. Do not point it at the repo’s `scripts/` directory (where this menu script lives) or at a parent that contains multiple agents.

### Vertex AI authentication

When your agent uses Vertex AI (e.g. `.env` has `GOOGLE_GENAI_USE_VERTEXAI=1`), run/web/resume will require Google Cloud credentials. The script checks for Application Default Credentials (ADC) and, if missing, tells you to run:

```bash
gcloud auth application-default login
```

From the interactive menu, you’ll be prompted to run that command. Alternatively, set `GOOGLE_APPLICATION_CREDENTIALS` to a service account key JSON path.

### Subcommands

| Command | Description |
|--------|-------------|
| (none) | Interactive menu |
| `init` | Create `.venv` in agent dir and `pip install google-adk` |
| `run` | Activate venv and run `adk run` (CLI) |
| `web` | Activate venv and run `adk web` from agent’s parent dir (port: `ADK_WEB_PORT`, default 8000) |
| `resume` | Discover `*.session.json` / `.session.json`, choose one, run `adk run --resume` |
| `create` | Prompt for agent name and parent dir, run `adk create`, offer to set path and init |
| `path` | Show current path; when run from menu, prompt to set and optionally save to config |
| `deploy` | Deploy current agent to Vertex AI Agent Engine (GCP project, region, display name) |
| `query-vertex` | List existing Agent Engines in project/region, select one, then run an interactive query session |
| `help` | Print usage |

### Deploy to Vertex AI Agent Engine

The `deploy` subcommand (menu option 7) runs `adk deploy agent_engine` for the current agent. You need:

- **GCP auth:** `gcloud auth application-default login` (or `GOOGLE_APPLICATION_CREDENTIALS`)
- **Project and region:** If your agent has a `.env` with `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION`, those are used; otherwise you’re prompted.
- **Display name:** Defaults to the agent folder name; you can override when prompted.
- **Staging bucket:** A GCS bucket (e.g. `gs://your-bucket`) is **required**. Set `ADK_DEPLOY_STAGING_BUCKET=gs://your-bucket` in `~/.adk-menu.conf` or in the agent’s `.env`, or you’ll be prompted. Create a bucket with: `gsutil mb -p PROJECT -l REGION gs://YOUR-BUCKET-NAME`.
- **Payload size:** The menu deploys from a **minimal copy** of your agent (excluding `.venv`, `__pycache__`, `.adk`, `.git`, `*.session.json`) so the request stays under Vertex’s 8MB limit. A `requirements.txt` is added from your venv if missing.

The script uses the ADK CLI to package the agent, build a container, and deploy to the managed Agent Engine service. Enable the Vertex AI API and Cloud Resource Manager API in your project first. After a successful deploy, you’re prompted **Query the deployed agent now? [y/N]**; if you choose yes, an interactive loop lets you send messages to the deployed agent and see streamed responses.

### Usage

```bash
./scripts/adk-menu.sh [command]
./scripts/adk-menu.sh          # interactive menu
./scripts/adk-menu.sh help
./scripts/adk-menu.sh path
./scripts/adk-menu.sh init
./scripts/adk-menu.sh deploy   # deploy current agent to Vertex AI Agent Engine
```

### Design

See [ADK Bash Menu — Design](../../docs/plans/2025-03-16-adk-menu-design.md) for scope, config precedence, and error messages.
