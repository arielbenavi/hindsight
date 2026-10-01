"""Connector tests: normalization of Muse's field names, the shared ingest path,
get_sync_status, and the HTTP routes (MCP + /ingest + /saves). No network:
Starlette's TestClient talks to the app in-process, with a throwaway data dir."""

import importlib
import json
import os
import sys
from pathlib import Path

import pytest
from starlette.testclient import TestClient

TOKEN = "testtoken"
MCP_HEADERS = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}


@pytest.fixture()
def server(tmp_path, monkeypatch):
    monkeypatch.setenv("HINDSIGHT_CONNECTOR_DATA", str(tmp_path))
    monkeypatch.setenv("HINDSIGHT_CONNECTOR_TOKEN", TOKEN)
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    module = importlib.reload(importlib.import_module("server"))
    yield module


def mcp_call(client, name, arguments):
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": arguments}}
    res = client.post(f"/{TOKEN}/mcp", json=body, headers=MCP_HEADERS)
    assert res.status_code == 200, res.text
    return res.json()["result"]["structuredContent"]


def test_normalizes_muses_own_field_names(server):
    # The exact shape of Muse's first real send (2026-09-30).
    post = server.normalized({
        "platform": "instagram", "author": "Shadow Samples", "author_username": "shadowsamples",
        "media_permalink": "https://www.instagram.com/p/Dd3JtZugQcK/", "media_type": "VIDEO",
        "post_type": "post", "post_creation_time": "2026-09-28 23:48:12",
        "tagged_users": ["@someone"], "collections": ["Saved", "All posts", "NYC Restaurants"],
    })
    assert post["author"] == "shadowsamples"
    assert post["author_display_name"] == "Shadow Samples"
    assert post["url"] == "https://www.instagram.com/p/Dd3JtZugQcK/"
    assert post["posted_at"] == "2026-09-28 23:48:12"
    assert post["kind"] == "video"
    assert post["mentions"] == [{"username": "someone", "display_name": None}]
    assert post["collections"] == ["NYC Restaurants"]


def test_ids_match_the_app(server):
    assert server.post_id("https://www.instagram.com/reel/ABC/?igsh=x", None) == "instagram:ABC"
    assert server.post_id("https://x.com/a/status/42", None) == "x:42"
    assert server.post_id("https://example.com/a", "web") == "web:https://example.com/a"


def test_ingest_dedupes_and_keeps_the_richer_record(server):
    first = server.ingest([{"url": "https://www.instagram.com/p/A1/", "caption": "short"}], source="muse")
    assert first["counts"] == {"accepted": 1, "duplicates": 0, "rejected": 0}
    again = server.ingest([
        {"url": "https://www.instagram.com/p/A1/?utm=1", "caption": "a much longer caption"},
        {"url": "not a url"},
    ], source="muse")
    assert again["counts"] == {"accepted": 0, "duplicates": 1, "rejected": 1}
    saves = server.load_saves()
    assert saves["instagram:A1"]["caption"] == "a much longer caption"
    assert saves["instagram:A1"]["source"] == "muse"


def test_notes_keep_their_own_id(server):
    note = {"id": "whatsapp:MSG1", "platform": "whatsapp", "kind": "note",
            "url": "hindsight-note:whatsapp/MSG1", "caption": "call mom"}
    assert server.ingest([note, note], source="whatsapp_bot")["counts"]["accepted"] == 1
    assert server.load_saves()["whatsapp:MSG1"]["kind"] == "note"


def test_get_sync_status(server):
    assert server.get_sync_status()["total_saves"] == 0
    server.ingest([{"url": f"https://www.instagram.com/p/P{i}/", "platform": "instagram"} for i in range(35)], "muse")
    status = server.get_sync_status()
    assert status["total_saves"] == 35
    assert status["platforms"] == {"instagram": 35}
    assert len(status["recent_urls"]) == 30


def test_http_routes(server):
    client = TestClient(server.RequestLog(server.app))
    with client:
        tools = client.post(f"/{TOKEN}/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
                            headers=MCP_HEADERS).json()["result"]["tools"]
        assert {t["name"] for t in tools} == {"ping", "get_sync_status", "submit_saved_posts"}
        assert client.get(f"/{TOKEN}/mcp").status_code == 405  # no open SSE stream (Muse timed out on it)

        result = mcp_call(client, "submit_saved_posts", {
            "posts": [{"url": "https://www.instagram.com/reel/R1/", "author_username": "chef"}], "final_batch": True})
        assert result == {"accepted": 1, "duplicates": 0, "rejected": 0, "continue": False}
        assert mcp_call(client, "get_sync_status", {})["total_saves"] == 1

        res = client.post(f"/{TOKEN}/ingest", json={"source": "whatsapp_bot", "posts": [
            {"url": "https://example.com/a", "platform": "web", "kind": "link"}]})
        assert res.json()["accepted"] == 1

        saves = client.get(f"/{TOKEN}/saves").json()
        assert {p["id"] for p in saves} == {"instagram:R1", "web:https://example.com/a"}
        assert next(p for p in saves if p["id"] == "instagram:R1")["author"] == "chef"

        assert client.get("/wrongtoken/saves").status_code == 404  # the secret path is the auth
        log = (Path(os.environ["HINDSIGHT_CONNECTOR_DATA"]) / "calls.log").read_text()
        assert '"event": "submit_saved_posts"' in log and '"event": "ingest"' in log
