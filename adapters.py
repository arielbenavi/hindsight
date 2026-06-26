"""Per-source adapters. Each turns a pending row into a done (or failed) row."""
from __future__ import annotations

import html as html_lib
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

import httpx
import trafilatura

import db
import gemini

log = logging.getLogger("savefeed.adapters")

YTDLP_CMD = [sys.executable, "-m", "yt_dlp"]
GALLERY_DL_CMD = [sys.executable, "-m", "gallery_dl"]

OEMBED_URL = "https://publish.x.com/oembed"
SYNDICATION_URL = "https://cdn.syndication.twimg.com/tweet-result"
_BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
COOKIES_FILE_ENV = "IG_COOKIES_FILE"


def _cookies_file() -> Optional[Path]:
    """Path to a Netscape cookies file if IG_COOKIES_FILE is set and points at a non-empty file."""
    raw = os.environ.get(COOKIES_FILE_ENV)
    if not raw:
        return None
    p = Path(raw).expanduser()
    return p if p.is_file() and p.stat().st_size > 0 else None


def _cookie_args(browser: str) -> list[str]:
    """`--cookies <file>` when IG_COOKIES_FILE is usable, else `--cookies-from-browser <browser>`."""
    cf = _cookies_file()
    return ["--cookies", str(cf)] if cf else ["--cookies-from-browser", browser]


def _cookie_browsers() -> tuple[str, ...]:
    """Single iteration when using a static cookies file; chrome→firefox otherwise."""
    return ("file",) if _cookies_file() else ("chrome", "firefox")


VIDEO_EXTS = {".mp4", ".mov", ".webm", ".mkv"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
LOGIN_WALL_MARKERS = (
    "log in",
    "sign up",
    "create an account",
    "enable javascript",
    "please enable cookies",
    "verifying you are human",
    "captcha",
    "register to continue",
    "you need to log in",
)


def process_ig_reel(item_id: int, url: str) -> None:
    with tempfile.TemporaryDirectory(prefix="savefeed-ig-") as td:
        td_path = Path(td)
        mp4 = _ytdlp_video(url, td_path)
        if mp4 is not None:
            g = gemini.gist_video(mp4)
            kind = "video"
        else:
            images = _gallery_dl_images(url, td_path)
            if not images:
                raise RuntimeError(
                    f"could not fetch as video (yt-dlp) or images (gallery-dl) for {url}"
                )
            g = gemini.gist_images(images)
            kind = "images"
    db.mark_done(
        item_id,
        kind=kind,
        summary=g.get("summary"),
        on_screen_text=g.get("on_screen_text"),
        transcript=g.get("spoken_transcript"),
        category=g.get("category"),
        key_takeaways=g.get("key_takeaways") or [],
        tags=g.get("tags") or [],
    )


def _ytdlp_video(url: str, into: Path, timeout: int = 240) -> Optional[Path]:
    """Try to download a video. Returns Path on success, None on any failure (caller may fall back)."""
    for browser in _cookie_browsers():
        cmd = [
            *YTDLP_CMD,
            *_cookie_args(browser),
            "-o", str(into / "%(id)s.%(ext)s"),
            "--merge-output-format", "mp4",
            "--quiet", "--no-warnings",
            "--print", "after_move:filepath",
            url,
        ]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            log.warning("yt-dlp timed out (%s) for %s", browser, url)
            continue
        if r.returncode == 0:
            lines = r.stdout.strip().splitlines()
            if lines:
                p = Path(lines[-1])
                if p.exists() and p.suffix.lower() in VIDEO_EXTS:
                    return p
        # Authoritative "this post has no video" — don't bother with firefox.
        if "No video could be found" in r.stderr:
            log.info("yt-dlp: no video in %s", url)
            return None
        log.warning("yt-dlp exit %s (%s) stderr: %s", r.returncode, browser, r.stderr[-400:])
    return None


def _gallery_dl_images(url: str, into: Path) -> list[Path]:
    """Fetch a carousel as images via gallery-dl. Returns sorted list, [] on failure."""
    for browser in _cookie_browsers():
        cmd = [
            *GALLERY_DL_CMD,
            *_cookie_args(browser),
            "-d", str(into),
            "--quiet",
            url,
        ]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired:
            log.warning("gallery-dl timed out (%s) for %s", browser, url)
            continue
        if r.returncode == 0:
            images = sorted(
                p for p in into.rglob("*")
                if p.is_file() and p.suffix.lower() in IMAGE_EXTS
            )
            if images:
                return images
        log.warning("gallery-dl exit %s (%s) stderr: %s", r.returncode, browser, r.stderr[-400:])
    return []


def _is_login_wall(text: str) -> bool:
    t = (text or "").lower().strip()
    if len(t) < 60:
        return True
    if len(t) < 600:
        return any(m in t for m in LOGIN_WALL_MARKERS)
    return False


def process_web(item_id: int, url: str) -> None:
    html = trafilatura.fetch_url(url)
    if not html:
        raise RuntimeError(f"trafilatura fetch returned nothing for {url}")
    text = trafilatura.extract(html) or ""
    if _is_login_wall(text):
        raise RuntimeError(f"blocked/login wall (extracted {len(text)} chars)")
    g = gemini.gist_text(text[:50000])
    db.mark_done(
        item_id,
        kind="article",
        raw_text=text[:200000],
        summary=g.get("summary"),
        category=g.get("category"),
        key_takeaways=g.get("key_takeaways") or [],
        tags=g.get("tags") or [],
    )


def process_note(item_id: int, text: str) -> None:
    g = gemini.gist_text(text)
    db.mark_done(
        item_id,
        kind="text",
        summary=g.get("summary"),
        category=g.get("category"),
        key_takeaways=g.get("key_takeaways") or [],
        tags=g.get("tags") or [],
    )


def _extract_tweet_id(url: str) -> Optional[str]:
    """Extract the numeric tweet ID from an x.com or twitter.com URL."""
    clean = url.split("?")[0].rstrip("/")
    m = re.search(r"/status/(\d+)", clean)
    return m.group(1) if m else None


def _twitter_syndication(url: str) -> dict:
    """Fetch tweet data via the syndication endpoint. Returns parsed JSON or empty dict."""
    tweet_id = _extract_tweet_id(url)
    if not tweet_id:
        log.warning("could not extract tweet ID from %s", url)
        return {}
    try:
        with httpx.Client(timeout=15, follow_redirects=True) as cx:
            r = cx.get(
                SYNDICATION_URL,
                params={"id": tweet_id, "token": "x"},
                headers={"User-Agent": _BROWSER_UA},
            )
    except httpx.HTTPError as e:
        log.warning("syndication fetch failed for %s: %s", url, e)
        return {}
    if r.status_code != 200:
        log.warning("syndication returned %s for %s", r.status_code, url)
        return {}
    try:
        return r.json()
    except json.JSONDecodeError:
        return {}


def _twitter_oembed(url: str) -> tuple[str, Optional[str]]:
    """Fallback: fetch tweet text + author via oEmbed."""
    try:
        with httpx.Client(timeout=15, follow_redirects=True) as cx:
            r = cx.get(OEMBED_URL, params={"url": url, "omit_script": "true"})
    except httpx.HTTPError as e:
        log.warning("oEmbed fetch failed for %s: %s", url, e)
        return "", None
    if r.status_code != 200:
        return "", None
    try:
        data = r.json()
    except json.JSONDecodeError:
        return "", None
    m = re.search(r"<p[^>]*>(.*?)</p>", data.get("html") or "", re.DOTALL)
    if not m:
        return "", data.get("author_name")
    inner = re.sub(r"<br\s*/?>", "\n", m.group(1), flags=re.IGNORECASE)
    inner = re.sub(r"<[^>]+>", "", inner)
    return html_lib.unescape(inner).strip().rstrip("…").strip(), data.get("author_name")


def _download_images(urls: list[str], into: Path) -> list[Path]:
    """Download image URLs to a directory. Skips individual failures."""
    paths: list[Path] = []
    with httpx.Client(timeout=30, follow_redirects=True) as cx:
        for i, img_url in enumerate(urls):
            try:
                r = cx.get(img_url)
                if r.status_code != 200:
                    log.warning("image download %s returned %s", img_url, r.status_code)
                    continue
                ext = Path(img_url.split("?")[0]).suffix or ".jpg"
                p = into / f"tweet_img_{i}{ext}"
                p.write_bytes(r.content)
                paths.append(p)
            except httpx.HTTPError as e:
                log.warning("image download failed for %s: %s", img_url, e)
    return paths


def process_tweet(item_id: int, url: str, note: Optional[str]) -> None:
    syn = _twitter_syndication(url)

    if syn:
        text = syn.get("text") or ""
        user = syn.get("user") or {}
        author = user.get("screen_name") or user.get("name")
        media = syn.get("mediaDetails") or []
        photos = [m for m in media if m.get("type") == "photo"]
        videos = [m for m in media if m.get("type") == "video"]
    else:
        log.warning("syndication failed for %s, falling back to oEmbed", url)
        text, author = _twitter_oembed(url)
        photos, videos = [], []

    with tempfile.TemporaryDirectory(prefix="savefeed-tw-") as td:
        td_path = Path(td)

        if videos:
            mp4 = _ytdlp_video(url, td_path, timeout=45)
            if mp4 is not None:
                g = gemini.gist_video(mp4)
                kind = "video"
            elif text:
                g = gemini.gist_text(text)
                kind = "text"
            else:
                raise RuntimeError(f"video tweet but yt-dlp failed and no text for {url}")
        elif photos:
            img_urls = [p.get("media_url_https") for p in photos if p.get("media_url_https")]
            downloaded = _download_images(img_urls, td_path)
            if downloaded:
                g = gemini.gist_images(downloaded, context=text if text else None)
                kind = "images"
            elif text:
                g = gemini.gist_text(text)
                kind = "text"
            else:
                raise RuntimeError(f"image tweet but downloads failed and no text for {url}")
        elif text:
            g = gemini.gist_text(text)
            kind = "text"
        else:
            mp4 = _ytdlp_video(url, td_path, timeout=45)
            if mp4 is not None:
                g = gemini.gist_video(mp4)
                kind = "video"
            else:
                raise RuntimeError(f"no text, media, or video for {url}")

    raw_parts: list[str] = []
    if author:
        raw_parts.append(f"[@{author}]")
    if text:
        raw_parts.append(text)
    raw = "\n\n".join(raw_parts) if raw_parts else ""
    if note:
        raw = f"[note: {note}]\n\n{raw}".strip() if raw else f"[note: {note}]"

    db.mark_done(
        item_id,
        kind=kind,
        raw_text=raw or None,
        summary=g.get("summary"),
        on_screen_text=g.get("on_screen_text"),
        transcript=g.get("spoken_transcript"),
        category=g.get("category"),
        key_takeaways=g.get("key_takeaways") or [],
        tags=g.get("tags") or [],
    )
