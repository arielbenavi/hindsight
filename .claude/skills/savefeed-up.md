---
name: savefeed-up
description: Start (or restart) the savefeed API server, Telegram bot, and Vite dev server. Use whenever code changes need a restart, or when any of the three processes isn't running.
trigger: auto
match:
  - server
  - restart
  - start
  - run
  - bot
  - up
---

# savefeed-up

Ensure all three savefeed processes are running. Kill and restart any that are already up (to pick up code changes). Run each in the background.

## Steps

1. **API server** (port 8000):
   ```bash
   lsof -ti:8000 2>/dev/null | xargs kill -9 2>/dev/null
   sleep 1
   cd /Users/arismac/Sync/win_mac_sync/dev/savefeed/web/backend && ./venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 &
   ```

2. **Telegram bot**:
   ```bash
   pkill -f 'python bot.py' 2>/dev/null
   sleep 1
   cd /Users/arismac/Sync/win_mac_sync/dev/savefeed/web/backend && ./venv/bin/python bot.py &
   ```

3. **Vite dev server** (port 5173):
   ```bash
   lsof -ti:5173 2>/dev/null | xargs kill -9 2>/dev/null
   sleep 1
   cd /Users/arismac/Sync/win_mac_sync/dev/savefeed/web/frontend && npm run dev &
   ```

4. Wait 2 seconds, then verify all three are up:
   ```bash
   curl -s http://localhost:8000/health | python3 -c "import sys,json; print('API:', json.load(sys.stdin).get('message'))"
   ps aux | grep -q '[p]ython bot.py' && echo 'Bot: running' || echo 'Bot: NOT running'
   curl -s http://localhost:5173 >/dev/null && echo 'Vite: running' || echo 'Vite: NOT running'
   ```

Do NOT ask the user to restart anything. Just do it.
