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

import contextvars
import json
import os
import re
import secrets
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import uvicorn
from mcp.server.mcpserver import Context, MCPServer
from mcp.server.transport_security import TransportSecuritySettings
from starlette.requests import Request
from starlette.responses import JSONResponse

DATA = Path(os.environ.get("HINDSIGHT_CONNECTOR_DATA") or Path(__file__).parent / "data")
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


# ── Tenants: isolated stores, one per URL ──
# `/<token>/t/<tenant>/{mcp,saves,ingest}` uses data/tenants/<tenant>/; the plain
# `/<token>/…` paths use the default store in data/. Each test run (and later,
# each user) gets its own tenant, so nothing leaks between them.
TENANT_HEADER = "x-hindsight-tenant"
TENANT_RE = re.compile(r"^[a-z0-9-]{3,40}$")
CURRENT_TENANT: contextvars.ContextVar[str | None] = contextvars.ContextVar("tenant", default=None)


def saves_path(tenant: str | None) -> Path:
    if not tenant:
        return SAVES
    folder = DATA / "tenants" / tenant
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "saves.json"


def tenant_from(headers: Any) -> str | None:
    value = (headers or {}).get(TENANT_HEADER) if headers is not None else None
    if value and TENANT_RE.match(value):
        return value
    # Single-user beta: once an account has adopted the default store (see create_tenant),
    # the plain `/<token>/…` URLs mean that account, so Muse, the bot and the backfill
    # keep working whichever URL they were given.
    default = DATA / "default_tenant"
    if default.exists():
        name = default.read_text().strip()
        return name if TENANT_RE.match(name) else None
    return None


# ── Per-account settings (data/tenants/<tenant>/settings.json, or data/settings.json) ──
# Only `assistant_search` for now: may AI assistants (Claude, …) read this account's saves
# through search_saves / recent_saves? Off unless the owner turns it on in the app.
SETTINGS_KEYS = {"assistant_search"}
ASSISTANT_SEARCH_OFF = (
    "The owner hasn't allowed assistants to search their saves. "
    "They can turn it on in hindsight → Sources → Use your saves in Claude."
)


def settings_path(tenant: str | None) -> Path:
    return saves_path(tenant).parent / "settings.json"


def load_settings(tenant: str | None) -> dict[str, Any]:
    """Stored settings with defaults filled in. The single-user beta's owner turned
    assistant search on by hand before this switch existed: the account named in
    data/default_tenant keeps it on until it saves a settings file of its own."""
    path = settings_path(tenant)
    if path.exists():
        try:
            stored = json.loads(path.read_text())
        except ValueError:
            stored = {}
        return {"assistant_search": bool(stored.get("assistant_search", False))}
    default = DATA / "default_tenant"
    owner = default.read_text().strip() if default.exists() else None
    return {"assistant_search": bool(tenant) and tenant == owner}


def save_settings(tenant: str | None, changes: dict[str, Any]) -> dict[str, Any]:
    with _lock:
        merged = {**load_settings(tenant), **changes}
        settings_path(tenant).write_text(json.dumps(merged, indent=1))
    return merged


def assistant_search_allowed(tenant: str | None) -> bool:
    return load_settings(tenant)["assistant_search"]


def readable(posts: Any) -> list[dict[str, Any]]:
    """What the read tools may show: never notes (WhatsApp notes are private text)."""
    return [p for p in posts if p.get("kind") != "note"]


def load_saves(tenant: str | None = None) -> dict[str, dict[str, Any]]:
    path = saves_path(tenant)
    return json.loads(path.read_text()) if path.exists() else {}


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
def get_sync_status(ctx: Context | None = None) -> dict[str, Any]:
    tenant = tenant_from(ctx.headers if ctx else None) or CURRENT_TENANT.get()
    saves = list(load_saves(tenant).values())
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
    log_call("get_sync_status", tenant=tenant, total=status["total_saves"])
    return status


SEARCH_FIELDS = (("caption", 3), ("transcript", 2), ("on_screen_text", 2), ("author", 3),
                 ("author_display_name", 2), ("hashtags", 3), ("collections", 3), ("url", 1))


def _terms(text: str) -> list[str]:
    return [t for t in re.findall(r"[^\W_]+", text.lower()) if len(t) > 1]


def search(saves: list[dict[str, Any]], query: str, platform: str | None = None, limit: int = 10) -> list[dict[str, Any]]:
    """Rank saves by how many query words they contain (caption, transcript, author, tags…),
    newest first on ties. Plain word matching: no embeddings, runs anywhere."""
    wanted = set(_terms(query))
    scored: list[tuple[float, str, dict[str, Any]]] = []
    for post in saves:
        if platform and post.get("platform") != platform:
            continue
        score, matched = 0.0, set()
        for field, weight in SEARCH_FIELDS:
            value = post.get(field)
            words = set(_terms(" ".join(map(str, value)) if isinstance(value, list) else str(value or "")))
            hits = wanted & words
            # A query word also matches as a prefix ("recipe" finds "recipes").
            hits |= {w for w in wanted if len(w) > 3 and any(x.startswith(w) for x in words)}
            score += weight * len(hits)
            matched |= hits
        if matched:
            score += 5 * len(matched)  # covering more of the query beats repeating one word
            scored.append((score, str(post.get("saved_at") or post.get("posted_at") or ""), post))
    scored.sort(key=lambda item: (item[0], item[1]), reverse=True)
    return [brief(post) for _, _, post in scored[: max(1, min(limit, 50))]]


def brief(post: dict[str, Any], text_chars: int = 700) -> dict[str, Any]:
    """A save trimmed for a model's context: the link, who, when, and the words in it."""
    def cut(value: Any) -> str | None:
        text = " ".join(str(value or "").split())
        return (text[:text_chars] + "…" if len(text) > text_chars else text) or None
    out = {
        "id": post.get("id"), "url": post.get("url"), "platform": post.get("platform"), "kind": post.get("kind"),
        "author": post.get("author"), "saved_at": post.get("saved_at") or post.get("posted_at"),
        "collections": post.get("collections") or None,
        "caption": cut(post.get("caption")), "transcript": cut(post.get("transcript")),
        "on_screen_text": cut(post.get("on_screen_text")),
    }
    return {k: v for k, v in out.items() if v}


@mcp.tool(
    description=(
        "Search the user's saved posts (Instagram, X, Facebook, WhatsApp notes…) by words: topic, "
        "author, technique, place. Returns the best matches with the link, author, date, caption "
        "and, when hindsight has it, the video's transcript and on-screen text. Use this to answer "
        "from what the user saved (\"what did I save about sidechain compression?\"). "
        "platform is optional: 'instagram', 'x', 'facebook', 'whatsapp', 'web'. limit up to 50."
    )
)
def search_saves(query: str, platform: str | None = None, limit: int = 10, ctx: Context | None = None) -> list[dict[str, Any]]:
    tenant = tenant_from(ctx.headers if ctx else None) or CURRENT_TENANT.get()
    if not assistant_search_allowed(tenant):
        log_call("search_saves", tenant=tenant, refused="assistant_search off")
        return [{"error": ASSISTANT_SEARCH_OFF}]
    results = search(readable(load_saves(tenant).values()), query, platform, limit)
    log_call("search_saves", tenant=tenant, query=query[:80], returned=len(results))
    return results


@mcp.tool(
    description=(
        "The user's most recently saved posts, newest first (optionally one platform). "
        "Same fields as search_saves. limit up to 50."
    )
)
def recent_saves(limit: int = 10, platform: str | None = None, ctx: Context | None = None) -> list[dict[str, Any]]:
    tenant = tenant_from(ctx.headers if ctx else None) or CURRENT_TENANT.get()
    if not assistant_search_allowed(tenant):
        log_call("recent_saves", tenant=tenant, refused="assistant_search off")
        return [{"error": ASSISTANT_SEARCH_OFF}]
    saves = [p for p in readable(load_saves(tenant).values()) if not platform or p.get("platform") == platform]
    saves.sort(key=lambda p: str(p.get("saved_at") or p.get("posted_at") or p.get("received_at") or ""), reverse=True)
    log_call("recent_saves", tenant=tenant, returned=min(len(saves), limit))
    return [brief(p) for p in saves[: max(1, min(limit, 50))]]


@mcp.tool(description="Check that the hindsight connector is reachable. Returns 'pong'.")
def ping(ctx: Context | None = None) -> str:
    log_call("ping", tenant=tenant_from(ctx.headers if ctx else None))
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
    ctx: Context | None = None,
) -> dict[str, Any]:
    tenant = tenant_from(ctx.headers if ctx else None) or CURRENT_TENANT.get()
    result = ingest(posts, source="muse", tenant=tenant)
    log_call("submit_saved_posts", tenant=tenant, sync_id=sync_id, final_batch=final_batch, **result["log"])
    return {**result["counts"], "continue": not final_batch}


def ingest(posts: list[dict[str, Any]], source: str, tenant: str | None = None) -> dict[str, Any]:
    """The one write path for every source (Muse, the WhatsApp bot, …): normalize to
    the contract, dedupe by id, keep the richer record on a re-send."""
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    accepted = duplicates = rejected = 0
    with _lock:
        saves = load_saves(tenant)
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
                    # The longer caption wins, but a field the new record lacks keeps its old value.
                    filled = {k: v for k, v in post.items() if v not in (None, "", [])}
                    saves[pid] = {**old, **filled, "id": pid, "received_at": old.get("received_at", now)}
                else:
                    # Same or shorter caption: still take fields we didn't have (a transcript, an author).
                    extra = {k: v for k, v in post.items() if v not in (None, "", []) and old.get(k) in (None, "", [])}
                    if extra:
                        saves[pid] = {**old, **extra}
                continue
            saves[pid] = {**post, "id": pid, "received_at": now}
            accepted += 1
        saves_path(tenant).write_text(json.dumps(saves, ensure_ascii=False, indent=1))
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
    tenant = tenant_from(request.headers)
    result = ingest(posts, source=source, tenant=tenant)
    log_call("ingest", tenant=tenant, source=source, **result["log"])
    return JSONResponse(result["counts"])


@mcp.custom_route(f"/{TOKEN}/saves", methods=["GET"])
async def saves_for_app(request: Request) -> JSONResponse:
    """The app pulls what Muse sent, as a contract-shaped JSON array (newest received first)."""
    since = request.query_params.get("since")
    tenant = tenant_from(request.headers)
    posts = sorted((normalized(p) for p in load_saves(tenant).values()), key=lambda p: p.get("received_at", ""), reverse=True)
    if since:
        posts = [p for p in posts if p.get("received_at", "") > since]
    log_call("app_pull", tenant=tenant, returned=len(posts), since=since)
    return JSONResponse(posts)


@mcp.custom_route(f"/{TOKEN}/settings", methods=["GET", "PUT"])
async def settings_route(request: Request) -> JSONResponse:
    """The app's switches for this account. PUT takes a JSON object with known keys only
    (`assistant_search`: true/false); anything else is a 400, so a typo never silently does nothing."""
    tenant = tenant_from(request.headers)
    if request.method == "PUT":
        try:
            body = await request.json()
        except ValueError:
            return JSONResponse({"error": "body must be JSON"}, status_code=400)
        if (not isinstance(body, dict) or not body or set(body) - SETTINGS_KEYS
                or not all(isinstance(v, bool) for v in body.values())):
            return JSONResponse({"error": f"only {sorted(SETTINGS_KEYS)} (true/false) can be set"}, status_code=400)
        settings = save_settings(tenant, body)
        log_call("settings", tenant=tenant, **body)
        return JSONResponse(settings)
    return JSONResponse(load_settings(tenant))


@mcp.custom_route(f"/{TOKEN}/tenants", methods=["POST"])
async def create_tenant(request: Request) -> JSONResponse:
    """New isolated store, e.g. for a 'fresh user' Muse test. Returns its base path;
    the app turns it into https://<host>/<token>/t/<tenant>."""
    tenant = "t-" + secrets.token_hex(4)
    saves_path(tenant)  # creates the folder
    log_call("tenant_created", tenant=tenant)
    # One-time hand-over (single-user beta): if data/adopt_default exists, the next new
    # account starts with everything in the default store (the Mac's backfill) and becomes
    # the backfill's target (data/backfill_tenant).
    flag = DATA / "adopt_default"
    if flag.exists():
        with _lock:
            saves_path(tenant).write_text(json.dumps(load_saves(None), ensure_ascii=False, indent=1))
        (DATA / "backfill_tenant").write_text(tenant)
        (DATA / "default_tenant").write_text(tenant)
        flag.unlink()
        log_call("tenant_adopted_default", tenant=tenant, saves=len(load_saves(tenant)))
    return JSONResponse({"tenant": tenant, "base_path": f"/{TOKEN}/t/{tenant}"})


@mcp.custom_route(f"/{TOKEN}/whatsapp", methods=["GET"])
async def whatsapp_bot(_: Request) -> JSONResponse:
    """The WhatsApp bot's number, so the app can open a chat with it. Kept out of
    the (public) repo: set HINDSIGHT_WHATSAPP_BOT or write it to data/whatsapp_bot."""
    file = DATA / "whatsapp_bot"
    number = os.environ.get("HINDSIGHT_WHATSAPP_BOT") or (file.read_text().strip() if file.exists() else "")
    return JSONResponse({"number": "".join(c for c in number if c.isdigit()) or None})


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
        # /<token>/t/<tenant>/<rest> → /<token>/<rest>, with the tenant as a header.
        match = re.match(rf"^/{re.escape(TOKEN)}/t/([^/]+)(/.*)$", scope["path"])
        if match:
            tenant, rest = match.groups()
            if not TENANT_RE.match(tenant):
                await send({"type": "http.response.start", "status": 404, "headers": [(b"content-length", b"0")]})
                await send({"type": "http.response.body", "body": b""})
                return
            scope = {**scope, "path": f"/{TOKEN}{rest}", "raw_path": f"/{TOKEN}{rest}".encode(),
                     "headers": [h for h in scope.get("headers", []) if h[0].decode().lower() != TENANT_HEADER]
                                + [(TENANT_HEADER.encode(), tenant.encode())]}
        headers = {k.decode(): v.decode() for k, v in scope.get("headers", [])}
        path = scope["path"].replace(TOKEN, "<token>") + (f" [tenant {match.group(1)}]" if match else "")
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
