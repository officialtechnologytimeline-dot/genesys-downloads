#!/usr/bin/env bash
# Decrypts the sources, runs the tests, builds the debug APK, uploads APK + log to the owner-only draft.
set -uo pipefail
JOB=$(jq -r .id ci/job.json); VER=$(jq -r .version ci/job.json)
VID=420089377; LOG=/tmp/log-cardkt-$JOB.txt; : > "$LOG"
say(){ echo "$*"; echo "$*" >> "$LOG"; }
asset_id(){ gh api "repos/$REPO/releases/$VID/assets?per_page=100" --jq ".[] | select(.name==\"$1\") | .id" | head -1; }
up(){ local n; n=$(basename "$1"); for a in $(gh api "repos/$REPO/releases/$VID/assets?per_page=100" --jq ".[] | select(.name==\"$n\") | .id"); do gh api -X DELETE "repos/$REPO/releases/assets/$a" >/dev/null; done
  curl -sS -f -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: application/octet-stream" --data-binary @"$1" "https://uploads.github.com/repos/$REPO/releases/$VID/assets?name=$n" -o /dev/null && echo "caricato (privato) $n"; }
finish(){ say "ESITO: $1"; up "$LOG"; [ "$1" = OK ] || exit 1; exit 0; }
say "== cardkt-ci $JOB $(date -u +%FT%TZ)"
umask 077
gh api "repos/$REPO/releases/assets/$(asset_id vault.key)" -H "Accept: application/octet-stream" > /tmp/vault.key || finish "cassaforte non raggiungibile"
openssl pkeyutl -decrypt -inkey /tmp/vault.key -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -in ci/payload.key.enc -out /tmp/one.key || finish "chiave non aperta"
mkdir -p /tmp/p; openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:/tmp/one.key -in ci/payload.enc | tar xz -C /tmp/p || finish "codice non aperto"
rm -f /tmp/vault.key /tmp/one.key
cd /tmp/p/cardkt
mkdir -p ~/.android && cp .ci/debug.keystore ~/.android/debug.keystore; [ -n "${ANDROID_USER_HOME:-}" ] && mkdir -p "$ANDROID_USER_HOME" && cp .ci/debug.keystore "$ANDROID_USER_HOME/debug.keystore" || true
if node tests/cardkt-core-regression.mjs >> "$LOG" 2>&1; then say "test: $(tail -1 "$LOG")"; else finish "TEST FALLITI"; fi
chmod +x gradlew
if ./gradlew --no-daemon --console=plain assembleDebug > /tmp/gradle.log 2>&1; then
  say "assembleDebug: BUILD SUCCESSFUL"; grep -E "^w: |warning:" /tmp/gradle.log | head -60 >> "$LOG" || true
else
  say "assembleDebug: BUILD FAILED"; { grep -E "^e: |error:|FAILURE|What went wrong|^> |\.java:[0-9]+" /tmp/gradle.log | head -120; echo ----; tail -60 /tmp/gradle.log; } >> "$LOG"; finish "COMPILAZIONE FALLITA"
fi
if ./gradlew --no-daemon --console=plain lintDebug > /tmp/lint.log 2>&1; then say "lint: OK"; else say "lint: problemi (non bloccanti per la prova)"; fi
grep -E "Error:|Warning:|errors?,|warnings?" /tmp/lint.log | head -40 >> "$LOG" || true
[ -f app/build/reports/lint-results-debug.txt ] && head -c 60000 app/build/reports/lint-results-debug.txt >> "$LOG"
APK=app/build/outputs/apk/debug/app-debug.apk
[ -f "$APK" ] || finish "APK NON CREATO"
BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
"$BT/apksigner" verify --print-certs "$APK" 2>/dev/null | grep -E "SHA-256" | head -2 >> "$LOG"
"$BT/aapt2" dump badging "$APK" 2>/dev/null | head -2 >> "$LOG"
env | grep -E "^ANDROID" | sed 's/=.*//' >> "$LOG"
OUT="/tmp/cardkt-$VER-debug.apk"
"$BT/apksigner" sign --ks .ci/debug.keystore --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out "$OUT" "$APK" || finish "FIRMA FALLITA"
say "firma fissa: $("$BT/apksigner" verify --print-certs "$OUT" 2>/dev/null | grep -m1 "SHA-256" | sed 's/.*: //')"
 (cd /tmp && sha256sum "$(basename "$OUT")" > "$OUT.sha256"); ls -l "$OUT" >> "$LOG"
up "$OUT"; up "$OUT.sha256"
finish OK
