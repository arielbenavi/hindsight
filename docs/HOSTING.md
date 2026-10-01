# Hosting (decision pending: Ariel + Reut)

What needs to run 24/7, and why:

| Service | Code | Why always-on | State |
|---|---|---|---|
| **Connector** | `connector/server.py` | Muse's daily routine calls it; the app pulls from it; the WhatsApp bot posts to it | `saves.json`, `calls.log`, `token` (one volume) |
| **WhatsApp bot** | `whatsapp-bot/bot.js` | must stay connected to receive new messages | `auth/` (bot login), `state/` (one volume) |
| Later: processing | port of `web/backend` | transcripts, summaries, embeddings | database + temp video files |

Today both run on Ariel's Mac (connector behind ngrok), so they only work while the Mac is awake.

## Options (two always-on processes rule out serverless-only hosts)

| Option | Fits? | Why | ~Cost |
|---|---|---|---|
| **Railway** | ✅ | easiest; always-on services + volumes; deploys from GitHub on push | ~$5–10/mo |
| **Fly.io** | ✅ | same model; configs already in the repo | ~$5–10/mo |
| **Render** | ✅ | always-on background workers + disks | ~$7–15/mo |
| Small VPS (Hetzner, DigitalOcean) | ✅ | cheapest, full control, but we maintain it | ~$5/mo |
| Google Cloud Run | ⚠️ | scales to zero, no disk: OK for the connector with a DB, **bad for the bot** | ~$0–10 |
| Vercel | ❌ | short-lived serverless functions: **can't keep the bot connected**, no disk | n/a |

Later, for real users: **Supabase** (hosted Postgres + auth) for accounts and the saves database.

## Recommendation: Railway or Fly.io
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
