#!/bin/zsh
# Make the connector look like a brand-new user's: moves saves.json and
# calls.log into data/archive-<time>/ (nothing is deleted). Keeps the token,
# so the MCP URL Muse knows stays the same. Restart the server afterwards.
set -euo pipefail
cd "$(dirname "$0")/data"
stamp=$(date +%Y%m%d-%H%M%S)
mkdir -p "archive-$stamp"
for f in saves.json calls.log; do [[ -f $f ]] && mv "$f" "archive-$stamp/"; done
echo "Archived to connector/data/archive-$stamp. Restart server.py."
