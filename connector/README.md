# Muse connector (experiment)

A tiny MCP server Muse can call to hand saved posts straight to hindsight, with no copy/paste. It's phase 1 of [docs/SYNC_PLAN.md](../docs/SYNC_PLAN.md). The question it answers: **does Meta let Muse pass Instagram/Facebook saves to a third-party connector, and does a daily routine keep doing it?**

Not production: single user, stored in local files, and a random secret in the URL path is the only auth.

## Run it

```bash
cd connector
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt   # once
.venv/bin/python server.py                                           # prints the secret paths
cloudflared tunnel --url http://127.0.0.1:8765                       # prints https://<random>.trycloudflare.com
```

- **MCP URL for Muse:** `https://<tunnel>/<token>/mcp`
- **Pull URL for the app** (Sync with Muse → Muse connector (dev)): `https://<tunnel>/<token>/saves`
- The token is in `data/token`, and stays the same across restarts. **The quick-tunnel hostname changes every time cloudflared restarts,** and the server only runs while the Mac is awake. A routine test needs both to stay up; a stable URL needs a named Cloudflare tunnel or a hosted server.

## Tools Muse sees
- `ping()` returns `"pong"`.
- `submit_saved_posts(posts, sync_id?, final_batch?)`: up to 50 posts per call, keyed like the data contract's `posts[]` (`url`, `platform`, `kind`, `author`, `author_display_name`, `caption`, `mentions`, `collections`, `saved_at`, `posted_at`, `location_tag`, `thumbnail_url`). It's idempotent: posts are deduped by the same id rule as the app (`platform:shortcode`), and a re-send with a longer caption replaces the shorter one. Returns `{accepted, duplicates, rejected, continue}`.

## What to check
- `data/calls.log`: one JSON line per call (time, batch size, accepted, platforms, caption length). **This is how we see whether a daily routine actually fires.**
- `data/saves.json`: everything received.

## Test script (on the phone)
1. In Muse, add a custom connector with the MCP URL. Either ask in chat ("add a custom connector, MCP server URL …") or use Settings → Connectors → Add custom.
2. "Ping the hindsight connector": `ping` shows up in `calls.log`.
3. "Send my 10 most recent Instagram saves to hindsight": do 10 arrive with full captions and collections?
4. Scale up: 50, 100, then "all of them, in batches".
5. Facebook: "send my Facebook saved items to hindsight".
6. Routine: "Every day at 9am, send my new Instagram saves since the last run to hindsight." Check `calls.log` the next day, with Muse closed and the phone locked.
