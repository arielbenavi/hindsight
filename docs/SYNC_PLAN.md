# Sync plan

Decided 2026-09-30, from [research/SYNC_RESEARCH_ANSWER.md](research/SYNC_RESEARCH_ANSWER.md) and what we verified on device ([DATA_FETCHING_RESEARCH.md](DATA_FETCHING_RESEARCH.md)).

## The model

Two separate features, with every source feeding one ingestion path:

- **Bring your old saves (backfill, once):** X API · Muse · Meta export (IG/FB) · TikTok export.
- **Keep up (ongoing):** X API (automatic) · **Share → hindsight** for IG, FB, TikTok and anything else · Muse connector later, if Meta allows it.

```
X API ────────┐
Muse ─────────┤
Share ext. ───┼──► ingest → normalize → dedupe → enrich → resurface
Meta export ──┤
TikTok export ┘
```

Every item keeps its provenance (`ingest_method`, original + canonical URL, captured-at, parser version).

**Never:** cookie/session scraping, or storing social logins. Not for any platform.

## Phases

### Phase 0: no backend needed (now)
| # | Work | Owner | Needs |
|---|------|-------|-------|
| 0.1 | **Request exports today** (they take days): Instagram + Facebook (Accounts Center → Your information → Download your information → JSON, all time), TikTok (Settings → Account → Download your data → JSON) | Ariel | nothing |
| 0.2 | **Muse via WhatsApp prefill test**: find Muse's WhatsApp number, try `https://wa.me/<number>?text=<prompt>` | Ariel + Claude | the number |
| 0.3 | **"Import a file" UI** for exports (parser already built). Test against the real exports from 0.1 and adjust the schemas | Claude | 0.1 |
| 0.4 | **Share extension, diagnostic build**: log what IG/TikTok/X/FB/Safari actually send (share payload matrix) | Claude | new target + App Group in `project.yml` (**coordinate with Reut**), team signing access |
| 0.5 | **Share extension v1**: Share → hindsight → "Saved ✓", durable App Group queue, merge into the store on app open | Claude | 0.4 |
| 0.6 | Onboarding: add **"Add hindsight to your Share menu"** and an optional **"Bring your old saves"** step | Claude | 0.3, 0.5 |

### Phase 1: minimal Muse connector experiment (the most important unknown)
- Tiny MCP server with only `ping` + `submit_saved_posts` (idempotent, returns `{accepted, duplicates, continue}`).
- Run it **locally behind a temporary HTTPS tunnel**, so no hosting decision is needed yet. Add it to Muse as a *custom* connector (custom connectors aren't reviewed).
- Ask Muse: "send my 10 most recent Instagram saves to hindsight." **Does Meta let data flow from Instagram into our connector?** Then scale (50/100/250/1,000), pagination, "every day" recurrence.
- If yes: this replaces the copy/paste flow and becomes the Instagram backfill/sync. Submit it to the Muse directory. If no: Muse stays as the copy/paste backfill, and nothing else depends on it.

### Phase 2: ingestion backend (hosting decision with Reut first)
- `/v1/saves/ingest` (batch, idempotent, provenance fields). The app uploads what it captures, and the Muse connector writes to the same place.
- Move X sync server-side (scheduled, incremental). Promise "recent bookmarks" (800 cap).
- Per-user auth for the app and the connector.

### Phase 3: enrichment
- Port `web/backend` adapters + Gemini: transcript, on-screen text, summary, tags, embeddings, thumbnail. Video is downloaded only while processing, then deleted (pending confirmation).

### Later
- TikTok Data Portability for EEA/UK users, only if we target them. Verify first that `activity` includes Favorites vs Likes.
- App Review rehearsal (privacy flow, extension explanation, delete-data flow).

## What to promise users
- X: "Automatically syncs your recent bookmarks."
- Instagram / Facebook / TikTok: "Import your history once, then save anything new with Share → hindsight."
- Muse: "Faster Instagram import via Meta's Muse", as a bonus, never required.
