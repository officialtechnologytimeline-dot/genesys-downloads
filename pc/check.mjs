// Collegamento all'app GENESYS avviata (porta di debug), foto e controlli dell'interfaccia.
import {chromium} from 'playwright-core';
import fs from 'node:fs';
const [kind, version] = process.argv.slice(2);
const ok = [], bad = []; const check = (c, m) => (c ? ok : bad).push(m);
let browser;
for (let i = 0; i < 40 && !browser; i++) { try { browser = await chromium.connectOverCDP('http://127.0.0.1:9222', {timeout: 5000}); } catch { await new Promise(r => setTimeout(r, 3000)); } }
if (!browser) { console.log('NON PARTE: nessuna finestra GENESYS dopo 2 minuti'); process.exit(1); }
const ctx = browser.contexts()[0];
let page = null;
for (let i = 0; i < 30 && !page; i++) { page = ctx.pages().find(p => p.url().startsWith('genesys://')) || null; if (!page) await new Promise(r => setTimeout(r, 2000)); }
check(!!page, 'finestra GENESYS aperta');
if (!page) { console.log('KO', bad); process.exit(1); }
await page.waitForTimeout(9000);
await page.screenshot({path: `shots/${kind}-1-avvio.png`});
const boot = await page.evaluate(() => window.genesys.bootstrap());
const b = boot.value || {};
console.log('bootstrap:', JSON.stringify({version: b.version, platform: b.platform, arch: b.arch, games: (b.games || []).length, google: b.googleAvailable, discord: b.discordAvailable, connected: b.connected, alpha: (b.games || []).filter(g => g.alpha).map(g => g.id), available: (b.games || []).filter(g => g.available).map(g => g.id + ' ' + g.version)}));
check(b.version === version, 'versione ' + b.version);
check((b.games || []).length >= 17, 'catalogo con ' + (b.games || []).length + ' giochi');
check(b.connected === true, 'canale GitHub letto e verificato');
check((b.games || []).some(g => g.id === '7th-day' && g.available), '7TH DAY disponibile per questo computer');
check((b.games || []).some(g => g.alpha), 'gioco in alpha chiusa nel catalogo');
const expect = {windows: ['win32', 'x64'], linux: ['linux', 'x64'], 'mac-intel': ['darwin', 'x64'], 'mac-apple': ['darwin', 'arm64']}[kind];
check(b.platform === expect[0] && b.arch === expect[1], `sistema ${b.platform} ${b.arch}`);
// 0.5.5: prima apertura: la lingua la sceglie l'utente (nessuna preselezione, "Continua" spento, non si salta)
const lang0 = await page.evaluate(() => { const d = document.getElementById('language-dialog'); return d ? {open: d.open, selected: document.querySelectorAll('.language-option.selected').length, n: document.querySelectorAll('.language-option').length, disabled: document.getElementById('language-ok').disabled} : null; });
check(!!lang0 && lang0.open && lang0.selected === 0 && lang0.n === 30 && lang0.disabled, 'lingua obbligatoria alla prima apertura: ' + JSON.stringify(lang0));
await page.screenshot({path: `shots/${kind}-0-lingua.png`});
await page.keyboard.press('Escape'); await page.waitForTimeout(400);
check(await page.evaluate(() => document.getElementById('language-dialog').open), 'Esc non salta la scelta della lingua');
const refused = await page.evaluate(async () => { const r = await window.genesys.launch('7th-day'); return r && !r.ok ? r.error : 'avviato'; });
check(refused !== 'avviato', 'senza lingua scelta nessun gioco parte: ' + refused);
await page.click('.language-option[data-code="en"]'); await page.waitForTimeout(300);
await page.click('#language-ok'); await page.waitForTimeout(1200);
const chosen = await page.evaluate(() => ({lang: document.documentElement.lang, open: document.getElementById('language-dialog').open, settings: state.settings.language, confirmed: state.settings.languageConfirmed}));
check(chosen.lang === 'en' && !chosen.open && chosen.settings === 'en' && chosen.confirmed === true, 'lingua scelta e salvata: ' + JSON.stringify(chosen));
// lingua (prima apertura) e pagina del gioco in alpha
const txt = await page.evaluate(() => document.body.innerText.slice(0, 300).replace(/\s+/g, ' '));
console.log('schermo:', txt);
await page.evaluate(() => { document.querySelectorAll('dialog[open]').forEach(d => { if (d.id !== 'detail-dialog') d.close(); }); });
await page.waitForTimeout(800);
await page.screenshot({path: `shots/${kind}-2-catalogo.png`});
await page.evaluate(() => showDetail('primal-dominion'));
await page.waitForTimeout(1500);
const alpha = await page.evaluate(() => { const x = document.querySelector('.alpha-box'); return x ? x.innerText.replace(/\s+/g, ' ') : null; });
check(!!alpha && /Closed Beta/.test(alpha), 'casella Closed Beta: ' + alpha);
const eyebrow = await page.evaluate(() => { const e = document.querySelector('#detail-dialog .eyebrow'); return e ? e.textContent : null; });
check(eyebrow === 'CLOSED BETA', 'stato nella scheda: ' + eyebrow);
await page.screenshot({path: `shots/${kind}-3-alpha.png`});
await page.evaluate(() => document.getElementById('detail-dialog').close());
// 0.5.3: novità di GENESYS (una volta dopo l'aggiornamento) e dei giochi (dal catalogo firmato)
const news = await page.evaluate(() => ({pending: window.GenesysWhatsNew ? window.GenesysWhatsNew.pending('0.5.4', state.version, true).map(e => e.version) : null, first: window.GenesysWhatsNew ? window.GenesysWhatsNew.pending('', state.version, false).length : null, game: (state.games.find(g => g.id === '7th-day') || {}).news?.version || null}));
console.log('novità:', JSON.stringify(news));
check(Array.isArray(news.pending) && news.pending[0] === version && news.first === 0, 'novità di GENESYS ' + version + ' (non alla prima installazione)');
check(news.game === '1.1.0', 'novità di 7TH DAY 1.1.0 nel catalogo');
await page.evaluate(() => { state.settings.whatsNewSeen = '0.5.4'; state.settings.onboardingComplete = true; document.querySelectorAll('dialog[open]').forEach(d => d.close()); showWhatsNew(); });
await page.waitForTimeout(1200);
const wtitle = await page.evaluate(() => document.getElementById('whatsnew-dialog').open ? document.getElementById('whatsnew-title').textContent : null);
check(!!wtitle, 'finestra novità: ' + wtitle);
await page.screenshot({path: `shots/${kind}-3b-novita.png`});
await page.evaluate(() => document.getElementById('whatsnew-dialog').close());
await page.waitForTimeout(800);
// 0.5.4: "Closed Beta" sulla locandina al posto dello stato, "100% gratis, senza pubblicità" nelle impostazioni
const card = await page.evaluate(() => { const c = [...document.querySelectorAll('.card-status')].map(x => x.textContent); return {beta: c.filter(x => x === 'Closed Beta').length, old: c.filter(x => /ALPHA/i.test(x)).length}; });
check(card.beta === 1 && card.old === 0, 'locandine: Closed Beta ' + card.beta + ', alpha ' + card.old);
await page.evaluate(() => setView('settings'));
await page.waitForTimeout(800);
const free = await page.evaluate(() => { const f = document.querySelector('.free-note'); return f ? f.textContent : null; });
check(!!free, 'impostazioni: ' + free);
await page.screenshot({path: `shots/${kind}-3c-impostazioni.png`});
await page.evaluate(() => setView('catalog'));
await page.waitForTimeout(600);
// 0.5.5: Little Shark con genere e descrizione dal catalogo nella lingua scelta (inglese)
await page.evaluate(() => showDetail('little-shark'));
await page.waitForTimeout(1000);
const shark = await page.evaluate(() => document.getElementById('detail-dialog').innerText.replace(/\s+/g, ' '));
check(/Swim with a little shark/.test(shark) && /Adventure · Arcade/.test(shark), 'Little Shark in inglese: ' + shark.slice(0, 160));
await page.screenshot({path: `shots/${kind}-5-little-shark.png`});
await page.evaluate(() => document.getElementById('detail-dialog').close());
await page.evaluate(() => showDetail('7th-day'));
await page.waitForTimeout(1200);
await page.screenshot({path: `shots/${kind}-4-7thday.png`});
console.log('OK:', ok.join(' | '));
if (bad.length) console.log('PROBLEMI:', bad.join(' | '));
await browser.close().catch(() => {});
process.exit(bad.length ? 1 : 0);
