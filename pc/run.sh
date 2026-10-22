#!/usr/bin/env bash
# Installa e prova GENESYS (versione in ci/job.json) su questo computer.
set -uo pipefail
V=$(jq -r .version ci/job.json); B="https://github.com/$REPO/releases/download/v$V"
echo "== GENESYS $V su $KIND ($(uname -a | cut -c1-80))"
mkdir -p dl shots prof
case "$KIND" in
  windows)   F="GENESYS-Setup-$V-x64.exe";;
  linux)     F="GENESYS-$V-linux-x86_64.AppImage";;
  mac-intel) F="GENESYS-$V-mac-x64.dmg";;
  mac-apple) F="GENESYS-$V-mac-arm64.dmg";;
esac
curl -sSL -o "dl/$F" "$B/$F" && curl -sSL -o dl/SHA256.txt "$B/GENESYS-$V-SHA256.txt"
WANT=$(grep "$F" dl/SHA256.txt | awk '{print $1}'); GOT=$( (sha256sum "dl/$F" 2>/dev/null || shasum -a 256 "dl/$F") | awk '{print $1}')
echo "scaricato $F $(wc -c < "dl/$F") byte · sha256 $([ "$WANT" = "$GOT" ] && echo OK || echo "DIVERSO ($GOT / $WANT)")"
PROF="$PWD/prof"
case "$KIND" in
  windows)
    # come un utente: lo script ufficiale del sito (PowerShell), installazione per l'utente senza amministratore
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://genesys.technology-timeline.com/install.ps1 | iex" > inst.log 2>&1 & IP=$!
    for i in $(seq 1 48); do kill -0 $IP 2>/dev/null || break; sleep 5; done
    if kill -0 $IP 2>/dev/null; then echo "INSTALLAZIONE FERMA dopo 4 minuti"; powershell -NoProfile -ExecutionPolicy Bypass -File pc/win-shot.ps1 "$(cygpath -w "$PWD/shots/windows-0-installazione-ferma.png")"; tasklist | grep -iE "genesys|setup|nsis|au_" ; fi
    cat inst.log | tail -8
    LA=$(cygpath -u "$LOCALAPPDATA"); PF=$(cygpath -u "$PROGRAMFILES")
    ls "$LA/Programs" "$PF" 2>/dev/null | grep -i genesys
    EXE=$(find "$LA/Programs" "$PF" -maxdepth 3 -iname "GENESYS.exe" 2>/dev/null | head -1)
    echo "installato: $EXE"
    [ -n "$EXE" ] || { tar czf "pc-shots-$KIND.tgz" shots; bash ci/upload.sh "pc-shots-$KIND.tgz"; echo "NON INSTALLATO"; exit 1; }
    taskkill //IM GENESYS.exe //F >/dev/null 2>&1; sleep 2
    "$EXE" --remote-debugging-port=9222 --user-data-dir="$(cygpath -w "$PROF")" > app.log 2>&1 &
    ;;
  linux)
    sudo apt-get update -qq >/dev/null && sudo apt-get install -y -qq xvfb libfuse2 >/dev/null 2>&1
    chmod +x "dl/$F"; (cd dl && ./"$F" --appimage-extract >/dev/null) && echo "AppImage estratta"
    curl -sSL -o dl/g.deb "$B/GENESYS-$V-linux-amd64.deb" && sudo apt-get install -y -qq ./dl/g.deb >/dev/null 2>&1 && echo "pacchetto deb installato: $(dpkg -s genesys-launcher 2>/dev/null | grep -i '^version' || dpkg -l | grep -i genesys | head -1)"
    xvfb-run -a -s "-screen 0 1440x900x24" ./dl/squashfs-root/AppRun --no-sandbox --remote-debugging-port=9222 --user-data-dir="$PROF" > app.log 2>&1 &
    ;;
  mac-*)
    M=$(hdiutil attach -nobrowse -noautoopen -readonly "dl/$F" | grep -o '/Volumes/.*' | tail -1); ditto "$M/GENESYS.app" /tmp/GENESYS.app; hdiutil detach "$M" -quiet
    echo "app: $(defaults read /tmp/GENESYS.app/Contents/Info.plist CFBundleShortVersionString) · $(lipo -archs /tmp/GENESYS.app/Contents/MacOS/GENESYS)"
    xattr -cr /tmp/GENESYS.app
    /tmp/GENESYS.app/Contents/MacOS/GENESYS --remote-debugging-port=9222 --user-data-dir="$PROF" > app.log 2>&1 &
    ;;
esac
npm i --silent --no-audit --no-fund playwright-core@1.56.1 >/dev/null 2>&1
node pc/check.mjs "$KIND" "$V"; RC=$?
echo "--- log dell'app"; tail -15 app.log
ls "$PROF" | head -20
(cd shots && ls) ; tar czf "pc-shots-$KIND.tgz" shots && bash ci/upload.sh "pc-shots-$KIND.tgz"
exit $RC
