# hindsight — Handoff

## Current status (2026-11-20)

**Read [LESSONS.md](LESSONS.md) first**, then [TESTING.md](TESTING.md) and [HOSTING.md](HOSTING.md).
The approved rework plan (Home shell, topics for everything, sync) is done through step 5. On top of it,
branch `ariel/today-and-jobs` replaced the single Home screen with **Today · Library · Ask** and gave every
topic a **job**.

### What the app is now
Bring saves in → see them organized by what they're for → get old ones back, three a day. After
onboarding (Welcome → How it works → Plug in your apps → You're in) there's a bottom tab bar:
- **Today** (the front door): one big card at a time, 3 a day ("1 of 3"), each answered with Not anymore /
  Open it / Did it, then "That's today." (what happened, new since yesterday, "One more"). Picks come from
  saves still `new`, not snoozed, whose topic's job allows Today (Go, Do, Learn); due reminders first. The
  set is saved (`today.json`) so a relaunch resumes; a new day starts fresh. 9:00 local notification, asked
  for the first time a set is finished, only scheduled when something is eligible.
- **Library**: topics grouped by job — Go, Do, Learn, Keep close, Look, Know — with "N saves still need a
  home", All saves and Let go at the end. Search on top, gear (Sources) and 🐞 in the header. A topic's page
  has the job's shape: Do = checklist, Look = picture board, Keep close = the quiet shelf ("What do you need
  right now?"), Go/Learn/Know = the list (with Open map / Open tips). "…" → "What is this for?" changes the job.
  Tapping a save opens its detail sheet (done, remind me, note, move to another topic, let go).
- **Ask**: a focused search (caption, author, hashtags, topic, notes) plus ready-made filters. No AI yet.

Library works from the raw imports the moment onboarding ends; sorting runs in the background and topics
appear as they're ready. The server is pulled on launch and on every return to the app; each install gets
its own server account.

User state lives outside the contract file, per dataset (`Application Support/Hindsight/<dataset>/`):
`save-states.json` (`Saves/SaveStateStore`: new/done/letGo, note, remindAt, shownInToday, lastOpened, opens),
`topic-prefs.json` (`TopicPrefsStore`: job overrides by topic id, moves post id → topic id, applied by
`Library/LibraryIndex` on top of `HomeTopics`), `today.json` (`Today/TodayStore`). The default job is
`TopicJobs.suggested` (the topic's view, else label keywords, EN + HE).

### Architecture (~15 lines)
- `Import/SavedPostStore` — every import (Muse, Meta export, X, WhatsApp, server pull), deduped. The source of truth.
- `Pipeline/SortEngine` — on-device Apple models (PCC first on iOS 27, then on-device): each post → screen
  (map/learn/fitness/none) + topic slug, places for map posts; one call names all slugs (none ones too);
  cached by post id + caption hash in `sort-cache.json`. Posts not sorted yet sit in "Unsorted".
- `assemble` writes the contract file (`Application Support/Hindsight/me/hindsight.json`, docs/data-contract.md).
- `App/AppModel` — loads that file (or a bundled sample), sets the views' layout (`LayoutRules.propose`),
  owns `PlaceStore` (MapKit matching), `PracticeStore`, and `syncWithServer()` (pull, ≤ 1/min).
- `App/RootView` → `MainTabs` (Today · Library · Ask; Sources sheet, server pull, reminders).
- `Today/` — `TodayScreen`, `TodayPlan` (pure: eligibility, picks, resume), `Resurface` (pure picks by day),
  `TodayStore`, `TodayNotifications` ("hd." ids; Learn/Fitness keep "hs.").
- `Library/` — `LibraryScreen` (sections by job), `TopicJob`/`TopicJobs`, `LibraryIndex`, `HomeTopics`,
  `TopicScreen` (+ job picker), `JobScreens` (Do list, Look board, Keep close shelf), `ShelfLogic` (pure);
  views pushed on the Library stack: `MapScreen`, `LearnScreen`, `FitnessScreen` (their setup is opt-in, inline).
- `Saves/` — `SaveStateStore`, `TopicPrefsStore`, `SaveDetailSheet`, `SaveArt`. `Ask/` — `AskScreen`, `AskSearch`.
- `Sync/MuseConnector` — server URL + this install's account (`ensureAccount`: tenant `…/<token>/t/<id>`).
- `connector/server.py` — MCP connector Muse calls, `/saves` for the app, `/ingest` for the bot, `/tenants`.
- `whatsapp-bot/` — Baileys bot on our number; posts notes/links to `/ingest` under the user's connect code (= tenant).

### Status
| Area | Status |
|---|---|
| Home shell, background sorting, topics for every save | ✅ merged (PR #20 + this branch), simulator-checked |
| Topics without a model (simulator, no Apple Intelligence, quota, refusals) | ✅ `Pipeline/TopicFallback`: collection → hashtags → caption words (EN/HE lexicon, 40 topics) → author → platform. Seed: 72% of captioned saves get a real topic (was 0%: all "Other"). Fallback decisions are marked in the sort cache and re-asked once a model is there (branch `ariel/topic-fallback`) |
| Pull on launch/foreground, one account per install | ✅ built, simulator-checked against the local connector |
| Muse → connector → app | ✅ verified on device 2026-09-30 |
| Meta export import, X bookmarks, WhatsApp export import | ✅ |
| WhatsApp bot | ⛔ **logged out since 2026-10-17**: the bot phone stayed offline 15 days (confirms the ~14-day rule). Needs relinking from a phone that stays online |
| Map / Tips / Workouts views | ✅ (from Reut's MVP), setup flows now opt-in |
| Phone builds | ⛔ the phone runs iOS 26.6.2; Xcode 26.3 here can't install on it. Needs a newer Xcode; until then, simulator only |
| Hosting (connector + bot 24/7) | 🟡 Dockerfiles ready, Railway or Fly recommended, **decision pending** ([HOSTING.md](HOSTING.md)) |
| TestFlight | 🟡 via Reut's account / Xcode Cloud ([XCODE_CLOUD.md](XCODE_CLOUD.md)) |
| Share extension (TikTok / any link) | ⏳ not started (needs App Groups → Reut's signing) |

### Next / blocked
1. **Hosting decision** (blocks real users): one small Railway or Fly machine with a volume, a domain, token + bot number as env vars. Then the app ships with that root URL and every install makes its own account automatically.
2. **Newer Xcode** to install on the phone (iOS 26.6.2), then the device pass in TESTING.md.
3. **Relink the WhatsApp bot** on a phone that stays online (or plan the relink every ~14 days).
4. **Share extension** and **TestFlight** (Reut's account / Xcode Cloud).
5. Still open with Reut: Info.plist document types ("Export chat → hindsight"); shared-group privacy rule ("links from anyone, text only from the owner").

### Running things locally
- Connector + ngrok run under launchd on Ariel's Mac (`connector/install-launchd.sh`; logs in `connector/data/`). By hand: `cd connector && .venv/bin/python server.py` + `ngrok http 8765` (fixed domain). The token is in `connector/data/token` (never commit it).
- Simulator with the server: launch with `-museConnectorBaseURL https://<host>/<token>`; the app makes its own account (tenant) on first launch and keeps it, even if the argument is passed again. DEBUG reset: Sources → Sync with Muse → "Fresh Muse test (new user)".
- Other launch args: `-resetOnboarding`, `-whatsAppBotNumber <digits>` (normally the app asks the server's `/whatsapp`).
- Phone builds (Personal Team, 7-day expiry): `ios/scripts/device.sh install|log`. Reut's Apple account is Individual, so Ariel can't sign under it.

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
