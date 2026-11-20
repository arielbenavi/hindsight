#!/bin/zsh
# Build an UNSIGNED Release .ipa for SideStore / LiveContainer and drop it in iCloud Drive.
#   scripts/ipa.sh            → ~/Library/Mobile Documents/com~apple~CloudDocs/Hindsight.ipa
# On the phone: LiveContainer → Apps → + → Hindsight.ipa → replace (same bundle id, data stays).
# The server URL is baked in (launch arguments don't reach an app inside LiveContainer):
# HINDSIGHT_CONNECTOR_URL, default the ngrok domain + the token in the main checkout's
# connector/data/token. HINDSIGHT_CONNECTOR_URL=none builds without a server.
set -euo pipefail
cd "$(dirname "$0")/.."
TOKEN_FILE="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/connector/data/token"
URL=${HINDSIGHT_CONNECTOR_URL:-}
[[ -z "$URL" && -f "$TOKEN_FILE" ]] && URL="https://supermom-depose-retail.ngrok-free.dev/$(cat "$TOKEN_FILE")"
[[ "$URL" == none ]] && URL=""
OUT=${TMPDIR:-/tmp}/hindsight-ipa; rm -rf "$OUT/stage"; mkdir -p "$OUT/stage/Payload"
xcodegen -q
xcodebuild build -project Hindsight.xcodeproj -scheme Hindsight -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath "$OUT/dd" -quiet \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" "HINDSIGHT_SERVER_URL=$URL"
cp -R "$OUT/dd/Build/Products/Release-iphoneos/Hindsight.app" "$OUT/stage/Payload/"
(cd "$OUT/stage" && rm -f "$OUT/Hindsight.ipa" && zip -qry "$OUT/Hindsight.ipa" Payload)
DEST="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
[[ -d "$DEST" ]] && cp "$OUT/Hindsight.ipa" "$DEST/Hindsight.ipa" && echo "Copied to iCloud Drive: Hindsight.ipa${URL:+ (server URL baked in)}" || echo "Built $OUT/Hindsight.ipa"
