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
tap(){ dump || { log "dump fallito"; return 1; }
  local xy; xy=$(python3 - "$1" <<'PY'
import sys,re,xml.etree.ElementTree as ET
want=sys.argv[1]; t=ET.parse('/tmp/ui.xml')
for n in t.iter('node'):
    if want in (n.get('text') or '') or want in (n.get('content-desc') or ''):
        a,b,c,d=map(int,re.findall(r'\d+',n.get('bounds'))); print((a+c)//2,(b+d)//2); break
PY
)
  [ -n "$xy" ] || { log "non trovato: $1"; return 1; }
  log "tocco '$1' a $xy"; adb shell input tap $xy; }
waitfor(){ for i in $(seq 1 ${2:-30}); do dump && grep -q "$1" /tmp/ui.xml && return 0; sleep 2; done; log "attesa scaduta: $1"; return 1; }
texts(){ dump && python3 -c "
import xml.etree.ElementTree as ET
print(' | '.join(n.get('text') for n in ET.parse('/tmp/ui.xml').iter('node') if n.get('text'))[:1500])"; }

adb install -r -g /tmp/test/genesys-debug.apk || exit 1
adb shell am start -W -n $ACT; sleep 6; shot lingua; texts
tap "Italiano"; sleep 1; shot lingua-italiano; tap "Continua"; sleep 3; shot accesso; texts
tap "Continua con Google"; sleep 15; shot sito-google; texts
adb shell am start -W -n $ACT; sleep 3; shot ritorno; texts
EXP=$(( $(date +%s) + 86400*100 ))
PAY=$(printf '{"p":"google","s":"0123456789abcdef0123456789abcdef","n":"Tester","iat":%s,"exp":%s}' $(date +%s) $EXP | base64 -w0 | tr '+/' '-_' | tr -d '=')
PASS="GA1.$PAY.testsignaturetestsignature0000"
adb shell am start -W -n $ACT --es genesys_test_pass "$PASS" --es genesys_test_consent "'{\"v\":\"2026-10-15.2\",\"c\":\"IT\"}'"
sleep 12; shot esplora; texts
adb shell input swipe 500 1600 500 600 400; sleep 2; shot esplora-giu
adb shell input swipe 500 600 500 1600 400; sleep 2
tap "7TH DAY"; sleep 4; shot 7thday; texts
tap "Scarica gratis"; sleep 3; shot permesso; texts
adb shell appops set $PKG REQUEST_INSTALL_PACKAGES allow; sleep 1
tap "Annulla" || true; sleep 1
tap "Scarica gratis"; sleep 20; shot download; texts
for i in $(seq 1 60); do dump; if grep -qiE "Installa|Install|Gioca|non riuscita|fallita|interrotto" /tmp/ui.xml; then break; fi; sleep 5; done
shot dopo-download; texts
tap "Installa" || tap "Install" || tap "INSTALLA" || tap "INSTALL" || true
sleep 20; shot installato; texts
adb shell pm list packages | grep -i seventh || log "7TH DAY non installato"
adb logcat -c
tap "Gioca" && { sleep 6; shot gioco-6s; sleep 12; shot gioco-18s; adb shell dumpsys activity activities | grep -m3 -i "mResumedActivity\|topResumedActivity"; }
adb logcat -d | grep -iE "seventhday|godot|ActivityTaskManager: START|FATAL|AndroidRuntime: |libc  |DEBUG   :|Abort|SecurityException" | tail -120 > $S/logcat-gioco.txt; tail -60 $S/logcat-gioco.txt
adb shell am start -W -n $ACT; sleep 3
adb shell input keyevent KEYCODE_BACK; sleep 2
tap "Impostazioni"; sleep 2; shot impostazioni; texts
tap "La mia libreria"; sleep 2; shot libreria; texts
adb shell am start -W -n $ACT --es genesys_test_language ar; sleep 3; tap "الإعدادات" || true; sleep 2; shot arabo
adb logcat -d -t 400 | grep -iE "genesys|AndroidRuntime|FATAL" | tail -60 > $S/logcat.txt
cd /tmp && zip -qr emu-shots.zip shots && ls -l emu-shots.zip
source ci/lib.sh 2>/dev/null || true
bash $GITHUB_WORKSPACE/ci/upload.sh /tmp/emu-shots.zip
