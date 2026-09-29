#!/usr/bin/env python3
"""Import saved posts from an Instagram data export (JSON or ZIP).

Usage:
    python scripts/import_ig_export.py <path_to_json_or_zip>

Instagram's data download contains saved post URLs in a JSON file.
This script finds the saved-posts JSON, extracts URLs, dedupes
against the DB, and ingests via /capture.

If you haven't exported yet:
    Settings → Privacy and Security → Download Your Information →
    Request Download → select "Saved" → JSON format.
    Instagram will email you a zip file.
"""
from __future__ import annotations

import json
import sys
import tempfile
import time
import zipfile
from pathlib import Path
from typing import Any

import httpx

API = "http://localhost:8000"
BACKFILL_CAP = 200


def _find_saved_json_in_dir(root: Path) -> Path | None:
    """Walk a directory for the saved-posts JSON file."""
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


def _extract_urls(data: Any) -> list[str]:
    """Pull URLs from IG export JSON. Structure varies by export version."""
    urls: list[str] = []

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


def _url_from_item(item: Any) -> str | None:
    """Extract a URL from a single saved-item dict."""
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


def _capture(url: str) -> dict:
    with httpx.Client(timeout=30) as cx:
        r = cx.post(f"{API}/capture", json={"payload": url})
        r.raise_for_status()
        return r.json()


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path_to_json_or_zip>")
        print("\nIf you haven't exported yet:")
        print("  Settings → Privacy and Security → Download Your Information →")
        print("  Request Download → select 'Saved' → JSON format.")
        sys.exit(1)

    src = Path(sys.argv[1]).expanduser()
    if not src.is_file():
        print(f"ERROR: {src} not found", file=sys.stderr)
        sys.exit(1)

    if src.suffix.lower() == ".zip":
        print(f"Extracting {src} ...")
        tmpdir = tempfile.mkdtemp(prefix="savefeed-ig-export-")
        with zipfile.ZipFile(src) as zf:
            zf.extractall(tmpdir)
        json_path = _find_saved_json_in_dir(Path(tmpdir))
        if not json_path:
            print("ERROR: could not find a saved-posts JSON in the zip.", file=sys.stderr)
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
    data = json.loads(json_path.read_text(encoding="utf-8"))
    urls = _extract_urls(data)
    print(f"  Found {len(urls)} saved post URLs")

    if not urls:
        print("\nNo URLs found. File structure:")
        if isinstance(data, dict):
            for k, v in data.items():
                vtype = type(v).__name__
                vlen = len(v) if isinstance(v, (list, dict)) else ""
                print(f"  {k}: {vtype} {vlen}")
        elif isinstance(data, list):
            print(f"  top-level list, {len(data)} items")
            if data:
                print(f"  first item keys: {list(data[0].keys()) if isinstance(data[0], dict) else type(data[0])}")
        sys.exit(1)

    # Dedupe against DB
    with httpx.Client(timeout=30) as cx:
        existing = cx.get(f"{API}/items").json()
    existing_urls = {r.get("source_url") for r in existing if r.get("source_url")}

    new_urls = [u for u in urls if u not in existing_urls]
    print(f"  Already in DB (deduped): {len(urls) - len(new_urls)}")
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
            status = "deduped" if result.get("deduped") else result.get("status", "?")
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
