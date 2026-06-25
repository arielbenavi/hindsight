"""SQLite store. Schema is Postgres-portable: TEXT/INTEGER, JSON-as-text."""
from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

DB_PATH = Path(__file__).parent / "savefeed.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL CHECK(source IN ('ig_reel','tweet','web','note')),
    source_url TEXT,
    kind TEXT,
    raw_text TEXT,
    summary TEXT,
    on_screen_text TEXT,
    transcript TEXT,
    category TEXT,
    key_takeaways TEXT,
    tags TEXT DEFAULT '[]',
    saved_at TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('pending','done','failed'))
);
CREATE INDEX IF NOT EXISTS items_saved_at ON items(saved_at DESC);
CREATE INDEX IF NOT EXISTS items_status ON items(status);
"""


@contextmanager
def connect() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with connect() as c:
        c.executescript(SCHEMA)
        # Idempotent migration: add `tags` to pre-existing tables.
        cols = {r[1] for r in c.execute("PRAGMA table_info(items)").fetchall()}
        if "tags" not in cols:
            c.execute("ALTER TABLE items ADD COLUMN tags TEXT DEFAULT '[]'")
        c.execute("UPDATE items SET tags='[]' WHERE tags IS NULL")


def insert_pending(
    source: str,
    source_url: Optional[str],
    kind: Optional[str],
    raw_text: Optional[str],
) -> int:
    with connect() as c:
        cur = c.execute(
            "INSERT INTO items (source, source_url, kind, raw_text, saved_at, status) "
            "VALUES (?, ?, ?, ?, ?, 'pending')",
            (source, source_url, kind, raw_text, datetime.now(timezone.utc).isoformat()),
        )
        return int(cur.lastrowid)


def mark_done(item_id: int, **fields: Any) -> None:
    fields["status"] = "done"
    _update(item_id, fields)


def mark_failed(item_id: int, error: str) -> None:
    _update(item_id, {"status": "failed", "summary": f"FAILED: {error[:500]}"})


JSON_FIELDS = {"key_takeaways", "tags"}  # decoded back to objects on read


def _update(item_id: int, fields: dict[str, Any]) -> None:
    serialized = {
        k: (json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else v)
        for k, v in fields.items()
    }
    cols = ", ".join(f"{k}=?" for k in serialized)
    with connect() as c:
        c.execute(f"UPDATE items SET {cols} WHERE id=?", (*serialized.values(), item_id))


def _row_to_dict(r: sqlite3.Row) -> dict[str, Any]:
    d = dict(r)
    for f in JSON_FIELDS:
        if d.get(f):
            try:
                d[f] = json.loads(d[f])
            except (json.JSONDecodeError, TypeError):
                pass
    return d


def get_item(item_id: int) -> Optional[dict[str, Any]]:
    with connect() as c:
        r = c.execute("SELECT * FROM items WHERE id=?", (item_id,)).fetchone()
    return _row_to_dict(r) if r else None


def list_items(
    category: Optional[str] = None,
    source: Optional[str] = None,
    q: Optional[str] = None,
    tag: Optional[str] = None,
) -> list[dict[str, Any]]:
    sql = "SELECT * FROM items WHERE 1=1"
    params: list[Any] = []
    if category:
        sql += " AND category = ?"
        params.append(category)
    if source:
        sql += " AND source = ?"
        params.append(source)
    if tag:
        # tags is a JSON array stored as text; match on the quoted token.
        sql += " AND tags LIKE ?"
        params.append(f'%"{tag.strip().lower()}"%')
    if q:
        like = f"%{q}%"
        sql += " AND (summary LIKE ? OR transcript LIKE ? OR raw_text LIKE ? OR on_screen_text LIKE ?)"
        params.extend([like, like, like, like])
    sql += " ORDER BY saved_at DESC, id DESC"
    with connect() as c:
        rows = c.execute(sql, params).fetchall()
    return [_row_to_dict(r) for r in rows]


def set_tags(item_id: int, tags: list[str]) -> None:
    with connect() as c:
        c.execute(
            "UPDATE items SET tags=? WHERE id=?",
            (json.dumps(tags, ensure_ascii=False), item_id),
        )


def list_pending_ids() -> list[int]:
    with connect() as c:
        return [r["id"] for r in c.execute("SELECT id FROM items WHERE status='pending'")]


def recent_ingestion_items(n: int = 10) -> list[dict[str, Any]]:
    """Most recent ig_reel + tweet captures, newest first. Used by /health."""
    with connect() as c:
        rows = c.execute(
            "SELECT * FROM items WHERE source IN ('ig_reel','tweet') "
            "ORDER BY saved_at DESC, id DESC LIMIT ?",
            (n,),
        ).fetchall()
    return [_row_to_dict(r) for r in rows]


def find_active_by_url(source_url: str) -> Optional[dict[str, Any]]:
    """Latest non-failed row with this exact source_url, or None.

    Failed rows don't block a fresh capture — re-forwarding a URL that
    previously errored should retry naturally.
    """
    with connect() as c:
        r = c.execute(
            "SELECT * FROM items WHERE source_url=? AND status IN ('pending','done') "
            "ORDER BY id DESC LIMIT 1",
            (source_url,),
        ).fetchone()
    return _row_to_dict(r) if r else None


def reset_to_pending(item_id: int) -> None:
    """Clear gist fields and flip status back to pending — used by /retry."""
    with connect() as c:
        c.execute(
            "UPDATE items SET status='pending', summary=NULL, on_screen_text=NULL, "
            "transcript=NULL, category=NULL, key_takeaways=NULL WHERE id=?",
            (item_id,),
        )
