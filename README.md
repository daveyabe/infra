# infrastructure

Infrastructure as code and provisioning scripts for GCP: project bootstrapping, ad hoc gcloud scripts, and Terraform.

## Repository layout

```
.
├── docs/                         # Documentation and project notes
│   └── gcp-projects/             # Per–GCP-project docs and runbooks
├── GCP/                          # GCP provisioning and ad hoc scripts
│   ├── layer0_bootstrap/         # Full project bootstrap (see GCP/README.md)
│   ├── Cloud SQL/                # Ad hoc scripts (e.g. SandboxDB, Secret Manager)
│   └── GCE/                      # Ad hoc scripts (instance metadata, startup scripts)
├── terraform/                    # Terraform configs (see terraform/README.md)
│   ├── bootstrap/                # One-time setup (state bucket, Workload Identity)
│   ├── modules/                  # Reusable modules (VPC, GCE, GCS, IAM, firewall, MIG, etc.)
│   ├── projects/                 # Project-specific environments (e.g. riley/dev)
│   └── projects-test/            # Test project configs
└── .github/workflows/            # CI (Terraform plan/apply, manual runs)
```

## Docs

| Area | Location | Description |
|------|----------|-------------|
| **Project docs** | `docs/gcp-projects/` | Notes and runbooks per GCP project (e.g. setup, quirks, operations). |

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
