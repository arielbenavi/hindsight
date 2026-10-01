#!/bin/bash
# Mac only: keep the bot running (restarts on crash/login) and run the health check
# every 2 days. Re-run after moving the repo or changing Node versions.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
NODE_DIR="$(dirname "$(command -v node)")"
AGENTS=~/Library/LaunchAgents
write() { # label, program, extra keys
  cat > "$AGENTS/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array><string>$2</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$NODE_DIR:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>StandardOutPath</key><string>$DIR/state/bot.log</string>
  <key>StandardErrorPath</key><string>$DIR/state/bot.log</string>
  $3
</dict></plist>
PLIST
  launchctl bootout "gui/$(id -u)/$1" 2>/dev/null && sleep 2 || true
  launchctl bootstrap "gui/$(id -u)" "$AGENTS/$1.plist"
  echo "loaded $1"
}
mkdir -p "$DIR/state"
write com.hindsight.whatsapp-bot "$DIR/run.sh" "<key>RunAtLoad</key><true/><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>"
write com.hindsight.whatsapp-bot-health "$DIR/healthcheck.sh" "<key>StartInterval</key><integer>172800</integer>"
