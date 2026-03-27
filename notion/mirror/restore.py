"""Restore Notion snapshots back into a Notion workspace.

Reads a snapshot (from mirror.db or a JSON file) and recreates the content
under a target parent page, handling schema mapping, block trees, rate
limiting, and ID remapping for internal references.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Optional

from dotenv import load_dotenv
from notion_client import Client
from notion_client.errors import APIResponseError

import storage

load_dotenv()

RATE_LIMIT_DELAY = 0.35  # ~3 req/s
MAX_BACKOFF = 60
BLOCKS_PER_APPEND = 100  # Notion's limit per append call

READ_ONLY_PROPERTY_TYPES = frozenset({
    "formula",
    "rollup",
    "created_time",
    "created_by",
    "last_edited_time",
    "last_edited_by",
    "unique_id",
    "verification",
})

UNSUPPORTED_BLOCK_TYPES = frozenset({
    "child_database",
    "synced_block",
    "unsupported",
    "table_of_contents",
    "breadcrumb",
    "link_to_page",
    "column_list",
    "column",
})

BLOCK_READ_ONLY_KEYS = frozenset({
    "id", "object", "parent", "created_time", "last_edited_time",
    "created_by", "last_edited_by", "has_children", "archived",
    "in_trash", "_children", "request_id",
})


class RestoreContext:
    """Tracks state across the restore: client, ID map, counters, options."""

    def __init__(self, client: Optional[Client], dry_run: bool = False):
        self.client = client
        self.dry_run = dry_run
        self.id_map: dict[str, str] = {}
        self.api_calls = 0
        self.skipped_blocks: list[str] = []
        self.warnings: list[str] = []
        self._backoff = 1.0

    def call(self, method: str, endpoint: str, fn, **kwargs) -> Any:
        """Rate-limited, retrying API call with progress tracking."""
        if self.dry_run:
            self.api_calls += 1
            _log(f"  [dry-run] {method} {endpoint}")
            return {"id": f"dry-run-{self.api_calls}", "object": "page"}

        if self.client is None:
            raise RuntimeError("Notion client is not configured")

        time.sleep(RATE_LIMIT_DELAY)

        while True:
            try:
                start = time.perf_counter()
                result = fn(**kwargs)
                latency = (time.perf_counter() - start) * 1000
                self.api_calls += 1
                self._backoff = 1.0

                storage.log_api_call(
                    endpoint=endpoint, method=method, status=200,
                    latency_ms=latency,
                    response_bytes=sys.getsizeof(result),
                )
                return result

            except APIResponseError as exc:
                storage.log_api_call(
                    endpoint=endpoint, method=method, status=exc.status,
                    error=str(exc),
                )
                if exc.status == 429:
                    wait = min(self._backoff, MAX_BACKOFF)
                    _log(f"  Rate limited — waiting {wait:.1f}s")
                    time.sleep(wait)
                    self._backoff *= 2
                    continue
                raise


def _log(msg: str) -> None:
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# Property schema mapping
# ---------------------------------------------------------------------------

def _clean_property_schema(name: str, prop: dict) -> dict | None:
    """Convert a read-back property dict into a create-database property spec.

    Returns None for properties that should be skipped.
    """
    ptype = prop.get("type", "")

    if ptype in READ_ONLY_PROPERTY_TYPES:
        return None

    # Title property is auto-created by Notion; we configure it separately
    if ptype == "title":
        return None

    spec: dict[str, Any] = {}

    if ptype == "select":
        options = prop.get("select", {}).get("options", [])
        spec["select"] = {"options": [{"name": o["name"], "color": o.get("color", "default")} for o in options]}
    elif ptype == "multi_select":
        options = prop.get("multi_select", {}).get("options", [])
        spec["multi_select"] = {"options": [{"name": o["name"], "color": o.get("color", "default")} for o in options]}
    elif ptype == "status":
        status_conf = prop.get("status", {})
        options = status_conf.get("options", [])
        groups = status_conf.get("groups", [])
        spec["status"] = {
            "options": [{"name": o["name"], "color": o.get("color", "default")} for o in options],
            "groups": [
                {"name": g["name"], "color": g.get("color", "default"),
                 "option_ids": [oid for oid in g.get("option_ids", [])]}
                for g in groups
            ],
        }
    elif ptype == "relation":
        rel = prop.get("relation", {})
        target_db = rel.get("database_id", "")
        spec["relation"] = {"database_id": target_db, "type": rel.get("type", "single_property")}
        if rel.get("type") == "dual_property":
            spec["relation"]["dual_property"] = {}
    elif ptype == "number":
        fmt = prop.get("number", {}).get("format", "number")
        spec["number"] = {"format": fmt}
    elif ptype == "date":
        spec["date"] = {}
    elif ptype == "checkbox":
        spec["checkbox"] = {}
    elif ptype == "url":
        spec["url"] = {}
    elif ptype == "email":
        spec["email"] = {}
    elif ptype == "phone_number":
        spec["phone_number"] = {}
    elif ptype == "rich_text":
        spec["rich_text"] = {}
    elif ptype == "people":
        spec["people"] = {}
    elif ptype == "files":
        spec["files"] = {}
    else:
        spec[ptype] = {}

    return spec


def _clean_property_value(name: str, prop: dict) -> dict | None:
    """Convert a read-back property value into a page-create property payload.

    Returns None for properties that cannot be written.
    """
    ptype = prop.get("type", "")

    if ptype in READ_ONLY_PROPERTY_TYPES:
        return None
    if ptype == "relation":
        return None  # handled in the ID-remap pass

    data = prop.get(ptype)

    if ptype == "title":
        return {"title": data} if data else None
    if ptype == "rich_text":
        return {"rich_text": data} if data else None
    if ptype in ("number", "checkbox", "url", "email", "phone_number"):
        return {ptype: data} if data is not None else None
    if ptype == "select":
        return {"select": {"name": data["name"]}} if data else None
    if ptype == "multi_select":
        return {"multi_select": [{"name": o["name"]} for o in data]} if data else None
    if ptype == "status":
        return {"status": {"name": data["name"]}} if data else None
    if ptype == "date":
        return {"date": data} if data else None
    if ptype == "people":
        return {"people": [{"id": p["id"]} for p in data]} if data else None
    if ptype == "files":
        external_files = [
            {"name": f.get("name", "file"), "type": "external",
             "external": {"url": f.get("external", {}).get("url", "")}}
            for f in (data or [])
            if f.get("type") == "external"
        ]
        return {"files": external_files} if external_files else None

    return None


# ---------------------------------------------------------------------------
# Block mapping
# ---------------------------------------------------------------------------

def _clean_block(block: dict) -> dict | None:
    """Convert a read-back block dict into a writable append payload."""
    btype = block.get("type", "")

    if btype in UNSUPPORTED_BLOCK_TYPES:
        return None

    cleaned: dict[str, Any] = {"type": btype}

    type_data = block.get(btype)
    if isinstance(type_data, dict):
        cleaned_type_data = {
            k: v for k, v in type_data.items()
            if k not in ("id",)
        }
        cleaned[btype] = cleaned_type_data
    elif type_data is not None:
        cleaned[btype] = type_data

    for key in BLOCK_READ_ONLY_KEYS:
        cleaned.pop(key, None)

    return cleaned


def _collect_block_tree(blocks: list[dict], ctx: RestoreContext) -> list[tuple[dict, list[dict]]]:
    """Build a list of (writable_block, original_children) pairs.

    Returns flat writable blocks; children are handled via separate append calls.
    """
    pairs = []
    for block in blocks:
        cleaned = _clean_block(block)
        if cleaned is None:
            ctx.skipped_blocks.append(block.get("type", "unknown"))
            continue
        children = block.get("_children", [])
        pairs.append((cleaned, children))
    return pairs


# ---------------------------------------------------------------------------
# Restore operations
# ---------------------------------------------------------------------------

def _append_blocks(ctx: RestoreContext, parent_id: str, blocks: list[dict]) -> list[dict]:
    """Append blocks to a parent, recursing into children. Returns created blocks."""
    pairs = _collect_block_tree(blocks, ctx)
    created_all: list[dict] = []

    # Notion accepts max 100 blocks per append call
    for i in range(0, len(pairs), BLOCKS_PER_APPEND):
        batch_pairs = pairs[i:i + BLOCKS_PER_APPEND]
        payloads = [p[0] for p in batch_pairs]

        result = ctx.call(
            "PATCH", f"/blocks/{parent_id}/children",
            lambda **kw: ctx.client.blocks.children.append(**kw),
            block_id=parent_id, children=payloads,
        )

        if isinstance(result, list):
            created_blocks = result
        elif isinstance(result, dict):
            created_blocks = result.get("results", [])
        else:
            created_blocks = []
        created_all.extend(created_blocks)

        # Recurse into children
        for j, (_, original_children) in enumerate(batch_pairs):
            if not original_children:
                continue
            if j < len(created_blocks):
                new_parent_id = created_blocks[j].get("id", parent_id)
                _append_blocks(ctx, new_parent_id, original_children)

    return created_all


def restore_page(ctx: RestoreContext, data: dict, parent_page_id: str) -> str:
    """Restore a page snapshot under the given parent page."""
    page_data = data.get("page", {})
    blocks = data.get("blocks", [])

    properties = {}
    for name, prop in page_data.get("properties", {}).items():
        cleaned = _clean_property_value(name, prop)
        if cleaned:
            properties[name] = cleaned

    if not any(v.get("title") is not None for v in properties.values()):
        properties["Name"] = {"title": [{"text": {"content": "Restored page"}}]}

    result = ctx.call(
        "POST", "/pages",
        lambda **kw: ctx.client.pages.create(**kw),
        parent={"type": "page_id", "page_id": parent_page_id},
        properties=properties,
    )

    new_page_id = result.get("id", "dry-run")
    old_id = page_data.get("id")
    if old_id:
        ctx.id_map[old_id] = new_page_id

    _log(f"  Created page: {new_page_id}")

    if blocks:
        _log(f"  Appending {len(blocks)} top-level blocks...")
        _append_blocks(ctx, new_page_id, blocks)

    return new_page_id


def restore_database(ctx: RestoreContext, data: dict, parent_page_id: str) -> str:
    """Restore a database (or stitched) snapshot under the given parent page."""
    schema = data.get("schema", {})
    rows = data.get("rows", [])
    title_text = data.get("title") or _schema_title(schema) or "Restored database"

    # Build property schema for create call
    properties: dict[str, Any] = {}
    title_prop_name = "Name"
    for name, prop in schema.get("properties", {}).items():
        if prop.get("type") == "title":
            title_prop_name = name
            continue
        cleaned = _clean_property_schema(name, prop)
        if cleaned:
            properties[name] = cleaned

    properties[title_prop_name] = {"title": {}}

    _log(f"Creating database: {title_text} ({len(properties)} properties)")

    result = ctx.call(
        "POST", "/databases",
        lambda **kw: ctx.client.databases.create(**kw),
        parent={"type": "page_id", "page_id": parent_page_id},
        title=[{"type": "text", "text": {"content": title_text}}],
        properties=properties,
    )

    new_db_id = result.get("id", "dry-run")
    old_db_id = schema.get("id")
    if old_db_id:
        ctx.id_map[old_db_id] = new_db_id

    _log(f"  Database created: {new_db_id}")

    # Create rows
    total = len(rows)
    for idx, row in enumerate(rows, 1):
        row_props: dict[str, Any] = {}
        for name, prop in row.get("properties", {}).items():
            cleaned = _clean_property_value(name, prop)
            if cleaned:
                row_props[name] = cleaned

        if not row_props:
            row_props[title_prop_name] = {"title": [{"text": {"content": "Untitled"}}]}

        row_title = _row_title(row)
        _log(f"  [{idx}/{total}] Creating row: {row_title}")

        row_result = ctx.call(
            "POST", "/pages",
            lambda **kw: ctx.client.pages.create(**kw),
            parent={"type": "database_id", "database_id": new_db_id},
            properties=row_props,
        )

        new_row_id = row_result.get("id", f"dry-run-row-{idx}")
        old_row_id = row.get("id")
        if old_row_id:
            ctx.id_map[old_row_id] = new_row_id

        # Append block content if present (stitched snapshots)
        row_blocks = row.get("_blocks", [])
        if row_blocks:
            _log(f"           Appending {len(row_blocks)} blocks")
            _append_blocks(ctx, new_row_id, row_blocks)

    return new_db_id


def _remap_relations(ctx: RestoreContext, data: dict, new_db_id: str) -> None:
    """Second pass: update relation properties that reference IDs we've remapped."""
    if ctx.dry_run:
        _log("  [dry-run] Skipping relation remap pass")
        return

    rows = data.get("rows", [])
    for row in rows:
        old_row_id = row.get("id")
        new_row_id = ctx.id_map.get(old_row_id)
        if not new_row_id:
            continue

        updates: dict[str, Any] = {}
        for name, prop in row.get("properties", {}).items():
            if prop.get("type") != "relation":
                continue
            relations = prop.get("relation", [])
            if not relations:
                continue

            remapped = []
            for rel in relations:
                target = rel.get("id", "")
                new_target = ctx.id_map.get(target, target)
                remapped.append({"id": new_target})
            updates[name] = {"relation": remapped}

        if updates:
            _log(f"  Remapping {len(updates)} relation(s) on {new_row_id[:12]}")
            ctx.call(
                "PATCH", f"/pages/{new_row_id}",
                lambda **kw: ctx.client.pages.update(**kw),
                page_id=new_row_id, properties=updates,
            )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _schema_title(schema: dict) -> str | None:
    title_arr = schema.get("title", [])
    if isinstance(title_arr, list):
        return "".join(t.get("plain_text", "") for t in title_arr) or None
    return None


def _row_title(row: dict) -> str:
    for prop in row.get("properties", {}).values():
        if prop.get("type") == "title":
            parts = prop.get("title", [])
            title = "".join(t.get("plain_text", "") for t in parts)
            if title:
                return title
    return row.get("id", "???")[:12]


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def _load_snapshot(args) -> tuple[str, dict]:
    """Load snapshot data, returning (object_type, data)."""
    if args.file:
        path = Path(args.file)
        if not path.exists():
            _log(f"Error: file not found: {path}")
            sys.exit(1)
        raw = json.loads(path.read_text())
        # Detect type from shape
        if "schema" in raw and "rows" in raw:
            obj_type = "stitched" if any("_blocks" in r for r in raw.get("rows", [])) else "database"
        elif "page" in raw and "blocks" in raw:
            obj_type = "page"
        else:
            _log("Error: cannot determine snapshot type from JSON structure")
            sys.exit(1)
        return obj_type, raw

    if args.snapshot_id:
        storage.init_db()
        snap = storage.get_snapshot(args.snapshot_id)
        if snap is None:
            _log(f"Error: snapshot #{args.snapshot_id} not found")
            sys.exit(1)
        return snap["object_type"], snap["data"]

    _log("Error: provide --snapshot-id or --file")
    sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Restore a Notion snapshot into a workspace.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  python restore.py --snapshot-id 42 --parent-page-id abc123
  python restore.py --file backup.json --parent-page-id abc123 --dry-run
  python restore.py --file db_export.json --parent-page-id abc123 --token ntn_xxx
""",
    )
    parser.add_argument("--snapshot-id", type=int, help="Snapshot ID from mirror.db")
    parser.add_argument("--file", help="Path to a JSON backup file")
    parser.add_argument("--parent-page-id", required=True, help="Notion page ID to create content under")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without calling Notion")
    parser.add_argument("--token", help="Notion API token (overrides NOTION_API_TOKEN env var)")

    args = parser.parse_args()

    token = args.token or os.environ.get("NOTION_API_TOKEN", "")
    if not token and not args.dry_run:
        _log("Error: set NOTION_API_TOKEN or pass --token")
        sys.exit(1)

    obj_type, data = _load_snapshot(args)
    _log(f"Snapshot type: {obj_type}")

    client = Client(auth=token) if token else None
    ctx = RestoreContext(client=client, dry_run=args.dry_run)

    if not args.dry_run:
        storage.init_db()

    try:
        if obj_type in ("database", "stitched"):
            row_count = len(data.get("rows", []))
            _log(f"Restoring database with {row_count} rows")
            new_id = restore_database(ctx, data, args.parent_page_id)
            _remap_relations(ctx, data, new_id)
        elif obj_type == "page":
            _log("Restoring page")
            new_id = restore_page(ctx, data, args.parent_page_id)
        else:
            _log(f"Error: unsupported snapshot type: {obj_type}")
            sys.exit(1)

        _log("")
        _log(f"Restore complete.")
        _log(f"  New root ID: {new_id}")
        _log(f"  API calls:   {ctx.api_calls}")
        _log(f"  ID mappings: {len(ctx.id_map)}")

        if ctx.skipped_blocks:
            from collections import Counter
            counts = Counter(ctx.skipped_blocks)
            _log(f"  Skipped block types: {dict(counts)}")

        if ctx.warnings:
            _log(f"  Warnings:")
            for w in ctx.warnings:
                _log(f"    - {w}")

    except APIResponseError as exc:
        _log(f"Notion API error: {exc.status} — {exc}")
        sys.exit(1)
    except KeyboardInterrupt:
        _log(f"\nInterrupted. {ctx.api_calls} API calls were made.")
        _log(f"ID mappings so far: {len(ctx.id_map)}")
        sys.exit(130)


if __name__ == "__main__":
    main()
