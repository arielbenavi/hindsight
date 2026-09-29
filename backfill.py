"""Full historical backfill — paginate through ALL saved content, resumably.

Reuses sweep.py helpers (_fetch_bookmarks, _fetch_ig_saved, _ingest, etc.)
but ignores watermarks and removes caps. State is saved to disk after every
item so backfills survive interruptions.
"""
from __future__ import annotations

import json
import logging
import os
import tempfile
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
from urllib.parse import parse_qs, urlparse

import auth
import db
import sweep

log = logging.getLogger("savefeed.backfill")

_SAVEFEED_DIR = Path.home() / ".savefeed"

TWITTER_INTER_ITEM_DELAY = 5
TWITTER_INTER_PAGE_DELAY = 1
IG_INTER_ITEM_DELAY = 10
IG_INTER_PAGE_DELAY = 3
IG_CAP_PER_SESSION = 100


class BackfillState:
    def __init__(self, platform: str):
        self.platform = platform
        self.path = _SAVEFEED_DIR / f"{platform}_backfill_state.json"
        self.data: dict[str, Any] = self._load()

    def _load(self) -> dict[str, Any]:
        if self.path.is_file():
            try:
                return json.loads(self.path.read_text())
            except (json.JSONDecodeError, OSError):
                pass
        return self._default()

    def _default(self) -> dict[str, Any]:
        return {
            "status": "idle",
            "cursor": None,
            "ingested": 0,
            "skipped": 0,
            "failed": 0,
            "total_seen": 0,
            "started_at": None,
            "last_activity": None,
            "more_available": True,
            "error": None,
        }

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self.data, indent=2))

    @property
    def status(self) -> str:
        return self.data.get("status", "idle")

    def is_running(self) -> bool:
        return self.status == "running"

    def start(self) -> None:
        if self.status == "idle" or self.status == "done":
            self.data = self._default()
        self.data["status"] = "running"
        self.data["started_at"] = self.data.get("started_at") or datetime.now(timezone.utc).isoformat()
        self.data["error"] = None
        self.save()

    def pause(self, reason: str = "") -> None:
        self.data["status"] = "paused"
        if reason:
            self.data["error"] = reason
        self.data["last_activity"] = datetime.now(timezone.utc).isoformat()
        self.save()

    def finish(self) -> None:
        self.data["status"] = "done"
        self.data["more_available"] = False
        self.data["last_activity"] = datetime.now(timezone.utc).isoformat()
        self.save()

    def record_item(self, result: str) -> None:
        if result == "ingested":
            self.data["ingested"] = self.data.get("ingested", 0) + 1
        elif result == "skipped":
            self.data["skipped"] = self.data.get("skipped", 0) + 1
        elif result == "failed":
            self.data["failed"] = self.data.get("failed", 0) + 1
        self.data["total_seen"] = self.data.get("total_seen", 0) + 1
        self.data["last_activity"] = datetime.now(timezone.utc).isoformat()
        self.save()

    def set_cursor(self, cursor: Optional[str]) -> None:
        self.data["cursor"] = cursor
        self.data["more_available"] = cursor is not None
        self.save()

    def to_dict(self) -> dict[str, Any]:
        return dict(self.data)


def get_all_status() -> dict[str, Any]:
    return {
        "twitter": BackfillState("twitter").to_dict(),
        "ig": BackfillState("ig").to_dict(),
        "facebook": BackfillState("facebook").to_dict(),
        "tiktok": BackfillState("tiktok").to_dict(),
        "ig_export": BackfillState("ig_export").to_dict(),
    }


def twitter_backfill() -> dict[str, Any]:
    state = BackfillState("twitter")
    if state.is_running():
        return {"error": "backfill already running", **state.to_dict()}

    token = auth.get_valid_token()
    if not token:
        return {"error": "not authenticated — visit /auth/twitter first"}

    user_id = sweep._get_user_id(token)
    if not user_id:
        return {"error": "could not determine Twitter user ID"}

    state.start()
    pagination_token = state.data.get("cursor")

    try:
        while True:
            token = auth.get_valid_token()
            if not token:
                state.pause("token expired and refresh failed")
                break

            result = sweep._fetch_bookmarks(token, user_id, pagination_token)

            if result.get("rate_limited"):
                result = sweep._fetch_bookmarks(token, user_id, pagination_token)
                if result.get("rate_limited") or result.get("error"):
                    state.pause("rate limited — resume later")
                    break

            if result.get("error"):
                state.pause(f"API error: {result['error'][:200]}")
                break

            tweets = result.get("data") or []
            if not tweets:
                state.finish()
                break

            includes = result.get("includes") or {}
            author_map = sweep._build_author_map(includes)
            meta = result.get("meta") or {}

            for tweet in tweets:
                tweet_id = tweet["id"]
                author_id = tweet.get("author_id", "")
                username = author_map.get(author_id, "unknown")
                url = f"https://x.com/{username}/status/{tweet_id}"

                existing = db.find_active_by_url(url)
                if existing:
                    state.record_item("skipped")
                    continue

                log.info("backfill: ingesting tweet %s", url)
                res = sweep._ingest(url)
                if res.get("deduped"):
                    state.record_item("skipped")
                elif res.get("status") == "failed":
                    state.record_item("failed")
                    time.sleep(TWITTER_INTER_ITEM_DELAY)
                else:
                    state.record_item("ingested")
                    time.sleep(TWITTER_INTER_ITEM_DELAY)

            pagination_token = meta.get("next_token")
            state.set_cursor(pagination_token)

            if not pagination_token:
                state.finish()
                break

            time.sleep(TWITTER_INTER_PAGE_DELAY)

    except Exception as e:
        log.exception("twitter backfill error")
        state.pause(f"exception: {e}")

    log.info(
        "twitter backfill stopped: ingested=%d skipped=%d failed=%d status=%s",
        state.data["ingested"], state.data["skipped"], state.data["failed"], state.status,
    )
    return state.to_dict()


def ig_backfill() -> dict[str, Any]:
    state = BackfillState("ig")
    if state.is_running():
        return {"error": "backfill already running", **state.to_dict()}

    cf = sweep._ig_cookies_file()
    if not cf:
        return {"error": "IG_COOKIES_FILE not set or missing"}

    cookies = sweep._parse_cookies_txt(cf)
    if "sessionid" not in cookies:
        return {"error": "no sessionid in cookies.txt — re-export cookies"}

    state.start()
    max_id = state.data.get("cursor")
    session_count = 0

    try:
        while session_count < IG_CAP_PER_SESSION:
            result = sweep._fetch_ig_saved(cookies, max_id)

            if result.get("auth_error"):
                state.pause(f"cookies expired (HTTP {result.get('status')}) — re-export cookies.txt")
                break
            if result.get("rate_limited"):
                state.pause("rate limited — resume later")
                break
            if result.get("error"):
                state.pause(f"API error: {result['error'][:200]}")
                break

            items = result.get("items") or []
            if not items:
                state.finish()
                break

            for item in items:
                if session_count >= IG_CAP_PER_SESSION:
                    state.pause(f"session cap reached ({IG_CAP_PER_SESSION} items)")
                    break

                media = item.get("media") or item
                shortcode = media.get("code") or media.get("shortcode")
                if not shortcode:
                    continue

                url = f"https://www.instagram.com/p/{shortcode}/"
                reel_url = f"https://www.instagram.com/reel/{shortcode}/"

                existing = db.find_active_by_url(url)
                existing_reel = db.find_active_by_url(reel_url) if not existing else None

                if existing or existing_reel:
                    state.record_item("skipped")
                    session_count += 1
                    continue

                log.info("backfill: ingesting IG %s", url)
                res = sweep._ingest(url)
                if res.get("deduped"):
                    state.record_item("skipped")
                    session_count += 1
                elif res.get("status") == "failed":
                    state.record_item("failed")
                    session_count += 1
                    time.sleep(IG_INTER_ITEM_DELAY)
                else:
                    state.record_item("ingested")
                    session_count += 1
                    time.sleep(IG_INTER_ITEM_DELAY)
            else:
                more_available = result.get("more_available", False)
                next_max_id = result.get("next_max_id")
                if more_available and next_max_id:
                    max_id = str(next_max_id)
                    state.set_cursor(max_id)
                    time.sleep(IG_INTER_PAGE_DELAY)
                    continue
                state.finish()
                break
            break

    except Exception as e:
        log.exception("ig backfill error")
        state.pause(f"exception: {e}")

    log.info(
        "ig backfill stopped: ingested=%d skipped=%d failed=%d status=%s",
        state.data["ingested"], state.data["skipped"], state.data["failed"], state.status,
    )
    return state.to_dict()


FB_INTER_ITEM_DELAY = 5
FB_SKIP_PATTERNS = ("/marketplace/", "/events/", "/groups/", "/fundraisers/", "/gaming/")


def _find_saved_json_in_dir(root: Path) -> Path | None:
    candidates = [
        "your_facebook_activity/saved_items_and_collections/saved_items_and_collections.json",
        "saved_items_and_collections/saved_items_and_collections.json",
        "saved_items_and_collections.json",
        "your_saved_items.json",
        "saved_items.json",
    ]
    for c in candidates:
        p = root / c
        if p.is_file():
            return p
    for p in root.rglob("*.json"):
        name = p.name.lower()
        if "saved" in name and ("item" in name or "collection" in name):
            return p
    return None


def _extract_fb_urls(data: Any) -> list[str]:
    urls: list[str] = []

    def _walk(obj: Any) -> None:
        if isinstance(obj, dict):
            for key in ("url", "uri", "href", "link"):
                val = obj.get(key)
                if isinstance(val, str) and val.startswith("http"):
                    urls.append(val)
                    return
            for v in obj.values():
                _walk(v)
        elif isinstance(obj, list):
            for item in obj:
                _walk(item)

    if isinstance(data, dict):
        for key in ("saves_and_collections", "saved_items", "saves", "saved_saved_items"):
            if key in data:
                _walk(data[key])
        if not urls:
            _walk(data)
    elif isinstance(data, list):
        _walk(data)
    return urls


def _unwrap_fb_redirect(url: str) -> str:
    parsed = urlparse(url)
    if parsed.hostname in ("l.facebook.com", "lm.facebook.com"):
        qs = parse_qs(parsed.query)
        if "u" in qs:
            return qs["u"][0]
    return url


def _fb_should_skip(url: str) -> bool:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    path = parsed.path.lower()
    if any(pat in path for pat in FB_SKIP_PATTERNS):
        return True
    if host in ("l.facebook.com", "lm.facebook.com"):
        return False
    if "facebook.com" in host and "/posts/" not in path and "/videos/" not in path and "/photo" not in path:
        if "/permalink" not in path and "/story" not in path:
            return True
    return False


def fb_export_backfill(file_path: str) -> dict[str, Any]:
    state = BackfillState("facebook")
    if state.is_running():
        return {"error": "backfill already running", **state.to_dict()}

    src = Path(file_path)
    if not src.is_file():
        return {"error": f"file not found: {file_path}"}

    json_path: Optional[Path] = None
    tmpdir: Optional[str] = None

    try:
        if src.suffix.lower() == ".zip":
            tmpdir = tempfile.mkdtemp(prefix="savefeed-fb-export-")
            with zipfile.ZipFile(src) as zf:
                zf.extractall(tmpdir)
            json_path = _find_saved_json_in_dir(Path(tmpdir))
            if not json_path:
                return {"error": "could not find saved-items JSON in zip"}
        elif src.suffix.lower() == ".json":
            json_path = src
        else:
            return {"error": f"expected .json or .zip, got {src.suffix}"}

        data = json.loads(json_path.read_bytes().decode("utf-8", errors="replace"))
        all_urls = _extract_fb_urls(data)
        unwrapped = [_unwrap_fb_redirect(u) for u in all_urls]
        filtered = [u for u in unwrapped if not _fb_should_skip(u)]

        if not filtered:
            return {"error": "no importable URLs found in export", "raw_count": len(all_urls)}

        state.start()
        state.data["total_found"] = len(filtered)
        state.save()

        for url in filtered:
            existing = db.find_active_by_url(url)
            if existing:
                state.record_item("skipped")
                continue

            log.info("backfill: ingesting FB %s", url)
            res = sweep._ingest(url)
            if res.get("deduped"):
                state.record_item("skipped")
            elif res.get("status") == "failed":
                state.record_item("failed")
                time.sleep(FB_INTER_ITEM_DELAY)
            else:
                state.record_item("ingested")
                time.sleep(FB_INTER_ITEM_DELAY)

        state.finish()

    except Exception as e:
        log.exception("fb export backfill error")
        state.pause(f"exception: {e}")

    log.info(
        "fb backfill stopped: ingested=%d skipped=%d failed=%d status=%s",
        state.data["ingested"], state.data["skipped"], state.data["failed"], state.status,
    )
    return state.to_dict()


def ig_export_backfill(file_path: str) -> dict[str, Any]:
    state = BackfillState("ig_export")
    if state.is_running():
        return {"error": "backfill already running", **state.to_dict()}

    src = Path(file_path)
    if not src.is_file():
        return {"error": f"file not found: {file_path}"}

    json_path: Optional[Path] = None
    tmpdir: Optional[str] = None

    try:
        if src.suffix.lower() == ".zip":
            tmpdir = tempfile.mkdtemp(prefix="savefeed-ig-export-")
            with zipfile.ZipFile(src) as zf:
                zf.extractall(tmpdir)
            json_path = _find_ig_saved_json(Path(tmpdir))
            if not json_path:
                return {"error": "could not find saved-posts JSON in zip"}
        elif src.suffix.lower() == ".json":
            json_path = src
        else:
            return {"error": f"expected .json or .zip, got {src.suffix}"}

        data = json.loads(json_path.read_text(encoding="utf-8"))
        urls = _extract_ig_export_urls(data)

        if not urls:
            return {"error": "no saved-post URLs found in export"}

        state.start()
        state.data["total_found"] = len(urls)
        state.save()

        for url in urls:
            existing = db.find_active_by_url(url)
            if existing:
                state.record_item("skipped")
                continue

            log.info("backfill: ingesting IG export %s", url)
            res = sweep._ingest(url)
            if res.get("deduped"):
                state.record_item("skipped")
            elif res.get("status") == "failed":
                state.record_item("failed")
                time.sleep(IG_INTER_ITEM_DELAY)
            else:
                state.record_item("ingested")
                time.sleep(IG_INTER_ITEM_DELAY)

        state.finish()

    except Exception as e:
        log.exception("ig export backfill error")
        state.pause(f"exception: {e}")

    log.info(
        "ig export backfill stopped: ingested=%d skipped=%d failed=%d status=%s",
        state.data["ingested"], state.data["skipped"], state.data["failed"], state.status,
    )
    return state.to_dict()


def _find_ig_saved_json(root: Path) -> Path | None:
    candidates = [
        "your_instagram_activity/saved/saved_posts.json",
        "saved/saved_posts.json",
        "saved_posts.json",
    ]
    for c in candidates:
        p = root / c
        if p.is_file():
            return p
    for p in root.rglob("*.json"):
        name = p.name.lower()
        if "saved" in name and ("post" in name or "media" in name or "collection" in name):
            return p
    return None


def _extract_ig_export_urls(data: Any) -> list[str]:
    urls: list[str] = []

    def _url_from_item(item: Any) -> str | None:
        if not isinstance(item, dict):
            return None
        for key in ("href", "url", "link"):
            if key in item and isinstance(item[key], str) and item[key].startswith("http"):
                return item[key]
        if "string_map_data" in item:
            smd = item["string_map_data"]
            if isinstance(smd, dict):
                for v in smd.values():
                    if isinstance(v, dict) and "href" in v:
                        return v["href"]
        if "media_map_data" in item:
            mmd = item["media_map_data"]
            if isinstance(mmd, dict):
                for v in mmd.values():
                    if isinstance(v, dict) and "uri" in v:
                        return v["uri"]
        return None

    if isinstance(data, list):
        for item in data:
            url = _url_from_item(item)
            if url:
                urls.append(url)
    elif isinstance(data, dict):
        for key in ("saved_saved_media", "saved_media", "saved_posts", "saved_saved_collections"):
            if key in data and isinstance(data[key], list):
                for item in data[key]:
                    url = _url_from_item(item)
                    if url:
                        urls.append(url)
        if not urls:
            for v in data.values():
                if isinstance(v, list):
                    for item in v:
                        url = _url_from_item(item)
                        if url:
                            urls.append(url)
    return urls
