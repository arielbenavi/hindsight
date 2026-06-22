"""FastAPI app: POST /capture, GET /items, background worker."""
from __future__ import annotations

import html
import logging
import threading
from contextlib import asynccontextmanager
from typing import Any, Optional

from dotenv import load_dotenv
from fastapi import BackgroundTasks, FastAPI
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

import adapters
import db
import router

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
log = logging.getLogger("savefeed")


class CaptureIn(BaseModel):
    payload: str
    note: Optional[str] = None


def _process(item: dict[str, Any]) -> None:
    item_id = item["id"]
    source = item["source"]
    log.info("processing item %s (%s)", item_id, source)
    try:
        if source == "ig_reel":
            adapters.process_ig_reel(item_id, item["source_url"])
        elif source == "web":
            adapters.process_web(item_id, item["source_url"])
        elif source == "note":
            adapters.process_note(item_id, item["raw_text"])
        elif source == "tweet":
            adapters.process_tweet(item_id, item["source_url"], item.get("raw_text"))
        else:
            raise RuntimeError(f"unknown source: {source}")
        log.info("item %s done", item_id)
    except Exception as e:
        log.exception("item %s failed", item_id)
        db.mark_failed(item_id, f"{type(e).__name__}: {e}")


def _drain_pending() -> None:
    for item_id in db.list_pending_ids():
        item = db.get_item(item_id)
        if item:
            _process(item)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    db.init_db()
    pending = db.list_pending_ids()
    if pending:
        log.info("re-enqueueing %d pending items on startup", len(pending))
        threading.Thread(target=_drain_pending, daemon=True).start()
    yield


app = FastAPI(title="savefeed", lifespan=lifespan)


@app.post("/capture")
def capture(body: CaptureIn, bg: BackgroundTasks):
    source, url = router.classify(body.payload)
    raw_text = body.payload if source == "note" else body.note
    item_id = db.insert_pending(source=source, source_url=url, kind=None, raw_text=raw_text)
    item = db.get_item(item_id)
    bg.add_task(_process, item)
    return {"id": item_id, "source": source, "status": "pending"}


@app.get("/items")
def items():
    return db.list_items()


_PRETTY_CSS = """
body { font: 14px/1.4 -apple-system, system-ui, sans-serif; margin: 1.5rem; color: #222; }
h1 { font-size: 1.1rem; margin: 0 0 1rem; color: #555; font-weight: 600; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #eee; vertical-align: top; }
th { background: #fafafa; font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: #666; }
tr:hover td { background: #f6faff; }
td.id { color: #999; font-variant-numeric: tabular-nums; }
td.src, td.cat { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
td.status-done { color: #1b7a3a; }
td.status-failed { color: #b00020; }
td.status-pending { color: #b07a00; }
td.summary { max-width: 480px; }
td.ost { max-width: 320px; color: #555; font-size: 13px; white-space: pre-wrap; }
.empty { color: #999; font-style: italic; margin-top: 1rem; }
"""


@app.get("/items/pretty", response_class=HTMLResponse)
def items_pretty():
    rows = db.list_items()
    body_rows: list[str] = []
    for r in rows:
        status = r.get("status") or ""
        body_rows.append(
            "<tr>"
            f"<td class='id'>#{r['id']}</td>"
            f"<td class='src'>{html.escape(r.get('source') or '')}</td>"
            f"<td class='status-{html.escape(status)}'>{html.escape(status)}</td>"
            f"<td class='cat'>{html.escape(r.get('category') or '')}</td>"
            f"<td class='summary'>{html.escape(r.get('summary') or '')}</td>"
            f"<td class='ost'>{html.escape(r.get('on_screen_text') or '')}</td>"
            "</tr>"
        )
    table = (
        "<table>"
        "<thead><tr><th>id</th><th>source</th><th>status</th>"
        "<th>category</th><th>summary</th><th>on-screen text</th></tr></thead>"
        f"<tbody>{''.join(body_rows)}</tbody>"
        "</table>"
        if body_rows
        else "<p class='empty'>no items yet</p>"
    )
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>savefeed</title>"
        f"<style>{_PRETTY_CSS}</style></head><body>"
        f"<h1>savefeed — {len(rows)} item(s), newest first</h1>"
        f"{table}"
        "</body></html>"
    )


@app.get("/items/{item_id}")
def item(item_id: int):
    row = db.get_item(item_id)
    if not row:
        return {"error": "not found"}, 404
    return row
