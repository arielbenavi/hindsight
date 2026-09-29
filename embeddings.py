"""Embedding generation and vector search using Gemini text-embedding-004."""
from __future__ import annotations

import hashlib
import json
import logging
import sqlite3
import time
from typing import Any, Optional

import numpy as np
from google import genai

import db

log = logging.getLogger("savefeed.embeddings")

EMBED_MODEL = "text-embedding-004"
EMBED_DIM = 768

EMBEDDINGS_SCHEMA = """
CREATE TABLE IF NOT EXISTS embeddings (
    item_id INTEGER PRIMARY KEY,
    embedding BLOB NOT NULL,
    text_hash TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);
"""


def init_embeddings() -> None:
    with db.connect() as c:
        c.executescript(EMBEDDINGS_SCHEMA)


def _build_text(item: dict[str, Any]) -> str:
    parts = []
    if item.get("summary"):
        parts.append(item["summary"])
    kts = item.get("key_takeaways")
    if kts and isinstance(kts, list):
        parts.append(" ".join(kts))
    tags = item.get("tags")
    if tags and isinstance(tags, list):
        parts.append(" ".join(tags))
    if item.get("transcript"):
        parts.append(item["transcript"][:500])
    if item.get("on_screen_text"):
        parts.append(item["on_screen_text"][:300])
    return " | ".join(parts) if parts else ""


def _text_hash(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def _embed_texts(texts: list[str]) -> list[np.ndarray]:
    client = genai.Client()
    result = client.models.embed_content(
        model=EMBED_MODEL,
        contents=texts,
    )
    return [np.array(e.values, dtype=np.float32) for e in result.embeddings]


def embed_item(item: dict[str, Any]) -> Optional[np.ndarray]:
    text = _build_text(item)
    if not text:
        return None
    th = _text_hash(text)
    with db.connect() as c:
        existing = c.execute(
            "SELECT text_hash FROM embeddings WHERE item_id = ?", (item["id"],)
        ).fetchone()
        if existing and existing[0] == th:
            return None
    vecs = _embed_texts([text])
    if not vecs:
        return None
    vec = vecs[0]
    blob = vec.tobytes()
    with db.connect() as c:
        c.execute(
            "INSERT OR REPLACE INTO embeddings (item_id, embedding, text_hash) VALUES (?, ?, ?)",
            (item["id"], blob, th),
        )
    return vec


def backfill(batch_size: int = 10, delay: float = 1.0) -> dict[str, int]:
    init_embeddings()
    with db.connect() as c:
        done_ids = c.execute(
            "SELECT i.id FROM items i LEFT JOIN embeddings e ON i.id = e.item_id "
            "WHERE i.status = 'done' AND e.item_id IS NULL"
        ).fetchall()
    ids = [r[0] for r in done_ids]
    embedded = 0
    skipped = 0
    for i in range(0, len(ids), batch_size):
        batch_ids = ids[i : i + batch_size]
        items = []
        texts = []
        for item_id in batch_ids:
            item = db.get_item(item_id)
            if not item:
                skipped += 1
                continue
            text = _build_text(item)
            if not text:
                skipped += 1
                continue
            items.append(item)
            texts.append(text)
        if not texts:
            continue
        try:
            vecs = _embed_texts(texts)
        except Exception as e:
            log.error("embedding batch failed: %s", e)
            skipped += len(texts)
            continue
        with db.connect() as c:
            for item, vec, text in zip(items, vecs, texts):
                th = _text_hash(text)
                c.execute(
                    "INSERT OR REPLACE INTO embeddings (item_id, embedding, text_hash) VALUES (?, ?, ?)",
                    (item["id"], vec.tobytes(), th),
                )
                embedded += 1
        if i + batch_size < len(ids):
            time.sleep(delay)
    return {"embedded": embedded, "skipped": skipped, "total_pending": len(ids)}


def search(query: str, top_k: int = 5) -> list[dict[str, Any]]:
    query_vec = _embed_texts([query])[0]
    with db.connect() as c:
        rows = c.execute("SELECT item_id, embedding FROM embeddings").fetchall()
    if not rows:
        return []
    ids = []
    vecs = []
    for r in rows:
        ids.append(r[0])
        vecs.append(np.frombuffer(r[1], dtype=np.float32))
    mat = np.stack(vecs)
    query_norm = query_vec / (np.linalg.norm(query_vec) + 1e-9)
    norms = np.linalg.norm(mat, axis=1, keepdims=True) + 1e-9
    mat_norm = mat / norms
    sims = mat_norm @ query_norm
    top_indices = np.argsort(sims)[::-1][:top_k]
    results = []
    for idx in top_indices:
        item = db.get_item(ids[idx])
        if item:
            item["similarity"] = float(sims[idx])
            results.append(item)
    return results


def get_status() -> dict[str, int]:
    init_embeddings()
    with db.connect() as c:
        total = c.execute("SELECT COUNT(*) FROM items WHERE status='done'").fetchone()[0]
        embedded = c.execute("SELECT COUNT(*) FROM embeddings").fetchone()[0]
    return {"total": total, "embedded": embedded, "pending": total - embedded}
