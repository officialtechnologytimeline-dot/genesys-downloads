#!/usr/bin/env bash
# Prova del SITO GENESYS con Chrome vero su Android (emulatore): ordine dei giochi, lingua, errori JavaScript.
# Usa il debug remoto di Chrome (DevTools) per leggere la pagina; foto dello schermo nella cassaforte privata.
set -uo pipefail
S=/tmp/shots; mkdir -p $S; N=0
log(){ echo "[sito] $*"; }
shot(){ N=$((N+1)); local f=$(printf "%s/%02d-%s.png" $S $N "$1"); adb exec-out screencap -p > "$f"; log "foto $f"; }
adb shell pm list packages | grep -iE "chrome|webview|browser" | sed 's/^/[sito] pacchetto: /'
CH=com.android.chrome
adb shell pm list packages | grep -q "package:$CH$" || { log "ERRORE: Chrome non c'è nell'emulatore"; exit 0; }
adb shell dumpsys package $CH | grep -m1 versionName | sed 's/^ */[sito] Chrome /'
adb shell am set-debug-app --persistent $CH
adb shell 'echo "_ --disable-fre --no-default-browser-check --no-first-run --disable-features=SigninPromo --remote-allow-origins=*" > /data/local/tmp/chrome-command-line'
adb shell settings put global development_settings_enabled 1
adb shell setprop persist.sys.locale it-IT 2>/dev/null; adb shell cmd locale set-app-locales $CH --locales it-IT 2>/dev/null || true
adb shell am start -W -a android.intent.action.VIEW -d "about:blank" $CH >/dev/null; sleep 8
adb forward tcp:9222 localabstract:chrome_devtools_remote >/dev/null
for i in 1 2 3 4 5 6; do curl -s localhost:9222/json/version >/dev/null && break; sleep 3; done
curl -s localhost:9222/json/version | head -5 | sed 's/^/[sito] /'
pip3 install --quiet --break-system-packages websocket-client 2>/dev/null || pip3 install --quiet websocket-client
cat > /tmp/cdp.py <<'PY'
# python3 /tmp/cdp.py <url> <etichetta>: apre l'indirizzo nella scheda di Chrome e legge ordine, stati, lingua, errori
import sys, json, time, urllib.request, websocket
url, label = sys.argv[1], sys.argv[2]
pages = [x for x in json.load(urllib.request.urlopen('http://localhost:9222/json')) if x.get('type') == 'page']
ws = websocket.create_connection(pages[0]['webSocketDebuggerUrl'], timeout=30, suppress_origin=True)
n = [0]; errors = []
def send(method, params=None):
    n[0] += 1; i = n[0]; ws.send(json.dumps({'id': i, 'method': method, 'params': params or {}}))
    while True:
        m = json.loads(ws.recv())
        if m.get('method') == 'Runtime.exceptionThrown':
            d = m['params']['exceptionDetails']; errors.append(((d.get('exception') or {}).get('description') or d.get('text') or '').split('\n')[0] + ' @' + (d.get('url') or '').split('/')[-1])
        if m.get('method') == 'Log.entryAdded' and m['params']['entry'].get('level') == 'error':
            errors.append('[log] ' + m['params']['entry'].get('text', '')[:160] + ' ' + (m['params']['entry'].get('url') or '').split('/')[-1])
        if m.get('id') == i: return m
for x in ['Runtime.enable', 'Log.enable', 'Page.enable', 'Network.enable']: send(x)
send('Network.setCacheDisabled', {'cacheDisabled': True})
send('Page.navigate', {'url': url})
end = time.time() + 12
ws.settimeout(1)
while time.time() < end:
    try:
        m = json.loads(ws.recv())
        if m.get('method') == 'Runtime.exceptionThrown':
            d = m['params']['exceptionDetails']; errors.append(((d.get('exception') or {}).get('description') or d.get('text') or '').split('\n')[0] + ' @' + (d.get('url') or '').split('/')[-1])
        if m.get('method') == 'Log.entryAdded' and m['params']['entry'].get('level') == 'error':
            errors.append('[log] ' + m['params']['entry'].get('text', '')[:160] + ' ' + (m['params']['entry'].get('url') or '').split('/')[-1])
    except Exception: pass
ws.settimeout(30)
JSX = """(()=>{const g=[...document.querySelectorAll('.game-grid .game-card')].filter(c=>!c.hidden).map(c=>{const r=c.getBoundingClientRect();return [c.dataset.name,(c.querySelector('.status')||{}).textContent,+c.dataset.statusRank,Math.round(r.top+scrollY)]});g.sort((a,b)=>a[3]-b[3]);
 return {lang:document.documentElement.lang, sort:(document.querySelector('#game-sort')||{}).value, script:[...document.scripts].map(s=>s.src.split('/').pop()).filter(Boolean).join(' '), cls:document.documentElement.className, order:g.map(x=>x[0]+' ('+x[1]+')'), ranks:g.map(x=>x[2])}})()"""
r = send('Runtime.evaluate', {'expression': JSX, 'returnByValue': True})
info = (r.get('result') or {}).get('result', {}).get('value') or {}
ranks = info.get('ranks') or []
print(f"[sito] {label}: lingua={info.get('lang')} ordina={info.get('sort')} schede={len(ranks)} {'ORDINE GIUSTO' if ranks and ranks == sorted(ranks) else 'ERRORE: ORDINE SBAGLIATO'}")
print(f"[sito] {label}: ordine visto = {' > '.join(info.get('order') or [])}")
print(f"[sito] {label}: script = {info.get('script')} | classi = {info.get('cls')}")
print(f"[sito] {label}: errori JavaScript = {' | '.join(errors) if errors else 'nessuno'}")
send('Runtime.evaluate', {'expression': "document.querySelector('.game-grid')&&document.querySelector('.game-grid').scrollIntoView()"})
ws.close()
PY
for u in "https://genesys.technology-timeline.com/|online" "https://fec415dd.genesys-site.pages.dev/|v60-di-ieri-sera" "https://bae9d766.genesys-site.pages.dev/|v61-di-stanotte"; do
  python3 /tmp/cdp.py "${u%%|*}" "${u##*|}" 2>&1 | tail -6; sleep 3; shot "${u##*|}"
  adb shell input swipe 500 1500 500 700 300; sleep 2; shot "${u##*|}-giu"
done
cd /tmp && zip -qr emu-shots.zip shots && ls -l emu-shots.zip
bash $GITHUB_WORKSPACE/ci/upload.sh /tmp/emu-shots.zip
