# hindsight — Handoff

## Current status (2026-10-01)

**Read [LESSONS.md](LESSONS.md) first**, then [SYNC_PLAN.md](SYNC_PLAN.md), [TESTING.md](TESTING.md) and [HOSTING.md](HOSTING.md).

### What exists and works
| Area | Status | Where |
|### To decide with Reut (sync 2026-10-01)
1. **Hosting** (blocking real users): connector + WhatsApp bot must run 24/7 with a persistent disk (the bot's WhatsApp login in `auth/`, its `state/`, and the saves). Today both run on Ariel's Mac behind ngrok, so everything stops when the Mac sleeps. Recommendation: one small Railway or Fly machine with a volume (see HOSTING.md). Needs: who owns the account/billing, a domain (e.g. `api.hindsight…`), and moving the token + bot number to env vars.
2. **Accounts:** each install should get its own store. The server already has tenants; the app needs to create one on first launch (`POST /<token>/tenants`) instead of using the one URL from a launch argument. The WhatsApp connect code already uses the tenant, so the bot files each person's notes under their store.
3. **App plumbing in Reut's area:** Info.plist document types ("Export chat → hindsight" in the share sheet), the share extension (TikTok/any link), TestFlight/Xcode Cloud, and where the Sources page lives in her UI.
4. **Shared-group privacy:** OK with "links from anyone, text only from the owner" + the hello message?

---|### To decide with Reut (sync 2026-10-01)
1. **Hosting** (blocking real users): connector + WhatsApp bot must run 24/7 with a persistent disk (the bot's WhatsApp login in `auth/`, its `state/`, and the saves). Today both run on Ariel's Mac behind ngrok, so everything stops when the Mac sleeps. Recommendation: one small Railway or Fly machine with a volume (see HOSTING.md). Needs: who owns the account/billing, a domain (e.g. `api.hindsight…`), and moving the token + bot number to env vars.
2. **Accounts:** each install should get its own store. The server already has tenants; the app needs to create one on first launch (`POST /<token>/tenants`) instead of using the one URL from a launch argument. The WhatsApp connect code already uses the tenant, so the bot files each person's notes under their store.
3. **App plumbing in Reut's area:** Info.plist document types ("Export chat → hindsight" in the share sheet), the share extension (TikTok/any link), TestFlight/Xcode Cloud, and where the Sources page lives in her UI.
4. **Shared-group privacy:** OK with "links from anyone, text only from the owner" + the hello message?

---|### To decide with Reut (sync 2026-10-01)
1. **Hosting** (blocking real users): connector + WhatsApp bot must run 24/7 with a persistent disk (the bot's WhatsApp login in `auth/`, its `state/`, and the saves). Today both run on Ariel's Mac behind ngrok, so everything stops when the Mac sleeps. Recommendation: one small Railway or Fly machine with a volume (see HOSTING.md). Needs: who owns the account/billing, a domain (e.g. `api.hindsight…`), and moving the token + bot number to env vars.
2. **Accounts:** each install should get its own store. The server already has tenants; the app needs to create one on first launch (`POST /<token>/tenants`) instead of using the one URL from a launch argument. The WhatsApp connect code already uses the tenant, so the bot files each person's notes under their store.
3. **App plumbing in Reut's area:** Info.plist document types ("Export chat → hindsight" in the share sheet), the share extension (TikTok/any link), TestFlight/Xcode Cloud, and where the Sources page lives in her UI.
4. **Shared-group privacy:** OK with "links from anyone, text only from the owner" + the hello message?

---|
| Data model (`SavedPost` = contract v1 posts[]) | ✅ merged | `ios/Hindsight/Models` |
| Parsers: seed md, Muse JSON, IG (current + old)/FB/TikTok exports, WhatsApp export | ✅ tested | `ios/Hindsight/Import` |
| Onboarding (5 screens) + shared source cards + Sources page | ✅ merged | `ios/Hindsight/Onboarding`, `Sync/SourceCards.swift`, `Sync/SourcesView.swift` |
| **Muse → connector → app (no copy/paste)** | ✅ **verified on device 2026-09-30** | `connector/`, `Sync/MuseSyncView.swift` |
| Muse `get_sync_status` + daily routine in the onboarding message | ✅ merged, needs device test (TESTING.md A) | `connector/`, `Sync/MuseConnector.swift` |
| Fresh-user Muse tests (connector tenants + dev button) | ✅ built, needs device test | branch `ariel/fresh-muse-test` |
| X sign-in + bookmarks | ✅ verified (97 bookmarks) | `Sync/X` |
| WhatsApp bot (add hindsight's number to your notes group) | ✅ live on the Mac since 2026-10-01 (launchd keeps it running): linked to the Tello number (WhatsApp Business on a spare phone). Verified: group hello, a note + an IG reel landed in /saves. Not yet verified: Reut's-message privacy rule, "last 100" history | `whatsapp-bot/` |
| WhatsApp screen v2: 1) "Open WhatsApp" (connect code links the WhatsApp number to the app's store) + "Save hindsight to contacts" 2) "chat with myself" (→ use the hindsight chat) vs "a group" (→ add hindsight) 3) old notes: export → send to hindsight in WhatsApp (bot imports it), Files import as fallback | ✅ built + simulator-checked, needs device test (TESTING.md C, F) | `Sync/WhatsAppImportView.swift`, `Sync/NewContactSheet.swift`, `whatsapp-bot/exportParser.js` |
| Bot health log (tests the "relink every 14 days" assumption) | ✅ every 2 days via launchd → `whatsapp-bot/state/health.log`, Mac notification on problems | `whatsapp-bot/healthcheck.sh` |
| Xcode Cloud (TestFlight on every push) | 🟡 script ready, **Reut sets up the workflow** | `ios/ci_scripts`, [XCODE_CLOUD.md](XCODE_CLOUD.md) |
| Hosting (connector + bot 24/7) | 🟡 Dockerfiles/fly.toml ready; Railway or Fly recommended (Vercel can't run the bot), **decision pending** | [HOSTING.md](HOSTING.md) |
| TikTok | ⏸ parked: no API for US users; share extension later | DATA_FETCHING_RESEARCH.md |
| Sorting/extraction pipeline (contract items 4–6) | ⏳ not started (Reut generated fixtures once; pipeline is ours) | data-contract.md |

### Waiting on others
- **Reut:**
  - merge PR #4 with `@preconcurrency import MapKit` in `MapSheet.swift` (needed on Xcode 26.3)
  - add 🐞 "Restart onboarding" + a profile/settings button opening `SourcesView`
  - set up Xcode Cloud ([XCODE_CLOUD.md](XCODE_CLOUD.md))
  - agree on the proposed contract additions (`web`/`whatsapp`, `link`/`note`)
- **After #4 merges:** add Info.plist document types so "Export chat → hindsight" appears in WhatsApp's share menu (removes the Save to Files step).
- **Reut:** was sent the full request list (merge #4 + MapKit fix, Sources/🐞 hooks, Xcode Cloud, contract additions, hosting) on 2026-10-01.
- **Ariel:** after opening WhatsApp on the bot phone, run `whatsapp-bot/healthcheck.sh opened` (feeds the 14-day log); keep the bot's spare phone online at least every ~14 days (or the bot gets logged out); hosting decision with Reut, manual tests in [TESTING.md](TESTING.md), and the WhatsApp research answer (`research/WHATSAPP_RESEARCH_PROMPT.md`).

### Running things locally
- Connector: `cd connector && .venv/bin/python server.py` + `ngrok http 8765` (fixed domain `supermom-depose-retail.ngrok-free.dev`). The token is in `connector/data/token`.
- Phone builds (Personal Team, 7-day expiry): `ios/scripts/device.sh install|log` with `HINDSIGHT_TEAM=Y93Y9ZACWZ HINDSIGHT_BUNDLE_ID=…`. Launch args: `-resetOnboarding`, `-museConnectorBaseURL <https://host/token>`, `-whatsAppBotNumber <digits>` (normally not needed: the app asks the server's `/whatsapp`, which reads `connector/data/whatsapp_bot`; the number stays out of this public repo).
- WhatsApp bot: runs under launchd (`whatsapp-bot/install-launchd.sh`), log in `whatsapp-bot/state/bot.log`.
- Reut's Apple account is **Individual**, so Ariel can't sign under it. TestFlight (Reut uploads) or Xcode Cloud are the shared-build paths.

### To decide with Reut (sync 2026-10-01)
1. **Hosting** (blocking real users): connector + WhatsApp bot must run 24/7 with a persistent disk (the bot's WhatsApp login in `auth/`, its `state/`, and the saves). Today both run on Ariel's Mac behind ngrok, so everything stops when the Mac sleeps. Recommendation: one small Railway or Fly machine with a volume (see HOSTING.md). Needs: who owns the account/billing, a domain (e.g. `api.hindsight…`), and moving the token + bot number to env vars.
2. **Accounts:** each install should get its own store. The server already has tenants; the app needs to create one on first launch (`POST /<token>/tenants`) instead of using the one URL from a launch argument. The WhatsApp connect code already uses the tenant, so the bot files each person's notes under their store.
3. **App plumbing in Reut's area:** Info.plist document types ("Export chat → hindsight" in the share sheet), the share extension (TikTok/any link), TestFlight/Xcode Cloud, and where the Sources page lives in her UI.
4. **Shared-group privacy:** OK with "links from anyone, text only from the owner" + the hello message?

---

# Web prototype handoff (historical)


REPO: /Users/arismac/Sync/win_mac_sync/dev/savefeed
GITHUB: https://github.com/arielbenavi/hindsight
READ README.md FIRST (root), then web/README.md for the prototype.

NOTE (2026-09-29): repo restructured. The web prototype below now lives in
web/ (Python in web/backend/, React in web/frontend/) and is deprecated.
The iOS app lives in ios/. Seed data stays in data/.

================================================================
PROJECT OVERVIEW
================================================================
hindsight (formerly savefeed) is a personal content aggregator.
Your saved posts across IG, X, FB, TikTok — organized with AI.

Three main components:
1. ONBOARDING — connect platforms, ask user how they want data organized
2. DATA FETCHING — each platform has unique challenges (see below)
3. DATA ORGANIZATION — clustering, multiple views, user preferences

Pipeline: Telegram bot / manual URL / sweep / Muse connector →
FastAPI (POST /capture) → per-source adapters (yt-dlp, gallery-dl,
trafilatura, syndication) → Gemini gist + embedding → SQLite →
Spotify-inspired React dashboard at :5173 with RAG chat.

================================================================
THREE COMPONENTS — DETAIL
================================================================

### 1. Onboarding Flow (TO BUILD)
First-run experience that:
- Walks user through connecting each platform
- IG/FB: one-tap "Sync with Muse" button (deep link muse://new?text=...)
- Twitter/X: OAuth flow (already built), Developer Studio automation TBD
- TikTok: approach TBD
- Asks "how do you want to see your data?" — clustering prefs, categories,
  layout choices that persist and drive the dashboard experience

### 2. Data Fetching (per-platform challenges)
- **Instagram**: Meta Muse MCP connector (planned, best path) / Cookie API
  (working but fragile, cookies expire every 90 days)
- **Facebook**: Meta Muse MCP connector (planned) / Data export fallback.
  Direct scraping fully blocked — 5 approaches tried and failed.
- **Twitter/X**: OAuth API working. Developer Studio automation for easier
  onboarding is a potential improvement (skip manual app creation?).
- **TikTok**: Unknown. Adapter exists (yt-dlp handles download), but no
  automated way to pull saved/liked TikToks yet.

### 3. Data Organization & Display (partially built)
- AI-powered clustering and categorization via Gemini
- Multiple screens: feed view, stats/topics, AI chat, detail panels
- User preferences from onboarding drive layout and grouping
- 768-dim embeddings for similarity search ("more like this")
- Spotify-inspired dark UI (see DESIGN.md)
- TO BUILD: onboarding-driven personalization, topic clustering,
  "collections" view, cross-platform timeline

================================================================
SEED DATA
================================================================
data/ig-saved-posts-seed.md — 1,216 Instagram saved posts
  (@pudabeats, July 2019 to September 2026)
  Pre-exported so development is not blocked on live API access.
  See data/README.md for format and usage.

================================================================
FILE MAP (5,238 lines total) — Python paths are relative to web/backend/
================================================================

app.py          (701)  FastAPI: /capture, /items, /health, /sweep/*, /chat, auth
db.py           (396)  SQLite schema + helpers, FTS5 search, embeddings, categories
router.py        (34)  classify payload to (source, url)
adapters.py     (395)  ig_reel / tweet / web / note processors
gemini.py       (221)  Gemini API: gist_video, gist_images, gist_text, embeddings
bot.py           (51)  Telegram polling to POST /capture
auth.py         (186)  Twitter OAuth 2.0 PKCE flow
sweep.py        (647)  Twitter bookmark + IG + FB saved posts sweep logic
backfill.py     (763)  Resumable full-history backfill for all platforms
preflight.py    (324)  Dry-run health checks + setup page
scripts/import_whatsapp.py  (213)  WhatsApp chat export importer
scripts/import_ig_export.py (199)  IG data download importer
scripts/import_fb_export.py (227)  FB data download importer
web/frontend/src/App.tsx (851)  Single-file React frontend (feed, stats, chat)
web/frontend/src/types.ts (30)  Source/Status/Item types, CATEGORIES, SOURCES
data/ig-saved-posts-seed.md (4809) 1,216 IG saved posts seed data

================================================================
TECH STACK
================================================================
- Python 3.13 + FastAPI + uvicorn
- SQLite with FTS5 + 768-dim embeddings (cosine similarity)
- Gemini 2.5-flash via google-genai SDK
- yt-dlp (video), trafilatura (articles), syndication (tweets)
- httpx for HTTP clients
- python-telegram-bot (Telegram polling)
- Vite + React 18 + TypeScript + Tailwind CSS (frontend)
- Spotify-inspired dark UI (DESIGN.md)

================================================================
DB STATE (as of 2026-09-29)
================================================================
~301 items in DB: 97 tweets (done), ~193 IG (done), misc web/notes.
1,216 IG posts in seed data file (not yet in DB).

Schema: items table with columns id, source, source_url, kind,
raw_text, summary, on_screen_text, transcript, category,
key_takeaways, tags, saved_at, status, embedding (768-dim BLOB).

FTS5 virtual table items_fts indexes summary, raw_text,
transcript, on_screen_text with INSERT/UPDATE/DELETE triggers.

Categories enforced: coding, quant, music, life-hack, productivity,
other. Fuzzy aliases map tech to coding, finance to quant, etc.

================================================================
PLATFORM STATUS
================================================================

Twitter/X — DONE
  - OAuth 2.0 PKCE, bookmark.read scope
  - 97 bookmarks fully backfilled, zero remaining
  - 30-min auto-sweep catches new bookmarks
  - Token auto-refreshes

Instagram — IN PROGRESS
  - Cookie-based private API (GET /api/v1/feed/saved/posts/)
  - ~193 items ingested via API, 1,216 total in seed data
  - 100 items/session cap, resumable
  - 30-min auto-sweep for new saves

Facebook — BLOCKED
  - All 5 scraping approaches failed (see docs/BACKFILL_STATUS.md)
  - Data export (scripts/import_fb_export.py) works but 24-48h wait
  - NEXT: Meta Muse AI agent integration via MCP connector

TikTok — DEFERRED
  - Adapter exists (yt-dlp to Gemini), no sweep yet
  - Manual URL capture only

================================================================
WHAT'S NEXT (suggested priorities)
================================================================

1. ONBOARDING FLOW — first-run UX: connect platforms + data prefs
2. MUSE MCP CONNECTOR — solves FB + IG in one integration
3. SEED DATA IMPORT — parse data/ig-saved-posts-seed.md into DB
4. DATA ORGANIZATION UX — clustering, collections, timeline
5. X ONBOARDING — smoother OAuth setup
6. TIKTOK — research automated fetch

================================================================
COLLABORATION SETUP
================================================================
- GitHub repo shared with @reyr13 (Reut, push access)
- Each person runs Claude Code locally against the repo
- Slack + Claude Tag for shared AI brainstorming
- Branches + PRs for code changes

================================================================
KEY DESIGN DECISIONS
================================================================
- All ingestion goes through /capture or _ingest() in sweep.py
- Token/state files go in ~/.savefeed/, NOT in the repo
- FB cookie scraping is dead — do not attempt
- Seed data in data/ is committed (public IG URLs, no private data)

================================================================
USER PREFERENCES
================================================================
- Do NOT ask user to restart servers. Handle it autonomously.
- Do NOT modify .env without user approval.
- One task = one commit.
- Do not burn API credits in tests.
