#!/usr/bin/env python3
"""Merge the per-post extraction batches into one contract file (docs/data-contract.md).

    merge.py <user>      reads work/<user>.posts.json, extraction/<user>-*.json and
                         tools/topics-<user>.json; writes <user>.hindsight.json

The topics file is the consolidation pass: it maps the extraction's free-form
`topic_hint`s onto a small set of named topics, per lego screen. Posts whose
(hint, screen) isn't mapped fall back to the screen's default topic.

Rules applied here (from the specs):
- fitness posts under the threshold (< 5) move to learn, using their `tip`
- each post is in exactly one topic; every non-`none` post has exactly one item
- items carry only the fields of their own lego screen
"""
import glob
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FITNESS_MIN = 5


def main(user):
    doc = json.loads((ROOT / f"work/{user}.posts.json").read_text())
    cfg = json.loads((ROOT / f"tools/topics-{user}.json").read_text())
    rows = {}
    for f in sorted(glob.glob(str(ROOT / f"extraction/{user}-*.json"))):
        for r in json.loads(Path(f).read_text()):
            rows[r["post_id"]] = r

    posts = doc["posts"]
    missing = [p["id"] for p in posts if p["id"] not in rows]
    if missing:
        sys.exit(f"{len(missing)} posts have no extraction, e.g. {missing[:3]}")

    fitness_count = sum(1 for r in rows.values() if r["lego_screen"] == "fitness")
    fitness_to_learn = fitness_count < FITNESS_MIN

    topics = {tid: dict(t, id=tid, post_ids=[]) for tid, t in cfg["topics"].items()}
    items = []
    for p in posts:
        r = rows[p["id"]]
        screen = r["lego_screen"]
        if screen == "fitness" and fitness_to_learn:
            screen = "learn"
        if screen == "learn" and not r.get("tip"):
            screen = "none"  # nothing to show
        tid = topic_for(cfg, r, screen)
        if topics[tid]["lego_screen"] != screen:
            sys.exit(f"{p['id']}: topic {tid} is {topics[tid]['lego_screen']}, post is {screen}")
        topics[tid]["post_ids"].append(p["id"])
        if screen == "none":
            continue
        item = {"post_id": p["id"], "lego_screen": screen, "topic_id": tid}
        key = {"map": "places", "learn": "tip", "fitness": "routine"}[screen]
        item[key] = clean(r[key])
        items.append(item)

    by_id = {p["id"]: p for p in posts}
    item_by_post = {i["post_id"]: i for i in items}
    out_topics = []
    for tid, t in topics.items():
        if not t["post_ids"]:
            continue
        out_topics.append({
            "id": tid,
            "label": t["label"],
            "emoji": t.get("emoji"),
            "lego_screen": t["lego_screen"],
            "confidence": t.get("confidence", "high"),
            "post_ids": t["post_ids"],
            "sample_post_ids": samples(t["post_ids"], by_id, item_by_post),
            "source_collections": source_collections(t["post_ids"], by_id),
            "ambiguity": t.get("ambiguity"),
        })

    doc["topics"] = out_topics
    doc["items"] = items
    out = ROOT / f"{user}.hindsight.json"
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    print(f"{out.name}: {len(posts)} posts, {len(out_topics)} topics, {len(items)} items"
          + (f" (fitness {fitness_count} < {FITNESS_MIN} → learn)" if fitness_to_learn and fitness_count else ""))


def topic_for(cfg, r, screen):
    hint = r.get("topic_hint") or ""
    if screen == "fitness" and "fitness_by_goal" in cfg:
        return cfg["fitness_by_goal"].get(r["routine"]["goal"], cfg["defaults"]["fitness"])
    mapped = cfg.get("map", {}).get(screen, {}).get(hint)
    return mapped or cfg["defaults"][screen]


def clean(value):
    """Contract rule: never "" as a stand-in for unknown."""
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    if isinstance(value, list):
        return [clean(v) for v in value if v != ""]
    if value == "":
        return None
    return value


def samples(ids, by_id, item_by_post, n=3):
    def score(pid):
        item = item_by_post.get(pid, {})
        tip = item.get("tip") or item.get("routine") or {}
        thin = tip.get("is_thin", False)
        places = item.get("places")
        return (thin, places == [], not by_id[pid]["caption"])
    return sorted(ids, key=score)[:n]


def source_collections(ids, by_id):
    counts = {}
    for pid in ids:
        for c in by_id[pid]["collections"]:
            counts[c] = counts.get(c, 0) + 1
    # a collection counts when at least a third of the topic came from it
    return [c for c, n in sorted(counts.items(), key=lambda x: -x[1]) if n * 3 >= len(ids)]


if __name__ == "__main__":
    main(sys.argv[1])
