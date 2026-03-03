# Notion workspace backup (GitHub Action → GCS)

## Purpose

Perform a full nightly backup of all Notion databases and pages, storing timestamped archives in Google Cloud Storage with automatic tiered lifecycle management.

## Architecture

```
┌──────────────┐  cron 03:00 UTC   ┌─────────────────────┐
│ GitHub Action │ ───────────────── │  Notion API (v1)    │
│  (scheduled)  │   search / read   │  pages + databases  │
└──────┬───────┘                    └─────────────────────┘
       │ .tar.gz
       ▼
┌─────────────────────────────────────────────────────────┐
│  GCS Bucket:  <PROJECT_ID>-notion-backups               │
│  ─────────────────────────────────────────────────────  │
│  Location:  US (multi-region, 99.95% availability SLA)  │
│  Durability: 99.999999999% (11 nines)                   │
│  Versioning: enabled                                    │
│                                                         │
│  Lifecycle:                                             │
│    STANDARD  ──30 d──▶  NEARLINE  ──90 d──▶  COLDLINE  │
│                                     365 d ──▶  DELETE   │
└─────────────────────────────────────────────────────────┘
```

## What gets backed up

| Category | Export method | Output |
|----------|-------------|--------|
| **Databases** | `GET /databases/{id}` + `POST /databases/{id}/query` | Schema (`schema.json`) + all row pages |
| **Pages** | `GET /pages/{id}` + `GET /blocks/{id}/children` (recursive) | Properties (`properties.json`) + full block tree (`content.json`) |
| **Manifest** | Generated | Timestamp, stats (page/db/block/API-call counts) |

Pages that belong to a database are exported as rows within that database's directory (to avoid duplication).

## Backup archive structure

```
notion-backup-20260303T030000Z/
├── manifest.json
├── databases/
│   ├── Idea_Database_26a1d62693dc/
│   │   ├── schema.json
│   │   ├── rows_index.json
│   │   └── rows/
│   │       ├── Spice_2a81d62693dc/
│   │       │   ├── properties.json
│   │       │   └── content.json
│   │       └── …
│   ├── Studio_Cycles_25b1d62693dc/
│   │   └── …
│   └── …
└── pages/
    ├── Engineering_Standup_3181d62693dc/
    │   ├── properties.json
    │   └── content.json
    └── …
```

## Components

| Item | Path |
|------|------|
| **Backup script** | `notion/scripts/backup_to_gcs.py` |
| **Python deps** | `notion/requirements.txt` |
| **Workflow** | `.github/workflows/notion-backup.yml` |
| **Terraform (bucket)** | `terraform/projects/notion/prod/` |
| **This doc** | `docs/notion-backup.md` |

## Setup

### 1. Notion internal integration

1. Go to [notion.so/my-integrations](https://www.notion.so/my-integrations) and create an integration.
2. Grant it **Read content** capabilities (no write needed).
3. In the Notion workspace, share each top-level page/database with the integration (or share the root workspace page to grant access to everything beneath it).
4. Copy the integration token.

### 2. GitHub repository secrets

| Secret | Description |
|--------|-------------|
| `NOTION_API_TOKEN` | The Notion integration token from step 1 |
| `GCP_PROJECT_ID` | Already configured for Terraform workflows |
| `GCP_PROJECT_NUMBER` | Already configured for Terraform workflows |

### 3. Provision the GCS bucket

The bucket lives in its own Terraform project at `terraform/projects/notion/prod/`. Copy the example tfvars, fill in your project ID, then plan and apply:

```bash
cd terraform/projects/notion/prod
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your GCP project ID

terraform init
terraform plan    # review the new bucket + IAM binding
terraform apply
```

Alternatively, merge this branch and let the Terraform CI workflow handle the apply on push to main. The `notion` project is registered in `.github/workflows/terraform.yml` and will be planned on PRs / applied on merge automatically.

### 4. IAM: grant the GitHub Actions service account write access

The Terraform config adds `roles/storage.objectCreator` on the backup bucket for the GitHub Actions service account. By default this is `terraform-github-actions@<PROJECT_ID>.iam.gserviceaccount.com`. Override with the `backup_writer_service_account` variable if you use a different SA.

The existing Workload Identity Federation setup (used by the Terraform and Figma workflows) already allows the GitHub Actions runner to authenticate as the SA — no additional WIF config is needed.

### 5. Verify

Trigger a manual run: **Actions → Notion backup to GCS → Run workflow**.

Check the GCS bucket:
```bash
gsutil ls gs://<PROJECT_ID>-notion-backups/backups/
```

## Storage costs (estimate)

| Tier | Price (US multi-region) | When |
|------|------------------------|------|
| Standard | $0.026/GB/mo | Days 0–30 |
| Nearline | $0.010/GB/mo | Days 30–90 |
| Coldline | $0.007/GB/mo | Days 90–365 |

A typical Notion workspace with dozens of databases and hundreds of pages produces archives in the 5–50 MB range. Annual storage cost at that scale is well under $1.

## Durability and availability

- **Durability**: 99.999999999% (11 nines) — GCS replicates data across multiple facilities within the US multi-region.
- **Availability**: 99.95% SLA for multi-region Standard storage.
- **Versioning**: Enabled — accidental overwrites are recoverable from prior object versions.
- **Lifecycle**: Older backups automatically transition to cheaper tiers, balancing cost and accessibility.

## Restoring from backup

1. Download an archive:
   ```bash
   gsutil cp gs://<PROJECT_ID>-notion-backups/backups/notion-backup-<TIMESTAMP>.tar.gz .
   ```
2. Extract:
   ```bash
   tar xzf notion-backup-<TIMESTAMP>.tar.gz
   ```
3. Each page's `properties.json` contains Notion API properties; `content.json` contains the full block tree. These can be replayed through the Notion API to recreate pages, or used as a reference for manual reconstruction.

## Rate limits

The Notion API has a rate limit of 3 requests/second per integration. The backup script throttles at ~2.8 req/s (0.35s delay) by default and retries on HTTP 429 with exponential backoff. For very large workspaces, increase `REQUEST_DELAY` via the environment variable.

## Monitoring

- **GitHub Actions**: Workflow runs are visible in the Actions tab. Failures trigger default GitHub notification emails.
- **Artifacts**: Each run also uploads the archive as a GitHub Actions artifact (7-day retention) as a safety net independent of GCS.
- **GCS**: Use Cloud Monitoring to set alerts on the bucket (e.g. alert if no new objects appear within 48 hours).
