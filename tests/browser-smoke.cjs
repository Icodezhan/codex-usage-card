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
  primary: { usedPercent: 5, windowDurationMins: 300 }, secondary: { usedPercent: 47, windowDurationMins: 10080 } } });
fs.writeFileSync(fixture, `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%;font-family:'Segoe UI',sans-serif}nav{display:flex;flex-direction:column;width:54px;height:850px;background:#eee}main{flex:1}footer{height:40px}
</style></head><body><nav data-app-navigation-rail><main></main><footer>Profile</footer></nav><script>
(${installUsageBadge.toString()})();
window.__codexUsageBadge.update(${JSON.stringify({ ...value, updatedAt: Date.now(), stale: false })});
const first = window.__codexUsageBadge.status();
(${installUsageBadge.toString()})();
const unique = document.querySelectorAll('#codex-usage-badge').length === 1;
const text = document.getElementById('codex-usage-badge').textContent;
window.__codexUsageBadge.update({updatedAt:Date.now()-180000,stale:false});
const expired = window.__codexUsageBadge.status();
window.__codexUsageBadge.destroy();
const clean = !document.querySelector('#codex-usage-badge,#codex-usage-tooltip,#codex-usage-badge-style');
const result = first.placed && first.mode === 'dual' && unique && text.includes('95%') && text.includes('53%') && expired.stale && expired.rings.every(r=>r.percent===null) && clean;
document.body.setAttribute('data-smoke-result', result ? 'PASS' : 'FAIL');
document.body.append(JSON.stringify({first,unique,text,expired,clean}));
</script></body></html>`);
try {
  const result = spawnSync(edge, ['--headless', '--disable-gpu', '--no-first-run', '--disable-extensions',
    '--disable-background-networking', '--dump-dom', '--virtual-time-budget=1000',
    '--user-data-dir=' + path.join(temp, 'profile'), pathToFileURL(fixture).href],
    { encoding: 'utf8', timeout: 25000, windowsHide: true, maxBuffer: 2 * 1024 * 1024 });
  if (result.error || !result.stdout?.includes('data-smoke-result="PASS"')) {
    console.error(result.stdout || result.error?.message || result.stderr || `Browser exited ${result.status} without returning a DOM. Try EDGE_BIN with a working Chromium executable.`);
    process.exitCode = 1;
  } else console.log('PASS: real Chromium rendering, dual percentages, placement, singleton, expiry and cleanup.');
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
