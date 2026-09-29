# hindsight

Personal content aggregator for saved posts across Twitter, Instagram, Facebook, and TikTok. Automatically scrapes your saved/bookmarked content, summarizes it with Gemini, and serves a searchable dashboard with RAG-powered chat.

Sources today: Instagram reels (yt-dlp + Gemini video), web articles
(trafilatura + Gemini text), free-form notes (Gemini text), tweets (stub —
URL + note only, no fetch).

## Layout

```
app.py        # FastAPI: POST /capture, GET /items, GET /items/{id}
db.py         # SQLite schema + helpers (Postgres-portable types)
router.py     # classify a payload into (source, url)
gemini.py     # Files API + text gist, with retry on 5xx/429
adapters.py   # ig_reel / web / note / tweet processors
bot.py        # Telegram front door (separate process)
```

## Setup

```
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
cp .env.example .env    # then fill in the two keys
```

Required env vars:

| var              | who needs it | where to get it                         |
|------------------|--------------|-----------------------------------------|
| `GEMINI_API_KEY` | API          | https://aistudio.google.com/apikey      |
| `BOT_TOKEN`      | bot          | @BotFather on Telegram, `/newbot`       |

Optional:

| var                | default                  | purpose                                  |
|--------------------|--------------------------|------------------------------------------|
| `SAVEFEED_API_URL` | `http://localhost:8000`  | where the bot finds the API              |
| `IG_COOKIES_FILE`  | unset                    | path to a Netscape cookies.txt for IG + X — bypasses the macOS keychain prompts that `--cookies-from-browser` triggers on every capture. See **Getting cookies.txt** below. |

`.env` is loaded automatically by both processes via `python-dotenv`.

### Getting cookies.txt

`yt-dlp` and `gallery-dl` both accept Netscape-format cookies.txt files via
`--cookies <file>`. With `IG_COOKIES_FILE` pointing at one, captures stop
reaching into Chrome's keychain (no more "savefeed wants to access
keychain" popups) and authenticate via the file instead.

1. Install a Netscape cookie-export extension in your browser. **Get
   cookies.txt LOCALLY** (Chrome / Firefox) is the common pick — it runs
   entirely client-side, no upload.
2. Log into **instagram.com** in that browser, click the extension, export
   cookies for the current site to a file, e.g. `~/.savefeed/cookies.txt`.
3. Log into **x.com** in the same browser, export again — most extensions
   append to the same file if you give it the same name, or you can
   concatenate two exports yourself (the format is one cookie per line and
   cookies are scoped by domain, so order doesn't matter).
4. Set `IG_COOKIES_FILE=/abs/path/to/cookies.txt` in `.env`.

Cookies expire (IG/X rotate session cookies on a multi-week cadence). When
captures start failing with auth errors, log in again in the browser and
re-export the file. The API logs a clear warning at boot if the path is
set but the file is missing or empty.

## Run

Three processes, three terminals:

```
make api     # tab 1 — FastAPI on :8000
make bot     # tab 2 — Telegram polling
make web     # tab 3 — Vite dev server on :5173 (optional, see Frontend)
```

(Or call uvicorn / python / npm directly — see the Makefile.)

Then in Telegram, send or forward any message to your bot. The bot replies
`saved #N as <source> (processing…)` and the worker fills in the gist
asynchronously.

## Frontend

A Vite + React + TypeScript + Tailwind feed lives in [./web](./web). It
reads the FastAPI backend over the wire — no SSR, just a SPA hitting
`/items` with `?category=`, `?source=`, `?q=` filters.

First-time setup:

```
cd web
npm install
```

Run the dev server (in a separate terminal from `make api`):

```
make web        # or: cd web && npm run dev
```

Open <http://localhost:5173>. The page is mobile-friendly (same `max-w-2xl`
single-column layout at every width — it's a feed, not a dashboard) and
polls the API every 15s so newly-forwarded items appear without a manual
refresh.

The API URL is hard-coded to `http://localhost:8000` but can be overridden
at build time with `VITE_API_URL=...` in `web/.env.local`. CORS for the
Vite origin is wired up in [app.py](app.py).

Failed rows get an inline `↻ retry` button (POSTs `/items/{id}/retry`).
Card actions: `↗ open original` opens the source URL in a new tab,
`details →` opens the existing `/items/{id}/pretty` page served by the
API.

## How to test

End-to-end without Telegram, in three steps:

1. **Start the API.** In one terminal: `make api`. Wait for
   `Application startup complete`.

2. **Capture one of each source** with curl:

   ```
   # IG reel — exercises yt-dlp + Gemini Files API
   curl -X POST localhost:8000/capture -H 'Content-Type: application/json' \
     -d '{"payload":"https://www.instagram.com/reels/<id>/"}'

   # Web article — exercises trafilatura + Gemini text
   curl -X POST localhost:8000/capture -H 'Content-Type: application/json' \
     -d '{"payload":"https://en.wikipedia.org/wiki/Kalman_filter"}'

   # Free-form note — exercises Gemini text only
   curl -X POST localhost:8000/capture -H 'Content-Type: application/json' \
     -d '{"payload":"random idea I want to come back to later"}'

   # Tweet — stub, returns done immediately
   curl -X POST localhost:8000/capture -H 'Content-Type: application/json' \
     -d '{"payload":"https://x.com/some/status/123","note":"context"}'
   ```

   Each call returns `{"id":N,"source":...,"status":"pending"}` fast.

3. **Eyeball the result.** Open <http://localhost:8000/items/pretty> in a
   browser — newest first, columns for source / status / category /
   summary / on-screen text. Refresh as the worker fills rows in
   (IG reels take ~20–40s; text gists are a few seconds).

   For raw JSON: `curl localhost:8000/items | jq`.

**Telegram path:** once the bot is running (`make bot`), forward an IG reel
post to your bot. You should get a `saved #N as ig_reel (processing…)`
reply, and the row should appear on `/items/pretty` with a gist shortly
after.

## API endpoints

| method | path | what it does |
|---|---|---|
| `POST` | `/capture` | Body `{payload, note?}`. Classifies, enqueues, returns `{id, source, status}`. Re-POSTing a known URL returns the existing row with `deduped: true` instead of duplicating. |
| `GET`  | `/items` | All items, newest first. Composable query params: `?category=`, `?source=`, `?tag=`, `?q=` (LIKE across summary/transcript/raw_text/on_screen_text). |
| `GET`  | `/items/{id}` | Raw JSON for one item. |
| `GET`  | `/items/{id}/pretty` | HTML detail view with chips, full summary, key-takeaways list, on-screen text, collapsible transcript + raw text, and the tag editor. |
| `GET`  | `/items/pretty` | HTML table view of all items (no filters). |
| `POST` | `/items/{id}/retry` | Resets a `failed` row to `pending` and re-runs the adapter. No-op on `done`/`pending`. |
| `POST` | `/items/{id}/tags` | Body `{tags: [...]}` — replaces the tag array. Server lowercases, strips, dedupes, caps at 20. |
| `GET`  | `/health` | Looks at the last 10 ig_reel/tweet captures and flags `warn: true` if ≥3 of the last 5 failed with an auth-wall signature ("login required", "restricted video", "rate-limit", etc.). The frontend banner reads this. Use it to detect expired cookies. |

## Notes

- yt-dlp uses `--cookies-from-browser chrome`, falling back to firefox.
  First IG download on macOS will prompt for Keychain access — allow it.
- The worker is FastAPI `BackgroundTasks`. On restart, pending rows are
  drained on startup. Fine for low volume; swap for a real queue later.
- DB is `./savefeed.db` (gitignored). Schema columns and types are
  Postgres-compatible; only `INTEGER PRIMARY KEY AUTOINCREMENT` needs to
  become `BIGSERIAL` / `GENERATED ALWAYS AS IDENTITY` on swap.
