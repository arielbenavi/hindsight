#!/usr/bin/env python3
"""Build the `posts[]` part of a data-contract file (docs/data-contract.md) from a seed.

Deterministic: no LLM. Extraction (topics[], items[]) is added later by merge.py.

    build_posts.py ig-export <dir> <out.json> --handle reut_rabin
    build_posts.py seed-md   <file> <out.json> --handle pudabeats
"""
import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

HASHTAG = re.compile(r"#([\w֐-׿가-힯]+)", re.UNICODE)
MENTION = re.compile(r"(?<![\w.])@([A-Za-z0-9._]{1,30}[A-Za-z0-9_])")


def fix_text(s):
    """Instagram exports escape UTF-8 bytes as Latin-1 characters (see data/README.md)."""
    if s is None:
        return None
    try:
        s = s.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    s = s.strip()
    return s or None


def shortcode(url):
    parts = [p for p in url.split("?")[0].split("/") if p]
    return parts[-1]


def kind_for(url):
    if "/reel/" in url or "/reels/" in url:
        return "reel"
    if "/p/" in url:
        return "post"
    if "/tv/" in url:
        return "video"
    return "unknown"


def hashtags(caption):
    seen = []
    for h in HASHTAG.findall(caption or ""):
        h = h.lower()
        if h not in seen:
            seen.append(h)
    return seen


def mentions(caption, display_names):
    seen = []
    for m in MENTION.findall(caption or ""):
        m = m.lower().rstrip(".")
        if m not in [x["username"] for x in seen]:
            seen.append({"username": m, "display_name": display_names.get(m)})
    return seen


def iso(ts):
    return dt.datetime.fromtimestamp(ts, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def post(url, author, display, caption, collections, saved_at, source, display_names, language=None):
    return {
        "id": f"instagram:{shortcode(url)}",
        "platform": "instagram",
        "url": url,
        "kind": kind_for(url),
        "author": {"username": author, "display_name": display},
        "caption": caption,
        "hashtags": hashtags(caption),
        "mentions": mentions(caption, display_names),
        "collections": collections,
        "saved_at": saved_at,
        "posted_at": None,
        "thumbnail_url": None,
        "location_tag": None,
        "language": language,
        "on_screen_text": None,
        "transcript": None,
        "source": source,
    }


# ---------- Instagram "Download your information" export ----------

def lv_get(label_values, label):
    for x in label_values:
        if x.get("label") == label:
            return x.get("value")
    return None


def lv_section(label_values, title):
    for x in label_values:
        if x.get("title") == title and "dict" in x:
            return x["dict"]
    return []


def parse_media(label_values):
    url = lv_get(label_values, "URL")
    caption = fix_text(lv_get(label_values, "Caption"))
    owner = lv_section(label_values, "Owner")
    username = display = None
    if owner:
        o = owner[0]["dict"]
        username = fix_text(lv_get(o, "Username"))
        display = fix_text(lv_get(o, "Name"))
    return url, caption, username, display


def build_ig_export(folder):
    folder = Path(folder)
    by_id = {}
    order = []

    def upsert(url, caption, username, display, ts, collection):
        pid = f"instagram:{shortcode(url)}"
        if pid not in by_id:
            by_id[pid] = dict(url=url, caption=caption, username=username, display=display, ts=ts, collections=[])
            order.append(pid)
        rec = by_id[pid]
        rec["caption"] = rec["caption"] or caption
        rec["username"] = rec["username"] or username
        rec["display"] = rec["display"] or display
        if ts and (not rec["ts"] or ts > rec["ts"]):
            rec["ts"] = ts
        if collection and collection not in rec["collections"]:
            rec["collections"].append(collection)

    for item in json.loads((folder / "saved_posts.json").read_text()):
        url, caption, username, display = parse_media(item["label_values"])
        if url:
            upsert(url, caption, username, display, item.get("timestamp"), None)

    for col in json.loads((folder / "saved_collections.json").read_text()):
        lv = col["label_values"]
        name = fix_text(lv_get(lv, "Name"))
        for x in lv:
            if "dict" not in x or x.get("title") != "Media":
                continue
            for media in x["dict"]:
                inner = media.get("dict", [])
                url, caption, username, display = parse_media(inner)
                if url:
                    # Collection entries carry no per-post save time; the collection's
                    # update time is an upper bound, used only when nothing better exists.
                    upsert(url, caption, username, display, None, name)
        # the collection's own timestamp as a fallback for posts with none
        for pid in order:
            rec = by_id[pid]
            if name in rec["collections"] and not rec["ts"]:
                rec["ts_fallback"] = max(rec.get("ts_fallback") or 0, col.get("timestamp") or 0)

    display_names = {r["username"].lower(): r["display"] for r in by_id.values() if r["username"] and r["display"]}
    posts = []
    for pid in order:
        r = by_id[pid]
        ts = r["ts"] or r.get("ts_fallback")
        posts.append(post(r["url"], (r["username"] or "unknown").lower(), r["display"], r["caption"],
                          r["collections"], iso(ts) if ts else None, "ig_export", display_names))
    posts.sort(key=lambda p: p["saved_at"] or "", reverse=True)
    return posts, ["instagram"]


# ---------- Muse seed markdown (data/ig-saved-posts-seed.md) ----------

ENTRY = re.compile(r"^\d+\.\s+\*\*@([^*]+)\*\*\s+·\s+(\w+)\s+·\s+(\d{4}-\d{2}-\d{2})\s*$")


def build_seed_md(path):
    lines = Path(path).read_text().splitlines()
    posts, cur = [], None

    def flush():
        if cur and cur["url"]:
            caption = "\n".join(cur["caption"]).strip() or None
            # The seed dates look like post dates; kept as `saved_at` only as the best we have.
            posts.append(post(cur["url"], cur["author"].lower(), None, caption, [], cur["date"], "seed_md", {}))

    for line in lines:
        m = ENTRY.match(line)
        if m:
            flush()
            cur = {"author": m.group(1), "date": m.group(3), "caption": [], "url": None}
            continue
        if cur is None:
            continue
        s = line.strip()
        if s.startswith("https://www.instagram.com/"):
            cur["url"] = s
        elif s:
            cur["caption"].append(s)
    flush()
    return posts, ["instagram"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("format", choices=["ig-export", "seed-md"])
    ap.add_argument("source")
    ap.add_argument("out")
    ap.add_argument("--handle", required=True)
    a = ap.parse_args()
    posts, platforms = build_ig_export(a.source) if a.format == "ig-export" else build_seed_md(a.source)
    seen = set()
    posts = [p for p in posts if not (p["id"] in seen or seen.add(p["id"]))]
    doc = {
        "contract_version": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "user": {"handle": a.handle, "platforms": platforms},
        "posts": posts,
        "topics": [],
        "items": [],
    }
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    print(f"{a.out}: {len(posts)} posts", file=sys.stderr)


if __name__ == "__main__":
    main()
