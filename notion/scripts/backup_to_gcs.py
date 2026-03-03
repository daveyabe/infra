#!/usr/bin/env python3
"""
Notion workspace backup → Google Cloud Storage.

Discovers all accessible pages and databases via the Notion API,
exports their full content (properties, blocks, database rows) as JSON,
packages them into a timestamped .tar.gz archive, and uploads to GCS.

Required environment variables:
  NOTION_API_TOKEN   – Notion internal integration token
  GCS_BUCKET_NAME    – Target GCS bucket (e.g. myproject-notion-backups)
  GCS_PREFIX         – Object prefix inside the bucket (default: "backups/")

Optional:
  BACKUP_DIR         – Local scratch directory (default: /tmp/notion-backup)
  NOTION_API_VERSION – API version header (default: 2022-06-28)
  PAGE_SIZE          – Pagination page size (default: 100, max 100)
  REQUEST_DELAY      – Seconds between API calls to respect rate limits (default: 0.35)
"""

import json
import logging
import os
import sys
import tarfile
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from google.cloud import storage

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

NOTION_API_TOKEN = os.environ["NOTION_API_TOKEN"]
GCS_BUCKET_NAME = os.environ["GCS_BUCKET_NAME"]
GCS_PREFIX = os.environ.get("GCS_PREFIX", "backups/").rstrip("/") + "/"

BACKUP_DIR = Path(os.environ.get("BACKUP_DIR", "/tmp/notion-backup"))
API_VERSION = os.environ.get("NOTION_API_VERSION", "2022-06-28")
PAGE_SIZE = int(os.environ.get("PAGE_SIZE", "100"))
REQUEST_DELAY = float(os.environ.get("REQUEST_DELAY", "0.35"))

BASE_URL = "https://api.notion.com/v1"
HEADERS = {
    "Authorization": f"Bearer {NOTION_API_TOKEN}",
    "Notion-Version": API_VERSION,
    "Content-Type": "application/json",
}

stats = {"pages": 0, "databases": 0, "blocks": 0, "api_calls": 0}


def api_request(method: str, url: str, **kwargs) -> dict:
    """Make a rate-limited request to the Notion API with retry on 429."""
    max_retries = 5
    for attempt in range(max_retries):
        time.sleep(REQUEST_DELAY)
        stats["api_calls"] += 1
        resp = requests.request(method, url, headers=HEADERS, timeout=60, **kwargs)
        if resp.status_code == 429:
            retry_after = float(resp.headers.get("Retry-After", 2 ** attempt))
            log.warning("Rate-limited (429). Retrying in %.1fs …", retry_after)
            time.sleep(retry_after)
            continue
        resp.raise_for_status()
        return resp.json()
    raise RuntimeError(f"Notion API returned 429 after {max_retries} retries: {url}")


def search_all(filter_value: str | None = None) -> list[dict]:
    """Paginate through Notion search results, optionally filtering by object type."""
    results = []
    payload: dict = {"page_size": PAGE_SIZE}
    if filter_value:
        payload["filter"] = {"value": filter_value, "property": "object"}

    while True:
        data = api_request("POST", f"{BASE_URL}/search", json=payload)
        results.extend(data.get("results", []))
        if not data.get("has_more"):
            break
        payload["start_cursor"] = data["next_cursor"]

    return results


def retrieve_block_children(block_id: str) -> list[dict]:
    """Recursively retrieve all block children for a given block/page."""
    blocks = []
    params: dict = {"page_size": PAGE_SIZE}

    while True:
        data = api_request("GET", f"{BASE_URL}/blocks/{block_id}/children", params=params)
        for block in data.get("results", []):
            stats["blocks"] += 1
            blocks.append(block)
            if block.get("has_children"):
                block["_children"] = retrieve_block_children(block["id"])
        if not data.get("has_more"):
            break
        params["start_cursor"] = data["next_cursor"]

    return blocks


def retrieve_page(page_id: str) -> dict:
    """Retrieve a page's properties."""
    return api_request("GET", f"{BASE_URL}/pages/{page_id}")


def retrieve_database(database_id: str) -> dict:
    """Retrieve a database's schema/metadata."""
    return api_request("GET", f"{BASE_URL}/databases/{database_id}")


def query_database(database_id: str) -> list[dict]:
    """Query all rows (pages) in a database with pagination."""
    rows = []
    payload: dict = {"page_size": PAGE_SIZE}

    while True:
        data = api_request("POST", f"{BASE_URL}/databases/{database_id}/query", json=payload)
        rows.extend(data.get("results", []))
        if not data.get("has_more"):
            break
        payload["start_cursor"] = data["next_cursor"]

    return rows


def write_json(filepath: Path, data: dict | list) -> None:
    filepath.parent.mkdir(parents=True, exist_ok=True)
    filepath.write_text(json.dumps(data, indent=2, ensure_ascii=False, default=str))


def safe_filename(title: str, obj_id: str) -> str:
    """Create a filesystem-safe name from a title + id."""
    clean = "".join(c if c.isalnum() or c in " _-" else "_" for c in title).strip()[:80]
    short_id = obj_id.replace("-", "")[:12]
    return f"{clean}_{short_id}" if clean else short_id


def extract_title(page: dict) -> str:
    """Best-effort extraction of a page or database title."""
    if page.get("object") == "database":
        title_parts = page.get("title", [])
        return "".join(t.get("plain_text", "") for t in title_parts) or "Untitled"

    props = page.get("properties", {})
    for prop in props.values():
        if prop.get("type") == "title":
            parts = prop.get("title", [])
            return "".join(t.get("plain_text", "") for t in parts) or "Untitled"
    return "Untitled"


def backup_page(page: dict, dest: Path) -> None:
    """Export a single page: metadata + full block tree."""
    page_id = page["id"]
    title = extract_title(page)
    dirname = safe_filename(title, page_id)
    page_dir = dest / dirname

    write_json(page_dir / "properties.json", page)

    try:
        blocks = retrieve_block_children(page_id)
        write_json(page_dir / "content.json", blocks)
    except requests.HTTPError as exc:
        log.warning("Could not retrieve blocks for page %s (%s): %s", title, page_id, exc)
        write_json(page_dir / "content.json", {"error": str(exc)})

    stats["pages"] += 1


def backup_database(db: dict, dest: Path) -> None:
    """Export a database: schema + all rows (each row = a page backup)."""
    db_id = db["id"]
    title = extract_title(db)
    dirname = safe_filename(title, db_id)
    db_dir = dest / dirname

    write_json(db_dir / "schema.json", db)

    try:
        rows = query_database(db_id)
        write_json(db_dir / "rows_index.json", rows)
    except requests.HTTPError as exc:
        log.warning("Could not query database %s (%s): %s", title, db_id, exc)
        write_json(db_dir / "rows_index.json", {"error": str(exc)})
        rows = []

    rows_dir = db_dir / "rows"
    for row in rows:
        backup_page(row, rows_dir)

    stats["databases"] += 1


def create_archive(source_dir: Path, timestamp: str) -> Path:
    archive_name = f"notion-backup-{timestamp}.tar.gz"
    archive_path = source_dir.parent / archive_name
    log.info("Creating archive: %s", archive_path)
    with tarfile.open(archive_path, "w:gz") as tar:
        tar.add(source_dir, arcname=f"notion-backup-{timestamp}")
    return archive_path


def upload_to_gcs(local_path: Path, timestamp: str) -> str:
    client = storage.Client()
    bucket = client.bucket(GCS_BUCKET_NAME)
    blob_name = f"{GCS_PREFIX}{local_path.name}"
    blob = bucket.blob(blob_name)

    log.info("Uploading %s → gs://%s/%s", local_path.name, GCS_BUCKET_NAME, blob_name)
    blob.upload_from_filename(str(local_path), timeout=600)

    latest_blob = bucket.blob(f"{GCS_PREFIX}latest.tar.gz")
    bucket.copy_blob(blob, bucket, latest_blob.name)
    log.info("Copied as latest → gs://%s/%s", GCS_BUCKET_NAME, latest_blob.name)

    return f"gs://{GCS_BUCKET_NAME}/{blob_name}"


def write_manifest(dest: Path, timestamp: str) -> None:
    manifest = {
        "backup_timestamp": timestamp,
        "backup_utc": datetime.now(timezone.utc).isoformat(),
        "stats": stats,
    }
    write_json(dest / "manifest.json", manifest)


def main() -> None:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dest = BACKUP_DIR / f"notion-backup-{timestamp}"

    if dest.exists():
        import shutil
        shutil.rmtree(dest)
    dest.mkdir(parents=True)

    log.info("=== Notion Backup Started: %s ===", timestamp)

    log.info("Discovering databases …")
    databases = search_all(filter_value="database")
    log.info("Found %d databases", len(databases))

    log.info("Discovering pages …")
    pages = search_all(filter_value="page")
    log.info("Found %d pages", len(pages))

    db_ids = {db["id"] for db in databases}

    db_dest = dest / "databases"
    for db in databases:
        title = extract_title(db)
        log.info("Backing up database: %s", title)
        backup_database(db, db_dest)

    page_dest = dest / "pages"
    for page in pages:
        if page.get("parent", {}).get("type") == "database_id":
            parent_db = page["parent"]["database_id"]
            if parent_db in db_ids:
                continue
        title = extract_title(page)
        log.info("Backing up page: %s", title)
        backup_page(page, page_dest)

    write_manifest(dest, timestamp)

    log.info(
        "Export complete — pages: %d, databases: %d, blocks: %d, API calls: %d",
        stats["pages"], stats["databases"], stats["blocks"], stats["api_calls"],
    )

    archive = create_archive(dest, timestamp)
    gcs_uri = upload_to_gcs(archive, timestamp)

    log.info("=== Backup uploaded: %s ===", gcs_uri)
    log.info("Archive size: %.2f MB", archive.stat().st_size / (1024 * 1024))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log.exception("Backup failed")
        sys.exit(1)
