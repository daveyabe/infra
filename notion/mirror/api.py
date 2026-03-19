"""Instrumented Notion API wrapper with pagination and recursive block retrieval."""

from __future__ import annotations

import sys
import time
from typing import Any

from notion_client import Client
from notion_client.errors import APIResponseError

import storage


def _make_client(token: str) -> Client:
    return Client(auth=token)


_client: Client | None = None


def init(token: str) -> None:
    global _client
    _client = _make_client(token)
    storage.init_db()


def _get_client() -> Client:
    if _client is None:
        raise RuntimeError("Call api.init(token) before using the API")
    return _client


def _instrumented_call(method: str, endpoint: str, fn, **kwargs) -> Any:
    """Execute a Notion SDK call, logging timing and status to SQLite."""
    start = time.perf_counter()
    status = None
    response_bytes = None
    error_msg = None
    try:
        result = fn(**kwargs)
        status = 200
        response_bytes = sys.getsizeof(result)
        return result
    except APIResponseError as exc:
        status = exc.status
        error_msg = str(exc)
        raise
    except Exception as exc:
        error_msg = str(exc)
        raise
    finally:
        latency_ms = (time.perf_counter() - start) * 1000
        storage.log_api_call(
            endpoint=endpoint,
            method=method,
            status=status,
            latency_ms=latency_ms,
            response_bytes=response_bytes,
            error=error_msg,
        )


# ── Search ─────────────────────────────────────────────────────────────

def search(query: str = "", filter_object: str | None = None) -> list[dict]:
    """Search across all pages and databases the integration has access to."""
    client = _get_client()
    results: list[dict] = []
    payload: dict[str, Any] = {"page_size": 100}
    if query:
        payload["query"] = query
    if filter_object:
        payload["filter"] = {"value": filter_object, "property": "object"}

    while True:
        data = _instrumented_call(
            "POST", "/search", client.search, **payload
        )
        results.extend(data.get("results", []))
        if not data.get("has_more"):
            break
        payload["start_cursor"] = data["next_cursor"]

    return results


# ── Databases / Data Sources ───────────────────────────────────────────

def list_databases() -> list[dict]:
    return search(filter_object="data_source")


def retrieve_database(database_id: str) -> dict:
    client = _get_client()
    return _instrumented_call(
        "GET", f"/data_sources/{database_id}",
        client.data_sources.retrieve, data_source_id=database_id,
    )


def query_database(database_id: str) -> list[dict]:
    """Query all rows in a database with automatic pagination."""
    client = _get_client()
    rows: list[dict] = []
    start_cursor: str | None = None

    while True:
        kwargs: dict[str, Any] = {"data_source_id": database_id, "page_size": 100}
        if start_cursor:
            kwargs["start_cursor"] = start_cursor

        data = _instrumented_call(
            "POST", f"/data_sources/{database_id}/query",
            client.data_sources.query, **kwargs,
        )
        rows.extend(data.get("results", []))
        if not data.get("has_more"):
            break
        start_cursor = data["next_cursor"]

    return rows


# ── Pages ──────────────────────────────────────────────────────────────

def list_pages() -> list[dict]:
    return search(filter_object="page")


def retrieve_page(page_id: str) -> dict:
    client = _get_client()
    return _instrumented_call(
        "GET", f"/pages/{page_id}",
        client.pages.retrieve, page_id=page_id,
    )


# ── Blocks ─────────────────────────────────────────────────────────────

def retrieve_block_children(block_id: str, recursive: bool = True) -> list[dict]:
    """Retrieve all block children, optionally recursing into nested blocks."""
    client = _get_client()
    blocks: list[dict] = []
    params: dict[str, Any] = {"block_id": block_id, "page_size": 100}

    while True:
        data = _instrumented_call(
            "GET", f"/blocks/{block_id}/children",
            client.blocks.children.list, **params,
        )
        for block in data.get("results", []):
            blocks.append(block)
            if recursive and block.get("has_children"):
                block["_children"] = retrieve_block_children(block["id"], recursive=True)
        if not data.get("has_more"):
            break
        params["start_cursor"] = data["next_cursor"]

    return blocks


# ── Convenience helpers ────────────────────────────────────────────────

def _rich_text_content(parts: list[dict]) -> str:
    """Extract text from a rich_text array, preferring plain_text then text.content."""
    texts = []
    for part in parts:
        text = part.get("plain_text", "")
        if not text:
            text = part.get("text", {}).get("content", "")
        if text:
            texts.append(text)
    return "".join(texts)


def extract_title(obj: dict) -> str:
    """Extract a display title from a page, database, or data_source object.

    Checks the top-level 'title' array first (databases/data_sources),
    then falls back to scanning properties for a 'title'-typed property
    (pages and database rows).
    """
    obj_id = obj.get("id", "")[:12]

    # Databases / data_sources have a top-level 'title' rich_text array
    top_title = obj.get("title")
    if isinstance(top_title, list) and top_title:
        title = _rich_text_content(top_title)
        if title:
            return title

    # Pages / rows have a 'title'-typed property inside 'properties'
    for prop in obj.get("properties", {}).values():
        if prop.get("type") == "title":
            title = _rich_text_content(prop.get("title", []))
            if title:
                return title

    # Last resort: try 'name' field (some API shapes use this)
    if obj.get("name"):
        return obj["name"]

    return obj_id


def snapshot_database(database_id: str) -> int:
    """Fetch a full database (schema + rows) and store as a snapshot."""
    schema = retrieve_database(database_id)
    rows = query_database(database_id)
    title = extract_title(schema)
    data = {"schema": schema, "rows": rows}
    return storage.save_snapshot("database", database_id, data, label=title)


def snapshot_page(page_id: str) -> int:
    """Fetch a page (properties + block tree) and store as a snapshot."""
    page = retrieve_page(page_id)
    blocks = retrieve_block_children(page_id)
    title = extract_title(page)
    data = {"page": page, "blocks": blocks}
    return storage.save_snapshot("page", page_id, data, label=title)


def stitch_database(database_id: str, on_row_progress=None) -> dict:
    """Fetch a database schema, all rows, and the block content of every row.

    Returns a dict with 'schema', 'rows' (each row augmented with a
    '_blocks' key containing its full block tree), and stats.
    """
    schema = retrieve_database(database_id)
    rows = query_database(database_id)
    title = extract_title(schema)

    for i, row in enumerate(rows):
        row["_blocks"] = retrieve_block_children(row["id"])
        if on_row_progress:
            on_row_progress(i + 1, len(rows), extract_title(row))

    return {
        "schema": schema,
        "title": title,
        "rows": rows,
        "stats": {
            "row_count": len(rows),
            "total_blocks": sum(
                _count_blocks(row.get("_blocks", [])) for row in rows
            ),
        },
    }


def _count_blocks(blocks: list[dict]) -> int:
    total = len(blocks)
    for b in blocks:
        total += _count_blocks(b.get("_children", []))
    return total


def snapshot_stitched(database_id: str, on_row_progress=None) -> int:
    """Stitch a full database and store as a single snapshot."""
    data = stitch_database(database_id, on_row_progress=on_row_progress)
    return storage.save_snapshot(
        "stitched", database_id, data, label=f"{data['title']} (stitched)"
    )
