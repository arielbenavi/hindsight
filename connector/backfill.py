"""Backfill from the Mac: fetch what was saved since the last run and hand it to the connector.

Sources (the same ones the legacy web backend swept, see docs/BACKFILL_STATUS.md):
  - Instagram saved posts, via the logged-in cookie API (~/.savefeed/cookies.txt)
  - X bookmarks, via the OAuth token in ~/.savefeed/twitter_tokens.json

Fetch only: no Gemini, no legacy database. Posts go to the connector's /ingest as
contract-shaped records, so they reach the app on its next pull. Each source stops at
the watermark in ~/.savefeed/*_sweep_state.json and moves it forward after a successful
ingest, so running this again only fetches what's new.

    cd connector && ../venv/bin/python backfill.py --dry-run     # count only, nothing written
    cd connector && ../venv/bin/python backfill.py               # fetch + ingest
    ... --only ig | --only x       ... --tenant t-xxxxxxxx       ... --cap 300

Without --tenant it uses the account named in data/backfill_tenant (the phone's), else the default store.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "web" / "backend"))


def load_env() -> None:
    """The legacy backend's settings (X client id, cookie file path) live in the repo's .env."""
    env = ROOT / ".env"
    if not env.is_file():
        return
    values: dict[str, str] = {}
    for line in env.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip().strip('"').strip("'")  # a repeated key: the last one wins, like dotenv
    for key, value in values.items():
        os.environ.setdefault(key, value)


def iso(ts: float | int | None) -> str | None:
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat(timespec="seconds") if ts else None


# ── Instagram ──

def ig_post(media: dict[str, Any]) -> dict[str, Any] | None:
    code = media.get("code")
    if not code:
        return None
    is_reel = media.get("product_type") == "clips"
    kind = "reel" if is_reel else {1: "post", 2: "video", 8: "carousel"}.get(media.get("media_type"), "post")
    user = media.get("user") or {}
    images = ((media.get("image_versions2") or {}).get("candidates")
              or ((media.get("carousel_media") or [{}])[0].get("image_versions2") or {}).get("candidates") or [])
    return {
        "platform": "instagram",
        "url": f"https://www.instagram.com/{'reel' if is_reel else 'p'}/{code}/",
        "kind": kind,
        "author": user.get("username"),
        "author_display_name": user.get("full_name") or None,
        "caption": (media.get("caption") or {}).get("text"),
        "posted_at": iso(media.get("taken_at")),
        "thumbnail_url": images[0].get("url") if images else None,
        "location_tag": (media.get("location") or {}).get("name"),
        "source": "ig_cookie",
    }


def fetch_instagram(cap: int) -> tuple[list[dict[str, Any]], str | None, str]:
    """New saves, newest first, up to the watermark. Returns (posts, new watermark, note)."""
    import sweep

    cookie_file = sweep._ig_cookies_file() or Path.home() / ".savefeed" / "cookies.txt"
    if not Path(cookie_file).is_file():
        return [], None, "no cookie file"
    cookies = sweep._parse_cookies_txt(Path(cookie_file))
    if "sessionid" not in cookies:
        return [], None, "cookie file has no Instagram session"
    watermark = sweep._load_ig_state().get("last_seen_shortcode")
    posts: list[dict[str, Any]] = []
    newest: str | None = None
    max_id: str | None = None
    note = "reached the cap"
    while len(posts) < cap:
        page = sweep._fetch_ig_saved(cookies, max_id)
        if page.get("auth_error"):
            return posts, newest, "Instagram rejected the cookies (expired: export them again)"
        if page.get("rate_limited") or page.get("error"):
            return posts, newest, f"stopped early: {page.get('error') or 'rate limited'}"
        items = page.get("items") or []
        for item in items:
            media = item.get("media") or item
            code = media.get("code")
            newest = newest or code
            if code and code == watermark:
                return posts, newest, "reached the last run's newest save"
            post = ig_post(media)
            if post:
                posts.append(post)
        if not page.get("more_available") or not items:
            note = "reached the end of Saved" + ("" if watermark else " (no watermark)")
            break
        max_id = page.get("next_max_id")
        time.sleep(2)
    return posts, newest, note


# ── X ──

def fetch_x(cap: int) -> tuple[list[dict[str, Any]], str | None, str]:
    import auth
    import sweep

    token = auth.get_valid_token()
    if not token:
        return [], None, "no valid X token (sign in again via the legacy /auth/twitter, or use the app's X connect)"
    user_id = sweep._get_user_id(token)
    if not user_id:
        return [], None, "couldn't read the X account"
    watermark = sweep._load_state().get("last_seen_id")
    posts: list[dict[str, Any]] = []
    newest: str | None = None
    page_token: str | None = None
    note = "reached the cap"
    while len(posts) < cap:
        page = sweep._fetch_bookmarks(token, user_id, page_token)
        if page.get("rate_limited") or page.get("error"):
            return posts, newest, f"stopped early: {page.get('error') or 'rate limited'}"
        authors = sweep._build_author_map(page.get("includes") or {})
        tweets = page.get("data") or []
        for tweet in tweets:
            newest = newest or tweet["id"]
            if tweet["id"] == watermark:
                return posts, newest, "reached the last run's newest bookmark"
            username = authors.get(tweet.get("author_id", ""), "i")
            posts.append({
                "platform": "x",
                "url": f"https://x.com/{username}/status/{tweet['id']}",
                "kind": "tweet",
                "author": username,
                "caption": tweet.get("text"),
                "posted_at": tweet.get("created_at"),
                "source": "x_api",
            })
        page_token = (page.get("meta") or {}).get("next_token")
        if not page_token or not tweets:
            note = "reached the end of Bookmarks"
            break
    return posts, newest, note


# ── Connector ──

def ingest(posts: list[dict[str, Any]], source: str, tenant: str | None) -> dict[str, Any]:
    token = (Path(__file__).parent / "data" / "token").read_text().strip()
    port = os.environ.get("PORT", "8765")
    headers = {"x-hindsight-tenant": tenant} if tenant else {}
    with httpx.Client(timeout=30) as cx:
        r = cx.post(f"http://127.0.0.1:{port}/{token}/ingest", json={"source": source, "posts": posts}, headers=headers)
    r.raise_for_status()
    return r.json()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="fetch and count; write nothing")
    parser.add_argument("--only", choices=["ig", "x"])
    parser.add_argument("--tenant", help="connector tenant (an install's account); default store if omitted")
    parser.add_argument("--cap", type=int, default=200, help="max new items per source per run")
    args = parser.parse_args()
    load_env()
    # The phone's account, once known (written when the app first creates its tenant).
    default_tenant = Path(__file__).parent / "data" / "backfill_tenant"
    if not args.tenant and default_tenant.is_file():
        args.tenant = default_tenant.read_text().strip() or None
    import sweep

    for name, source, fetch, save in (
        ("ig", "ig_cookie", fetch_instagram, lambda mark: sweep._save_ig_state({
            "last_seen_shortcode": mark, "last_sweep_timestamp": datetime.now(timezone.utc).isoformat()})),
        ("x", "x_api", fetch_x, lambda mark: sweep._save_state({**sweep._load_state(), "last_seen_id": mark})),
    ):
        if args.only and args.only != name:
            continue
        posts, newest, note = fetch(args.cap)
        line = f"{name}: {len(posts)} new ({note})"
        if args.dry_run or not posts:
            print(line + (" [dry run]" if args.dry_run and posts else ""))
            continue
        counts = ingest(posts, source, args.tenant)
        if newest:
            save(newest)
        print(f"{line} → accepted {counts.get('accepted')}, already had {counts.get('duplicates')}, rejected {counts.get('rejected')}")


if __name__ == "__main__":
    main()
