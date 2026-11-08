'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const { installUsageBadge, formatRateLimits } = require('../agent.cjs');
const edge = [process.env.EDGE_BIN,
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe'].find(p => p && fs.existsSync(p));
if (!edge) throw new Error('Chrome or Microsoft Edge is required for the real-browser smoke test. Set EDGE_BIN to override.');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-usage-card-browser-'));
const fixture = path.join(temp, 'test.html');
const value = formatRateLimits({ rateLimits: { planType: 'plus',
  primary: { usedPercent: 5, windowDurationMins: 300, resetsAt:new Date(2026,10,9,18,30).getTime()/1000 },
  secondary: { usedPercent: 47, windowDurationMins: 10080, resetsAt:new Date(2026,10,10,8,5).getTime()/1000 } } });
fs.writeFileSync(fixture, `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%;font-family:'Segoe UI',sans-serif}nav{position:relative;display:flex;flex-direction:column;align-items:center;gap:8px;box-sizing:border-box;padding:8px;width:54px;height:850px;background:#eee}main{flex:1;min-height:0;overflow:auto;width:36px}footer{display:flex;flex-direction:column;gap:8px;flex-shrink:0}button{box-sizing:border-box;width:36px;height:36px;flex-shrink:0;padding:0}
</style></head><body><nav data-app-navigation-rail><main><button>Home</button></main><footer><button>Usage</button><button id="profile" aria-haspopup="menu" aria-expanded="false">Profile</button></footer></nav><script>
(async () => {
const checks = {};
const waitForPlacement = () => new Promise(resolve => setTimeout(resolve, 250));
const nav = document.querySelector('nav');
const footer = document.querySelector('footer');
const rect = el => el.getBoundingClientRect();
const overlaps = (a,b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
const canHit = el => { const r = rect(el); return document.elementFromPoint(r.left+r.width/2,r.top+r.height/2)?.closest('button') === el; };
const nativeButtonsFit = () => [...footer.querySelectorAll('button')].every(b => rect(b).top >= rect(nav).top && rect(b).bottom <= rect(nav).bottom);
(${installUsageBadge.toString()})();
window.__codexUsageBadge.update(${JSON.stringify({ ...value, updatedAt: Date.now(), stale: false })});
const first = window.__codexUsageBadge.status();
(${installUsageBadge.toString()})();
const unique = document.querySelectorAll('#codex-usage-badge').length === 1;
const badge = document.getElementById('codex-usage-badge');
const text = badge.textContent;
const resetLabels = () => [...badge.querySelectorAll('.usage-reset')].map(el=>el.textContent);
checks.resetLabels = JSON.stringify(resetLabels()) === JSON.stringify(['18:30','11-10']);
checks.resetLabelsFit = [...badge.querySelectorAll('.usage-reset')].every(el => {
  const r=rect(el), p=rect(el.parentElement);
  return r.left>=p.left && r.right<=p.right && r.bottom<=p.bottom && el.scrollWidth<=el.clientWidth;
});
window.__codexUsageBadge.update({stale:true});
checks.staleLabelsCleared = resetLabels().every(text=>text==='—');
window.__codexUsageBadge.update(${JSON.stringify({ ...value, updatedAt: Date.now(), stale: false })});
checks.labelsRecovered = JSON.stringify(resetLabels()) === JSON.stringify(['18:30','11-10']);
const profile = document.querySelector('#profile');
const tooltip = document.querySelector('#codex-usage-tooltip');
profile.addEventListener('click', () => profile.setAttribute('aria-expanded', 'true'));
badge.dispatchEvent(new MouseEvent('mouseenter'));
await new Promise(resolve => setTimeout(resolve, 400));
checks.tooltipBeforeProfile = !tooltip.hidden;
profile.click();
await Promise.resolve();
checks.profileMenuHidesImmediately = badge.hidden && tooltip.hidden && canHit(profile);
window.__codexUsageBadge.update({updatedAt:Date.now()});
checks.profileMenuStaysHiddenOnRefresh = badge.hidden && tooltip.hidden;
profile.setAttribute('aria-expanded', 'false');
await waitForPlacement();
checks.profileMenuRestoresCard = !badge.hidden && tooltip.hidden && JSON.stringify(resetLabels()) === JSON.stringify(['18:30','11-10']);
const update = document.createElement('button');
update.textContent = 'Update';
footer.prepend(update);
await waitForPlacement();
checks.updateInFooter = !badge.hidden && !overlaps(rect(badge),rect(update)) && nativeButtonsFit() && canHit(update);
nav.style.height = '190px';
await waitForPlacement();
checks.shortRailYields = badge.hidden && nativeButtonsFit();
nav.style.height = '850px';
await waitForPlacement();
checks.restoresOnResize = !badge.hidden && nativeButtonsFit();
update.style.cssText = 'position:absolute;bottom:100px;left:9px';
await waitForPlacement();
checks.absoluteUpdateYields = badge.hidden && canHit(update);
update.hidden = true;
await waitForPlacement();
checks.restoresWhenUpdateHidden = !badge.hidden;
update.hidden = false;
await waitForPlacement();
checks.hiddenAttributeObserved = badge.hidden;
update.remove();
await waitForPlacement();
checks.restoresAfterRemoval = !badge.hidden;
const siblingUpdate = document.createElement('button');
siblingUpdate.textContent = 'Restart to update';
nav.insertBefore(siblingUpdate,footer);
await waitForPlacement();
checks.separateUpdate = !badge.hidden && !overlaps(rect(badge),rect(siblingUpdate)) && nativeButtonsFit();
siblingUpdate.remove();
nav.style.height = '260px';
await waitForPlacement();
checks.navigationKeepsRoom = badge.hidden && rect(nav.querySelector('main')).height >= 36 && nativeButtonsFit();
window.__codexUsageBadge.update({mode:'single',rings:null});
checks.singleFits = !badge.hidden && nativeButtonsFit();
window.__codexUsageBadge.update(${JSON.stringify({ ...value, updatedAt: Date.now(), stale: false })});
checks.dualYieldsAgain = badge.hidden && nativeButtonsFit();
nav.style.height = '850px';
await waitForPlacement();
// A clipped scroll-list button must not be mistaken for an overlapping update.
nav.querySelector('main').innerHTML = '<div style="height:1000px"></div><button>Scrolled out</button>';
await waitForPlacement();
checks.clippedNavigationIgnored = !badge.hidden;
nav.style.display = 'none';
await waitForPlacement();
checks.hiddenRail = badge.hidden;
nav.style.display = 'flex';
await waitForPlacement();
checks.restoresRail = !badge.hidden;
window.__codexUsageBadge.update({updatedAt:Date.now()-180000,stale:false});
const expired = window.__codexUsageBadge.status();
checks.expiredLabelsCleared = resetLabels().every(text=>text==='—') && expired.rings.every(r=>r.resetText===null);
window.__codexUsageBadge.destroy();
const clean = !document.querySelector('#codex-usage-badge,#codex-usage-tooltip,#codex-usage-badge-style');
const result = first.placed && first.mode === 'dual' && unique && text.includes('95%') && text.includes('53%') && expired.stale && expired.rings.every(r=>r.percent===null) && clean && Object.values(checks).every(Boolean);
document.body.setAttribute('data-smoke-result', result ? 'PASS' : 'FAIL');
document.body.append(JSON.stringify({first,unique,text,expired,clean,checks}));
})().catch(error => { document.body.setAttribute('data-smoke-result','FAIL'); document.body.append(error.stack); });
</script></body></html>`);
try {
  const result = spawnSync(edge, ['--headless', '--disable-gpu', '--no-first-run', '--disable-extensions',
    '--disable-background-networking', '--dump-dom', '--window-size=900,1000', '--virtual-time-budget=6000',
    '--user-data-dir=' + path.join(temp, 'profile'), pathToFileURL(fixture).href],
    { encoding: 'utf8', timeout: 25000, windowsHide: true, maxBuffer: 2 * 1024 * 1024 });
  if (result.error || !result.stdout?.includes('data-smoke-result="PASS"')) {
    console.error(result.stdout?.match(/<\/script>([\s\S]*)<\/body>/)?.[1] || result.error?.message || result.stderr || `Browser exited ${result.status} without returning a DOM. Try EDGE_BIN with a working Chromium executable.`);
    process.exitCode = 1;
  } else console.log('PASS: real Chromium rendering, profile menu hide/recovery, update-button clearance, short-rail fallback/recovery, dynamic styles, single/dual layout, singleton, expiry and cleanup.');
} finally {
  // The target is created above by mkdtemp, never a user-supplied path.
  try {
    const resolved = fs.realpathSync(temp);
    const allowedRoot = fs.realpathSync(os.tmpdir()) + path.sep;
    if (!resolved.toLowerCase().startsWith(allowedRoot.toLowerCase()) || !path.basename(resolved).startsWith('codex-usage-card-browser-')) {
      throw new Error('Unsafe browser test cleanup target.');
    }
    fs.rmSync(resolved, { recursive: true, force: true });
  } catch { }
}
