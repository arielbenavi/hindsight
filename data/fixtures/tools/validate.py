#!/usr/bin/env python3
"""Check a contract file against docs/data-contract.md. Exit 1 on any error.

    validate.py <file.hindsight.json> [...]
"""
import json
import re
import sys

ENUMS = {
    "platform": {"instagram", "facebook", "x", "tiktok"},
    "kind": {"reel", "post", "carousel", "video", "tweet", "unknown"},
    "source": {"muse", "ig_export", "fb_export", "tiktok_export", "x_api", "seed_md"},
    "topic_screen": {"map", "learn", "fitness", "none"},
    "item_screen": {"map", "learn", "fitness"},
    "confidence": {"high", "low"},
    "place_type": {"food", "cafe", "bakery", "bar", "other"},
    "evidence_kind": {"location_tag", "pin_emoji", "mention", "address", "plain_text", "collection_only"},
    "tip_type": {"tool", "technique", "tutorial", "list", "idea"},
    "body_area": {"neck", "shoulders", "upper_back", "lower_back", "hips", "knees", "ankles", "core", "full_body"},
    "goal": {"pain_relief", "mobility", "posture", "strength", "recovery"},
    "equipment": {"none", "mat", "band", "foam_roller", "dumbbell", "other"},
}
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2}))?$")


def validate(path):
    errors, warnings = [], []
    doc = json.load(open(path))

    def err(msg):
        errors.append(msg)

    def no_empty_strings(value, where):
        if value == "":
            err(f'{where}: "" (use null)')
        elif isinstance(value, dict):
            for k, v in value.items():
                if k != k.lower() or " " in k:
                    err(f"{where}.{k}: key not snake_case")
                no_empty_strings(v, f"{where}.{k}")
        elif isinstance(value, list):
            for i, v in enumerate(value):
                no_empty_strings(v, f"{where}[{i}]")

    no_empty_strings(doc, "$")
    if doc.get("contract_version") != 1:
        err("contract_version must be 1")

    posts = {}
    for p in doc["posts"]:
        pid = p["id"]
        if pid in posts:
            err(f"duplicate post id {pid}")
        posts[pid] = p
        if not pid.startswith(p["platform"] + ":"):
            err(f"{pid}: id must be <platform>:<shortcode>")
        for field, enum in (("platform", "platform"), ("kind", "kind"), ("source", "source")):
            if p[field] not in ENUMS[enum]:
                err(f"{pid}: bad {field} {p[field]!r}")
        for field in ("saved_at", "posted_at"):
            if p.get(field) is not None and not DATE.match(p[field]):
                err(f"{pid}: bad {field} {p[field]!r}")
        for h in p["hashtags"]:
            if h.startswith("#") or h != h.lower():
                err(f"{pid}: hashtag {h!r} must be lowercase without #")

    topic_of = {}
    topics = {}
    for t in doc["topics"]:
        topics[t["id"]] = t
        if t["lego_screen"] not in ENUMS["topic_screen"]:
            err(f"topic {t['id']}: bad lego_screen")
        if t["confidence"] not in ENUMS["confidence"]:
            err(f"topic {t['id']}: bad confidence")
        for pid in t["post_ids"]:
            if pid not in posts:
                err(f"topic {t['id']}: unknown post {pid}")
            if pid in topic_of:
                err(f"{pid} is in two topics ({topic_of[pid]}, {t['id']})")
            topic_of[pid] = t["id"]
        for pid in t["sample_post_ids"]:
            if pid not in t["post_ids"]:
                err(f"topic {t['id']}: sample {pid} not in topic")
        if not 1 <= len(t["sample_post_ids"]) <= 5:
            err(f"topic {t['id']}: needs 1–5 samples")
        amb = t.get("ambiguity")
        if amb:
            for o in amb["options"]:
                if o["lego_screen"] not in ENUMS["topic_screen"]:
                    err(f"topic {t['id']}: ambiguity option bad lego_screen")
    for pid in posts:
        if pid not in topic_of:
            err(f"{pid}: in no topic")
    if sum(1 for t in doc["topics"] if t.get("ambiguity")) > 2:
        warnings.append("more than 2 ambiguity questions (the chat asks only the top 2)")

    seen_items = set()
    for it in doc["items"]:
        pid = it["post_id"]
        where = f"item {pid}"
        if pid in seen_items:
            err(f"{where}: duplicate item")
        seen_items.add(pid)
        if pid not in posts:
            err(f"{where}: unknown post")
            continue
        screen = it["lego_screen"]
        if screen not in ENUMS["item_screen"]:
            err(f"{where}: bad lego_screen")
        t = topics.get(it["topic_id"])
        if not t or topic_of.get(pid) != it["topic_id"]:
            err(f"{where}: topic_id doesn't match the post's topic")
        elif t["lego_screen"] != screen:
            err(f"{where}: lego_screen differs from its topic's")
        keys = {"places", "tip", "routine"} & set(it)
        want = {"map": "places", "learn": "tip", "fitness": "routine"}.get(screen)
        if keys != {want}:
            err(f"{where}: must carry exactly `{want}`, has {sorted(keys)}")
            continue
        if screen == "map":
            caption = posts[pid]["caption"] or ""
            for i, pl in enumerate(it["places"]):
                w = f"{where}.places[{i}]"
                if not pl.get("name"):
                    err(f"{w}: no name")
                if pl["type"] not in ENUMS["place_type"]:
                    err(f"{w}: bad type {pl['type']!r}")
                if pl["evidence_kind"] not in ENUMS["evidence_kind"]:
                    err(f"{w}: bad evidence_kind")
                if pl["confidence"] not in ENUMS["confidence"]:
                    err(f"{w}: bad confidence")
                if pl.get("reason") and len(pl["reason"]) > 60:
                    warnings.append(f"{w}: reason > 60 chars")
                if pl["evidence_kind"] != "collection_only" and pl["evidence"] not in caption:
                    warnings.append(f"{w}: evidence not verbatim in caption")
        elif screen == "learn":
            tip = it["tip"]
            if tip["tip_type"] not in ENUMS["tip_type"]:
                err(f"{where}: bad tip_type")
            if len(tip["title"]) > 60:
                warnings.append(f"{where}: title > 60")
            if tip.get("gist") and len(tip["gist"]) > 140:
                warnings.append(f"{where}: gist > 140")
            if tip.get("try_prompt") and len(tip["try_prompt"]) > 100:
                warnings.append(f"{where}: try_prompt > 100")
            if tip["is_thin"] and tip.get("try_prompt"):
                err(f"{where}: thin tip has a try_prompt")
            if not tip["is_thin"] and not tip.get("try_prompt"):
                warnings.append(f"{where}: not thin but no try_prompt")
            if len(tip["key_points"]) > 5:
                err(f"{where}: > 5 key_points")
        elif screen == "fitness":
            r = it["routine"]
            if not r["body_areas"] or any(a not in ENUMS["body_area"] for a in r["body_areas"]):
                err(f"{where}: bad body_areas")
            if r["goal"] not in ENUMS["goal"]:
                err(f"{where}: bad goal")
            if any(e not in ENUMS["equipment"] for e in r["equipment"]):
                err(f"{where}: bad equipment")
            if len(r["title"]) > 40:
                warnings.append(f"{where}: title > 40")
            if r["is_thin"] and r.get("do_prompt"):
                err(f"{where}: thin routine has a do_prompt")

    for pid, tid in topic_of.items():
        if topics[tid]["lego_screen"] != "none" and pid not in seen_items:
            err(f"{pid}: in {topics[tid]['lego_screen']} topic {tid} but has no item")
        if topics[tid]["lego_screen"] == "none" and pid in seen_items:
            err(f"{pid}: in a none topic but has an item")

    print(f"{path}: {len(posts)} posts, {len(topics)} topics, {len(seen_items)} items, "
          f"{len(errors)} errors, {len(warnings)} warnings")
    for e in errors[:40]:
        print("  ERROR", e)
    for w in warnings[:15]:
        print("  warn ", w)
    if len(warnings) > 15:
        print(f"  … {len(warnings) - 15} more warnings")
    return not errors


if __name__ == "__main__":
    ok = all([validate(p) for p in sys.argv[1:]])
    sys.exit(0 if ok else 1)
