# hindsight

Your saved posts, finally organized. Hindsight pulls everything you've saved across Instagram, Twitter/X, Facebook, and TikTok — summarizes it with AI — and gives you a searchable, personalized dashboard to actually find things again.

**GitHub:** [arielbenavi/hindsight](https://github.com/arielbenavi/hindsight)

## Three main components

### 1. Onboarding
First-run flow that connects your platforms and asks how you want your content organized:
- Connect Instagram & Facebook via Meta Muse (AI agent with native saved post access)
- Connect Twitter/X via OAuth (Developer Studio automation TBD for smoother setup)
- Connect TikTok (approach TBD)
- "How do you want to see your data?" — user picks preferred clustering, categories, layout

### 2. Data fetching
Each platform has its own challenges:

| Platform | Method | Status |
|----------|--------|--------|
| **Instagram** | Meta Muse MCP connector (planned) / Cookie API (working) | 1,216 posts in seed data |
| **Facebook** | Meta Muse MCP connector (planned) / Data export (fallback) | Blocked on direct scraping |
| **Twitter/X** | OAuth API (working) — Developer Studio automation for easier onboarding? | 97 bookmarks done |
| **TikTok** | Unknown — adapter exists (yt-dlp), no automated fetch yet | Deferred |

### 3. Data organization & display
After fetching, the real product begins:
- AI-powered clustering and categorization (Gemini)
- Multiple views: feed, stats/topics, AI chat, detail panels
- User preferences from onboarding drive layout and grouping
- Embeddings-based similarity for "more like this"
- Spotify-inspired dark UI

## How the pipeline works

1. **Fetch** — sweeps pull new saves every 30 min; backfill grabs full history
2. **Capture** — each URL routes through per-source adapters (yt-dlp for video, trafilatura for articles, syndication for tweets)
3. **Summarize** — Gemini 2.5-flash generates a gist, key takeaways, tags, category, and a 768-dim embedding
4. **Store** — SQLite with FTS5 full-text search
5. **Browse** — React SPA with filters, search, tag editing, detail panels, stats, and AI chat

You can also forward links to a Telegram bot, paste URLs via curl, or bulk-import from platform data exports.

## Seed data

`data/ig-saved-posts-seed.md` — 1,216 Instagram saved posts (@pudabeats, 2019–2026). Used for development so we're not blocked on live API access. See [data/README.md](data/README.md).

## Layout

```
app.py          (701)  FastAPI: /capture, /items, /health, /sweep/*, /chat, auth routes
db.py           (396)  SQLite schema + helpers, FTS5 search, category normalization
router.py        (34)  classify payload → (source, url)
adapters.py     (395)  ig_reel / tweet / web / note processors
gemini.py       (221)  Gemini API: gist_video, gist_images, gist_text, embeddings
bot.py           (51)  Telegram polling → POST /capture
auth.py         (186)  Twitter OAuth 2.0 PKCE flow
sweep.py        (647)  Twitter bookmark + IG + FB saved posts sweep logic
backfill.py     (763)  Resumable full-history backfill for all platforms
preflight.py    (324)  Dry-run health checks + setup page

scripts/
  import_whatsapp.py   (213)  WhatsApp chat export importer
  import_ig_export.py  (199)  IG data download importer
  import_fb_export.py  (227)  FB data download importer

web/src/
  App.tsx        (851)  Single-file React frontend (feed, stats, chat views)
  types.ts        (30)  Source/Status/Item types, CATEGORIES, SOURCES
```

## Setup

```bash
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
cp .env.example .env    # then fill in the keys
cd web && npm install
```

### Required env vars

| var | who needs it | where to get it |
|-----|-------------|-----------------|
| `GEMINI_API_KEY` | API | https://aistudio.google.com/apikey |
| `BOT_TOKEN` | bot | @BotFather on Telegram, `/newbot` |

### Optional env vars

| var | default | purpose |
|-----|---------|---------|
| `SAVEFEED_API_URL` | `http://localhost:8000` | where the bot finds the API |
| `IG_COOKIES_FILE` | unset | path to Netscape cookies.txt for IG authentication |
| `X_CLIENT_ID` | unset | Twitter/X OAuth 2.0 client ID |
| `X_CLIENT_SECRET` | unset | Twitter/X OAuth 2.0 client secret |

`.env` is loaded automatically via `python-dotenv`.

### Cookie setup (Instagram)

1. Install [Get cookies.txt LOCALLY](https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc) in Chrome
2. Go to instagram.com (logged in), click the extension, export cookies
3. Save to `~/.savefeed/cookies.txt`
4. Set `IG_COOKIES_FILE=/Users/you/.savefeed/cookies.txt` in `.env`

Cookies expire every ~90 days. Re-export when the health check turns red.

### Twitter/X setup

1. Sign up at [developer.x.com](https://developer.x.com) (free tier)
2. Create a project + app with OAuth 2.0 PKCE, callback URL: `http://localhost:8000/auth/twitter/callback`
3. Add `X_CLIENT_ID` and `X_CLIENT_SECRET` to `.env`
4. Visit `http://localhost:8000/auth/twitter` to authorize
5. Tokens auto-refresh; re-auth only needed if revoked

## Run

Three processes:

```bash
make api     # FastAPI on :8000
make bot     # Telegram polling
make web     # Vite dev server on :5173
```

Open http://localhost:5173 for the dashboard, or http://localhost:8000/setup for health checks.

The server auto-starts recurring sweeps for Twitter (30 min) and Instagram (30 min). New saves appear in the feed without manual action.

## Backfill (full history import)

Once sweeps are connected, pull your entire saved history:

| Platform | Method | Command |
|----------|--------|---------|
| Twitter | API pagination | `curl -X POST http://127.0.0.1:8000/sweep/twitter/backfill` |
| Instagram | Cookie API pagination | `curl -X POST http://127.0.0.1:8000/sweep/ig/backfill` |
| Facebook | Data export only | `python scripts/import_fb_export.py ~/Downloads/facebook-export.zip` |

Backfills are **resumable** — they save progress to `~/.savefeed/{platform}_backfill_state.json` after every item. If interrupted, re-run the same command to continue.

IG backfill caps at 100 items/session to avoid bans. Run it 2-3 times with breaks between.

Monitor progress: `curl http://127.0.0.1:8000/backfill/status`

## API endpoints

| method | path | what it does |
|--------|------|-------------|
| `POST` | `/capture` | `{payload, note?}` — classify, enqueue, return `{id, source, status}`. Dedupes by URL. |
| `GET` | `/items` | All items, newest first. Filters: `?category=`, `?source=`, `?tag=`, `?q=` |
| `GET` | `/items/{id}` | Raw JSON for one item |
| `POST` | `/items/{id}/retry` | Reset a failed row and re-run the adapter |
| `POST` | `/items/{id}/tags` | `{tags: [...]}` — replace tags |
| `GET` | `/health` | Cookie/auth health with failure rate detection |
| `GET` | `/setup` | Interactive health check + setup guide page |
| `GET` | `/sweep/status` | All sweep statuses (auth, last run, counts) |
| `GET` | `/backfill/status` | All backfill progress |
| `POST` | `/sweep/{platform}` | Trigger one-off sweep (twitter, ig, fb) |
| `POST` | `/sweep/{platform}/backfill` | Trigger full-history backfill |
| `POST` | `/chat` | `{message}` — RAG-powered chat over your saved items |
| `GET` | `/auth/twitter` | Start Twitter OAuth flow |

## Platform status

| Platform | Sweep | Backfill | Status |
|----------|-------|----------|--------|
| **Twitter/X** | OAuth API, 30-min auto | API pagination | **Done** — 97 bookmarks fully backfilled |
| **Instagram** | Cookie API, 30-min auto | API pagination (100/session cap) | **In progress** — ~193 items, more available |
| **Facebook** | Blocked (Meta defenses) | Data export only | **Blocked** — see [BACKFILL_STATUS.md](docs/BACKFILL_STATUS.md) |
| **TikTok** | Not yet | Deferred | Adapter exists (yt-dlp), no sweep |

Facebook cookie scraping was attempted via 5 different approaches (mbasic HTML, www static, GraphQL API, Chrome DOM, network interception) — all blocked by Meta. See [BACKFILL_STATUS.md](docs/BACKFILL_STATUS.md) for full details. **Next approach:** Meta Muse AI agent integration via MCP connector.

## Tech stack

- Python 3.13 + FastAPI + uvicorn
- SQLite with FTS5 full-text search + 768-dim embeddings
- Gemini 2.5-flash (summarization, embeddings, chat)
- yt-dlp (video), trafilatura (articles), syndication (tweets)
- httpx for HTTP clients
- python-telegram-bot (Telegram polling)
- Vite + React 18 + TypeScript + Tailwind CSS (frontend)
- Spotify-inspired dark UI (see [DESIGN.md](DESIGN.md))

## State files

All token/state files live in `~/.savefeed/`, never in the repo:

| file | purpose |
|------|---------|
| `cookies.txt` | IG authentication cookies |
| `fb_cookies.txt` | FB authentication cookies |
| `twitter_tokens.json` | OAuth2 access + refresh tokens |
| `twitter_backfill_state.json` | Twitter backfill progress |
| `ig_backfill_state.json` | IG backfill progress |
| `fb_backfill_state.json` | FB backfill progress |
| `server.log` | Server logs |

## Auto-start on login (macOS)

```bash
launchctl load ~/Library/LaunchAgents/com.savefeed.server.plist
```

## Collaboration

Repo shared with [@reyr13](https://github.com/reyr13) (Reut). Workflow:
- Each person runs Claude Code locally against the repo
- Slack + Claude Tag for brainstorming and research
- Branches + PRs for code changes
