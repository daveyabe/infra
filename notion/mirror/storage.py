"""SQLite storage layer for snapshots, API call logs, and diff history."""

from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DB_PATH = Path(__file__).parent / "mirror.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS snapshots (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    object_type TEXT    NOT NULL,  -- 'page', 'database', 'blocks'
    notion_id   TEXT    NOT NULL,
    label       TEXT,              -- human-readable title
    data_json   TEXT    NOT NULL,
    captured_at TEXT    NOT NULL   -- ISO-8601 UTC
);

CREATE INDEX IF NOT EXISTS idx_snapshots_notion_id
    ON snapshots (notion_id, captured_at DESC);

CREATE TABLE IF NOT EXISTS api_calls (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    endpoint       TEXT    NOT NULL,
    method         TEXT    NOT NULL,
    status         INTEGER,
    latency_ms     REAL,
    response_bytes INTEGER,
    error          TEXT,
    timestamp      TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_api_calls_timestamp
    ON api_calls (timestamp DESC);

CREATE TABLE IF NOT EXISTS diffs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    snapshot_a_id INTEGER NOT NULL REFERENCES snapshots(id),
    snapshot_b_id INTEGER,          -- NULL when comparing against live fetch
    diff_json     TEXT    NOT NULL,
    summary       TEXT,
    created_at    TEXT    NOT NULL
);
"""


@contextmanager
def _conn():
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with _conn() as conn:
        conn.executescript(SCHEMA)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── Snapshots ──────────────────────────────────────────────────────────

def save_snapshot(
    object_type: str,
    notion_id: str,
    data: Any,
    label: str | None = None,
) -> int:
    with _conn() as conn:
        cur = conn.execute(
            "INSERT INTO snapshots (object_type, notion_id, label, data_json, captured_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (object_type, notion_id, label, json.dumps(data, default=str), _now()),
        )
        return cur.lastrowid  # type: ignore[return-value]


def get_snapshot(snapshot_id: int) -> dict | None:
    with _conn() as conn:
        row = conn.execute(
            "SELECT * FROM snapshots WHERE id = ?", (snapshot_id,)
        ).fetchone()
        if row is None:
            return None
        d = dict(row)
        d["data"] = json.loads(d.pop("data_json"))
        return d


def list_snapshots(
    notion_id: str | None = None,
    object_type: str | None = None,
    limit: int = 50,
) -> list[dict]:
    clauses, params = [], []
    if notion_id:
        clauses.append("notion_id = ?")
        params.append(notion_id)
    if object_type:
        clauses.append("object_type = ?")
        params.append(object_type)

    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    params.append(limit)

    with _conn() as conn:
        rows = conn.execute(
            f"SELECT id, object_type, notion_id, label, captured_at "
            f"FROM snapshots {where} ORDER BY captured_at DESC LIMIT ?",
            params,
        ).fetchall()
        return [dict(r) for r in rows]


# ── API call logs ──────────────────────────────────────────────────────

def log_api_call(
    endpoint: str,
    method: str,
    status: int | None = None,
    latency_ms: float | None = None,
    response_bytes: int | None = None,
    error: str | None = None,
) -> None:
    with _conn() as conn:
        conn.execute(
            "INSERT INTO api_calls (endpoint, method, status, latency_ms, response_bytes, error, timestamp) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (endpoint, method, status, latency_ms, response_bytes, error, _now()),
        )


def get_api_call_stats(since: str | None = None) -> list[dict]:
    where = ""
    params: list[Any] = []
    if since:
        where = "WHERE timestamp >= ?"
        params.append(since)

    with _conn() as conn:
        rows = conn.execute(
            f"SELECT endpoint, method, status, latency_ms, response_bytes, error, timestamp "
            f"FROM api_calls {where} ORDER BY timestamp DESC",
            params,
        ).fetchall()
        return [dict(r) for r in rows]


def get_api_call_summary() -> dict:
    with _conn() as conn:
        row = conn.execute(
            "SELECT "
            "  COUNT(*) as total_calls, "
            "  AVG(latency_ms) as avg_latency_ms, "
            "  MAX(latency_ms) as max_latency_ms, "
            "  SUM(response_bytes) as total_bytes, "
            "  SUM(CASE WHEN status = 429 THEN 1 ELSE 0 END) as rate_limited, "
            "  SUM(CASE WHEN error IS NOT NULL THEN 1 ELSE 0 END) as errors "
            "FROM api_calls"
        ).fetchone()
        return dict(row) if row else {}


# ── Diffs ──────────────────────────────────────────────────────────────

def save_diff(
    snapshot_a_id: int,
    snapshot_b_id: int | None,
    diff_json: str,
    summary: str | None = None,
) -> int:
    with _conn() as conn:
        cur = conn.execute(
            "INSERT INTO diffs (snapshot_a_id, snapshot_b_id, diff_json, summary, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (snapshot_a_id, snapshot_b_id, diff_json, summary, _now()),
        )
        return cur.lastrowid  # type: ignore[return-value]


def list_diffs(limit: int = 50) -> list[dict]:
    with _conn() as conn:
        rows = conn.execute(
            "SELECT d.id, d.snapshot_a_id, d.snapshot_b_id, d.summary, d.created_at, "
            "  sa.label as label_a, sb.label as label_b "
            "FROM diffs d "
            "LEFT JOIN snapshots sa ON d.snapshot_a_id = sa.id "
            "LEFT JOIN snapshots sb ON d.snapshot_b_id = sb.id "
            "ORDER BY d.created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]


def get_diff(diff_id: int) -> dict | None:
    with _conn() as conn:
        row = conn.execute(
            "SELECT * FROM diffs WHERE id = ?", (diff_id,)
        ).fetchone()
        if row is None:
            return None
        d = dict(row)
        d["diff_data"] = json.loads(d.pop("diff_json"))
        return d
