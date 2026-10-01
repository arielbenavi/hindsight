#!/bin/bash
# Is the bot still linked? Appends one line to state/health.log and shows a Mac
# notification when something needs Ariel. Runs every 2 days via launchd.
#
# Also tests our assumption that WhatsApp logs a linked device out when its
# primary phone stays offline ~14 days:
#   ./healthcheck.sh opened   → record "I opened WhatsApp on the bot phone today"
# The log then shows days since the phone was last opened next to the bot's status,
# and a reminder fires from day 10.
cd "$(dirname "$0")"
mkdir -p state
LOG=state/health.log OPENED=state/phone_opened
now=$(date +%s)

if [ "$1" = "opened" ]; then
  date -u +%Y-%m-%dT%H:%M:%SZ > "$OPENED"
  echo "$(date '+%F %T') bot phone opened" >> "$LOG"; echo "Noted."; exit 0
fi

field() { /usr/bin/python3 -c "import json,sys;print(json.load(open('state/health.json')).get('$1') or '')" 2>/dev/null; }
status=$(field status); last_connected=$(field lastConnected); last_message=$(field lastMessage)
pgrep -f "node bot.js" >/dev/null && running=yes || running=no

days_since() { [ -n "$1" ] || { echo "?"; return; }
  t=$(date -j -u -f %Y-%m-%dT%H:%M:%S "${1%%.*}" +%s 2>/dev/null) || { echo "?"; return; }
  echo $(( (now - t) / 86400 )); }
opened_days=$(days_since "$(cat "$OPENED" 2>/dev/null)")

line="$(date '+%F %T') running=$running status=${status:-unknown} last_connected=${last_connected:-never} last_message=${last_message:-never} phone_opened_days_ago=$opened_days"
echo "$line" >> "$LOG"; echo "$line"

notify() { osascript -e "display notification \"$1\" with title \"hindsight WhatsApp bot\"" 2>/dev/null; }
if [ "$status" = "logged_out" ]; then
  notify "Logged out after $opened_days days without opening the bot phone. Re-link: see whatsapp-bot/README.md"
elif [ "$running" = "no" ]; then
  notify "The bot isn't running."
elif [ "$opened_days" != "?" ] && [ "$opened_days" -ge 10 ]; then
  notify "Open WhatsApp on the bot phone (last opened $opened_days days ago), then run: whatsapp-bot/healthcheck.sh opened"
fi
