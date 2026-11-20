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
        assert {t["name"] for t in tools} == {"ping", "get_sync_status", "submit_saved_posts", "search_saves", "recent_saves"}
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


def test_tenants_are_isolated(server):
    client = TestClient(server.RequestLog(server.app))
    with client:
        created = client.post(f"/{TOKEN}/tenants").json()
        tenant, base = created["tenant"], created["base_path"]
        assert base == f"/{TOKEN}/t/{tenant}"

        # Muse talks to the tenant's own MCP URL.
        body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
            "name": "submit_saved_posts", "arguments": {"posts": [{"url": "https://www.instagram.com/p/T1/"}]}}}
        res = client.post(f"{base}/mcp", json=body, headers=MCP_HEADERS)
        assert res.json()["result"]["structuredContent"]["accepted"] == 1
        status = client.post(f"{base}/mcp", headers=MCP_HEADERS, json={
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "get_sync_status", "arguments": {}}}).json()["result"]["structuredContent"]
        assert status["total_saves"] == 1

        # The tenant sees it; the default store and other tenants don't.
        assert [p["id"] for p in client.get(f"{base}/saves").json()] == ["instagram:T1"]
        assert client.get(f"/{TOKEN}/saves").json() == []
        other = client.post(f"/{TOKEN}/tenants").json()["base_path"]
        assert client.get(f"{other}/saves").json() == []

        # Same for /ingest, and bad tenant ids are rejected.
        client.post(f"{other}/ingest", json={"source": "whatsapp_bot", "posts": [{"url": "https://example.com/z", "platform": "web"}]})
        assert len(client.get(f"{other}/saves").json()) == 1
        assert len(client.get(f"{base}/saves").json()) == 1
        assert client.get(f"/{TOKEN}/t/ab/saves").status_code == 404  # too short
        assert client.get(f"/{TOKEN}/t/BAD_ID!/saves").status_code == 404


def test_whatsapp_bot_number(server, monkeypatch):
    client = TestClient(server.RequestLog(server.app))
    assert client.get(f"/{TOKEN}/whatsapp").json() == {"number": None}
    monkeypatch.setenv("HINDSIGHT_WHATSAPP_BOT", "+1 555 123-4567")
    assert client.get(f"/{TOKEN}/whatsapp").json() == {"number": "15551234567"}
    assert client.get(f"/{TOKEN}/t/t-abc123/whatsapp").json() == {"number": "15551234567"}  # same from a tenant URL


def test_new_account_can_adopt_the_default_store_once(server, tmp_path):
    client = TestClient(server.RequestLog(server.app))
    client.post(f"/{TOKEN}/ingest", json={"source": "ig_cookie", "posts": [{"url": "https://www.instagram.com/p/ADOPT1/", "platform": "instagram"}]})
    (tmp_path / "adopt_default").write_text("")
    first = client.post(f"/{TOKEN}/tenants").json()
    assert len(client.get(f"{first['base_path']}/saves").json()) == 1
    assert (tmp_path / "backfill_tenant").read_text() == first["tenant"]
    # From now on the plain URLs mean that account.
    client.post(f"/{TOKEN}/ingest", json={"source": "muse", "posts": [{"url": "https://www.instagram.com/p/ADOPT2/", "platform": "instagram"}]})
    assert len(client.get(f"{first['base_path']}/saves").json()) == 2
    second = client.post(f"/{TOKEN}/tenants").json()  # the flag is used up
    assert client.get(f"{second['base_path']}/saves").json() == []


def test_a_resend_never_blanks_a_field_and_fills_missing_ones(server):
    url = "https://www.instagram.com/p/MERGE1/"
    server.ingest([{"url": url, "platform": "instagram", "author": "anna", "caption": "short"}], source="muse")
    server.ingest([{"url": url, "platform": "instagram", "author": None, "caption": "a much longer caption", "transcript": "words"}], source="ig_cookie")
    saved = next(iter(server.load_saves().values()))
    assert saved["author"] == "anna" and saved["caption"] == "a much longer caption" and saved["transcript"] == "words"
    server.ingest([{"url": url, "platform": "instagram", "caption": "x", "location_tag": "NYC"}], source="muse")
    saved = next(iter(server.load_saves().values()))
    assert saved["caption"] == "a much longer caption" and saved["location_tag"] == "NYC"


def test_search_saves_ranks_by_words_and_reads_transcripts(server):
    server.ingest([
        {"url": "https://www.instagram.com/reel/S1/", "platform": "instagram", "author": "mixwithmike",
         "caption": "How I glue my drums", "transcript": "sidechain compression on the 808 so the kick punches through", "saved_at": "2026-01-02T00:00:00Z"},
        {"url": "https://www.instagram.com/reel/S2/", "platform": "instagram", "author": "chef.anna", "caption": "Crispy rice salad recipes", "saved_at": "2026-03-01T00:00:00Z"},
        {"url": "https://x.com/karpathy/status/9", "platform": "x", "author": "karpathy", "caption": "Compression is intelligence", "saved_at": "2026-02-01T00:00:00Z"},
    ], source="test")
    saves = list(server.load_saves().values())
    hits = server.search(saves, "sidechain compression 808")
    assert hits[0]["author"] == "mixwithmike" and "sidechain" in hits[0]["transcript"]
    assert [h["author"] for h in server.search(saves, "recipe")] == ["chef.anna"]  # prefix match
    assert [h["author"] for h in server.search(saves, "compression", platform="x")] == ["karpathy"]
    assert server.search(saves, "nothing-like-this") == []
    assert server.recent_saves(limit=1)[0]["author"] == "chef.anna"
