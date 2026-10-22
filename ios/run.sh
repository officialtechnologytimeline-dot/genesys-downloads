#!/usr/bin/env bash
# Prova della web app GENESYS sul simulatore iPhone. Foto ogni 12 s + foto del test -> cassaforte privata (ios-shots.zip).
set -uo pipefail
URL=$(jq -r .url ci/job.json); MODE=$(jq -r ".mode // \"home\"" ci/job.json); WATCH=$(jq -r ".watch // 1080" ci/job.json)
echo "== GENESYS iPhone $(jq -r .id ci/job.json) $(date -u +%FT%TZ) · $URL"
xcodebuild -version | head -2
brew install xcodegen >/dev/null 2>&1 || { echo "xcodegen non installato"; exit 1; }
xcrun simctl list runtimes | grep -i ios | tail -2
LINE=$(xcrun simctl list devices available | grep -E "^\s+iPhone 16 \(" | head -1)
[ -n "$LINE" ] || LINE=$(xcrun simctl list devices available | grep -E "^\s+iPhone [0-9]+ \(" | tail -1)
UDID=$(echo "$LINE" | grep -oE "[A-F0-9-]{36}"); echo "dispositivo: $LINE"
xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null; echo "acceso"
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true
mkdir -p /tmp/shots
( i=0; while true; do i=$((i+1)); xcrun simctl io "$UDID" screenshot --type=jpeg "/tmp/shots/$(printf %03d $i)-$(date +%H%M%S).jpg" >/dev/null 2>&1; sleep 12; done ) & LOOP=$!
xcrun simctl openurl "$UDID" "$URL"; echo "pagina aperta in Safari"
cd ios && xcodegen generate --quiet && echo "progetto generato"
TEST_RUNNER_GENESYS_URL="$URL" TEST_RUNNER_GENESYS_MODE="$MODE" TEST_RUNNER_GENESYS_WATCH="$WATCH" xcodebuild test -project GenesysSim.xcodeproj -scheme SimUITests -destination "id=$UDID" -resultBundlePath /tmp/R.xcresult CODE_SIGNING_ALLOWED=NO > /tmp/xcb.log 2>&1; RC=$?
grep -E "\[ios\]|error:|Test Case|\*\* TEST" /tmp/xcb.log | cut -c1-600
[ $RC -ne 0 ] && tail -40 /tmp/xcb.log
kill $LOOP 2>/dev/null
mkdir -p /tmp/shots/test && (xcrun xcresulttool export attachments --path /tmp/R.xcresult --output-path /tmp/shots/test >/dev/null 2>&1 || true)
ls /tmp/shots | wc -l; ls /tmp/shots/test | head -20
cd /tmp && zip -qr ios-shots.zip shots && ls -l ios-shots.zip
bash "$GITHUB_WORKSPACE/ci/upload.sh" /tmp/ios-shots.zip
echo "FINE (xcodebuild $RC)"
