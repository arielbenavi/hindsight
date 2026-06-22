"""FastAPI app: POST /capture, GET /items, background worker."""
from __future__ import annotations

import logging
import threading
from contextlib import asynccontextmanager
from typing import Any, Optional

from dotenv import load_dotenv
from fastapi import BackgroundTasks, FastAPI
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


@app.get("/items/{item_id}")
def item(item_id: int):
    row = db.get_item(item_id)
    if not row:
        return {"error": "not found"}, 404
    return row
