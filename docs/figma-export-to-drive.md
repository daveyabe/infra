# Figma export to Google Drive (GitHub Action)

## Purpose

Export Figma file(s) top-level frames as images (PNG by default) and upload them to a Google Drive folder. Supports **single file**, **multiple file keys**, or **entire team** (discover all files via team → projects → files). Runs on a schedule and/or on demand via `workflow_dispatch`.

## Modes

- **Team (entire team’s files)**  
  Set `FIGMA_TEAM_ID` (team ID from the Figma URL when viewing the team). The script lists all projects in the team, then all files in each project, and exports every file. Drive structure: `root/ProjectName/FileName/frame1.png`. Optionally set `FIGMA_PROJECT_IDS` (comma-separated) to limit to specific projects.
- **Multiple files**  
  Set `FIGMA_FILE_KEYS` to a comma-separated list of file keys. Drive structure: `root/FileName/frame1.png` (one subfolder per file).
- **Single file**  
  Set `FIGMA_FILE_KEY`. All frames go directly into the root Drive folder.

## Behaviour

- **Trigger**: Optional `schedule` (cron) and/or `workflow_dispatch` for on-demand export.
- **Figma API**:
  - Team mode: `GET /v1/teams/:team_id/projects`, then `GET /v1/projects/:project_id/files` per project (requires `projects:read`).
  - Per file: `GET /v1/files/:key`, collect root-level frame node IDs, `GET /v1/images/:key?ids=...&format=png`, then download each image URL.
- **Google Drive**: For each file, create subfolders as needed (project name, then file name when in team mode; file name only when using `FIGMA_FILE_KEYS`). Upload each frame image into the file’s folder. File names are sanitized; duplicate names in the same folder will overwrite (no versioning by default).
- **Secrets / variables**:
  - `FIGMA_ACCESS_TOKEN` — Figma personal access token (secret). For team mode, the token must have access to the team and `projects:read` if using OAuth.
  - **Google Cloud (WIF, recommended):** The workflow uses Workload Identity Federation; no service account key is stored in GitHub. Set these **repository variables**:
    - **`WIF_PROVIDER`** — Full Workload Identity Provider resource name, e.g. `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID`.
    - **`WIF_SERVICE_ACCOUNT`** — Service account email, e.g. `figma-export@PROJECT_ID.iam.gserviceaccount.com`. The root folder **must be inside a Shared Drive** (service accounts have no storage quota in "My Drive"). Add this email as a member of the Shared Drive (e.g. Content manager). The same SA must be granted `roles/iam.workloadIdentityUser` for the GitHub repo principal (see [Setup: Workload Identity Federation](#setup-workload-identity-federation) below).
  - **Alternative (JSON key):** If you prefer a key, set secret **`GOOGLE_DRIVE_CREDENTIALS_JSON`** to the service account key JSON string. The script uses it when present; otherwise it uses Application Default Credentials (from the WIF auth step).
  - `GOOGLE_DRIVE_FOLDER_ID` — Root folder ID (variable). **When using a service account, this folder must be inside a [Shared Drive](https://support.google.com/drive/answer/7212025).** Use either the ID only or the full folder URL; the script normalizes URLs to the ID.
  - One of: `FIGMA_TEAM_ID`, `FIGMA_FILE_KEYS` (comma-separated), or `FIGMA_FILE_KEY`. Optional: `FIGMA_PROJECT_IDS` (comma-separated) to restrict team export to certain projects.
  - **`FIGMA_EXPORT_FORMAT`** — `png` (default), `jpg`, `svg`, or `pdf`.
  - **`FIGMA_COMBINE_PDF_PER_FILE`** — When set to `true` (or `1`) and format is `pdf`, all frames in each file are merged into a single PDF per file (e.g. one deck PDF per Figma Slides file). Otherwise each frame is uploaded as a separate file.

## Workflow summary

| Item | Value |
|------|--------|
| **Workflow file** | `.github/workflows/figma-export-to-drive.yml` |
| **Export script** | `figma/scripts/export-to-drive.js` (Node.js; run with `node figma/scripts/export-to-drive.js`) |
| **Schedule** | Optional; set `schedule` in the workflow (e.g. `0 8 * * 1-5` = 08:00 UTC weekdays). |
| **Manual run** | Yes (`workflow_dispatch`) |
| **Output** | PNG files in the specified Google Drive folder |

## Troubleshooting: 403 "Service Accounts do not have storage quota"

When using a **service account** (WIF or JSON key), the root folder must be inside a **Shared Drive** (formerly Team Drive), not in "My Drive". Service accounts have no storage quota in My Drive. Do this:

1. Create or use a **Shared Drive** in Google Drive (Drive for desktop or drive.google.com → Shared drives).
2. Create a folder inside that Shared Drive to use as the export root (or use the Shared Drive root).
3. Add the service account email (`WIF_SERVICE_ACCOUNT`) as a member of the Shared Drive with **Content manager** (or at least **Writer**) access.
4. Set `GOOGLE_DRIVE_FOLDER_ID` to that folder’s ID (from the folder URL).

The script sends `supportsAllDrives: true` so list/create work correctly in Shared Drives.

## Rate limits and robustness

- Figma image export URLs expire quickly; the script downloads them immediately after calling the images endpoint.
- Figma API is rate-limited; for a large team the script makes many requests (projects + files + file + images per file). Consider running during off-peak times or adding a short delay between files if you hit limits.
- If a file has no exportable frames, it is skipped; the run continues with the next file.
- Files that return "File type not supported by this endpoint" from Figma (e.g. blank templates, FigJam boards) are skipped with a log message; the run continues.
- Files that return 404 "File not found" (deleted, moved, or no access) are skipped; the run continues.
- Drive upload or folder-creation failures (e.g. permission or quota) cause the script to exit with an error and the workflow to fail.
- **Team ID**: You cannot get the team ID from the API. Copy it from the Figma URL when viewing the team in the browser (e.g. `figma.com/files/team/123456789` → team ID is `123456789`).

## Combined PDF per deck

When exporting slides or multi-frame files as PDF, set **`FIGMA_EXPORT_FORMAT=pdf`** and **`FIGMA_COMBINE_PDF_PER_FILE=true`** (or `1`). The script will request one PDF per frame from Figma, merge them in frame order with `pdf-lib`, and upload a single combined PDF per file (e.g. `My Deck.pdf`). Frame order follows the order of frames in the Figma file.

## Optional extensions

- **Versioning**: Extend the script to append a timestamp or run ID to file names (or create dated subfolders) instead of overwriting.
