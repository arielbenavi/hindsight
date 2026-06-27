"""Bookmark sweep: poll platform APIs for new saved content.

Supports Twitter/X bookmarks and Instagram saved posts. The sweep
runs on a 30-minute loop inside the API server, or can be triggered
manually via POST /sweep/twitter or POST /sweep/ig.
"""
from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx

import auth
import db

log = logging.getLogger("savefeed.sweep")

STATE_PATH = Path.home() / ".savefeed" / "twitter_sweep_state.json"
IG_STATE_PATH = Path.home() / ".savefeed" / "ig_sweep_state.json"
IG_CAP_PER_SWEEP = 30
IG_INTER_ITEM_DELAY = 5
IG_PAGINATION_DELAY = 2
BOOKMARKS_URL = "https://api.x.com/2/users/{user_id}/bookmarks"
ME_URL = "https://api.x.com/2/users/me"
BACKFILL_CAP = 200
INTER_ITEM_DELAY = 5
RATE_LIMIT_PAUSE = 60

_last_sweep_time: Optional[str] = None
_last_sweep_result: Optional[dict[str, int]] = None


def _load_state() -> dict[str, Any]:
    if STATE_PATH.is_file():
        try:
            return json.loads(STATE_PATH.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def _save_state(state: dict[str, Any]) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2))


def _get_user_id(token: str) -> Optional[str]:
    """GET /2/users/me to get the authenticated user's ID."""
    tokens = auth.load_tokens() or {}
    if tokens.get("user_id"):
        return tokens["user_id"]
    try:
        with httpx.Client(timeout=15) as cx:
            r = cx.get(ME_URL, headers={"Authorization": f"Bearer {token}"})
        if r.status_code != 200:
            log.warning("GET /users/me failed: %s %s", r.status_code, r.text[:200])
            return None
        user_id = r.json().get("data", {}).get("id")
        if user_id:
            tokens["user_id"] = user_id
            auth.save_tokens(tokens)
        return user_id
    except Exception as e:
        log.exception("GET /users/me error: %s", e)
        return None


def _fetch_bookmarks(
    token: str, user_id: str, pagination_token: Optional[str] = None
) -> dict[str, Any]:
    params: dict[str, str] = {
        "max_results": "100",
        "tweet.fields": "created_at,author_id,attachments",
        "expansions": "author_id",
    }
    if pagination_token:
        params["pagination_token"] = pagination_token
    try:
        with httpx.Client(timeout=30) as cx:
            r = cx.get(
                BOOKMARKS_URL.format(user_id=user_id),
                headers={"Authorization": f"Bearer {token}"},
                params=params,
            )
        if r.status_code == 429:
            log.warning("Twitter API rate limited, pausing %ds", RATE_LIMIT_PAUSE)
            time.sleep(RATE_LIMIT_PAUSE)
            return {"rate_limited": True}
        if r.status_code != 200:
            log.warning("bookmarks fetch failed: %s %s", r.status_code, r.text[:200])
            return {"error": r.text[:200]}
        return r.json()
    except Exception as e:
        log.exception("bookmarks fetch error: %s", e)
        return {"error": str(e)}


def _build_author_map(includes: dict) -> dict[str, str]:
    """Map author_id -> username from the includes.users expansion."""
    users = includes.get("users") or []
    return {u["id"]: u.get("username", u.get("name", "unknown")) for u in users}


def _ingest(url: str) -> dict[str, Any]:
    """Ingest a URL through the capture pipeline (in-process)."""
    import router as rt
    import adapters
    source, resolved_url = rt.classify(url)
    if resolved_url:
        existing = db.find_active_by_url(resolved_url)
        if existing:
            return {"id": existing["id"], "status": existing["status"], "deduped": True}
    raw_text = None
    item_id = db.insert_pending(source=source, source_url=resolved_url, kind=None, raw_text=raw_text)
    item = db.get_item(item_id)
    try:
        if source == "tweet":
            adapters.process_tweet(item_id, resolved_url, None)
        elif source == "ig_reel":
            adapters.process_ig_reel(item_id, resolved_url)
        elif source == "web":
            adapters.process_web(item_id, resolved_url)
        else:
            adapters.process_note(item_id, url)
        return {"id": item_id, "status": "done"}
    except Exception as e:
        log.exception("sweep ingest failed for %s", url)
        db.mark_failed(item_id, f"{type(e).__name__}: {e}")
        return {"id": item_id, "status": "failed", "error": str(e)}


def sweep_twitter_bookmarks() -> dict[str, int]:
    """Run one sweep cycle. Returns {processed, skipped, failed}."""
    global _last_sweep_time, _last_sweep_result

    token = auth.get_valid_token()
    if not token:
        log.info("Twitter not authenticated — run /auth/twitter first")
        return {"processed": 0, "skipped": 0, "failed": 0}

    user_id = _get_user_id(token)
    if not user_id:
        log.error("Could not determine Twitter user ID")
        return {"processed": 0, "skipped": 0, "failed": 0}

    state = _load_state()
    last_seen_id = state.get("last_seen_id")
    pagination_state = state.get("pagination_token")

    processed = 0
    skipped = 0
    failed = 0
    newest_id: Optional[str] = None
    pagination_token = pagination_state
    hit_watermark = False

    while processed + skipped < BACKFILL_CAP:
        token = auth.get_valid_token()
        if not token:
            break

        result = _fetch_bookmarks(token, user_id, pagination_token)
        if result.get("rate_limited"):
            result = _fetch_bookmarks(token, user_id, pagination_token)
            if result.get("rate_limited") or result.get("error"):
                log.warning("still rate limited after pause, stopping sweep")
                break
        if result.get("error"):
            break

        tweets = result.get("data") or []
        if not tweets:
            break

        includes = result.get("includes") or {}
        author_map = _build_author_map(includes)
        meta = result.get("meta") or {}

        for tweet in tweets:
            tweet_id = tweet["id"]

            if newest_id is None:
                newest_id = tweet_id

            if last_seen_id and int(tweet_id) <= int(last_seen_id):
                hit_watermark = True
                break

            author_id = tweet.get("author_id", "")
            username = author_map.get(author_id, "unknown")
            url = f"https://x.com/{username}/status/{tweet_id}"

            existing = db.find_active_by_url(url)
            if existing:
                skipped += 1
                continue

            log.info("sweep: ingesting bookmark %s", url)
            res = _ingest(url)
            if res.get("deduped"):
                skipped += 1
            elif res.get("status") == "failed":
                failed += 1
            else:
                processed += 1

            if processed + skipped + failed < BACKFILL_CAP:
                time.sleep(INTER_ITEM_DELAY)

        if hit_watermark:
            break

        pagination_token = meta.get("next_token")
        if not pagination_token:
            break

    new_state: dict[str, Any] = {}
    if newest_id:
        new_state["last_seen_id"] = newest_id
    if not hit_watermark and pagination_token and processed + skipped >= BACKFILL_CAP:
        new_state["pagination_token"] = pagination_token
        log.info("backfill capped at %d, will continue next sweep cycle", BACKFILL_CAP)
    _save_state(new_state)

    _last_sweep_time = datetime.now(timezone.utc).isoformat()
    _last_sweep_result = {"processed": processed, "skipped": skipped, "failed": failed}
    log.info("sweep done: processed=%d skipped=%d failed=%d", processed, skipped, failed)
    return _last_sweep_result


# ── Instagram saved posts sweep ──────────────────────────────────

_ig_last_sweep_time: Optional[str] = None
_ig_last_sweep_result: Optional[dict[str, int]] = None


def _ig_username() -> Optional[str]:
    return os.environ.get("IG_USERNAME") or None


def _ig_session_path(username: str) -> Path:
    return Path.home() / ".config" / "instaloader" / f"session-{username}"


def _ig_session_status() -> str:
    username = _ig_username()
    if not username:
        return "not_configured"
    if not _ig_session_path(username).is_file():
        return "not_configured"
    return "valid"


def _load_ig_state() -> dict[str, Any]:
    if IG_STATE_PATH.is_file():
        try:
            return json.loads(IG_STATE_PATH.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def _save_ig_state(state: dict[str, Any]) -> None:
    IG_STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    IG_STATE_PATH.write_text(json.dumps(state, indent=2))


def sweep_ig_saved() -> dict[str, int]:
    global _ig_last_sweep_time, _ig_last_sweep_result

    username = _ig_username()
    if not username:
        log.info("IG_USERNAME not set — skipping IG sweep")
        return {"processed": 0, "skipped": 0, "failed": 0}

    session_file = _ig_session_path(username)
    if not session_file.is_file():
        log.info("no Instaloader session for %s — run: instaloader --login %s", username, username)
        return {"processed": 0, "skipped": 0, "failed": 0}

    try:
        import instaloader
    except ImportError:
        log.error("instaloader not installed")
        return {"processed": 0, "skipped": 0, "failed": 0}

    L = instaloader.Instaloader()
    try:
        L.load_session_from_file(username)
    except Exception as e:
        log.error("failed to load Instaloader session: %s", e)
        return {"processed": 0, "skipped": 0, "failed": 0}

    state = _load_ig_state()
    last_seen = state.get("last_seen_shortcode")

    processed = 0
    skipped = 0
    failed = 0
    newest_shortcode: Optional[str] = None

    try:
        saved_iter = L.get_saved_posts()
    except instaloader.exceptions.LoginRequiredException:
        log.warning("IG session expired — re-authenticate with: instaloader --login %s", username)
        _ig_last_sweep_time = datetime.now(timezone.utc).isoformat()
        _ig_last_sweep_result = {"processed": 0, "skipped": 0, "failed": 0}
        return _ig_last_sweep_result
    except instaloader.exceptions.ConnectionException as e:
        if "401" in str(e) or "checkpoint" in str(e).lower():
            log.warning("IG session expired/checkpoint — re-authenticate with: instaloader --login %s", username)
        else:
            log.warning("IG connection error: %s", e)
        _ig_last_sweep_time = datetime.now(timezone.utc).isoformat()
        _ig_last_sweep_result = {"processed": 0, "skipped": 0, "failed": 0}
        return _ig_last_sweep_result

    try:
        for post in saved_iter:
            if processed + skipped + failed >= IG_CAP_PER_SWEEP:
                log.info("IG sweep capped at %d, will continue next cycle", IG_CAP_PER_SWEEP)
                break

            shortcode = post.shortcode
            if newest_shortcode is None:
                newest_shortcode = shortcode

            if last_seen and shortcode == last_seen:
                log.info("IG sweep hit watermark at %s", shortcode)
                break

            url = f"https://www.instagram.com/p/{shortcode}/"
            existing = db.find_active_by_url(url)
            reel_url = f"https://www.instagram.com/reel/{shortcode}/"
            existing_reel = db.find_active_by_url(reel_url) if not existing else None

            if existing or existing_reel:
                skipped += 1
                log.info("IG sweep: already in DB, stopping fast-update")
                break

            log.info("IG sweep: ingesting %s", url)
            res = _ingest(url)
            if res.get("deduped"):
                skipped += 1
            elif res.get("status") == "failed":
                failed += 1
            else:
                processed += 1

            time.sleep(IG_INTER_ITEM_DELAY)
            time.sleep(IG_PAGINATION_DELAY)

    except instaloader.exceptions.QueryReturnedNotFoundException:
        log.warning("IG post not found during sweep, continuing")
    except instaloader.exceptions.ConnectionException as e:
        if "429" in str(e) or "too many" in str(e).lower():
            log.warning("IG rate limited, stopping sweep — will resume next cycle")
        else:
            log.warning("IG connection error during sweep: %s", e)
    except Exception as e:
        log.exception("unexpected IG sweep error: %s", e)

    if newest_shortcode:
        _save_ig_state({
            "last_seen_shortcode": newest_shortcode,
            "last_sweep_timestamp": datetime.now(timezone.utc).isoformat(),
        })

    _ig_last_sweep_time = datetime.now(timezone.utc).isoformat()
    _ig_last_sweep_result = {"processed": processed, "skipped": skipped, "failed": failed}
    log.info("IG sweep done: processed=%d skipped=%d failed=%d", processed, skipped, failed)
    return _ig_last_sweep_result


# ── status ───────────────────────────────────────────────────────

def get_status() -> dict[str, Any]:
    tokens = auth.load_tokens()
    return {
        "twitter": {
            "authenticated": tokens is not None and "access_token" in (tokens or {}),
            "last_sweep": _last_sweep_time,
            "last_sweep_result": _last_sweep_result,
        },
        "ig_saved": {
            "authenticated": _ig_session_status() == "valid",
            "last_sweep": _ig_last_sweep_time,
            "last_sweep_result": _ig_last_sweep_result,
            "session_status": _ig_session_status(),
        },
    }
