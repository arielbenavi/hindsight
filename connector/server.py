"""hindsight Muse connector: experiment (docs/SYNC_PLAN.md, phase 1).

A minimal MCP server that Muse can call to hand over the user's saved posts,
so the copy/paste step goes away. It answers the plan's key questions:
does Meta let Muse pass Instagram saves to a third-party connector, how many
per call, and does a "do this every day" routine keep calling us?

Run locally behind a temporary tunnel (see README.md). Everything is stored in
connector/data/ (gitignored). Single user, no accounts: a random secret in the
URL path is the only auth, good enough for an experiment, not for production.
"""

from __future__ import annotations

import json
import os
import secrets
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import uvicorn
from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings
from starlette.requests import Request
from starlette.responses import JSONResponse

DATA = Path(__file__).parent / "data"
DATA.mkdir(exist_ok=True)
SAVES = DATA / "saves.json"
CALLS = DATA / "calls.log"
TOKEN_FILE = DATA / "token"

TOKEN = os.environ.get("HINDSIGHT_CONNECTOR_TOKEN") or (
    TOKEN_FILE.read_text().strip() if TOKEN_FILE.exists() else ""
)
if not TOKEN:
    TOKEN = secrets.token_urlsafe(18)
    TOKEN_FILE.write_text(TOKEN)

_lock = threading.Lock()


def log_call(event: str, **details: Any) -> None:
    line = {"at": datetime.now(timezone.utc).isoformat(timespec="seconds"), "event": event, **details}
    with _lock, CALLS.open("a") as f:
        f.write(json.dumps(line, ensure_ascii=False) + "\n")
    print(json.dumps(line, ensure_ascii=False), flush=True)


def load_saves() -> dict[str, dict[str, Any]]:
    return json.loads(SAVES.read_text()) if SAVES.exists() else {}


# Same identity rule as the app's SavedPost.id: "<platform>:<shortcode>" for known
# platforms, "<platform>:<full url>" otherwise.
PLATFORM_HOSTS = {
    "instagram": ("instagram.com",),
    "facebook": ("facebook.com", "fb.watch"),
    "x": ("x.com", "twitter.com"),
    "tiktok": ("tiktok.com", "tiktokv.com"),
}


def platform_for(url: str) -> str | None:
    host = (urlparse(url).hostname or "").lower()
    for platform, suffixes in PLATFORM_HOSTS.items():
        if any(host == s or host.endswith("." + s) for s in suffixes):
            return platform
    return None


def post_id(url: str, platform: str | None) -> str:
    known = platform_for(url)
    platform = platform or known or "instagram"
    parts = [p for p in urlparse(url).path.split("/") if p]
    return f"{platform}:{parts[-1] if known and parts else url}"


# Instagram's built-in folders, not collections the user made.
DEFAULT_COLLECTIONS = {"saved", "all posts", "all saved", "all", "all saved posts"}


def normalized(post: dict[str, Any]) -> dict[str, Any]:
    """Map whatever keys Muse used onto the contract's posts[] keys.

    Muse doesn't stick to the schema it's given: first real send (2026-09-30)
    used author=<display name> + author_username, post_creation_time,
    tagged_users, media_type, and the default "Saved"/"All posts" folders.
    Unknown keys are kept (the app ignores them)."""
    out = dict(post)

    def first(*keys: str) -> Any:
        return next((post[k] for k in keys if post.get(k) not in (None, "", [])), None)

    username = first("author_username", "username", "owner_username")
    if username:
        if post.get("author") and post.get("author") != username and not post.get("author_display_name"):
            out["author_display_name"] = post["author"]
        out["author"] = username
    if isinstance(out.get("author"), str):
        out["author"] = out["author"].lstrip("@")
    out["url"] = first("url", "media_permalink", "permalink") or post.get("url")
    out["posted_at"] = first("posted_at", "post_creation_time", "created_at", "timestamp")
    out["saved_at"] = first("saved_at", "saved_time", "date")
    if not post.get("mentions") and isinstance(post.get("tagged_users"), list):
        out["mentions"] = [
            {"username": str(u).lstrip("@"), "display_name": None} if not isinstance(u, dict)
            else {"username": str(u.get("username", "")).lstrip("@"), "display_name": u.get("display_name") or u.get("name")}
            for u in post["tagged_users"]
        ]
    if isinstance(post.get("collections"), list):
        out["collections"] = [c for c in post["collections"] if str(c).strip().lower() not in DEFAULT_COLLECTIONS]
    if post.get("kind") in ("note", "link"):
        return out
    if not post.get("kind") or post.get("kind") == "post":
        media = str(post.get("media_type") or post.get("post_type") or "").lower()
        path = str(out.get("url") or "")
        out["kind"] = ("reel" if "/reel" in path else "carousel" if "carousel" in media or "album" in media
                       else "video" if media == "video" else post.get("kind") or "post")
    return out


mcp = MCPServer(
    name="hindsight",
    title="hindsight",
    description="Sends your saved posts to your hindsight app.",
    instructions=(
        "hindsight is the user's app for organizing their saved posts. To sync: first call "
        "get_sync_status to see what hindsight already has. Then read the user's Instagram and "
        "Facebook saved posts newest first and pass them to submit_saved_posts in batches of up "
        "to 50. Stop when a batch comes back with continue=false, or when you reach a post whose "
        "url is in recent_urls (everything older is already there). On the very first sync "
        "(total_saves is 0) send all of them. Don't print the posts in the chat."
    ),
    version="0.1",
)


@mcp.tool(
    description=(
        "What hindsight already has, so you only send what's missing. Returns total_saves, "
        "counts per platform, newest_saved_at, last_received_at, and recent_urls: the "
        "permalinks of the 30 most recently received saves. When syncing newest-first, stop "
        "at the first post whose url is in recent_urls."
    )
)
def get_sync_status() -> dict[str, Any]:
    saves = list(load_saves().values())
    recent = sorted(saves, key=lambda p: p.get("received_at", ""), reverse=True)
    platforms: dict[str, int] = {}
    for post in saves:
        key = str(post.get("platform") or "unknown")
        platforms[key] = platforms.get(key, 0) + 1
    status = {
        "total_saves": len(saves),
        "platforms": platforms,
        "newest_saved_at": max((str(p.get("saved_at")) for p in saves if p.get("saved_at")), default=None),
        "last_received_at": recent[0].get("received_at") if recent else None,
        "recent_urls": [p.get("url") for p in recent[:30] if p.get("url")],
    }
    log_call("get_sync_status", total=status["total_saves"])
    return status


@mcp.tool(description="Check that the hindsight connector is reachable. Returns 'pong'.")
def ping() -> str:
    log_call("ping")
    return "pong"


@mcp.tool(
    description=(
        "Save a batch of the user's saved posts (Instagram, Facebook, …) to hindsight. "
        "Call repeatedly, up to 50 posts per call. Each post: url (permalink, required), "
        "platform ('instagram' or 'facebook'), kind ('reel', 'post', 'carousel', 'video'), "
        "author (username without @), author_display_name, caption (the full caption, "
        "unshortened), mentions ([{username, display_name}]), collections (the user's "
        "saved-collection names containing it), saved_at, posted_at (ISO dates), "
        "location_tag ({name, address}) and thumbnail_url. Use null or [] when unknown; "
        "never guess. Set final_batch=true on the last call."
    )
)
def submit_saved_posts(
    posts: list[dict[str, Any]],
    sync_id: str | None = None,
    final_batch: bool = False,
) -> dict[str, Any]:
    result = ingest(posts, source="muse")
    log_call("submit_saved_posts", sync_id=sync_id, final_batch=final_batch, **result["log"])
    return {**result["counts"], "continue": not final_batch}


def ingest(posts: list[dict[str, Any]], source: str) -> dict[str, Any]:
    """The one write path for every source (Muse, the WhatsApp bot, …): normalize to
    the contract, dedupe by id, keep the richer record on a re-send."""
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    accepted = duplicates = rejected = 0
    with _lock:
        saves = load_saves()
        for post in map(normalized, posts):
            post.setdefault("source", source)
            url = str(post.get("url") or "").strip()
            if not (url.startswith("http") or url.startswith("hindsight-note:")):
                rejected += 1
                continue
            pid = post.get("id") if url.startswith("hindsight-note:") and post.get("id") else post_id(url, post.get("platform"))
            if pid in saves:
                duplicates += 1
                old = saves[pid]
                if len(post.get("caption") or "") > len(old.get("caption") or ""):
                    saves[pid] = {**old, **post, "id": pid, "received_at": old.get("received_at", now)}
                continue
            saves[pid] = {**post, "id": pid, "received_at": now}
            accepted += 1
        SAVES.write_text(json.dumps(saves, ensure_ascii=False, indent=1))
    return {
        "counts": {"accepted": accepted, "duplicates": duplicates, "rejected": rejected},
        "log": {
            "received": len(posts), "accepted": accepted, "duplicates": duplicates, "rejected": rejected,
            "platforms": sorted({str(p.get("platform")) for p in posts}),
            "caption_chars": sum(len(p.get("caption") or "") for p in posts),
        },
    }


@mcp.custom_route(f"/{TOKEN}/ingest", methods=["POST"])
async def ingest_route(request: Request) -> JSONResponse:
    """Other hindsight services (the WhatsApp bot, …) post contract-shaped posts here."""
    body = await request.json()
    posts = body.get("posts", []) if isinstance(body, dict) else body
    source = (body.get("source") if isinstance(body, dict) else None) or "unknown"
    result = ingest(posts, source=source)
    log_call("ingest", source=source, **result["log"])
    return JSONResponse(result["counts"])


@mcp.custom_route(f"/{TOKEN}/saves", methods=["GET"])
async def saves_for_app(request: Request) -> JSONResponse:
    """The app pulls what Muse sent, as a contract-shaped JSON array (newest received first)."""
    since = request.query_params.get("since")
    posts = sorted((normalized(p) for p in load_saves().values()), key=lambda p: p.get("received_at", ""), reverse=True)
    if since:
        posts = [p for p in posts if p.get("received_at", "") > since]
    log_call("app_pull", returned=len(posts), since=since)
    return JSONResponse(posts)


@mcp.custom_route("/health", methods=["GET"])
async def health(_: Request) -> JSONResponse:
    return JSONResponse({"ok": True})


app = mcp.streamable_http_app(
    streamable_http_path=f"/{TOKEN}/mcp",
    stateless_http=True,
    json_response=True,
    # Requests arrive through the tunnel's hostname; the secret path is the auth.
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)


class RequestLog:
    """Logs every HTTP request (method, path, client, status) to calls.log, and
    answers GET on the MCP endpoint with 405: we don't offer a standalone SSE
    stream (the spec allows this), and holding it open made clients time out."""

    def __init__(self, inner: Any) -> None:
        self.inner = inner

    async def __call__(self, scope: dict[str, Any], receive: Any, send: Any) -> None:
        if scope["type"] != "http":
            await self.inner(scope, receive, send)
            return
        headers = {k.decode(): v.decode() for k, v in scope.get("headers", [])}
        path = scope["path"].replace(TOKEN, "<token>")
        status: dict[str, int] = {}

        async def send_logged(message: dict[str, Any]) -> None:
            if message["type"] == "http.response.start":
                status["code"] = message["status"]
            await send(message)

        if scope["method"] == "GET" and scope["path"].endswith("/mcp"):
            await send({"type": "http.response.start", "status": 405,
                        "headers": [(b"allow", b"POST"), (b"content-length", b"0")]})
            await send({"type": "http.response.body", "body": b""})
            status["code"] = 405
        else:
            await self.inner(scope, receive, send_logged)
        log_call("http", method=scope["method"], path=path, status=status.get("code"),
                 user_agent=headers.get("user-agent", "")[:80], accept=headers.get("accept", "")[:60])


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8765"))
    print(f"MCP endpoint path: /{TOKEN}/mcp   app pull path: /{TOKEN}/saves", flush=True)
    uvicorn.run(RequestLog(app), host="127.0.0.1", port=port, log_level="warning")
