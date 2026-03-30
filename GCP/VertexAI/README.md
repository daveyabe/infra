# Vertex AI Model Garden -- Gas Town Integration

Deploy OSS models from Google's Vertex AI Model Garden and generate
ready-to-use configuration for Gas Town agents.

## Prerequisites

1. **gcloud CLI** installed and authenticated (`gcloud auth login`)
2. **GCP project** with billing enabled
3. **Vertex AI API** enabled (the script does this automatically)
4. **GPU quota** in your target region (check at
   https://console.cloud.google.com/iam-admin/quotas -- filter for
   "GPUs (all regions)" or specific accelerator types like NVIDIA_L4)
5. **Cursor IDE** connected to the Gas Town VM via Remote SSH

## Quick Start

```bash
# Deploy a model (interactive)
./GCP/VertexAI/vertex-model-garden.sh deploy

# Generate Gas Town + Cursor config
./GCP/VertexAI/vertex-model-garden.sh generate-config vertex-gemma-2-9b

# When done, stop billing
./GCP/VertexAI/vertex-model-garden.sh undeploy vertex-gemma-2-9b
```

## Subcommands

| Command                   | Description                         |
| ------------------------- | ----------------------------------- |
| `list [filter]`           | List deployable Model Garden models |
| `configs [model]`         | Show hardware options for a model   |
| `deploy`                  | Interactive deploy workflow         |
| `status`                  | List active deployments             |
| `undeploy [alias]`        | Stop and delete a deployment        |
| `generate-config [alias]` | Generate Gas Town + Cursor config   |
| `help`                    | Show usage                          |
| *(no command)*            | Interactive menu                    |

## Auth Strategies

### Option A: LiteLLM Proxy (recommended)

LiteLLM runs as a local proxy on port 4000, handling GCP auth
automatically via Application Default Credentials. Cursor connects
to `http://localhost:4000/v1` with a stable API key.

Install with:

```bash
source /opt/gastown/data/engineering/scripts/gastown-host-tools.sh
gastown_install_litellm_proxy
```

### Option B: Manual Token

Paste a GCP access token directly into Cursor's API key field.
Tokens expire after ~1 hour and must be refreshed:

```bash
gcloud auth print-access-token
```

## Config File

Optional: `~/.vertex-model-garden/config`

```
PROJECT=my-gcp-project
REGION=us-central1
HF_TOKEN=hf_...
```

## Cost Warning

GPU endpoints bill **continuously** while deployed, not per-request:

| Machine Type   | Accelerator  | Approx. Cost/Hour |
| -------------- | ------------ | ----------------- |
| g2-standard-12 | 1x NVIDIA L4 | ~$1.50            |
| a2-highgpu-1g  | 1x A100 40GB | ~$5.00            |
| a3-highgpu-1g  | 1x H100 80GB | ~$12.00           |

Always run `undeploy` when you're done experimenting.
