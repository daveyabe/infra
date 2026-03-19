"""Structural diffing of Notion snapshots using deepdiff."""

from __future__ import annotations

import json
import re
from typing import Any

from deepdiff import DeepDiff

import storage

VOLATILE_PATHS = re.compile(
    r"(last_edited_time|last_edited_by|request_id"
    r"|root\[.*?\]\['url'\]"  # signed URLs rotate
    r"|root\[.*?\]\['public_url'\]"
    r"|root\[.*?\]\['\w+'\]\['file'\]\['url'\]"  # Notion-hosted file signed URLs
    r"|root\[.*?\]\['\w+'\]\['file'\]\['expiry_time'\])"
)


def _strip_volatile(diff_dict: dict) -> dict:
    """Remove paths matching volatile patterns from a DeepDiff result."""
    cleaned = {}
    for change_type, changes in diff_dict.items():
        if isinstance(changes, dict):
            filtered = {
                path: val
                for path, val in changes.items()
                if not VOLATILE_PATHS.search(path)
            }
            if filtered:
                cleaned[change_type] = filtered
        else:
            cleaned[change_type] = changes
    return cleaned


def compute_diff(data_a: Any, data_b: Any) -> dict:
    """Compute a structural diff between two JSON-compatible structures.

    Returns a dict with 'raw' (the full DeepDiff), 'filtered' (volatile
    fields removed), and 'summary' (change counts).
    """
    dd = DeepDiff(data_a, data_b, ignore_order=True, verbose_level=2)
    raw = dd.to_dict()
    filtered = _strip_volatile(raw)

    summary = {}
    for change_type, changes in filtered.items():
        if isinstance(changes, dict):
            summary[change_type] = len(changes)
        elif isinstance(changes, list):
            summary[change_type] = len(changes)
        else:
            summary[change_type] = 1

    return {
        "raw": raw,
        "filtered": filtered,
        "summary": summary,
        "has_meaningful_changes": len(filtered) > 0,
    }


def diff_snapshots(snapshot_a_id: int, snapshot_b_id: int) -> dict:
    """Diff two stored snapshots and persist the result."""
    snap_a = storage.get_snapshot(snapshot_a_id)
    snap_b = storage.get_snapshot(snapshot_b_id)
    if snap_a is None or snap_b is None:
        raise ValueError("One or both snapshots not found")

    result = compute_diff(snap_a["data"], snap_b["data"])

    summary_text = (
        "No meaningful changes"
        if not result["has_meaningful_changes"]
        else "; ".join(f"{k}: {v}" for k, v in result["summary"].items())
    )

    diff_id = storage.save_diff(
        snapshot_a_id=snapshot_a_id,
        snapshot_b_id=snapshot_b_id,
        diff_json=json.dumps(result, default=str),
        summary=summary_text,
    )
    result["diff_id"] = diff_id
    return result


def diff_snapshot_vs_live(snapshot_id: int, live_data: Any) -> dict:
    """Diff a stored snapshot against freshly-fetched live data."""
    snap = storage.get_snapshot(snapshot_id)
    if snap is None:
        raise ValueError(f"Snapshot {snapshot_id} not found")

    result = compute_diff(snap["data"], live_data)

    summary_text = (
        "No meaningful changes"
        if not result["has_meaningful_changes"]
        else "; ".join(f"{k}: {v}" for k, v in result["summary"].items())
    )

    diff_id = storage.save_diff(
        snapshot_a_id=snapshot_id,
        snapshot_b_id=None,
        diff_json=json.dumps(result, default=str),
        summary=summary_text,
    )
    result["diff_id"] = diff_id
    return result
