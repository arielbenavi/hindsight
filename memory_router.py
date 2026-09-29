"""LLM memory pipeline skeleton — auto-route saved content to relevant projects."""
from __future__ import annotations

import json
import logging
import sqlite3
from typing import Any, Optional

import db

log = logging.getLogger("savefeed.memory_router")

MEMORY_SCHEMA = """
CREATE TABLE IF NOT EXISTS memory_routes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_name TEXT NOT NULL UNIQUE,
    description TEXT,
    memory_file_path TEXT,
    match_tags TEXT DEFAULT '[]',
    match_categories TEXT DEFAULT '[]',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS memory_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    route_id INTEGER NOT NULL,
    action TEXT NOT NULL CHECK(action IN ('suggested','applied','dismissed')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
    FOREIGN KEY (route_id) REFERENCES memory_routes(id) ON DELETE CASCADE
);
"""


def init_memory() -> None:
    with db.connect() as c:
        c.executescript(MEMORY_SCHEMA)


def add_route(
    project_name: str,
    description: str = "",
    memory_file_path: str = "",
    match_tags: list[str] | None = None,
    match_categories: list[str] | None = None,
) -> int:
    with db.connect() as c:
        cur = c.execute(
            "INSERT INTO memory_routes (project_name, description, memory_file_path, match_tags, match_categories) "
            "VALUES (?, ?, ?, ?, ?)",
            (
                project_name,
                description,
                memory_file_path,
                json.dumps(match_tags or []),
                json.dumps(match_categories or []),
            ),
        )
        return int(cur.lastrowid)


def list_routes() -> list[dict[str, Any]]:
    with db.connect() as c:
        rows = c.execute("SELECT * FROM memory_routes ORDER BY project_name").fetchall()
    results = []
    for r in rows:
        d = dict(r)
        for f in ("match_tags", "match_categories"):
            try:
                d[f] = json.loads(d[f]) if d[f] else []
            except (json.JSONDecodeError, TypeError):
                d[f] = []
        results.append(d)
    return results


def match_item(item: dict[str, Any]) -> list[dict[str, Any]]:
    routes = list_routes()
    item_tags = set(item.get("tags") or [])
    item_cat = item.get("category") or ""
    matches = []
    for route in routes:
        route_tags = set(route.get("match_tags") or [])
        route_cats = set(route.get("match_categories") or [])
        tag_overlap = item_tags & route_tags
        cat_match = item_cat in route_cats if route_cats else False
        if tag_overlap or cat_match:
            matches.append({
                "route": route,
                "matched_tags": list(tag_overlap),
                "category_match": cat_match,
            })
    return matches


def log_suggestion(item_id: int, route_id: int) -> None:
    with db.connect() as c:
        existing = c.execute(
            "SELECT id FROM memory_log WHERE item_id=? AND route_id=?",
            (item_id, route_id),
        ).fetchone()
        if not existing:
            c.execute(
                "INSERT INTO memory_log (item_id, route_id, action) VALUES (?, ?, 'suggested')",
                (item_id, route_id),
            )


def update_suggestion(item_id: int, route_id: int, action: str) -> None:
    with db.connect() as c:
        c.execute(
            "UPDATE memory_log SET action=? WHERE item_id=? AND route_id=?",
            (action, item_id, route_id),
        )


def get_suggestions(limit: int = 20) -> list[dict[str, Any]]:
    with db.connect() as c:
        rows = c.execute(
            "SELECT ml.*, mr.project_name, i.summary, i.source "
            "FROM memory_log ml "
            "JOIN memory_routes mr ON ml.route_id = mr.id "
            "JOIN items i ON ml.item_id = i.id "
            "WHERE ml.action = 'suggested' "
            "ORDER BY ml.created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return [dict(r) for r in rows]


def route_new_item(item: dict[str, Any]) -> int:
    matches = match_item(item)
    count = 0
    for m in matches:
        log_suggestion(item["id"], m["route"]["id"])
        count += 1
    return count
