"""Gemini Files API + text gist helpers. Model: gemini-3.5-flash."""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Optional

from google import genai
from google.genai import types

MODEL = "gemini-3.5-flash"

VIDEO_PROMPT = """\
You are analyzing a short video (e.g. an Instagram reel). Return ONLY a JSON object (no code fences, no prose) with these keys:
- summary: <= 40 words
- spoken_transcript: full transcript of any speech (empty string if has_speech is false)
- on_screen_text: ALL visible text overlays / captions / signs. Many reels are silent text-overlay videos — read overlays carefully even when has_speech is false.
- category: one short label (e.g. "comedy", "cooking", "fitness", "news", "education")
- key_takeaways: array of 1-5 short strings
- has_speech: boolean
"""

TEXT_PROMPT_HEADER = """\
Return ONLY a JSON object (no code fences, no prose) with these keys:
- summary: <= 40 words
- category: one short label (e.g. "tech", "finance", "politics", "personal", "science")
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


def _generate(contents: list[Any]) -> dict[str, Any]:
    c = client()
    cfg = types.GenerateContentConfig(response_mime_type="application/json")
    last: Optional[Exception] = None
    for attempt in range(3):
        try:
            resp = c.models.generate_content(model=MODEL, contents=contents, config=cfg)
            return json.loads(resp.text)
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


def gist_text(text: str) -> dict[str, Any]:
    return _generate([TEXT_PROMPT_HEADER + text])
