# infrastructure

Infrastructure as code and provisioning scripts for GCP: project bootstrapping, ad hoc gcloud scripts, and Terraform.

## Repository layout

```
.
├── docs/                         # Documentation and project notes
│   ├── gcp-projects/             # Per–GCP-project docs and runbooks
│   └── cloudflare-dns-export.md  # Spec for Cloudflare DNS zone export workflow
├── cloudflare/                   # Cloudflare-related assets (exports retained as workflow artifacts)
├── figma/                        # Figma → Google Drive export (script + deps)
├── GCP/                          # GCP provisioning and ad hoc scripts
│   ├── layer0_bootstrap/         # Full project bootstrap (see GCP/README.md)
│   ├── Cloud SQL/                # Ad hoc scripts (e.g. SandboxDB, Secret Manager)
│   └── GCE/                      # Ad hoc scripts (instance metadata, startup scripts)
├── terraform/                    # Terraform configs (see terraform/README.md)
│   ├── bootstrap/                # One-time setup (state bucket, Workload Identity)
│   ├── modules/                  # Reusable modules (VPC, GCE, GCS, IAM, firewall, MIG, etc.)
│   ├── projects/                 # Project-specific environments (e.g. riley/dev)
│   └── projects-test/            # Test project configs
└── .github/workflows/            # CI (Terraform plan/apply, Cloudflare DNS export, manual runs)
```

## Docs

| Area | Location | Description |
|------|----------|-------------|
| **Project docs** | `docs/gcp-projects/` | Notes and runbooks per GCP project (e.g. setup, quirks, operations). |
| **Cloudflare DNS export** | [docs/cloudflare-dns-export.md](docs/cloudflare-dns-export.md) | Spec for the GitHub Action that exports Cloudflare DNS zones to BIND files and retains them as workflow artifacts. |
| **Figma export to Drive** | [docs/figma-export-to-drive.md](docs/figma-export-to-drive.md) | GitHub Action to export Figma file(s) or entire team to Google Drive (PNG frames). |

## Cloudflare

A GitHub Action exports all DNS zones from Cloudflare to BIND-format files and retains them as **workflow artifacts** (download from the run’s Artifacts section). Runs on a schedule and via **Actions → Cloudflare DNS export → Run workflow**. Requires repo secret `CLOUDFLARE_API_TOKEN` (Zone DNS Read). See **[docs/cloudflare-dns-export.md](docs/cloudflare-dns-export.md)** for the full spec.

## GCP — bootstrapping and scripts

| Area | Location | Description |
|------|----------|-------------|
| **Bootstrap** | `GCP/layer0_bootstrap/` | End-to-end new-project provisioning: create project, link billing, enable APIs, Terraform SA, Workload Identity Federation (GitHub Actions), and quota increases. Driven by a Makefile; see **[GCP/README.md](GCP/README.md)**. |
| **Ad hoc gcloud** | `GCP/Cloud SQL/`, `GCP/GCE/` | One-off scripts (e.g. Cloud SQL + Secret Manager, GCE instance metadata and startup scripts). Run manually as needed. |

## Terraform

Terraform manages GCP resources after bootstrap:

- **`terraform/bootstrap/`** — One-time: GCS state bucket, Workload Identity for CI.
- **`terraform/modules/`** — Shared modules: VPC, GCE, GCS, IAM, firewall, instance templates, MIGs, workload identity, Cloud Run, Artifact Registry.
- **`terraform/projects/`** — Per-project, per-environment configs (e.g. `riley/dev`).

CI runs in `.github/workflows/` (plan on PR, apply on merge; manual workflow available).

See **[terraform/README.md](terraform/README.md)** for setup, backend config, and usage.
