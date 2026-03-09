# Cloudflare DNS zone export (GitHub Action)

## Purpose

Export all DNS zones from Cloudflare and retain the export files as **GitHub Actions artifacts**. Exports run on a schedule and can be triggered manually; each run produces a downloadable artifact containing BIND-format zone files.

## Behaviour

- **Trigger**: Scheduled (e.g. daily or weekly) and/or `workflow_dispatch` for on-demand export.
- **API**: Uses Cloudflare API v4:
  - [List zones](https://developers.cloudflare.com/api/operations/zones-list-zones) to get all zones for the account.
  - [Export DNS records](https://developers.cloudflare.com/api/operations/dns-records-export-dns-records) per zone (BIND-format zone file).
- **Output**: One file per zone (e.g. `example.com.zone`) packaged as a single workflow artifact. Artifacts are retained for a configurable period (default **90 days**). Download from **Actions → Cloudflare DNS export → run → Artifacts**.
- **Secrets**: One secret required:
  - `CLOUDFLARE_API_TOKEN` — API token with **Zone / DNS / Read** (or **Edit**) for the account.

## Artifact retention

- **Where**: Repo **Actions** tab → select a **Cloudflare DNS export** run → **Artifacts** section.
- **Retention**: Set in the workflow (`retention-days`, default 90). Repo/org settings can impose a maximum retention period.
- **Naming**: Artifacts are named `cloudflare-dns-exports-<run_number>` so each run has a distinct artifact.

## Workflow summary

| Item | Value |
|------|--------|
| **Workflow file** | `.github/workflows/cloudflare-dns-export.yml` |
| **Export script** | `cloudflare/scripts/export-dns-zones.sh` (versioned, testable locally) |
| **Schedule** | Configurable `schedule` (e.g. `0 2 * * *` = 02:00 UTC daily) |
| **Manual run** | Yes (`workflow_dispatch`) |
| **Retention** | GitHub Actions artifacts (`retention-days: 90`, configurable) |
| **Permissions** | Default (no `contents: write`; artifact upload uses built-in permissions) |

## Rate limits and robustness

- Cloudflare export is subject to [rate limits](https://developers.cloudflare.com/fundamentals/api/reference/limits/). The script throttles with `EXPORT_DELAY_SEC` (default 25s) between zone exports.
- Zone file size limit (export): 256 KiB per zone. Larger zones may need handling (e.g. split or document exception).
- If no zones are exported (e.g. token issue or empty account), the script exits with an error and the workflow does not upload an artifact.
- Per-zone export failures are logged as warnings and skipped; the run still succeeds if at least one zone was exported.

## Optional extensions

- **JSON export**: In addition to BIND, include JSON per zone (e.g. from List DNS records) in the same artifact for tooling.
- **Longer retention**: Increase `retention-days` in the workflow (subject to repo/org limits) or copy artifacts to external storage in a follow-up job.
- **Commit instead of artifact**: Optional job to commit exports to a branch (e.g. `cloudflare-dns-exports`) for long-term versioned history.
