#!/usr/bin/env bash
# Foto dell'app GENESYS per Android IN INGLESE per il video di presentazione (emulatore, pass di prova vero).
set -uo pipefail
sed -n '1,34p' ci/emu.sh > /tmp/emulib.sh; . /tmp/emulib.sh
S=/tmp/shots; mkdir -p $S; N=0
adb install -r -g /tmp/test/genesys-debug.apk || exit 1
adb shell am start -W -n $ACT; sleep 6
tap "English"; sleep 1; shot en-lingua; tap "=Continue"; sleep 3; shot en-accesso; texts
VID=420089377
AID=$(gh api "repos/$REPO/releases/$VID/assets?per_page=100" --jq '.[] | select(.name=="ci-pass.txt") | .id' | head -1)
PASS=$(gh api "repos/$REPO/releases/assets/$AID" -H "Accept: application/octet-stream" | tr -d '\n\r ')
log "pass di prova: ${#PASS} caratteri"
adb shell am start -W -n $ACT --es genesys_test_pass "$PASS" --es genesys_test_consent "'{\"v\":\"2026-10-15.2\",\"c\":\"IT\",\"s\":true}'" --es genesys_test_language en
sleep 15; adb shell am force-stop $PKG; sleep 1; adb shell am start -W -n $ACT --es genesys_test_language en >/dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do sleep 3; dump; grep -q "7TH DAY" /tmp/ui.xml && break; done
anr; sleep 3; shot en-esplora; texts
for k in 1 2 3 4 5; do adb shell input swipe 500 1700 500 1000 600; sleep 2; shot en-esplora-giu$k; done
adb shell am force-stop $PKG; sleep 1; adb shell am start -W -n $ACT --es genesys_test_language en >/dev/null; sleep 8
tap "Smartphone games first" || tap "games first"; sleep 2; shot en-ordina; tap "Development status" || tap "status"; sleep 3; shot en-per-stato
for k in 1 2; do adb shell input swipe 500 1700 500 1000 600; sleep 2; shot en-per-stato-giu$k; done
opengame(){ adb shell am force-stop $PKG; sleep 1; adb shell am start -W -n $ACT --es genesys_test_language en >/dev/null; sleep 5
  for k in 1 2 3 4 5 6; do tap "=$1" && return 0; adb shell input swipe 500 1500 500 800 400; sleep 1; done; return 1; }
for g in "7TH DAY" "Primal Dominion" "Groundstrike Zero" "Mini-Kart" "Little Shark"; do
  if opengame "$g"; then sleep 3; shot "en-$(echo $g | tr ' A-Z' '-a-z')"; texts; else log "non trovato: $g"; fi
done
adb shell am force-stop $PKG; sleep 1
adb shell am start -W -n $ACT --es genesys_test_seen 0.2.3 --es genesys_test_language en; sleep 6; shot en-novita; texts
cd /tmp && zip -qr foto-app-en.zip shots && ls -l foto-app-en.zip
bash $GITHUB_WORKSPACE/ci/upload.sh /tmp/foto-app-en.zip
