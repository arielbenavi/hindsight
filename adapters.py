"""Per-source adapters. Each turns a pending row into a done (or failed) row."""
from __future__ import annotations

import logging
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

import trafilatura

import db
import gemini

log = logging.getLogger("savefeed.adapters")

YTDLP_CMD = [sys.executable, "-m", "yt_dlp"]


def process_ig_reel(item_id: int, url: str) -> None:
    with tempfile.TemporaryDirectory(prefix="savefeed-ig-") as td:
        mp4 = _ytdlp_download(url, Path(td))
        g = gemini.gist_video(mp4)
    db.mark_done(
        item_id,
        kind="video",
        summary=g.get("summary"),
        on_screen_text=g.get("on_screen_text"),
        transcript=g.get("spoken_transcript"),
        category=g.get("category"),
        key_takeaways=g.get("key_takeaways") or [],
    )


def _ytdlp_download(url: str, into: Path) -> Path:
    last_err = ""
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
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
        except subprocess.TimeoutExpired:
            last_err = f"yt-dlp timed out after 240s ({browser})"
            continue
        if r.returncode == 0:
            lines = r.stdout.strip().splitlines()
            if lines and Path(lines[-1]).exists():
                return Path(lines[-1])
        last_err = f"yt-dlp exit {r.returncode} ({browser}) stderr: {r.stderr[-800:]}"
        log.warning(last_err)
    raise RuntimeError(f"yt-dlp failed (chrome+firefox). last: {last_err}")


def process_web(item_id: int, url: str) -> None:
    html = trafilatura.fetch_url(url)
    if not html:
        raise RuntimeError(f"trafilatura fetch returned nothing for {url}")
    text = trafilatura.extract(html) or ""
    if not text.strip():
        raise RuntimeError("trafilatura extracted empty text")
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
    """Stub: no fetch, no gist — just record."""
    db.mark_done(item_id, kind="post", raw_text=note)
