#!/bin/bash
# Mac only (until real hosting): keep the connector and its ngrok tunnel running,
# started at login and restarted if they crash, and run the backfill (new Instagram
# saves + X bookmarks → connector) every 6 hours. Re-run after moving the repo.
#   NGROK_URL  the reserved ngrok domain (default: the dev one in docs/HANDOFF.md)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
NGROK="$(command -v ngrok)"
NGROK_URL="${NGROK_URL:-supermom-depose-retail.ngrok-free.dev}"
AGENTS=~/Library/LaunchAgents
mkdir -p "$DIR/data"
write() { # label, log file, program args...
  local label=$1 log=$2; shift 2
  local args=""; for a in "$@"; do args+="<string>$a</string>"; done
  cat > "$AGENTS/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>$args</array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>StandardOutPath</key><string>$DIR/data/$log</string>
  <key>StandardErrorPath</key><string>$DIR/data/$log</string>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
PLIST
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null && sleep 2 || true
  launchctl bootstrap "gui/$(id -u)" "$AGENTS/$label.plist"
  echo "loaded $label"
}
write com.hindsight.connector server.out "$DIR/.venv/bin/python" "$DIR/server.py"
# ngrok 3.39 prints nothing (and may stall) with --log=stdout when not on a terminal; log to a file.
write com.hindsight.ngrok ngrok.out "$NGROK" http 8765 "--url=$NGROK_URL" "--log=$DIR/data/ngrok.log"

# Backfill: a periodic job, not a daemon.
cat > "$AGENTS/com.hindsight.backfill.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.hindsight.backfill</string>
  <key>ProgramArguments</key><array><string>$DIR/../venv/bin/python</string><string>$DIR/backfill.py</string></array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>StandardOutPath</key><string>$DIR/data/backfill.log</string>
  <key>StandardErrorPath</key><string>$DIR/data/backfill.log</string>
  <key>StartInterval</key><integer>21600</integer>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/com.hindsight.backfill" 2>/dev/null && sleep 2 || true
launchctl bootstrap "gui/$(id -u)" "$AGENTS/com.hindsight.backfill.plist"
echo "loaded com.hindsight.backfill"
