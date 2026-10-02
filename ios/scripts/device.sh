#!/bin/zsh
# Build + install on a connected iPhone, or pull the app's debug log.
#   scripts/device.sh install      build, install, launch
#   scripts/device.sh log          copy debug-log.txt off the phone and print it
# Server: if ../connector/data/token exists, the app is launched pointing at the
# connector (HINDSIGHT_CONNECTOR_URL, default the ngrok domain + that token), so a
# reinstall never leaves it without a server. Skip with HINDSIGHT_CONNECTOR_URL=none.
# Signing: uses project.yml's team unless you override for your own free team:
#   HINDSIGHT_TEAM=XXXXXXXXXX HINDSIGHT_BUNDLE_ID=com.you.hindsight scripts/device.sh install
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /(available|connected)/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) {print $i; exit}}')
[[ -z "$DEVICE" ]] && { echo "No iPhone connected (plug it in, unlock it)."; exit 1; }
BUNDLE_ID=${HINDSIGHT_BUNDLE_ID:-com.reutrabin.hindsight}
OVERRIDES=()
[[ -n "${HINDSIGHT_TEAM:-}" ]] && OVERRIDES+=(DEVELOPMENT_TEAM=$HINDSIGHT_TEAM)
[[ -n "${HINDSIGHT_BUNDLE_ID:-}" ]] && OVERRIDES+=(PRODUCT_BUNDLE_IDENTIFIER=$HINDSIGHT_BUNDLE_ID)
DERIVED=${TMPDIR:-/tmp}/hindsight-device-build
# The token lives in the main checkout (connector/data is gitignored), also when run from a worktree.
TOKEN_FILE="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/connector/data/token"
CONNECTOR_URL=${HINDSIGHT_CONNECTOR_URL:-}
[[ -z "$CONNECTOR_URL" && -f "$TOKEN_FILE" ]] && CONNECTOR_URL="https://supermom-depose-retail.ngrok-free.dev/$(cat "$TOKEN_FILE")"
LAUNCH_ARGS=()
[[ -n "$CONNECTOR_URL" && "$CONNECTOR_URL" != none ]] && LAUNCH_ARGS+=(-museConnectorBaseURL "$CONNECTOR_URL")

case "${1:-install}" in
  install)
    xcodegen -q
    UDID=$(xcrun devicectl device info details --device "$DEVICE" 2>/dev/null | awk '/udid:/ {print $NF; exit}')
    xcodebuild build -project Hindsight.xcodeproj -scheme Hindsight -destination "id=$UDID" \
      -allowProvisioningUpdates -derivedDataPath "$DERIVED" -quiet "${OVERRIDES[@]}"
    xcrun devicectl device install app --device "$DEVICE" "$DERIVED/Build/Products/Debug-iphoneos/Hindsight.app" >/dev/null
    xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID" "${LAUNCH_ARGS[@]}" >/dev/null
    echo "Installed and launched $BUNDLE_ID$( (( ${#LAUNCH_ARGS} )) && echo " (with the connector URL)")"
    ;;
  log)
    xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" --source "Library/Application Support/debug-log.txt" \
      --destination "$DERIVED-log.txt" >/dev/null
    cat "$DERIVED-log.txt"
    ;;
  *) echo "usage: $0 install|log"; exit 1 ;;
esac
