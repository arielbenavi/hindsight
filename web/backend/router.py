"""Classify an incoming payload into (source, url)."""
from __future__ import annotations

import re
from typing import Optional
from urllib.parse import urlparse

URL_RE = re.compile(r"https?://\S+")


def first_url(text: str) -> Optional[str]:
    m = URL_RE.search(text or "")
    if not m:
        return None
    return m.group(0).rstrip(".,;)\"'")


def classify(payload: str) -> tuple[str, Optional[str]]:
    """Returns (source, url_or_None) — source is one of ig_reel|tweet|tiktok|facebook|web|note."""
    url = first_url(payload)
    if not url:
        return "note", None
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    path = parsed.path.lower()
    if "instagram.com" in host and any(seg in path for seg in ("/reel/", "/reels/", "/p/")):
        return "ig_reel", url
    if host in {"x.com", "twitter.com"} or host.endswith(".x.com") or host.endswith(".twitter.com"):
        return "tweet", url
    if "tiktok.com" in host or host == "vm.tiktok.com":
        return "tiktok", url
    if "facebook.com" in host or "fb.watch" in host or host == "fb.com":
        return "facebook", url
    return "web", url
