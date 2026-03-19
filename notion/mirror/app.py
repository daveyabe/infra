"""Streamlit Notion API Mirror — browse, snapshot, and diff Notion data."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone

import streamlit as st
from dotenv import load_dotenv

import api
import diff_engine
import storage

load_dotenv()

st.set_page_config(page_title="N43 Studio Notion Data Explorer", page_icon="🔬", layout="wide")

st.markdown("""
<style>
[data-testid="stSidebar"] {
    background: linear-gradient(180deg, #0b0d17 0%, #111936 30%, #0f1529 60%, #0b0d17 100%);
    overflow: hidden;
}
[data-testid="stSidebar"] [data-testid="stMarkdownContainer"] p,
[data-testid="stSidebar"] .stRadio label,
[data-testid="stSidebar"] h1 {
    color: #e0e0e0 !important;
}
[data-testid="stSidebar"]::before {
    content: "";
    position: absolute;
    inset: 0;
    pointer-events: none;
    overflow: hidden;
    z-index: 0;
    background:
        radial-gradient(1px 1px at 10% 5%, rgba(255,255,255,0.5), transparent),
        radial-gradient(1px 1px at 30% 12%, rgba(255,255,255,0.4), transparent),
        radial-gradient(1px 1px at 50% 8%, rgba(255,255,255,0.3), transparent),
        radial-gradient(1px 1px at 70% 18%, rgba(255,255,255,0.5), transparent),
        radial-gradient(1px 1px at 85% 25%, rgba(255,255,255,0.4), transparent),
        radial-gradient(1px 1px at 15% 32%, rgba(255,255,255,0.3), transparent),
        radial-gradient(1px 1px at 60% 38%, rgba(255,255,255,0.4), transparent),
        radial-gradient(1px 1px at 40% 42%, rgba(255,255,255,0.3), transparent),
        radial-gradient(1px 1px at 90% 48%, rgba(255,255,255,0.5), transparent),
        radial-gradient(1px 1px at 25% 55%, rgba(255,255,255,0.2), transparent),
        radial-gradient(1px 1px at 75% 60%, rgba(255,255,255,0.4), transparent),
        radial-gradient(1px 1px at 8% 65%, rgba(255,255,255,0.3), transparent),
        radial-gradient(1px 1px at 55% 72%, rgba(255,255,255,0.5), transparent),
        radial-gradient(1px 1px at 35% 78%, rgba(255,255,255,0.3), transparent),
        radial-gradient(1px 1px at 80% 82%, rgba(255,255,255,0.4), transparent),
        radial-gradient(1px 1px at 20% 88%, rgba(255,255,255,0.5), transparent),
        radial-gradient(1px 1px at 65% 92%, rgba(255,255,255,0.3), transparent),
        radial-gradient(1px 1px at 45% 96%, rgba(255,255,255,0.4), transparent),
        radial-gradient(1.5px 1.5px at 5% 50%, rgba(255,255,255,0.6), transparent),
        radial-gradient(1.5px 1.5px at 92% 70%, rgba(255,255,255,0.6), transparent);
}
[data-testid="stSidebar"] > div {
    position: relative;
    z-index: 2;
}

@keyframes floatA {
    0%, 100% { transform: translateY(0px) translateX(0px); }
    33% { transform: translateY(-10px) translateX(4px); }
    66% { transform: translateY(-6px) translateX(-3px); }
}
@keyframes floatB {
    0%, 100% { transform: translateY(0px) translateX(0px); }
    50% { transform: translateY(-14px) translateX(-5px); }
}
@keyframes floatC {
    0%, 100% { transform: translateY(0px); }
    50% { transform: translateY(-8px); }
}
@keyframes floatRing {
    0%, 100% { transform: translateX(-50%) translateY(0px); }
    50% { transform: translateX(-50%) translateY(-10px); }
}

.space-field {
    position: fixed;
    top: 0;
    left: 0;
    width: var(--sidebar-width, 336px);
    height: 100vh;
    pointer-events: none;
    z-index: 1;
    overflow: hidden;
    opacity: 0.5;
}
.sp, .star {
    pointer-events: auto;
    cursor: pointer;
    transition: transform 0.3s ease, box-shadow 0.3s ease, filter 0.3s ease;
}
.sp:hover {
    transform: scale(1.4) !important;
    filter: brightness(1.6);
}
.star:hover {
    transform: scale(2) !important;
    filter: brightness(2);
}
.sp-ring-1:hover, .sp-ring-2:hover {
    transform: scale(1.4) translateX(-50%) !important;
}
.sp {
    position: absolute;
    border-radius: 50%;
}

/* — Planet 1: large blue — top-left */
.sp-1 {
    width: 44px; height: 44px;
    background: radial-gradient(circle at 35% 35%, #6c8ebf, #2a4a7f, #1a2d5a);
    box-shadow: 0 0 18px rgba(108,142,191,0.3), inset -8px -4px 12px rgba(0,0,0,0.4);
    top: 8%; left: 12%;
    animation: floatA 7s ease-in-out infinite;
}
/* — Planet 2: small orange — top-right */
.sp-2 {
    width: 22px; height: 22px;
    background: radial-gradient(circle at 35% 35%, #d4956a, #a0522d, #6b3419);
    box-shadow: 0 0 10px rgba(212,149,106,0.25), inset -4px -2px 6px rgba(0,0,0,0.4);
    top: 12%; right: 18%;
    animation: floatB 9s ease-in-out infinite 1s;
}
/* — Planet 3: tiny green — upper area */
.sp-3 {
    width: 14px; height: 14px;
    background: radial-gradient(circle at 35% 35%, #8fbc8f, #4a7c59, #2d4f36);
    box-shadow: 0 0 6px rgba(143,188,143,0.2), inset -3px -2px 4px rgba(0,0,0,0.4);
    top: 20%; left: 55%;
    animation: floatC 6s ease-in-out infinite 2s;
}
/* — Planet 4: ringed (Saturn) — upper-mid */
.sp-ring-1 {
    width: 56px; height: 34px;
    top: 28%; left: 50%;
    transform: translateX(-50%);
    animation: floatRing 10s ease-in-out infinite 0.5s;
}
.sp-ring-1 .ring-body {
    width: 34px; height: 34px;
    border-radius: 50%;
    background: radial-gradient(circle at 35% 35%, #c9b896, #8b7355, #5a4a32);
    box-shadow: 0 0 12px rgba(201,184,150,0.2), inset -6px -3px 10px rgba(0,0,0,0.4);
    position: absolute; top: 0; left: 11px;
}
.sp-ring-1 .ring-disc {
    width: 56px; height: 11px;
    border: 2px solid rgba(201,184,150,0.35);
    border-radius: 50%;
    position: absolute; top: 11px; left: 0;
}

/* — Planet 5: medium purple — mid-left */
.sp-5 {
    width: 30px; height: 30px;
    background: radial-gradient(circle at 35% 35%, #9b8ec4, #5e4d8e, #3a2d5c);
    box-shadow: 0 0 14px rgba(155,142,196,0.25), inset -5px -3px 8px rgba(0,0,0,0.4);
    top: 40%; left: 10%;
    animation: floatB 8s ease-in-out infinite 3s;
}
/* — Planet 6: tiny pink — mid-right */
.sp-6 {
    width: 12px; height: 12px;
    background: radial-gradient(circle at 35% 35%, #d4a0b9, #a05a7a, #6b2d4a);
    box-shadow: 0 0 6px rgba(212,160,185,0.2), inset -2px -1px 3px rgba(0,0,0,0.4);
    top: 45%; right: 22%;
    animation: floatC 5s ease-in-out infinite 1.5s;
}
/* — Planet 7: large teal — mid-lower */
.sp-7 {
    width: 38px; height: 38px;
    background: radial-gradient(circle at 35% 35%, #6bbfb9, #2e7f7a, #1a4f4c);
    box-shadow: 0 0 16px rgba(107,191,185,0.25), inset -7px -3px 10px rgba(0,0,0,0.4);
    top: 58%; right: 12%;
    animation: floatA 9s ease-in-out infinite 2s;
}
/* — Planet 8: ringed (ice) — lower-mid */
.sp-ring-2 {
    width: 50px; height: 30px;
    top: 68%; left: 20%;
    animation: floatRing 11s ease-in-out infinite 4s;
}
.sp-ring-2 .ring-body {
    width: 28px; height: 28px;
    border-radius: 50%;
    background: radial-gradient(circle at 35% 35%, #a8d8ea, #5b9bb5, #3a6e82);
    box-shadow: 0 0 10px rgba(168,216,234,0.2), inset -5px -3px 8px rgba(0,0,0,0.4);
    position: absolute; top: 1px; left: 11px;
}
.sp-ring-2 .ring-disc {
    width: 50px; height: 10px;
    border: 1.5px solid rgba(168,216,234,0.3);
    border-radius: 50%;
    position: absolute; top: 10px; left: 0;
}

/* — Stars / suns — */
@keyframes pulse {
    0%, 100% { transform: scale(1); opacity: 0.9; }
    50% { transform: scale(1.3); opacity: 1; }
}
.star {
    position: absolute;
    border-radius: 50%;
}
.star-1 {
    width: 10px; height: 10px;
    background: radial-gradient(circle at 50% 50%, #fff, #fffbe6, #ffd54f);
    box-shadow: 0 0 12px 4px rgba(255,253,230,0.6), 0 0 30px 8px rgba(255,213,79,0.25);
    top: 35%; right: 10%;
    animation: pulse 3s ease-in-out infinite;
}
.star-2 {
    width: 7px; height: 7px;
    background: radial-gradient(circle at 50% 50%, #fff, #e8f0ff, #90caf9);
    box-shadow: 0 0 10px 3px rgba(232,240,255,0.5), 0 0 24px 6px rgba(144,202,249,0.2);
    top: 78%; left: 65%;
    animation: pulse 4s ease-in-out infinite 1.5s;
}

</style>
""", unsafe_allow_html=True)


def _init():
    token = os.environ.get("NOTION_API_TOKEN", "")
    if not token:
        st.error(
            "Set **NOTION_API_TOKEN** in your `.env` file or environment. "
            "See `.env.example`."
        )
        st.stop()
    if "api_initialised" not in st.session_state:
        api.init(token)
        st.session_state.api_initialised = True


_init()


def _db_label(db: dict) -> str:
    """Consistent display label for a database: 'Title (id)'."""
    title = api.extract_title(db)
    return f"{title} ({db['id']})"


# ── Sidebar navigation ────────────────────────────────────────────────

st.sidebar.title("Notion43")

st.sidebar.markdown("""
<div class="space-field">
    <div class="sp sp-1"></div>
    <div class="sp sp-2"></div>
    <div class="sp sp-3"></div>
    <div class="sp sp-ring-1">
        <div class="ring-body"></div>
        <div class="ring-disc"></div>
    </div>
    <div class="sp sp-5"></div>
    <div class="sp sp-6"></div>
    <div class="sp sp-7"></div>
    <div class="sp sp-ring-2">
        <div class="ring-body"></div>
        <div class="ring-disc"></div>
    </div>
    <div class="star star-1"></div>
    <div class="star star-2"></div>
</div>
""", unsafe_allow_html=True)

page = st.sidebar.radio(
    "Navigate",
    ["Explorer", "Page Viewer", "Stitched Mirror", "Mirror", "Diff", "API Metrics"],
)


# ═══════════════════════════════════════════════════════════════════════
# Explorer
# ═══════════════════════════════════════════════════════════════════════

def _render_explorer():
    st.header("N43 Studio Notion Data Explorer")
    st.caption("Browse all databases and pages your integration can access.")

    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Databases")
        if st.button("Fetch databases", key="fetch_dbs"):
            with st.spinner("Querying Notion..."):
                st.session_state.databases = api.list_databases()

        for db in st.session_state.get("databases", []):
            label = _db_label(db)
            with st.expander(f"📊 {label}"):
                st.text(f"Last edited: {db.get('last_edited_time', 'N/A')}")

                props = db.get("properties", {})
                if props:
                    st.markdown("**Schema properties:**")
                    for name, prop in props.items():
                        st.text(f"  • {name} ({prop.get('type', '?')})")

                if st.button(f"Query rows", key=f"query_{db['id']}"):
                    with st.spinner("Fetching rows..."):
                        rows = api.query_database(db["id"])
                        st.session_state[f"rows_{db['id']}"] = rows

                rows = st.session_state.get(f"rows_{db['id']}", [])
                if rows:
                    st.markdown(f"**{len(rows)} rows**")
                    for row in rows[:20]:
                        row_title = api.extract_title(row)
                        st.text(f"  - {row_title} ({row['id']})")
                    if len(rows) > 20:
                        st.caption(f"…and {len(rows) - 20} more")

                if st.button(f"Snapshot", key=f"snap_db_{db['id']}"):
                    with st.spinner("Snapshotting..."):
                        sid = api.snapshot_database(db["id"])
                        st.success(f"Snapshot #{sid} saved")

                with st.popover("Raw JSON"):
                    st.json(db)

    with col2:
        st.subheader("Pages")
        if st.button("Fetch pages", key="fetch_pages"):
            with st.spinner("Querying Notion..."):
                st.session_state.pages = api.list_pages()

        for pg in st.session_state.get("pages", []):
            title = api.extract_title(pg)
            with st.expander(f"📄 {title} ({pg['id']})"):
                st.text(f"Last edited: {pg.get('last_edited_time', 'N/A')}")

                parent = pg.get("parent", {})
                parent_type = parent.get("type", "unknown")
                st.text(f"Parent: {parent_type}")

                if st.button(f"View blocks", key=f"view_{pg['id']}"):
                    st.session_state.viewer_page_id = pg["id"]
                    st.session_state.viewer_page_title = title

                if st.button(f"Snapshot", key=f"snap_pg_{pg['id']}"):
                    with st.spinner("Snapshotting..."):
                        sid = api.snapshot_page(pg["id"])
                        st.success(f"Snapshot #{sid} saved")

                with st.popover("Raw JSON"):
                    st.json(pg)


# ═══════════════════════════════════════════════════════════════════════
# Page Viewer
# ═══════════════════════════════════════════════════════════════════════

BLOCK_ICONS = {
    "paragraph": "¶",
    "heading_1": "H1",
    "heading_2": "H2",
    "heading_3": "H3",
    "bulleted_list_item": "•",
    "numbered_list_item": "#",
    "to_do": "☑",
    "toggle": "▸",
    "code": "</>",
    "quote": "❝",
    "callout": "💡",
    "divider": "—",
    "image": "🖼",
    "video": "🎬",
    "file": "📎",
    "bookmark": "🔗",
    "table": "⊞",
    "child_page": "📄",
    "child_database": "📊",
}


def _block_text(block: dict) -> str:
    """Extract plain text from a block's rich_text array."""
    block_type = block.get("type", "")
    type_data = block.get(block_type, {})
    rich_text = type_data.get("rich_text", [])
    if not rich_text and isinstance(type_data, dict):
        rich_text = type_data.get("text", [])
    return "".join(rt.get("plain_text", "") for rt in rich_text)


def _render_blocks(blocks: list[dict], depth: int = 0):
    """Recursively render a block tree."""
    indent = "  " * depth
    for block in blocks:
        block_type = block.get("type", "unknown")
        icon = BLOCK_ICONS.get(block_type, "?")
        text = _block_text(block)
        display = text if text else f"[{block_type}]"
        st.text(f"{indent}{icon}  {display}")

        children = block.get("_children", [])
        if children:
            _render_blocks(children, depth + 1)


def _render_page_viewer():
    st.header("Page Viewer")

    page_id = st.text_input(
        "Page ID",
        value=st.session_state.get("viewer_page_id", ""),
        placeholder="Paste a Notion page ID or select from Explorer",
    )

    if not page_id:
        st.info("Enter a page ID above, or click **View blocks** from Explorer.")
        return

    if st.button("Fetch page content"):
        with st.spinner("Fetching page and blocks..."):
            pg = api.retrieve_page(page_id)
            blocks = api.retrieve_block_children(page_id)
            st.session_state.viewer_page = pg
            st.session_state.viewer_blocks = blocks
            st.session_state.viewer_page_title = api.extract_title(pg)

    pg = st.session_state.get("viewer_page")
    blocks = st.session_state.get("viewer_blocks")

    if pg is None:
        return

    title = st.session_state.get("viewer_page_title", "Untitled")
    st.subheader(title)
    st.caption(f"{len(blocks or [])} blocks")

    tab_rendered, tab_json = st.tabs(["Rendered", "Raw JSON"])

    with tab_rendered:
        if blocks:
            _render_blocks(blocks)
        else:
            st.info("No blocks found.")

    with tab_json:
        col_page, col_blocks = st.columns(2)
        with col_page:
            st.markdown("**Page properties**")
            st.json(pg)
        with col_blocks:
            st.markdown("**Block tree**")
            st.json(blocks)


# ═══════════════════════════════════════════════════════════════════════
# Stitched Mirror
# ═══════════════════════════════════════════════════════════════════════

def _extract_property_value(prop: dict) -> str:
    """Best-effort extraction of a displayable value from a Notion property."""
    ptype = prop.get("type", "")
    data = prop.get(ptype)

    if data is None:
        return ""
    if ptype == "title":
        return "".join(t.get("plain_text", "") for t in data)
    if ptype == "rich_text":
        return "".join(t.get("plain_text", "") for t in data)
    if ptype in ("number", "checkbox"):
        return str(data)
    if ptype == "select":
        return data.get("name", "") if data else ""
    if ptype == "multi_select":
        return ", ".join(o.get("name", "") for o in data) if data else ""
    if ptype == "date":
        if isinstance(data, dict):
            start = data.get("start", "")
            end = data.get("end", "")
            return f"{start} → {end}" if end else start
        return str(data)
    if ptype == "status":
        return data.get("name", "") if data else ""
    if ptype == "url":
        return str(data)
    if ptype == "email":
        return str(data)
    if ptype == "phone_number":
        return str(data)
    if ptype == "formula":
        ftype = data.get("type", "")
        return str(data.get(ftype, ""))
    if ptype == "relation":
        return ", ".join(r.get("id", "")[:8] for r in data) if data else ""
    if ptype == "rollup":
        rtype = data.get("type", "")
        return str(data.get(rtype, ""))
    if ptype == "people":
        return ", ".join(p.get("name", p.get("id", "")[:8]) for p in data) if data else ""
    if ptype == "created_time":
        return str(data)
    if ptype == "last_edited_time":
        return str(data)
    if ptype == "created_by":
        return data.get("name", "") if isinstance(data, dict) else ""
    if ptype == "last_edited_by":
        return data.get("name", "") if isinstance(data, dict) else ""
    if ptype == "files":
        return f"{len(data)} file(s)" if data else ""
    return str(data)[:80]


def _render_stitched_mirror():
    st.header("Stitched Mirror")
    st.caption(
        "Reconstruct a full database: schema + all rows + page content inside each row. "
        "This makes many API calls — ideal for stress-testing."
    )

    databases = st.session_state.get("databases", [])
    if not databases:
        st.info("Fetch databases from **Explorer** first, or enter a database ID below.")

    db_options = {}
    for db in databases:
        db_options[_db_label(db)] = db["id"]

    col_select, col_manual = st.columns(2)

    with col_select:
        if db_options:
            selected_label = st.selectbox("Select a database", list(db_options.keys()))
            selected_id = db_options[selected_label]
        else:
            selected_id = ""

    with col_manual:
        manual_id = st.text_input("Or enter database ID directly", placeholder="optional override")

    database_id = manual_id.strip() if manual_id.strip() else selected_id

    if not database_id:
        return

    db_title = None
    for db in databases:
        if db["id"] == database_id:
            db_title = _db_label(db)
            break
    st.text(f"Selected: {db_title or database_id}")

    if st.button("Stitch & fetch all", key="stitch_fetch"):
        progress_bar = st.progress(0, text="Starting...")
        status_text = st.empty()

        def _on_progress(current, total, row_title):
            pct = current / total if total > 0 else 1.0
            progress_bar.progress(pct, text=f"Row {current}/{total}: {row_title}")

        with st.spinner("Fetching schema, rows, and all block content..."):
            try:
                data = api.stitch_database(database_id, on_row_progress=_on_progress)
                st.session_state.stitched_data = data
                st.session_state.stitched_db_id = database_id
                progress_bar.progress(1.0, text="Done")
            except Exception as exc:
                st.error(f"Error: {exc}")
                return

    if st.button("Stitch & snapshot", key="stitch_snap"):
        progress_bar = st.progress(0, text="Starting...")

        def _on_progress(current, total, row_title):
            pct = current / total if total > 0 else 1.0
            progress_bar.progress(pct, text=f"Row {current}/{total}: {row_title}")

        with st.spinner("Stitching and saving snapshot..."):
            try:
                sid = api.snapshot_stitched(database_id, on_row_progress=_on_progress)
                progress_bar.progress(1.0, text="Done")
                st.success(f"Stitched snapshot #{sid} saved")
            except Exception as exc:
                st.error(f"Error: {exc}")
                return

    data = st.session_state.get("stitched_data")
    if data is None or st.session_state.get("stitched_db_id") != database_id:
        return

    st.divider()

    # Stats
    col_s1, col_s2, col_s3 = st.columns(3)
    col_s1.metric("Database", data["title"])
    col_s2.metric("Rows", data["stats"]["row_count"])
    col_s3.metric("Total blocks", data["stats"]["total_blocks"])

    # Schema
    with st.expander("Schema (column definitions)"):
        schema_props = data["schema"].get("properties", {})
        for name, prop in schema_props.items():
            st.text(f"  • {name} ({prop.get('type', '?')})")

    st.subheader("Rows")

    # Build a table view from row properties
    import pandas as pd

    schema_props = data["schema"].get("properties", {})
    col_names = sorted(schema_props.keys())

    table_rows = []
    for row in data["rows"]:
        row_data = {"_id": row["id"]}
        props = row.get("properties", {})
        for col_name in col_names:
            prop = props.get(col_name, {})
            row_data[col_name] = _extract_property_value(prop)
        block_count = api._count_blocks(row.get("_blocks", []))
        row_data["_blocks"] = block_count
        table_rows.append(row_data)

    if table_rows:
        df = pd.DataFrame(table_rows)
        st.dataframe(df, use_container_width=True)

    # Expandable rows with block content
    st.subheader("Row details")
    for row in data["rows"]:
        row_title = api.extract_title(row)
        block_count = api._count_blocks(row.get("_blocks", []))
        with st.expander(f"{row_title} ({row['id']}) — {block_count} blocks"):
            tab_props, tab_blocks, tab_json = st.tabs(["Properties", "Blocks", "Raw JSON"])

            with tab_props:
                props = row.get("properties", {})
                for name in col_names:
                    prop = props.get(name, {})
                    val = _extract_property_value(prop)
                    st.text(f"  {name}: {val}")

            with tab_blocks:
                blocks = row.get("_blocks", [])
                if blocks:
                    _render_blocks(blocks)
                else:
                    st.caption("No block content")

            with tab_json:
                st.json(row)


# ═══════════════════════════════════════════════════════════════════════
# Mirror
# ═══════════════════════════════════════════════════════════════════════

def _render_mirror():
    st.header("Mirror")
    st.caption("Manage local snapshots of Notion data.")

    col_filter, col_actions = st.columns([2, 1])

    with col_filter:
        obj_type = st.selectbox("Filter by type", ["all", "database", "page", "blocks", "stitched"])
        notion_id = st.text_input("Filter by Notion ID", placeholder="optional")

    snapshots = storage.list_snapshots(
        notion_id=notion_id if notion_id else None,
        object_type=obj_type if obj_type != "all" else None,
    )

    with col_actions:
        st.metric("Total snapshots", len(snapshots))

    if not snapshots:
        st.info("No snapshots yet. Use Explorer to snapshot databases or pages.")
        return

    for snap in snapshots:
        label = snap.get("label") or snap["notion_id"][:12]
        ts = snap["captured_at"][:19]
        with st.expander(f"#{snap['id']}  {snap['object_type']}  {label}  ({ts})"):
            st.text(f"Notion ID: {snap['notion_id']}")
            st.text(f"Captured: {snap['captured_at']}")

            full = storage.get_snapshot(snap["id"])
            if full:
                st.json(full["data"])


# ═══════════════════════════════════════════════════════════════════════
# Diff
# ═══════════════════════════════════════════════════════════════════════

def _render_diff():
    st.header("Diff")
    st.caption("Compare two snapshots, or a snapshot vs live Notion data.")

    snapshots = storage.list_snapshots(limit=200)
    if not snapshots:
        st.info("Take at least one snapshot first.")
        return

    snap_options = {
        f"#{s['id']}  {s['object_type']}  {s.get('label', '')}  ({s['captured_at'][:19]})": s["id"]
        for s in snapshots
    }

    mode = st.radio("Compare", ["Snapshot vs Snapshot", "Snapshot vs Live"])

    snap_a_label = st.selectbox("Snapshot A", list(snap_options.keys()), key="diff_a")
    snap_a_id = snap_options[snap_a_label]

    if mode == "Snapshot vs Snapshot":
        snap_b_label = st.selectbox("Snapshot B", list(snap_options.keys()), key="diff_b")
        snap_b_id = snap_options[snap_b_label]

        if st.button("Compute diff"):
            with st.spinner("Diffing..."):
                result = diff_engine.diff_snapshots(snap_a_id, snap_b_id)
                st.session_state.last_diff = result

    else:
        snap_a_data = storage.get_snapshot(snap_a_id)
        if snap_a_data:
            st.caption(f"Will re-fetch Notion ID: {snap_a_data['notion_id']} ({snap_a_data['object_type']})")

        if st.button("Fetch live & diff"):
            with st.spinner("Fetching live data and diffing..."):
                snap = storage.get_snapshot(snap_a_id)
                if snap is None:
                    st.error("Snapshot not found")
                    return

                if snap["object_type"] == "stitched":
                    live_data = api.stitch_database(snap["notion_id"])
                elif snap["object_type"] == "database":
                    schema = api.retrieve_database(snap["notion_id"])
                    rows = api.query_database(snap["notion_id"])
                    live_data = {"schema": schema, "rows": rows}
                elif snap["object_type"] == "page":
                    pg = api.retrieve_page(snap["notion_id"])
                    blocks = api.retrieve_block_children(snap["notion_id"])
                    live_data = {"page": pg, "blocks": blocks}
                else:
                    blocks = api.retrieve_block_children(snap["notion_id"])
                    live_data = blocks

                result = diff_engine.diff_snapshot_vs_live(snap_a_id, live_data)
                st.session_state.last_diff = result

    result = st.session_state.get("last_diff")
    if result is None:
        return

    st.divider()

    if result["has_meaningful_changes"]:
        st.warning("Differences found")
        st.subheader("Summary")
        for change_type, count in result["summary"].items():
            st.text(f"  {change_type}: {count}")
    else:
        st.success("No meaningful changes (volatile fields excluded)")

    tab_filtered, tab_raw = st.tabs(["Filtered diff", "Full raw diff"])

    with tab_filtered:
        st.json(result["filtered"])

    with tab_raw:
        st.json(result["raw"])


# ═══════════════════════════════════════════════════════════════════════
# API Metrics
# ═══════════════════════════════════════════════════════════════════════

def _render_metrics():
    st.header("API Metrics")
    st.caption("Track Notion API call performance and rate-limit behaviour.")

    summary = storage.get_api_call_summary()
    if not summary or summary.get("total_calls", 0) == 0:
        st.info("No API calls recorded yet. Use Explorer to start making calls.")
        return

    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Total calls", summary.get("total_calls", 0))
    col2.metric("Avg latency", f"{summary.get('avg_latency_ms', 0):.0f} ms")
    col3.metric("Rate limited (429)", summary.get("rate_limited", 0))
    col4.metric("Errors", summary.get("errors", 0))

    total_bytes = summary.get("total_bytes") or 0
    if total_bytes > 1_048_576:
        st.metric("Data transferred", f"{total_bytes / 1_048_576:.1f} MB")
    else:
        st.metric("Data transferred", f"{total_bytes / 1024:.1f} KB")

    st.divider()

    calls = storage.get_api_call_stats()
    if not calls:
        return

    st.subheader("Call log")

    import pandas as pd

    df = pd.DataFrame(calls)
    df["timestamp"] = pd.to_datetime(df["timestamp"])

    st.subheader("Latency over time")
    latency_df = df[["timestamp", "latency_ms"]].dropna()
    if not latency_df.empty:
        st.line_chart(latency_df.set_index("timestamp")["latency_ms"])

    st.subheader("Calls by endpoint")
    endpoint_counts = df["endpoint"].value_counts()
    st.bar_chart(endpoint_counts)

    st.subheader("Status code distribution")
    status_counts = df["status"].value_counts()
    st.bar_chart(status_counts)

    rate_limited = df[df["status"] == 429]
    if not rate_limited.empty:
        st.subheader("Rate limit events (429)")
        st.dataframe(
            rate_limited[["timestamp", "endpoint", "latency_ms"]],
            use_container_width=True,
        )

    with st.expander("Full call log"):
        st.dataframe(df, use_container_width=True)


# ── Page router ────────────────────────────────────────────────────────

if page == "Explorer":
    _render_explorer()
elif page == "Page Viewer":
    _render_page_viewer()
elif page == "Stitched Mirror":
    _render_stitched_mirror()
elif page == "Mirror":
    _render_mirror()
elif page == "Diff":
    _render_diff()
elif page == "API Metrics":
    _render_metrics()
