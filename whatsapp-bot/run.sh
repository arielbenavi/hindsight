#!/bin/bash
# Starts the bot against the local connector (used by launchd, see README "Run it on the Mac").
cd "$(dirname "$0")"
export HINDSIGHT_INGEST_URL="${HINDSIGHT_INGEST_URL:-http://127.0.0.1:8765/$(cat ../connector/data/token)/ingest}"
exec "$(command -v node || echo /opt/homebrew/bin/node)" bot.js
