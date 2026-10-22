#!/usr/bin/env bash
# Automatic test of GENESYS for Android on an emulator: screenshots of every step go to the private draft.
set -uo pipefail
PKG=com.technologytimeline.genesys.debug
ACT=$PKG/com.technologytimeline.genesys.MainActivity
S=/tmp/shots; mkdir -p $S; N=0
log(){ echo "[emu] $*"; }
shot(){ N=$((N+1)); local f=$(printf "%s/%02d-%s.png" $S $N "$1"); adb exec-out screencap -p > "$f"; log "foto $f"; }
dump(){ for i in 1 2 3 4 5; do adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb shell cat /sdcard/ui.xml > /tmp/ui.xml && return 0; sleep 2; done; return 1; }
# tap the first element whose text or description contains $1
# the emulator sometimes shows "Pixel Launcher isn't responding" over everything: answer "Wait"
anr(){ grep -q "isn't responding" /tmp/ui.xml 2>/dev/null || return 0
  local xy; xy=$(python3 -c "
import re,xml.etree.ElementTree as ET
for n in ET.parse('/tmp/ui.xml').iter('node'):
    if (n.get('text') or '') in ('Wait','Close app'):
        a,b,c,d=map(int,re.findall(r'\\d+',n.get('bounds')));print((a+c)//2,(b+d)//2)
        if n.get('text')=='Wait': break
" | tail -1); [ -n "$xy" ] && { log "finestra 'non risponde' chiusa"; adb shell input tap $xy; sleep 2; dump; }; }
tap(){ dump || { log "dump fallito"; return 1; }; anr
  local xy; xy=$(python3 - "$1" <<'PY'
import sys,re,xml.etree.ElementTree as ET
want=sys.argv[1]; exact=want.startswith('='); want=want.lstrip('='); t=ET.parse('/tmp/ui.xml')
match=(lambda v: v==want) if exact else (lambda v: want in v)
for n in t.iter('node'):
    if match(n.get('text') or '') or match(n.get('content-desc') or ''):
        a,b,c,d=map(int,re.findall(r'\d+',n.get('bounds'))); print((a+c)//2,(b+d)//2); break
PY
)
  [ -n "$xy" ] || { log "non trovato: $1"; return 1; }
  log "tocco '$1' a $xy"; adb shell input tap $xy; }
waitfor(){ for i in $(seq 1 ${2:-30}); do dump && grep -q "$1" /tmp/ui.xml && return 0; sleep 2; done; log "attesa scaduta: $1"; return 1; }
texts(){ dump && anr; python3 -c "
import xml.etree.ElementTree as ET
print(' | '.join(n.get('text') for n in ET.parse('/tmp/ui.xml').iter('node') if n.get('text'))[:1500])"; }

adb install -r -g /tmp/test/genesys-debug.apk || exit 1
adb shell am start -W -n $ACT; sleep 6; shot lingua; texts
tap "Italiano"; sleep 1; shot lingua-italiano; tap "Continua"; sleep 3; shot accesso; texts
tap "Continua con Google"; sleep 15; shot sito-google; texts
adb shell am start -W -n $ACT; sleep 3; shot ritorno; texts
# 0.2.0: pass di prova VERO (2 giorni, identità "Prova GENESYS") dalla cassaforte privata: serve per avere dal server
# la chiave del gioco cifrato. Consenso con statistiche (prova anche il segnale "attivo questo mese").
VID=$(gh api "repos/$REPO/releases?per_page=100" --jq '.[] | select(.draft and .name=="genesys-ci-vault") | .id' | head -1)
AID=$(gh api "repos/$REPO/releases/$VID/assets?per_page=100" --jq '.[] | select(.name=="ci-pass.txt") | .id' | head -1)
PASS=$(gh api "repos/$REPO/releases/assets/$AID" -H "Accept: application/octet-stream" | tr -d '\n\r ')
log "pass di prova: ${#PASS} caratteri"
adb shell am start -W -n $ACT --es genesys_test_pass "$PASS" --es genesys_test_consent "'{\"v\":\"2026-10-15.2\",\"c\":\"IT\",\"s\":true}'"
sleep 12; shot esplora; texts
dump; anr; grep -q "Novità di GENESYS" /tmp/ui.xml && log "ERRORE: novità mostrate alla prima installazione" || log "prima installazione: nessuna finestra novità (giusto)"
adb shell input swipe 500 1600 500 600 400; sleep 2; shot esplora-giu
adb shell input swipe 500 600 500 1600 400; sleep 2
tap "7TH DAY"; sleep 4; shot 7thday; texts
tap "Scarica gratis"; sleep 3; shot permesso; texts
adb shell appops set $PKG REQUEST_INSTALL_PACKAGES allow; sleep 1
tap "Annulla" || true; sleep 1
tap "Scarica gratis"; sleep 20; shot download; texts
for i in $(seq 1 90); do dump; if grep -qiE "Installa|Install|Gioca|non riuscita|fallita|interrotto|Codice|Accedi" /tmp/ui.xml; then break; fi; sleep 5; done
shot decifrato; texts
adb logcat -d | grep -iE "genesys|PackageInstaller" | tail -20
shot dopo-download; texts
tap "Installa" || tap "Install" || tap "INSTALLA" || tap "INSTALL" || true
sleep 20; shot installato; texts
adb shell pm list packages | grep -i seventh || log "7TH DAY non installato"
adb shell dumpsys package com.alessandro.seventhday | grep -m1 -i "versionName" | sed 's/^ */[emu] /'
# 1.1.0: nessuna icona nel telefono e nessun avvio da fuori GENESYS (permesso a firma dell'app GENESYS)
G7=com.alessandro.seventhday
log "icona nel telefono: $(adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $G7 | tail -1)"
log "monkey (come un launcher): $(adb shell monkey -p $G7 -c android.intent.category.LAUNCHER 1 2>&1 | grep -iE 'no activities|events injected' | head -1)"
log "avvio da fuori (alias): $(adb shell am start -W -n $G7/com.godot.game.GodotAppLauncher 2>&1 | grep -iE 'error|exception|denial|Status' | head -1)"
log "avvio da fuori (attivita): $(adb shell am start -W -n $G7/com.godot.game.GodotApp 2>&1 | grep -iE 'error|exception|denial|Status' | head -1)"
sleep 3; shot da-fuori; log "in primo piano: $(adb shell dumpsys activity activities | grep -m1 -i topResumedActivity)"
adb shell am start -W -n $ACT; sleep 3
adb logcat -c
tap "=Gioca" && { sleep 6; shot gioco-6s; sleep 14; shot gioco-20s; adb shell dumpsys activity activities | grep -m3 -i "mResumedActivity\|topResumedActivity"; }
adb logcat -d | grep -iE "GENESYS android|godot   :" | head -12
adb shell input tap 1200 540; sleep 4; shot gioco-tocco
# secondo livello: anche forzando l'avvio (root sull'emulatore, senza i dati dell'app GENESYS) il gioco mostra il blocco
adb shell am force-stop $G7; sleep 1
if adb root >/dev/null 2>&1; then sleep 4; adb wait-for-device
  log "root: avvio forzato senza GENESYS: $(adb shell am start -W -n $G7/com.godot.game.GodotAppLauncher 2>&1 | grep -iE 'Status|error|denial' | head -1)"
  sleep 16; shot forzato-blocco; adb logcat -d | grep -iE "GENESYS android" | tail -2
  adb shell am force-stop $G7; adb unroot >/dev/null 2>&1; sleep 4; adb wait-for-device
else log "root non disponibile: salto la prova del secondo livello"; fi
adb logcat -d | grep -iE "seventhday|godot|ActivityTaskManager: START|FATAL|AndroidRuntime: |libc  |DEBUG   :|Abort|SecurityException" | tail -120 > $S/logcat-gioco.txt; tail -60 $S/logcat-gioco.txt
# 0.2.1: novità una sola volta dopo l'aggiornamento (simulo un utente che arriva dalla 0.2.0)
adb shell am force-stop $PKG; sleep 1
adb shell am start -W -n $ACT --es genesys_test_seen 0.2.0; sleep 5; shot novita; texts
dump; anr; grep -q "Novità di GENESYS 0.2.1" /tmp/ui.xml && log "novità mostrate: ok" || log "ERRORE: novità non mostrate"
tap "Ho capito"; sleep 2
adb shell am force-stop $PKG; sleep 1; adb shell am start -W -n $ACT; sleep 5
dump; anr; grep -q "Novità di GENESYS" /tmp/ui.xml && log "ERRORE: novità mostrate due volte" || log "riaperta: novità non ripetute (giusto)"
# novità dei giochi: 7TH DAY passato dalla 1.0.1 (code 31) alla 1.1.0
adb shell am force-stop $PKG; sleep 1
adb shell am start -W -n $ACT --es genesys_test_gamever 7th-day:31; sleep 6; shot novita-gioco; texts
dump; anr; grep -q "Novità di 7TH DAY 1.1.0" /tmp/ui.xml && log "novità del gioco mostrate: ok" || log "ERRORE: novità del gioco non mostrate"
tap "Ho capito"; sleep 2
adb shell am force-stop $PKG; sleep 1; adb shell am start -W -n $ACT; sleep 5
dump; anr; grep -q "Novità di 7TH DAY" /tmp/ui.xml && log "ERRORE: novità del gioco ripetute" || log "riaperta: novità del gioco non ripetute (giusto)"
adb shell am force-stop $PKG; sleep 1
adb shell am start -W -n $ACT --es genesys_test_seen 0.2.0 --es genesys_test_language ar; sleep 5; shot novita-arabo
tap "حسنًا" || true; sleep 2
adb shell am start -W -n $ACT --es genesys_test_language it; sleep 3
adb shell input keyevent KEYCODE_BACK; sleep 2
tap "Impostazioni"; sleep 2; shot impostazioni; texts
tap "La mia libreria"; sleep 2; shot libreria; texts
adb shell am start -W -n $ACT --es genesys_test_language ar; sleep 3; tap "الإعدادات" || true; sleep 2; shot arabo
adb logcat -d -t 400 | grep -iE "genesys|AndroidRuntime|FATAL" | tail -60 > $S/logcat.txt
cd /tmp && zip -qr emu-shots.zip shots && ls -l emu-shots.zip
source ci/lib.sh 2>/dev/null || true
bash $GITHUB_WORKSPACE/ci/upload.sh /tmp/emu-shots.zip
