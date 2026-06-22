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


def _update(item_id: int, fields: dict[str, Any]) -> None:
    if "key_takeaways" in fields and not isinstance(fields["key_takeaways"], (str, type(None))):
        fields["key_takeaways"] = json.dumps(fields["key_takeaways"], ensure_ascii=False)
    cols = ", ".join(f"{k}=?" for k in fields)
    with connect() as c:
        c.execute(f"UPDATE items SET {cols} WHERE id=?", (*fields.values(), item_id))


def _row_to_dict(r: sqlite3.Row) -> dict[str, Any]:
    d = dict(r)
    if d.get("key_takeaways"):
        try:
            d["key_takeaways"] = json.loads(d["key_takeaways"])
        except (json.JSONDecodeError, TypeError):
            pass
    return d


def get_item(item_id: int) -> Optional[dict[str, Any]]:
    with connect() as c:
        r = c.execute("SELECT * FROM items WHERE id=?", (item_id,)).fetchone()
    return _row_to_dict(r) if r else None


def list_items() -> list[dict[str, Any]]:
    with connect() as c:
        rows = c.execute("SELECT * FROM items ORDER BY saved_at DESC, id DESC").fetchall()
    return [_row_to_dict(r) for r in rows]


def list_pending_ids() -> list[int]:
    with connect() as c:
        return [r["id"] for r in c.execute("SELECT id FROM items WHERE status='pending'")]
