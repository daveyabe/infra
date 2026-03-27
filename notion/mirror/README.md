# Notion Mirror

A Streamlit app for browsing, snapshotting, and diffing Notion workspace data. Built on top of Notion's API, it persists every observation to a local SQLite database so you can track changes over time and inspect the raw data structures Notion returns.

## Architecture

```
Streamlit UI (app.py)
 ├── api.py          → Notion SDK wrapper (pagination, recursion, instrumentation)
 │    └──────────────→ storage.log_api_call (every request is logged)
 ├── storage.py      → SQLite layer (snapshots, API call log, diff history)
 └── diff_engine.py  → DeepDiff-based structural comparison with volatile-path filtering
```

### Modules

| File | Role |
|------|------|
| `app.py` | Streamlit entrypoint — UI, navigation, session state, rendering |
| `api.py` | Thin instrumented wrapper around `notion-client`. Handles search, pagination, recursive block retrieval, and "stitched" database fetches |
| `storage.py` | SQLite persistence (`mirror.db`) for snapshots, API call metrics, and diff results. Uses WAL mode |
| `diff_engine.py` | Structural diffs via DeepDiff. Strips volatile paths (timestamps, signed URLs) from the filtered view while preserving full results |

### Data flow

1. **Fetch** — `api.py` calls Notion and logs every request (endpoint, status, latency) to SQLite.
2. **Snapshot** — Any fetched object (database, page, stitched database) can be saved as a point-in-time snapshot.
3. **Diff** — Compare two snapshots, or a snapshot against the current live state, to see exactly what changed.

## App screens

| Screen | What it does |
|--------|-------------|
| **Explorer** | List databases and pages from the workspace. View schemas, query rows, take snapshots |
| **Page Viewer** | Fetch a single page by ID with its full recursive block tree |
| **Stitched Mirror** | Fetch an entire database including every row's nested blocks — useful for full-fidelity mirroring and stress-testing |
| **Mirror** | Browse all saved snapshots with filters by object type and Notion ID |
| **Diff** | Compare snapshot-vs-snapshot or snapshot-vs-live. Shows filtered (noise-free) and raw DeepDiff output |
| **Import** | Upload external `.json` backups (API exports or files saved from this app). Auto-detects `database`, `page`, or `stitched` shape; saves into `mirror.db` for Mirror/Diff |
| **API Metrics** | Charts for latency, endpoints, status codes. Highlights rate-limit 429s |

## Setup

### Prerequisites

- Python 3.10+
- A [Notion integration](https://www.notion.so/my-integrations) token with access to the workspaces/pages/databases you want to mirror

### Install

```bash
cd notion/mirror
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Configure

```bash
cp .env.example .env
```

Edit `.env` and set your integration token:

```
NOTION_API_TOKEN=ntn_your_integration_token_here
```

### Run

```bash
streamlit run app.py
```

The app must be launched from the `notion/mirror` directory so that local imports resolve correctly.

On first run, `mirror.db` is created automatically in the same directory. It is gitignored.

## Dependencies

| Package | Purpose |
|---------|---------|
| `streamlit` | Web UI framework |
| `notion-client` | Official Notion SDK (v3 data-sources API) |
| `deepdiff` | Structural object comparison |
| `python-dotenv` | `.env` file loading |
| `watchdog` | Streamlit file-watcher backend |

Pandas is used for table rendering in the Stitched Mirror view; it ships as a transitive dependency of Streamlit.

## Import (JSON into the app)

Use the **Import** screen to load one or more `.json` files without calling Notion. The app infers the snapshot type from the structure (`schema` + `rows` → database or stitched if any row has `_blocks`; `page` + `blocks` → page). You can override the type or set a label. Snapshots are stored in `mirror.db` and behave like ones taken from Explorer.

## Restore (CLI)

`restore.py` pushes a snapshot back into a Notion workspace under a **parent page** you choose (create an empty page in Notion and share it with your integration).

```bash
cd notion/mirror
source .venv/bin/activate
python restore.py --snapshot-id 42 --parent-page-id YOUR_PAGE_ID
# or from a file:
python restore.py --file backup.json --parent-page-id YOUR_PAGE_ID --dry-run
```

| Flag | Meaning |
|------|--------|
| `--snapshot-id` | Row id in the `snapshots` table (from Mirror or after an import) |
| `--file` | Path to a JSON file with the same shape as a stored snapshot |
| `--parent-page-id` | Required. Page under which the database or page is created |
| `--dry-run` | Log intended API calls without contacting Notion (no token required) |
| `--token` | Optional; defaults to `NOTION_API_TOKEN` |

The script rate-limits requests (~3/s), backs off on HTTP 429, logs calls into the same `api_calls` table, maps old Notion IDs to new ones for relation updates on a second pass, and skips block types the API cannot create (e.g. `child_database`, `synced_block`).

### Restore limitations

- Notion assigns new IDs; links and bookmarks to old IDs will not resolve.
- Signed URLs in file/image blocks expire; the API cannot re-upload arbitrary binaries the same way the UI does.
- Formula, rollup, and several read-only property types are omitted when recreating schema and rows.
- Relation columns that pointed at databases outside the restored snapshot may still reference old IDs until you fix them manually.
