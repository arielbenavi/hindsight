"""Gemini Files API + text/image gist helpers. Model: gemini-3.5-flash."""
from __future__ import annotations

import json
import mimetypes
import os
import time
from pathlib import Path
from typing import Any, Optional

from google import genai
from google.genai import types

MODEL = "gemini-3.5-flash"

ALLOWED_CATEGORIES = ["coding", "quant", "music", "life-hack", "productivity", "other"]
_CATEGORY_LIST_STR = ", ".join(ALLOWED_CATEGORIES)

VIDEO_PROMPT = f"""\
You are analyzing a short video (e.g. an Instagram reel). Return ONLY a JSON object (no code fences, no prose) with these keys:
- summary: <= 40 words
- spoken_transcript: full transcript of any speech (empty string if has_speech is false)
- on_screen_text: a single string with ALL visible text overlays / captions / signs, separated by newlines. Many reels are silent text-overlay videos — read overlays carefully even when has_speech is false.
- category: MUST be exactly one of [{_CATEGORY_LIST_STR}]. Pick "other" if nothing fits.
- key_takeaways: array of 1-5 short strings
- has_speech: boolean
"""

IMAGE_PROMPT = f"""\
You are analyzing an Instagram post carousel (a series of images, no video). Return ONLY a JSON object (no code fences, no prose) with these keys:
- summary: <= 40 words
- spoken_transcript: "" (carousels have no audio)
- on_screen_text: a single string with ALL visible text across the images, separated by newlines.
- category: MUST be exactly one of [{_CATEGORY_LIST_STR}]. Pick "other" if nothing fits.
- key_takeaways: array of 1-5 short strings
- has_speech: false
"""

TEXT_PROMPT_HEADER = f"""\
Return ONLY a JSON object (no code fences, no prose) with these keys:
- summary: <= 40 words
- category: MUST be exactly one of [{_CATEGORY_LIST_STR}]. Pick "other" if nothing fits.
- key_takeaways: array of 1-5 short strings

Text to summarize follows:
---
"""

_client: Optional[genai.Client] = None


def client() -> genai.Client:
    global _client
    if _client is None:
        key = os.environ.get("GEMINI_API_KEY")
        if not key:
            raise RuntimeError("GEMINI_API_KEY not set")
        _client = genai.Client(api_key=key)
    return _client


def _is_retryable(exc: Exception) -> bool:
    s = f"{type(exc).__name__}: {exc}"
    return any(code in s for code in ("503", "429", "500", "504", "UNAVAILABLE", "DEADLINE_EXCEEDED"))


def _coerce_str(v: Any, joiner: str = "\n") -> Optional[str]:
    if v is None:
        return None
    if isinstance(v, list):
        return joiner.join(str(x) for x in v if x is not None)
    if isinstance(v, dict):
        return json.dumps(v, ensure_ascii=False)
    return str(v)


def _normalize_category(c: Any) -> str:
    if not isinstance(c, str):
        return "other"
    c = c.strip().lower()
    return c if c in ALLOWED_CATEGORIES else "other"


def _normalize_result(result: dict[str, Any]) -> dict[str, Any]:
    for f in ("summary", "spoken_transcript", "on_screen_text"):
        if f in result:
            result[f] = _coerce_str(result[f])
    result["category"] = _normalize_category(result.get("category"))
    kt = result.get("key_takeaways")
    if isinstance(kt, str):
        result["key_takeaways"] = [kt]
    elif not isinstance(kt, list):
        result["key_takeaways"] = []
    return result


def _generate(contents: list[Any]) -> dict[str, Any]:
    c = client()
    cfg = types.GenerateContentConfig(response_mime_type="application/json")
    last: Optional[Exception] = None
    for attempt in range(3):
        try:
            resp = c.models.generate_content(model=MODEL, contents=contents, config=cfg)
            return _normalize_result(json.loads(resp.text))
        except Exception as e:
            last = e
            if not _is_retryable(e):
                raise
            time.sleep(2 ** attempt)
    raise last  # type: ignore[misc]


def gist_video(mp4: Path) -> dict[str, Any]:
    c = client()
    f = c.files.upload(file=str(mp4))
    deadline = time.time() + 180
    while f.state.name == "PROCESSING":
        if time.time() > deadline:
            raise RuntimeError("Gemini Files API processing timed out after 180s")
        time.sleep(2)
        f = c.files.get(name=f.name)
    if f.state.name != "ACTIVE":
        raise RuntimeError(f"Gemini Files API state: {f.state.name}")
    return _generate([f, VIDEO_PROMPT])


def gist_images(paths: list[Path]) -> dict[str, Any]:
    parts: list[Any] = []
    for p in paths:
        mt = mimetypes.guess_type(str(p))[0] or "image/jpeg"
        parts.append(types.Part.from_bytes(data=p.read_bytes(), mime_type=mt))
    parts.append(IMAGE_PROMPT)
    return _generate(parts)


def gist_text(text: str) -> dict[str, Any]:
    return _generate([TEXT_PROMPT_HEADER + text])
