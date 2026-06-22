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

Optional: `SAVEFEED_API_URL` (default `http://localhost:8000`) — used by
the bot to find the API.

`.env` is loaded automatically by both processes via `python-dotenv`.

## Run

Two processes, two terminals:

```
# terminal 1 — API
./venv/bin/uvicorn app:app --reload

# terminal 2 — Telegram bot
./venv/bin/python bot.py
```

Then in Telegram, send or forward any message to your bot. The bot replies
`saved #N as <source> (processing…)` and the worker fills in the gist
asynchronously.

## Verify

```
curl localhost:8000/items | jq '.[0]'
```

End-to-end smoke (no Telegram needed):

```
curl -X POST localhost:8000/capture \
  -H 'Content-Type: application/json' \
  -d '{"payload":"https://www.instagram.com/reels/<id>/"}'
```

## Notes

- yt-dlp uses `--cookies-from-browser chrome`, falling back to firefox.
  First IG download on macOS will prompt for Keychain access — allow it.
- The worker is FastAPI `BackgroundTasks`. On restart, pending rows are
  drained on startup. Fine for low volume; swap for a real queue later.
- DB is `./savefeed.db` (gitignored). Schema columns and types are
  Postgres-compatible; only `INTEGER PRIMARY KEY AUTOINCREMENT` needs to
  become `BIGSERIAL` / `GENERATED ALWAYS AS IDENTITY` on swap.
