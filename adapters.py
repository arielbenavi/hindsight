"""Per-source adapters. Each turns a pending row into a done (or failed) row."""
from __future__ import annotations

import html as html_lib
import json
import logging
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
    )


def _ytdlp_video(url: str, into: Path, timeout: int = 240) -> Optional[Path]:
    """Try to download a video. Returns Path on success, None on any failure (caller may fall back)."""
    for browser in ("chrome", "firefox"):
        cmd = [
            *YTDLP_CMD,
            "--cookies-from-browser", browser,
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
    for browser in ("chrome", "firefox"):
        cmd = [
            *GALLERY_DL_CMD,
            "--cookies-from-browser", browser,
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
    )


def process_note(item_id: int, text: str) -> None:
    g = gemini.gist_text(text)
    db.mark_done(
        item_id,
        kind="text",
        summary=g.get("summary"),
        category=g.get("category"),
        key_takeaways=g.get("key_takeaways") or [],
    )


def process_tweet(item_id: int, url: str, note: Optional[str]) -> None:
    text, author = _twitter_oembed(url)
    with tempfile.TemporaryDirectory(prefix="savefeed-tw-") as td:
        mp4 = _ytdlp_video(url, Path(td), timeout=45)
        if mp4 is not None:
            g = gemini.gist_video(mp4)
            kind = "video"
        elif text:
            g = gemini.gist_text(text)
            kind = "post"
        else:
            raise RuntimeError(f"no video via yt-dlp and no text via oEmbed for {url}")

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
    )


def _twitter_oembed(url: str) -> tuple[str, Optional[str]]:
    """Fetch a tweet's text + author via Twitter's public oEmbed endpoint."""
    try:
        with httpx.Client(timeout=15, follow_redirects=True) as cx:
            r = cx.get(OEMBED_URL, params={"url": url, "omit_script": "true"})
    except httpx.HTTPError as e:
        log.warning("oEmbed fetch failed for %s: %s", url, e)
        return "", None
    if r.status_code != 200:
        log.warning("oEmbed %s returned %s for %s", OEMBED_URL, r.status_code, url)
        return "", None
    try:
        data = r.json()
    except json.JSONDecodeError:
        return "", None
    text = _strip_oembed_html(data.get("html") or "")
    return text, data.get("author_name")


def _strip_oembed_html(blob: str) -> str:
    m = re.search(r"<p[^>]*>(.*?)</p>", blob, re.DOTALL)
    if not m:
        return ""
    inner = m.group(1)
    inner = re.sub(r"<br\s*/?>", "\n", inner, flags=re.IGNORECASE)
    inner = re.sub(r"<[^>]+>", "", inner)
    return html_lib.unescape(inner).strip().rstrip("…").strip()
