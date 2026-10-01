# Hosting (decision pending: Ariel + Reut)

What needs to run 24/7, and why:

| Service | Code | Why always-on | State |
|---|---|---|---|
| **Connector** | `connector/server.py` | Muse's daily routine calls it; the app pulls from it; the WhatsApp bot posts to it | `saves.json`, `calls.log`, `token` (one volume) |
| **WhatsApp bot** | `whatsapp-bot/bot.js` | must stay connected to receive new messages | `auth/` (bot login), `state/` (one volume) |
| Later: processing | port of `web/backend` | transcripts, summaries, embeddings | database + temp video files |

Today both run on Ariel's Mac (connector behind ngrok), so they only work while the Mac is awake.

## Recommendation: Fly.io
- Both services are small, long-running processes with a disk, which is exactly Fly's model (~$2–5/mo each on the smallest machines + 1 GB volumes).
- Ready: `connector/Dockerfile` + `connector/fly.toml`, `whatsapp-bot/Dockerfile`.
- Deploy (once there's an account): see the comments at the top of `connector/fly.toml`. The bot is the same with `HINDSIGHT_INGEST_URL=https://hindsight-connector.fly.dev/<token>/ingest` and a volume mounted at `/data`. The first start shows a pairing code in `fly logs`.
- Then the app's connector URL becomes `https://hindsight-connector.fly.dev/<token>` (no ngrok), and Muse gets that URL.

## Why not Cloud Run (yet)
Scales to zero and has no persistent disk: the bot can't stay connected, and `saves.json` would have to move to a database. Fine later, once there's a real database and per-user accounts.

## Before real users (any host)
- **Per-user accounts:** today it's one store and one secret path. Needs user ids, auth for the app (Sign in with Apple), per-user connector URLs/tokens for Muse, and the bot mapping WhatsApp chats to users (e.g. a one-time code the user sends the bot).
- A real database instead of `saves.json`.
- Backups, and deletion on request (privacy).
