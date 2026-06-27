#!/usr/bin/env python3
"""Import messages from a WhatsApp chat-with-self export (.txt).

Usage:
    python scripts/import_whatsapp.py <path_to_txt>

The script auto-detects the timestamp format from the file, parses
messages, classifies URLs by domain, dedupes against the DB, asks
for confirmation, then ingests via /capture.
"""
from __future__ import annotations

import re
import sys
import time
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import httpx

API = "http://localhost:8000"

# ── parsing ──────────────────────────────────────────────────────

SYSTEM_MARKERS = (
    "end-to-end encrypted",
    "created group",
    "changed the subject",
    "added you",
    "removed you",
    "changed this group",
    "changed the group",
    "left",
    "joined using",
    "security code changed",
    "messages and calls are",
    "you were added",
)

MEDIA_PLACEHOLDER = re.compile(r"<media omitted>|<attached:", re.IGNORECASE)
URL_RE = re.compile(r"https?://\S+")


def _detect_timestamp_re(lines: list[str]) -> re.Pattern:
    """Build a timestamp regex from the first few lines of the file."""
    patterns = [
        # DD/MM/YYYY, HH:MM - or DD/MM/YY, HH:MM -
        re.compile(r"^(\d{1,2}/\d{1,2}/\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\s*[-–]\s"),
        # [DD/MM/YYYY, HH:MM:SS] or [MM/DD/YY, HH:MM:SS]
        re.compile(r"^\[(\d{1,2}/\d{1,2}/\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\]\s"),
        # YYYY-MM-DD HH:MM -
        re.compile(r"^(\d{4}-\d{2}-\d{2},?\s+\d{1,2}:\d{2}(?::\d{2})?)\s*[-–]\s"),
        # DD.MM.YYYY, HH:MM -
        re.compile(r"^(\d{1,2}\.\d{1,2}\.\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\s*[-–]\s"),
    ]
    for line in lines[:50]:
        for pat in patterns:
            if pat.match(line):
                return pat
    print("ERROR: could not detect timestamp format from first 50 lines.", file=sys.stderr)
    print("First 5 lines:", file=sys.stderr)
    for line in lines[:5]:
        print(f"  {line!r}", file=sys.stderr)
    sys.exit(1)


def _parse_messages(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    if not lines:
        print("ERROR: file is empty", file=sys.stderr)
        sys.exit(1)

    ts_re = _detect_timestamp_re(lines)
    messages: list[dict] = []

    for line in lines:
        m = ts_re.match(line)
        if m:
            rest = line[m.end():]
            colon_pos = rest.find(": ")
            if colon_pos == -1:
                body = rest
            else:
                body = rest[colon_pos + 2:]
            messages.append({"timestamp": m.group(1).strip(), "text": body})
        elif messages:
            messages[-1]["text"] += "\n" + line

    return messages


def _is_system_or_skip(msg: dict) -> bool:
    text = msg["text"].strip().lower()
    if len(text) < 10:
        return True
    if MEDIA_PLACEHOLDER.search(text):
        return True
    if any(marker in text for marker in SYSTEM_MARKERS):
        return True
    return False


def _classify(text: str) -> tuple[str, Optional[str]]:
    m = URL_RE.search(text)
    if not m:
        return "note", None
    url = m.group(0).rstrip(".,;)\"'")
    host = (urlparse(url).hostname or "").lower()
    path = urlparse(url).path.lower()
    if "instagram.com" in host and any(seg in path for seg in ("/reel/", "/reels/", "/p/")):
        return "ig_reel", url
    if host in {"x.com", "twitter.com"} or host.endswith(".x.com") or host.endswith(".twitter.com"):
        return "tweet", url
    if "instagram.com" in host:
        return "ig_reel", url
    return "web", url


# ── ingestion ────────────────────────────────────────────────────

def _capture(payload: str, note: Optional[str] = None) -> dict:
    body: dict = {"payload": payload}
    if note:
        body["note"] = note
    with httpx.Client(timeout=30) as cx:
        r = cx.post(f"{API}/capture", json=body)
        r.raise_for_status()
        return r.json()


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path_to_whatsapp_export.txt>")
        sys.exit(1)

    path = Path(sys.argv[1]).expanduser()
    if not path.is_file():
        print(f"ERROR: {path} not found", file=sys.stderr)
        sys.exit(1)

    print(f"Parsing {path} ...")
    all_msgs = _parse_messages(path)
    print(f"  Total lines parsed: {len(all_msgs)}")

    msgs = [m for m in all_msgs if not _is_system_or_skip(m)]
    print(f"  After filtering system/short/media: {len(msgs)}")

    items: list[dict] = []
    for m in msgs:
        source, url = _classify(m["text"])
        items.append({"source": source, "url": url, "text": m["text"], "timestamp": m["timestamp"]})

    by_source: dict[str, int] = {}
    for it in items:
        by_source[it["source"]] = by_source.get(it["source"], 0) + 1

    # Dedupe against DB
    with httpx.Client(timeout=30) as cx:
        existing = cx.get(f"{API}/items").json()
    existing_urls = {r.get("source_url") for r in existing if r.get("source_url")}
    existing_texts = {(r.get("raw_text") or "")[:200] for r in existing if r.get("source") == "note"}

    deduped: list[dict] = []
    skipped_dupes = 0
    for it in items:
        if it["url"] and it["url"] in existing_urls:
            skipped_dupes += 1
            continue
        if it["source"] == "note" and it["text"][:200] in existing_texts:
            skipped_dupes += 1
            continue
        deduped.append(it)

    print(f"\n  Breakdown: {by_source}")
    print(f"  Already in DB (deduped): {skipped_dupes}")
    print(f"  New items to ingest: {len(deduped)}")

    if not deduped:
        print("\nNothing new to import.")
        return

    confirm = input(f"\nIngest {len(deduped)} items? [y/N] ").strip().lower()
    if confirm != "y":
        print("Aborted.")
        return

    processed = 0
    failed = 0
    for i, it in enumerate(deduped):
        payload = it["url"] if it["url"] else it["text"]
        try:
            result = _capture(payload)
            status = "deduped" if result.get("deduped") else result.get("status", "?")
            processed += 1
        except Exception as e:
            print(f"  FAILED #{i+1}: {e}")
            failed += 1
            status = "error"

        if (i + 1) % 5 == 0 or i == len(deduped) - 1:
            print(f"  Progress: {i+1}/{len(deduped)} (ok={processed}, fail={failed})")

        delay = 3 if it["source"] == "note" else 10
        if i < len(deduped) - 1:
            time.sleep(delay)

    print(f"\nDone. Processed: {processed}, Failed: {failed}")


if __name__ == "__main__":
    main()
