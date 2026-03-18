FROM ubuntu:24.04

LABEL maintainer="N43 Studio - Dash" \
      description="ADK Menu — interactive helper for Google ADK agents" \
      usage.interactive="docker run -it adk-menu" \
      usage.command="docker run adk-menu <command>" \
      commands.init="Create .venv in agent dir and pip install google-adk" \
      commands.run="Activate venv and run adk session (CLI)" \
      commands.web="Activate venv and run adk web UI (port: ADK_WEB_PORT, default 8000)" \
      commands.resume="Discover saved sessions, choose one, resume with adk run --resume" \
      commands.create="Scaffold a new ADK agent via adk create" \
      commands.path="Show current ADK_AGENT_PATH" \
      commands.deploy="Deploy agent to Vertex AI Agent Engine" \
      commands.query-vertex="List deployed Agent Engines and open interactive query loop" \
      commands.help="Print usage information"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash \
       curl \
       gnupg \
       apt-transport-https \
       ca-certificates \
       python3 \
       python3-venv \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
       > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
       | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY adk-menu.sh .
RUN chmod +x adk-menu.sh

ENTRYPOINT ["./adk-menu.sh"]
