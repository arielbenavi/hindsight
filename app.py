"""FastAPI app: POST /capture, GET /items, background worker."""
from __future__ import annotations

import html
import json
import logging
import os
import threading
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Optional

from dotenv import load_dotenv
from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
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


class TagsIn(BaseModel):
    tags: list[str]


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
    _check_cookies_file()
    pending = db.list_pending_ids()
    if pending:
        log.info("re-enqueueing %d pending items on startup", len(pending))
        threading.Thread(target=_drain_pending, daemon=True).start()
    yield


def _check_cookies_file() -> None:
    raw = os.environ.get("IG_COOKIES_FILE")
    if not raw:
        log.info("IG_COOKIES_FILE not set; using --cookies-from-browser (may prompt for keychain)")
        return
    p = Path(raw).expanduser()
    if not p.is_file() or p.stat().st_size == 0:
        log.warning(
            "IG_COOKIES_FILE=%s is missing or empty — falling back to --cookies-from-browser; "
            "keychain prompts will appear until you export a Netscape cookies.txt to this path",
            raw,
        )
    else:
        log.info("IG_COOKIES_FILE=%s (%d bytes) — keychain access disabled", raw, p.stat().st_size)


app = FastAPI(title="savefeed", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


@app.post("/capture")
def capture(body: CaptureIn, bg: BackgroundTasks):
    source, url = router.classify(body.payload)
    if url:
        existing = db.find_active_by_url(url)
        if existing:
            return {
                "id": existing["id"],
                "source": existing["source"],
                "status": existing["status"],
                "deduped": True,
            }
    raw_text = body.payload if source == "note" else body.note
    item_id = db.insert_pending(source=source, source_url=url, kind=None, raw_text=raw_text)
    item = db.get_item(item_id)
    bg.add_task(_process, item)
    return {"id": item_id, "source": source, "status": "pending"}


@app.post("/items/{item_id}/retry")
def retry(item_id: int, bg: BackgroundTasks):
    row = db.get_item(item_id)
    if not row:
        raise HTTPException(404, "not found")
    if row["status"] != "failed":
        return {"id": item_id, "status": row["status"], "msg": "not failed — no-op"}
    db.reset_to_pending(item_id)
    fresh = db.get_item(item_id)
    bg.add_task(_process, fresh)
    return {"id": item_id, "status": "pending"}


@app.get("/items")
def items(
    category: Optional[str] = None,
    source: Optional[str] = None,
    q: Optional[str] = None,
    tag: Optional[str] = None,
):
    return db.list_items(category=category, source=source, q=q, tag=tag)


@app.post("/items/{item_id}/tags")
def set_item_tags(item_id: int, body: TagsIn):
    row = db.get_item(item_id)
    if not row:
        raise HTTPException(404, "not found")
    clean: list[str] = []
    seen: set[str] = set()
    for t in body.tags:
        n = (t or "").strip().lower()
        if n and n not in seen:
            seen.add(n)
            clean.append(n)
    db.set_tags(item_id, clean[:20])
    return {"id": item_id, "tags": clean[:20]}


_PRETTY_CSS = """
body { font: 14px/1.4 -apple-system, system-ui, sans-serif; margin: 1.5rem; color: #222; }
h1 { font-size: 1.1rem; margin: 0 0 1rem; color: #555; font-weight: 600; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #eee; vertical-align: top; }
th { background: #fafafa; font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: #666; }
tr:hover td { background: #f6faff; }
td.id { color: #999; font-variant-numeric: tabular-nums; }
td.id a { color: inherit; text-decoration: none; }
td.id a:hover { color: #0a66c2; text-decoration: underline; }
td.src, td.cat { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
td.status-done { color: #1b7a3a; }
td.status-failed { color: #b00020; }
td.status-pending { color: #b07a00; }
td.summary { max-width: 480px; }
td.ost { max-width: 320px; color: #555; font-size: 13px; white-space: pre-wrap; }
.empty { color: #999; font-style: italic; margin-top: 1rem; }
button.retry { margin-left: 6px; font-size: 11px; padding: 2px 6px; border: 1px solid #b00020; background: #fff; color: #b00020; border-radius: 3px; cursor: pointer; }
button.retry:hover { background: #b00020; color: #fff; }
.crumb { color: #888; font-size: 12px; margin-bottom: 0.5rem; }
.crumb a { color: #0a66c2; text-decoration: none; }
.meta { color: #666; font-size: 12px; margin: 0.25rem 0 1.5rem; }
.meta .chip { display: inline-block; padding: 1px 7px; background: #f0f0f0; border-radius: 10px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11px; margin-right: 6px; }
.meta .chip.status-done { background: #def0e3; color: #1b7a3a; }
.meta .chip.status-failed { background: #fce0e4; color: #b00020; }
.meta .chip.status-pending { background: #fdf0d5; color: #b07a00; }
.meta a { color: #0a66c2; word-break: break-all; }
section { margin: 1.25rem 0; }
section h2 { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: #888; font-weight: 600; margin: 0 0 0.4rem; }
section .body { white-space: pre-wrap; }
section.mono .body { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; background: #fafafa; padding: 8px 10px; border-radius: 4px; }
section ul { margin: 0; padding-left: 1.25rem; }
details { margin-top: 0.4rem; }
details summary { cursor: pointer; color: #888; font-size: 12px; }
.tag-chip { display: inline-flex; align-items: center; padding: 2px 4px 2px 8px; background: #eef2ff; color: #3730a3; border-radius: 10px; font-size: 12px; margin: 0 4px 4px 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.tag-chip .tag-x { background: transparent; border: 0; color: inherit; opacity: 0.5; cursor: pointer; padding: 0 4px; font-size: 14px; line-height: 1; }
.tag-chip .tag-x:hover { opacity: 1; }
form.tag-form { margin-top: 6px; display: flex; gap: 6px; }
form.tag-form input { padding: 4px 8px; border: 1px solid #ddd; border-radius: 4px; font-size: 13px; min-width: 0; flex: 1; max-width: 240px; }
form.tag-form button { padding: 4px 10px; border: 1px solid #ddd; background: #fafafa; border-radius: 4px; font-size: 12px; cursor: pointer; }
form.tag-form button:hover { background: #f0f0f0; }
"""

_PRETTY_JS = """
function retry(id) {
  fetch('/items/' + id + '/retry', {method: 'POST'})
    .then(r => r.json())
    .then(() => location.reload());
}
function postTags(id, tags) {
  fetch('/items/' + id + '/tags', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({tags: tags}),
  }).then(() => location.reload());
}
function removeTag(id, t) {
  postTags(id, (window.__TAGS || []).filter(x => x !== t));
}
function addTag(e, id) {
  e.preventDefault();
  const input = document.getElementById('new-tag');
  const t = (input.value || '').trim().toLowerCase();
  if (!t) return;
  const cur = window.__TAGS || [];
  if (cur.includes(t)) { input.value = ''; return; }
  postTags(id, cur.concat([t]));
}
"""


@app.get("/items/pretty", response_class=HTMLResponse)
def items_pretty():
    rows = db.list_items()
    body_rows: list[str] = []
    for r in rows:
        status = r.get("status") or ""
        retry_btn = (
            f"<button class='retry' onclick='retry({r['id']})'>retry</button>"
            if status == "failed"
            else ""
        )
        body_rows.append(
            "<tr>"
            f"<td class='id'><a href='/items/{r['id']}/pretty'>#{r['id']}</a></td>"
            f"<td class='src'>{html.escape(r.get('source') or '')}</td>"
            f"<td class='status-{html.escape(status)}'>{html.escape(status)}{retry_btn}</td>"
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
        f"<script>{_PRETTY_JS}</script>"
        "</body></html>"
    )


@app.get("/items/{item_id}/pretty", response_class=HTMLResponse)
def item_pretty(item_id: int):
    row = db.get_item(item_id)
    if not row:
        return HTMLResponse(
            f"<!doctype html><body style='font:14px sans-serif;margin:2rem'>"
            f"<p><a href='/items/pretty'>← back</a></p>"
            f"<p>item #{item_id} not found.</p></body>",
            status_code=404,
        )
    return _render_item_detail(row)


@app.get("/items/{item_id}")
def item(item_id: int):
    row = db.get_item(item_id)
    if not row:
        raise HTTPException(404, "not found")
    return row


def _render_item_detail(r: dict[str, Any]) -> str:
    status = r.get("status") or ""
    url = r.get("source_url")
    url_html = (
        f"<a href='{html.escape(url)}' target='_blank' rel='noopener'>{html.escape(url)}</a>"
        if url
        else "<span style='color:#bbb'>—</span>"
    )
    chips = " ".join(
        [
            f"<span class='chip'>{html.escape(r.get('source') or '')}</span>",
            f"<span class='chip'>kind: {html.escape(r.get('kind') or '—')}</span>",
            f"<span class='chip'>{html.escape(r.get('category') or '—')}</span>",
            f"<span class='chip status-{html.escape(status)}'>{html.escape(status)}</span>",
        ]
    )
    parts: list[str] = [
        f"<p class='crumb'><a href='/items/pretty'>← items</a></p>",
        f"<h1>item #{r['id']}</h1>",
        f"<div class='meta'>{chips}</div>",
        f"<div class='meta'>url: {url_html}<br>saved: {html.escape(r.get('saved_at') or '')}</div>",
    ]
    if status == "failed":
        parts.append(
            f"<p><button class='retry' onclick='retry({r['id']})'>retry</button> "
            "<span style='color:#888;font-size:12px'>re-runs the adapter</span></p>"
        )
    if r.get("summary"):
        parts.append(_section("summary", r["summary"]))
    parts.append(_tags_section(r.get("tags") or [], r["id"]))
    takeaways = r.get("key_takeaways")
    if isinstance(takeaways, list) and takeaways:
        items_html = "".join(f"<li>{html.escape(str(t))}</li>" for t in takeaways)
        parts.append(f"<section><h2>key takeaways</h2><ul>{items_html}</ul></section>")
    if r.get("on_screen_text"):
        parts.append(_section("on-screen text", r["on_screen_text"], mono=True))
    if r.get("transcript"):
        parts.append(_collapsible_section("transcript", r["transcript"]))
    if r.get("raw_text"):
        parts.append(_collapsible_section("raw text", r["raw_text"], mono=True))
    body = "".join(parts)
    tags_seed = json.dumps(r.get("tags") or [])
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<title>savefeed · #{r['id']}</title>"
        f"<style>{_PRETTY_CSS}</style></head><body>"
        f"{body}"
        f"<script>window.__TAGS = {tags_seed};{_PRETTY_JS}</script>"
        "</body></html>"
    )


def _section(label: str, text: str, mono: bool = False) -> str:
    cls = "mono" if mono else ""
    return (
        f"<section class='{cls}'><h2>{html.escape(label)}</h2>"
        f"<div class='body'>{html.escape(text)}</div></section>"
    )


def _tags_section(tags: list[str], item_id: int) -> str:
    if tags:
        chips = "".join(
            f"<span class='tag-chip'>{html.escape(t)}"
            f"<button class='tag-x' onclick=\"removeTag({item_id}, {json.dumps(t)})\" "
            "title='remove tag'>×</button></span>"
            for t in tags
        )
    else:
        chips = "<span style='color:#bbb;font-size:13px'>(none yet)</span>"
    return (
        "<section><h2>tags</h2>"
        f"<div>{chips}</div>"
        f"<form class='tag-form' onsubmit='addTag(event, {item_id})'>"
        "<input id='new-tag' type='text' placeholder='add tag…' autocomplete='off'/>"
        "<button type='submit'>add</button>"
        "</form></section>"
    )


def _collapsible_section(label: str, text: str, mono: bool = False) -> str:
    cls = "mono" if mono else ""
    preview = text[:120] + ("…" if len(text) > 120 else "")
    return (
        f"<section class='{cls}'><h2>{html.escape(label)}</h2>"
        f"<details><summary>{html.escape(preview)}</summary>"
        f"<div class='body' style='margin-top:0.5rem'>{html.escape(text)}</div>"
        f"</details></section>"
    )
