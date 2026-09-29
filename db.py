"""SQLite store. Schema is Postgres-portable: TEXT/INTEGER, JSON-as-text."""
from __future__ import annotations

import json
import logging
import shutil
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

log = logging.getLogger("savefeed.db")

_SAVEFEED_DIR = Path.home() / ".savefeed"
DB_PATH = _SAVEFEED_DIR / "savefeed.db"
_BACKUP_DIR = _SAVEFEED_DIR / "backups"

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL CHECK(source IN ('ig_reel','tweet','tiktok','facebook','web','note')),
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

FTS_SCHEMA = """
CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
    summary, raw_text, transcript, on_screen_text,
    content='items', content_rowid='id'
);

CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
    INSERT INTO items_fts(rowid, summary, raw_text, transcript, on_screen_text)
    VALUES (new.id, new.summary, new.raw_text, new.transcript, new.on_screen_text);
END;

CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
    INSERT INTO items_fts(items_fts, rowid, summary, raw_text, transcript, on_screen_text)
    VALUES ('delete', old.id, old.summary, old.raw_text, old.transcript, old.on_screen_text);
END;

CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
    INSERT INTO items_fts(items_fts, rowid, summary, raw_text, transcript, on_screen_text)
    VALUES ('delete', old.id, old.summary, old.raw_text, old.transcript, old.on_screen_text);
    INSERT INTO items_fts(rowid, summary, raw_text, transcript, on_screen_text)
    VALUES (new.id, new.summary, new.raw_text, new.transcript, new.on_screen_text);
END;

INSERT INTO items_fts(items_fts) VALUES('rebuild');
"""


@contextmanager
def connect() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=5000")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    _SAVEFEED_DIR.mkdir(parents=True, exist_ok=True)
    _migrate_old_db()
    with connect() as c:
        c.execute("PRAGMA journal_mode=WAL")
        c.executescript(SCHEMA)
        cols = {r[1] for r in c.execute("PRAGMA table_info(items)").fetchall()}
        if "tags" not in cols:
            c.execute("ALTER TABLE items ADD COLUMN tags TEXT DEFAULT '[]'")
        c.execute("UPDATE items SET tags='[]' WHERE tags IS NULL")
        _migrate_source_constraint(c)
        c.executescript(FTS_SCHEMA)
    _integrity_check()
    backup_db()


def _migrate_old_db() -> None:
    """One-time migration: move DB from repo dir to ~/.savefeed/."""
    old = Path(__file__).parent / "savefeed.db"
    if old.is_file() and not DB_PATH.is_file():
        log.info("migrating DB from %s to %s", old, DB_PATH)
        shutil.copy2(old, DB_PATH)


def _migrate_source_constraint(c: sqlite3.Connection) -> None:
    """Widen the source CHECK constraint to include tiktok and facebook."""
    schema = c.execute("SELECT sql FROM sqlite_master WHERE name='items'").fetchone()
    if schema and "'tiktok'" not in schema[0]:
        log.info("migrating source CHECK constraint to add tiktok/facebook")
        c.execute("DROP TRIGGER IF EXISTS items_ai")
        c.execute("DROP TRIGGER IF EXISTS items_ad")
        c.execute("DROP TRIGGER IF EXISTS items_au")
        c.execute("DROP TABLE IF EXISTS items_fts")
        c.execute("DROP TABLE IF EXISTS items_new")
        c.execute("""
            CREATE TABLE items_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT NOT NULL CHECK(source IN ('ig_reel','tweet','tiktok','facebook','web','note')),
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
            )
        """)
        c.execute("""
            INSERT INTO items_new (id, source, source_url, kind, raw_text, summary,
                on_screen_text, transcript, category, key_takeaways, tags, saved_at, status)
            SELECT id, source, source_url, kind, raw_text, summary,
                on_screen_text, transcript, category, key_takeaways, tags, saved_at, status
            FROM items
        """)
        c.execute("DROP TABLE items")
        c.execute("ALTER TABLE items_new RENAME TO items")
        c.execute("CREATE INDEX IF NOT EXISTS items_saved_at ON items(saved_at DESC)")
        c.execute("CREATE INDEX IF NOT EXISTS items_status ON items(status)")


def _integrity_check() -> None:
    try:
        with connect() as c:
            result = c.execute("PRAGMA integrity_check").fetchone()[0]
        if result != "ok":
            log.error("DB integrity check failed: %s", result)
        else:
            log.info("DB integrity check passed")
    except Exception as e:
        log.error("DB integrity check error: %s", e)


def backup_db() -> None:
    if not DB_PATH.is_file():
        return
    _BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    dest = _BACKUP_DIR / f"savefeed_{stamp}.db"
    try:
        src = sqlite3.connect(DB_PATH)
        dst = sqlite3.connect(dest)
        src.backup(dst)
        dst.close()
        src.close()
        log.info("backup saved to %s", dest)
    except Exception as e:
        log.error("backup failed: %s", e)
        return
    backups = sorted(_BACKUP_DIR.glob("savefeed_*.db"))
    for old in backups[:-7]:
        old.unlink(missing_ok=True)


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

ALLOWED_CATEGORIES = {"coding", "quant", "music", "life-hack", "productivity", "funny", "other"}
_CATEGORY_ALIASES = {
    "tech": "coding",
    "technology": "coding",
    "science": "coding",
    "programming": "coding",
    "finance": "quant",
    "trading": "quant",
    "lifehack": "life-hack",
    "life hack": "life-hack",
    "meme": "funny",
    "humor": "funny",
    "comedy": "funny",
    "entertainment": "funny",
}


def _normalize_category(c: Any) -> str:
    if not isinstance(c, str) or not c.strip():
        return "other"
    c = c.strip().lower()
    if c in ALLOWED_CATEGORIES:
        return c
    return _CATEGORY_ALIASES.get(c, "other")


def _update(item_id: int, fields: dict[str, Any]) -> None:
    if "category" in fields:
        fields["category"] = _normalize_category(fields["category"])
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


def _fts_query(raw: str) -> str:
    words = raw.strip().split()
    if not words:
        return '""'
    return " ".join(f'"{w}"' for w in words)


def list_items(
    category: Optional[str] = None,
    source: Optional[str] = None,
    q: Optional[str] = None,
    tag: Optional[str] = None,
    exclude_category: Optional[str] = None,
) -> list[dict[str, Any]]:
    if q:
        sql = "SELECT items.* FROM items JOIN items_fts ON items.id = items_fts.rowid WHERE items_fts MATCH ?"
        params: list[Any] = [_fts_query(q)]
    else:
        sql = "SELECT * FROM items WHERE 1=1"
        params = []
    if category:
        sql += " AND category = ?"
        params.append(category)
    if exclude_category:
        sql += " AND (category != ? OR category IS NULL)"
        params.append(exclude_category)
    if source:
        sql += " AND source = ?"
        params.append(source)
    if tag:
        sql += " AND tags LIKE ?"
        params.append(f'%"{tag.strip().lower()}"%')
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


def get_stats() -> dict[str, Any]:
    with connect() as c:
        total = c.execute("SELECT COUNT(*) FROM items WHERE status='done'").fetchone()[0]
        by_source = [
            dict(r) for r in c.execute(
                "SELECT source, COUNT(*) as count FROM items WHERE status='done' GROUP BY source"
            ).fetchall()
        ]
        by_category = [
            dict(r) for r in c.execute(
                "SELECT category, COUNT(*) as count FROM items WHERE status='done' GROUP BY category"
            ).fetchall()
        ]
        by_status = [
            dict(r) for r in c.execute(
                "SELECT status, COUNT(*) as count FROM items GROUP BY status"
            ).fetchall()
        ]
        timeline = [
            dict(r) for r in c.execute(
                "SELECT DATE(saved_at) as day, COUNT(*) as count FROM items "
                "WHERE status='done' GROUP BY DATE(saved_at) ORDER BY day DESC LIMIT 90"
            ).fetchall()
        ]
    return {
        "total": total,
        "by_source": by_source,
        "by_category": by_category,
        "by_status": by_status,
        "timeline": timeline,
    }


def get_tag_counts() -> list[dict[str, Any]]:
    with connect() as c:
        rows = c.execute("SELECT tags, category FROM items WHERE status='done'").fetchall()
    from collections import Counter
    tag_counter: Counter[str] = Counter()
    tag_categories: dict[str, Counter[str]] = {}
    for r in rows:
        try:
            tags = json.loads(r["tags"]) if r["tags"] else []
        except (json.JSONDecodeError, TypeError):
            continue
        cat = r["category"] or "other"
        for t in tags:
            tag_counter[t] += 1
            if t not in tag_categories:
                tag_categories[t] = Counter()
            tag_categories[t][cat] += 1
    return [
        {"tag": tag, "count": count, "categories": dict(tag_categories.get(tag, {}))}
        for tag, count in tag_counter.most_common()
    ]
