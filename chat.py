"""RAG chat — retrieve relevant items via embeddings, generate grounded response via Gemini."""
from __future__ import annotations

import logging
from typing import Any

from google import genai
from google.genai import types

import embeddings

log = logging.getLogger("savefeed.chat")

MODEL = "gemini-2.5-flash"

SYSTEM_PROMPT = (
    "You are a helpful assistant that answers questions about the user's saved social media content. "
    "You will be given relevant items from their saved collection. Use ONLY the provided context to answer. "
    "If the context doesn't contain enough info, say so. Be concise. "
    "Reference specific items by their ID when relevant (e.g. 'Item #42')."
)


def _format_context(items: list[dict[str, Any]]) -> str:
    parts = []
    for item in items:
        lines = [f"--- Item #{item['id']} ({item.get('source', '?')}, {item.get('category', '?')}) ---"]
        if item.get("summary"):
            lines.append(f"Summary: {item['summary']}")
        kts = item.get("key_takeaways")
        if kts and isinstance(kts, list):
            lines.append("Takeaways: " + "; ".join(kts))
        tags = item.get("tags")
        if tags and isinstance(tags, list):
            lines.append("Tags: " + ", ".join(tags))
        if item.get("on_screen_text"):
            lines.append(f"Text: {item['on_screen_text'][:300]}")
        parts.append("\n".join(lines))
    return "\n\n".join(parts)


def answer(message: str, history: list[dict[str, str]] | None = None) -> dict[str, Any]:
    results = embeddings.search(message, top_k=5)
    if not results:
        return {
            "response": "I don't have any embedded content to search through yet. Try generating embeddings first.",
            "sources": [],
        }
    context = _format_context(results)
    prompt = f"Context from user's saved items:\n\n{context}\n\nUser question: {message}"
    contents = []
    if history:
        for msg in history[-6:]:
            role = "user" if msg.get("role") == "user" else "model"
            contents.append(types.Content(role=role, parts=[types.Part.from_text(text=msg.get("text", ""))]))
    contents.append(types.Content(role="user", parts=[types.Part.from_text(text=prompt)]))
    client = genai.Client()
    response = client.models.generate_content(
        model=MODEL,
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            temperature=0.3,
            max_output_tokens=1024,
        ),
    )
    return {
        "response": response.text or "No response generated.",
        "sources": [r["id"] for r in results],
    }
