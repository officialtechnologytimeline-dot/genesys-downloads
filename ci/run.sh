#!/usr/bin/env bash
# GENESYS for Android CI. ci/job.json says what to do: vault | build | publish.
set -euo pipefail
JOB=$(jq -r .id ci/job.json); KIND=$(jq -r .kind ci/job.json)
echo "== GENESYS CI job $JOB ($KIND) $(date -u +%FT%TZ)"
vault_id(){ gh api "repos/$REPO/releases?per_page=100" --jq '.[] | select(.draft and .name=="genesys-ci-vault") | .id' | head -1; }
VID=$(vault_id)
if [ -z "$VID" ]; then
  echo "creo la cassaforte privata (release in bozza)"
  umask 077; openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out /tmp/vault.key 2>/dev/null
  openssl pkey -in /tmp/vault.key -pubout -out vault-public.pem
  cp /tmp/vault.key vault.key
  gh release create genesys-ci-vault --draft --title genesys-ci-vault --notes "Area privata della compilazione di GENESYS per Android. Bozza: visibile solo ai proprietari del repository. Non pubblicare." vault.key vault-public.pem
  rm -f vault.key; VID=$(vault_id)
fi
echo "cassaforte $VID"
asset_id(){ gh api "repos/$REPO/releases/$VID/assets?per_page=100" --jq ".[] | select(.name==\"$1\") | .id" | head -1; }
get(){ local id; id=$(asset_id "$1"); [ -n "$id" ] || { echo "manca $1"; return 1; }; gh api "repos/$REPO/releases/assets/$id" -H "Accept: application/octet-stream" > "$2"; }
up(){ local n; n=$(basename "$1"); for a in $(gh api "repos/$REPO/releases/$VID/assets?per_page=100" --jq ".[] | select(.name==\"$n\") | .id"); do gh api -X DELETE "repos/$REPO/releases/assets/$a"; done
  curl -sS -f -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: application/octet-stream" --data-binary @"$1" "https://uploads.github.com/repos/$REPO/releases/$VID/assets?name=$n" -o /dev/null; echo "caricato (privato) $n"; }
open_enc(){ # $1 = encrypted tar.gz, $2 = its RSA-wrapped key, $3 = destination
  umask 077; mkdir -p "$3"; [ -f /tmp/vault.key ] || get vault.key /tmp/vault.key
  openssl pkeyutl -decrypt -inkey /tmp/vault.key -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -in "$2" -out /tmp/one.key
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:/tmp/one.key -in "$1" | tar xz -C "$3"
  rm -f /tmp/one.key; echo "aperto $1"
}
BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
case "$KIND" in
  vault)
    get vault-public.pem vault-public.pem; echo "CHIAVE PUBBLICA DELLA CASSAFORTE:"; cat vault-public.pem
    echo "build-tools: $BT"; ls "$ANDROID_HOME/platforms"
    ;;
  build)
    VER=$(jq -r .version ci/job.json)
    open_enc ci/payload.enc ci/payload.key.enc /tmp/p
    open_enc ci/keys.enc ci/keys.key.enc /tmp/keys
    rm -f /tmp/vault.key
    cd /tmp/p/genesys-android
    set -a; . /tmp/keys/signing.env; set +a
    export GENESYS_KEYSTORE=/tmp/keys/genesys-android.p12
    if ! gradle --no-daemon --console=plain -PgenesysVersion="$VER" assembleRelease > /tmp/gradle.log 2>&1; then
      grep -E "^e: |error:|FAILURE|What went wrong|^> " /tmp/gradle.log | head -80; tail -40 /tmp/gradle.log; exit 1
    fi
    grep -E "^w: |BUILD SUCCESSFUL" /tmp/gradle.log | tail -40 || true
    APK=app/build/outputs/apk/release/app-release.apk
    [ -f "$APK" ] || { echo "APK NON CREATO"; exit 1; }
    "$BT/apksigner" verify --print-certs "$APK" | grep -v "^WARNING" | head -8
    "$BT/aapt2" dump badging "$APK" | head -3
    OUT="genesys-android-$VER.apk"; cp "$APK" "$OUT"; sha256sum "$OUT" | tee "$OUT.sha256"; ls -l "$OUT"
    up "$OUT"; up "$OUT.sha256"
    ;;
  catalog)
    jq -e . ci/android-catalog.json >/dev/null
    cp ci/android-catalog.json android-catalog.json
    gh release upload genesys-channel android-catalog.json --clobber
    echo "catalogo Android pubblicato"
    ;;
  source)
    VER=$(jq -r .version ci/job.json)
    open_enc ci/payload.enc ci/payload.key.enc /tmp/p; rm -f /tmp/vault.key
    tar czf "genesys-android-source-$VER.tgz" -C /tmp/p genesys-android
    up "genesys-android-source-$VER.tgz"
    ;;
  test)
    open_enc ci/payload.enc ci/payload.key.enc /tmp/p
    rm -f /tmp/vault.key
    cd /tmp/p/genesys-android
    if ! gradle --no-daemon --console=plain assembleDebug > /tmp/gradle.log 2>&1; then
      grep -E "^e: |error:|FAILURE|What went wrong|^> " /tmp/gradle.log | head -80; tail -40 /tmp/gradle.log; exit 1
    fi
    mkdir -p /tmp/test && cp app/build/outputs/apk/debug/app-debug.apk /tmp/test/genesys-debug.apk && ls -l /tmp/test
    ;;
  publish)
    VER=$(jq -r .version ci/job.json); TAG="android-$VER"; OUT="genesys-android-$VER.apk"
    get "$OUT" "$OUT"; get "$OUT.sha256" "$OUT.sha256"; sha256sum -c "$OUT.sha256"
    jq -e . ci/android-catalog.json >/dev/null
    if ! gh release view "$TAG" >/dev/null 2>&1; then
      gh release create "$TAG" --title "GENESYS per Android $VER" --notes "App GENESYS per smartphone Android. Si installa dal sito GENESYS; da qui scarica, aggiorna e avvia i giochi." "$OUT" "$OUT.sha256"
    else gh release upload "$TAG" "$OUT" "$OUT.sha256" --clobber; fi
    cp ci/android-catalog.json android-catalog.json
    gh release upload genesys-channel android-catalog.json --clobber
    echo "pubblicato $TAG e android-catalog.json"
    ;;
  *) echo "lavoro sconosciuto: $KIND"; exit 1;;
esac
echo "FINE-OK"
