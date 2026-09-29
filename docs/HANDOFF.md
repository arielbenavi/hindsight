# hindsight — Handoff

## Current status (2026-09-29, branch `ariel/onboarding-data`)

**Read [LESSONS.md](LESSONS.md) first**, then [DATA_FETCHING_RESEARCH.md](DATA_FETCHING_RESEARCH.md).

### Built in the iOS app (Ariel: onboarding + data)
- **Data layer:** `SavedPost` (canonical model), `SavedPostParser` (Muse JSON + seed markdown), `SavedPostStore` (seed + imports, dedup, persisted JSON), `DataExportParser` + `ZipReader` (IG/FB/TikTok data-download exports; no UI yet).
- **Onboarding (5 screens):** welcome → how it works → connect apps → "how do you want to see it" → done. The look is brrr.now-inspired, and all styling lives in `OnboardingStyle.swift` so it can be reskinned. Preferences (grouping, layout, topics, resurface cadence) are saved via `OnboardingPreferences.save()`/`.load()` for the dashboard to read. Topic chips show real counts from the user's saves (keyword heuristic, a placeholder for real clustering).
- **Muse sync (IG + FB):** works on device through copy/paste (details in DATA_FETCHING_RESEARCH.md).
- **Connect X:** works on device (OAuth 2.0 PKCE, 97 bookmarks). Client ID is in `Sync/X/XConfig.swift`.
- **Device testing:** `ios/scripts/device.sh install|log`, plus a DEBUG event log on the phone.
- 26 unit tests (Swift Testing), all passing. None of them call real APIs.

### Open decisions
1. **Ingestion backend hosting:** Fly.io vs Google Cloud Run. Ariel + Reut to decide. Tradeoffs are in DATA_FETCHING_RESEARCH.md → "Ingestion backend".
2. **Video storage:** proposal is to keep transcript/summary/on-screen text/thumbnail/embedding only, and delete video files after processing.
3. **TikTok:** no official path for US users. Share extension + export import is the current plan. Research brief: [research/SYNC_RESEARCH_PROMPT.md](research/SYNC_RESEARCH_PROMPT.md).
4. **Share extension** needs a new target in `project.yml` (coordinate with Reut).

### Next up
- Ingestion backend: port `web/backend/` adapters + Gemini into a service and run it locally on seed data first.
- Muse: a "Get older saves" paging button, then the MCP connector on the backend (removes the paste).
- Share extension ("Share → hindsight") for TikTok and everything else.
- Try the remaining Muse link-lab candidates on device, looking for a prompt-prefill link.

### Setup notes
- Ariel's Apple ID is on Reut's team as **App Manager**, which can't sign device builds. Reut needs to grant "Access to Certificates, Identifiers & Profiles" (or the Developer role). Until then, use Personal Team overrides (see ios/README.md).
- X console: regenerate the unused hindsight-ios secrets that were exposed in screenshots during setup.

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
