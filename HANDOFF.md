# hindsight — Handoff Prompt

REPO: /Users/arismac/Sync/win_mac_sync/dev/savefeed
READ README.md FIRST.

================================================================
PROJECT OVERVIEW
================================================================
hindsight (formerly savefeed) is a personal content aggregator. Pipeline: Telegram bot →
FastAPI (POST /capture) → per-source adapters (yt-dlp, gallery-dl,
trafilatura, syndication) → Gemini gist → SQLite → React feed at
:5173.

The user forwards links/notes to a Telegram bot. The API classifies
the payload (ig_reel, tweet, web, note), downloads media, generates
a Gemini summary, and stores everything in SQLite. A React SPA
renders the feed with filters, search, tags, and detail views.

================================================================
FILE MAP (3,206 lines total)
================================================================
```
app.py        (479)  FastAPI: /capture, /items, /health, /sweep/*, auth routes
db.py         (239)  SQLite schema + helpers, FTS5 search, category normalization
router.py      (30)  classify payload → (source, url)
adapters.py   (333)  ig_reel / tweet / web / note processors
gemini.py     (192)  Gemini API: gist_video, gist_images, gist_text
bot.py         (51)  Telegram polling → POST /capture
auth.py       (186)  Twitter OAuth 2.0 PKCE flow
sweep.py      (398)  Twitter bookmark + IG saved posts sweep logic
scripts/import_whatsapp.py  (213)  WhatsApp chat export importer
scripts/import_ig_export.py (199)  IG data download importer
scripts/import_fb_export.py (227)  FB data download importer
web/src/App.tsx     (659)  Single-file React frontend
web/src/types.ts     (30)  Source/Status/Item types, CATEGORIES, SOURCES
web/src/main.tsx            React entry point
```

================================================================
TECH STACK
================================================================
- Python 3.13 + FastAPI + uvicorn
- SQLite with FTS5 virtual table for full-text search
- Gemini 2.5-flash via google-genai SDK
- yt-dlp (video), gallery-dl (images), trafilatura (articles)
- Instaloader (IG saved posts enumeration)
- python-telegram-bot (Telegram polling)
- httpx for HTTP clients
- Vite + React 18 + TypeScript + Tailwind CSS (frontend)
- Netscape cookies.txt for IG/X authentication (yt-dlp/gallery-dl)

================================================================
DB STATE (as of handoff)
================================================================
18 items: 6 ig_reel(done), 7 tweet(done), 1 tweet(failed),
2 web(done), 2 note(done).

Schema: items table with columns id, source, source_url, kind,
raw_text, summary, on_screen_text, transcript, category,
key_takeaways, tags, saved_at, status.

FTS5 virtual table `items_fts` indexes summary, raw_text,
transcript, on_screen_text with INSERT/UPDATE/DELETE triggers.

Categories enforced: coding, quant, music, life-hack, productivity,
other. Fuzzy aliases map tech→coding, finance→quant, etc. Defense
in depth: normalized in both gemini.py and db.py.

================================================================
WHAT'S BEEN BUILT (chronological)
================================================================

Phase 1 — Core pipeline:
- POST /capture with URL dedup + POST /items/{id}/retry
- Netscape cookies.txt replacing --cookies-from-browser
- Server-rendered /items/pretty and /items/{id}/pretty

Phase 2 — Frontend:
- Vite + React + TS + Tailwind SPA at :5173
- CORS + filter/search params (category, source, tag, q)
- Free-form model-suggested tags
- Search box with debounce
- GET /health + dismissible cookie-expiry banner

Phase 3 — Hardening:
- Gemini model switch: 3.5-flash → 2.5-flash (persistent 503)
- Category normalization with fuzzy aliases
- Tweet adapter: syndication endpoint replacing oEmbed
  (full text + images + video detection)
- Native React detail view (slide-over panel with tag editing)
- FTS5 search replacing 4-way LIKE queries

Phase 4 — Sweep layer (current):
- Twitter bookmark sweep: OAuth2 PKCE flow (auth.py), 30-min
  auto-poll with backfill cap (sweep.py). BLOCKED: user needs to
  set up X developer account + add X_CLIENT_ID, X_CLIENT_SECRET
  to .env. Pay-per-use $0.001/bookmark read.
- IG saved posts sweep: Instaloader-based enumeration, 30-min
  auto-poll, 30-post cap per cycle. BLOCKED: user needs to run
  `instaloader --login pudabeats` to create session file, and
  add IG_USERNAME=pudabeats to .env.
- Import scripts: WhatsApp, IG export, FB export (all done)
- Sweep status dashboard in React frontend (done)

================================================================
GIT LOG (master branch)
================================================================
a5cb886 feat: IG saved posts sweep via Instaloader
b2e5eee deps: add instaloader for IG saved posts sweep
6a3726f feat: sweep status dashboard in React frontend
111e8d0 feat: Twitter bookmark sweep with OAuth2 PKCE + 30min auto-poll
6ae285d feat: Facebook saved items import script
e4e0bcc feat: Instagram data export import script
6538bc0 feat: WhatsApp chat-with-self import script
670a374 feat: FTS5 search replacing LIKE queries
9c55353 feat: native React detail view
1fd1639 feat: switch tweet adapter to syndication endpoint
75f3c39 fix: enforce category normalization with fuzzy aliases
bb96567 fix: switch Gemini model to 2.5-flash
(earlier commits: health endpoint, search, tags, frontend, CORS,
 dedup/retry, cookies.txt, initial pipeline)

================================================================
ENV VARS (.env — do NOT modify without user approval)
================================================================
GEMINI_API_KEY=<set>
BOT_TOKEN=<set>
SAVEFEED_API_URL=http://localhost:8000
IG_COOKIES_FILE=/Users/arismac/.savefeed/cookies.txt
X_CLIENT_ID=<not set — needs X developer account>
X_CLIENT_SECRET=<not set — needs X developer account>
IG_USERNAME=<not set — user needs to add "pudabeats">

================================================================
RUNNING THE APP
================================================================
Three processes:
  make api     → uvicorn on :8000
  make bot     → Telegram polling
  make web     → Vite dev server on :5173

There is a skill at .claude/skills/savefeed-up.md that restarts
all three. The user has explicitly requested: do NOT ask the user
to restart servers — handle it yourself (kill + relaunch in
background). See memory: feedback_restart_servers.md.

================================================================
WHAT'S BLOCKED (user action required)
================================================================

1. IG sweep activation:
   - User must add IG_USERNAME=pudabeats to .env
   - User must run: ./venv/bin/instaloader --login pudabeats
     (creates session at ~/.config/instaloader/session-pudabeats)
   - Then restart API server → 30-min auto-sweep kicks in
   - Manual trigger: POST /sweep/ig

2. Twitter sweep activation:
   - User must sign up at developer.x.com (free)
   - Load credits (pay-per-use, $0.001/bookmark read)
   - Create project + app with OAuth 2.0 PKCE
   - Callback URL: http://localhost:8000/auth/twitter/callback
   - Add X_CLIENT_ID + X_CLIENT_SECRET to .env
   - Visit http://localhost:8000/auth/twitter to authorize
   - Then 30-min auto-sweep kicks in

================================================================
WHAT'S NEXT (suggested priorities)
================================================================

1. ACTIVATE SWEEPS — help user through the blocked steps above.

2. README UPDATE — README.md is stale. It still says tweets are
   "stub — URL + note only, no fetch" and doesn't mention the
   sweep layer, import scripts, FTS5 search, or the React detail
   view. Needs a full rewrite covering:
   - Updated source descriptions (syndication tweets, image tweets)
   - Sweep section (Twitter bookmarks, IG saved posts)
   - Import scripts section (WhatsApp, IG export, FB export)
   - Re-auth flows for IG (instaloader) and Twitter (OAuth)
   - Updated env var table
   - Updated API endpoint table

3. URL DEDUP IMPROVEMENT — query params (e.g. ?s=46 on x.com URLs)
   cause different URLs for the same content. Known issue, not yet
   fixed. Could strip known tracking params before dedup comparison.

4. FAILED ROW #25 — tweet kaboreleon/1938272029498253801 is
   genuinely deleted/private (404 on both syndication and oEmbed).
   Can be cleaned up from the DB.

5. POSSIBLE FEATURES (not requested, just observations):
   - Pagination on /items (currently returns all rows)
   - Export/backup (JSON dump of all items)
   - Bulk retry for failed items
   - Category/tag analytics (what does the user save most?)
   - Dark mode toggle (currently follows system preference)
   - Mobile PWA (already mobile-friendly layout)

================================================================
KEY DESIGN DECISIONS + GOTCHAS
================================================================

- All ingestion goes through /capture or the _ingest() helper in
  sweep.py. No direct DB inserts for content items.
- Gemini occasionally ignores prompt constraints on category. Belt
  and suspenders: normalized in gemini.py AND db.py.
- Tweet adapter uses syndication first, oEmbed fallback. Syndication
  returns mediaDetails for photo/video detection.
- FTS5 uses external content table (content='items') — the FTS
  index is rebuilt on every server startup via INSERT INTO
  items_fts(items_fts) VALUES('rebuild').
- Sweep modules import adapters/router lazily inside _ingest() to
  avoid circular imports.
- Token/state files go in ~/.savefeed/, NOT in the repo.
- Instaloader session files go in ~/.config/instaloader/.
- The user's IG username is pudabeats.

================================================================
USER PREFERENCES (from memory)
================================================================
- Do NOT ask user to restart servers. Handle it autonomously.
- User prefers terse communication. No trailing summaries.
- Do NOT modify .env without user approval.
- One task = one commit.
