# savefeed

Continuous-ingest spine for saved content. Forward a link or a note to the
Telegram bot; it lands in SQLite with a Gemini-generated gist.

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

Two processes, two terminals:

```
# terminal 1 — API
make api

# terminal 2 — Telegram bot
make bot
```

(Or call uvicorn / python directly — see the Makefile.)

Then in Telegram, send or forward any message to your bot. The bot replies
`saved #N as <source> (processing…)` and the worker fills in the gist
asynchronously.

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

## Notes

- yt-dlp uses `--cookies-from-browser chrome`, falling back to firefox.
  First IG download on macOS will prompt for Keychain access — allow it.
- The worker is FastAPI `BackgroundTasks`. On restart, pending rows are
  drained on startup. Fine for low volume; swap for a real queue later.
- DB is `./savefeed.db` (gitignored). Schema columns and types are
  Postgres-compatible; only `INTEGER PRIMARY KEY AUTOINCREMENT` needs to
  become `BIGSERIAL` / `GENERATED ALWAYS AS IDENTITY` on swap.
