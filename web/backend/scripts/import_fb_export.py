#!/usr/bin/env python3
"""Import saved items from a Facebook data export (JSON or ZIP).

Usage:
    python scripts/import_fb_export.py <path_to_json_or_zip>

Facebook's data download includes saved items (links, posts, videos).
This script extracts URLs, skips marketplace/events, dedupes against
the DB, and ingests via /capture.

If you haven't exported yet:
    Settings → Your Facebook Information → Download Your Information →
    Saved Items and Collections → JSON format → Create File.
"""
from __future__ import annotations

import json
import sys
import tempfile
import time
import zipfile
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx

API = "http://localhost:8000"
BACKFILL_CAP = 200

SKIP_HOSTS = {
    "www.facebook.com/marketplace",
    "facebook.com/marketplace",
    "www.facebook.com/events",
    "facebook.com/events",
}

SKIP_PATTERNS = (
    "/marketplace/",
    "/events/",
    "/groups/",
    "/fundraisers/",
    "/gaming/",
)


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


def _extract_urls(data: Any) -> list[str]:
    """Pull external URLs from the FB export JSON."""
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


def _should_skip(url: str) -> bool:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    path = parsed.path.lower()
    if any(pat in path for pat in SKIP_PATTERNS):
        return True
    if host in ("l.facebook.com", "lm.facebook.com"):
        return False
    if "facebook.com" in host and "/posts/" not in path and "/videos/" not in path and "/photo" not in path:
        if "/permalink" not in path and "/story" not in path:
            return True
    return False


def _unwrap_fb_redirect(url: str) -> str:
    """Facebook wraps external links in l.facebook.com redirects."""
    parsed = urlparse(url)
    if parsed.hostname in ("l.facebook.com", "lm.facebook.com"):
        from urllib.parse import parse_qs
        qs = parse_qs(parsed.query)
        if "u" in qs:
            return qs["u"][0]
    return url


def _capture(url: str) -> dict:
    with httpx.Client(timeout=30) as cx:
        r = cx.post(f"{API}/capture", json={"payload": url})
        r.raise_for_status()
        return r.json()


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path_to_json_or_zip>")
        print("\nIf you haven't exported yet:")
        print("  Settings → Your Facebook Information → Download Your Information →")
        print("  Saved Items and Collections → JSON format → Create File.")
        sys.exit(1)

    src = Path(sys.argv[1]).expanduser()
    if not src.is_file():
        print(f"ERROR: {src} not found", file=sys.stderr)
        sys.exit(1)

    if src.suffix.lower() == ".zip":
        print(f"Extracting {src} ...")
        tmpdir = tempfile.mkdtemp(prefix="savefeed-fb-export-")
        with zipfile.ZipFile(src) as zf:
            zf.extractall(tmpdir)
        json_path = _find_saved_json_in_dir(Path(tmpdir))
        if not json_path:
            print("ERROR: could not find a saved-items JSON in the zip.", file=sys.stderr)
            print("Files in archive:", file=sys.stderr)
            for name in sorted(zipfile.ZipFile(src).namelist())[:30]:
                print(f"  {name}", file=sys.stderr)
            sys.exit(1)
        print(f"  Found: {json_path.relative_to(tmpdir)}")
    elif src.suffix.lower() == ".json":
        json_path = src
    else:
        print(f"ERROR: expected .json or .zip, got {src.suffix}", file=sys.stderr)
        sys.exit(1)

    print(f"Parsing {json_path.name} ...")
    raw = json_path.read_bytes()
    text = raw.decode("utf-8", errors="replace")
    data = json.loads(text)

    all_urls = _extract_urls(data)
    print(f"  Raw URLs found: {len(all_urls)}")

    unwrapped = [_unwrap_fb_redirect(u) for u in all_urls]
    filtered = [u for u in unwrapped if not _should_skip(u)]
    print(f"  After skipping marketplace/events/non-content: {len(filtered)}")

    if not filtered:
        print("\nNo importable URLs found. File structure:")
        if isinstance(data, dict):
            for k, v in data.items():
                vtype = type(v).__name__
                vlen = len(v) if isinstance(v, (list, dict)) else ""
                print(f"  {k}: {vtype} {vlen}")
        elif isinstance(data, list):
            print(f"  top-level list, {len(data)} items")
            if data:
                sample = data[0]
                print(f"  first item: {json.dumps(sample, ensure_ascii=False)[:200]}")
        sys.exit(1)

    # Dedupe against DB
    with httpx.Client(timeout=30) as cx:
        existing = cx.get(f"{API}/items").json()
    existing_urls = {r.get("source_url") for r in existing if r.get("source_url")}

    new_urls = [u for u in filtered if u not in existing_urls]
    print(f"  Already in DB (deduped): {len(filtered) - len(new_urls)}")
    print(f"  New items to ingest: {len(new_urls)}")

    if len(new_urls) > BACKFILL_CAP:
        print(f"  Capping at {BACKFILL_CAP} items (will continue on next run)")
        new_urls = new_urls[:BACKFILL_CAP]

    if not new_urls:
        print("\nNothing new to import.")
        return

    confirm = input(f"\nIngest {len(new_urls)} items? [y/N] ").strip().lower()
    if confirm != "y":
        print("Aborted.")
        return

    processed = 0
    failed = 0
    for i, url in enumerate(new_urls):
        try:
            result = _capture(url)
            processed += 1
        except Exception as e:
            print(f"  FAILED #{i+1}: {e}")
            failed += 1

        if (i + 1) % 5 == 0 or i == len(new_urls) - 1:
            print(f"  Progress: {i+1}/{len(new_urls)} (ok={processed}, fail={failed})")

        if i < len(new_urls) - 1:
            time.sleep(10)

    print(f"\nDone. Processed: {processed}, Failed: {failed}")


if __name__ == "__main__":
    main()
