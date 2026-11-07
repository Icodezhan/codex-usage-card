'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { formatRateLimits, mergeRateLimitsResponse, unavailableValue, isMainWindow, CdpSession,
  resolveCodexBin, AppServerClient } = require('../agent.cjs');

test('Plus renders independent five-hour and weekly remaining allowances', () => {
  const result = formatRateLimits({ rateLimitsByLimitId: { codex: { planType: 'plus',
    primary: { usedPercent: 5, windowDurationMins: 300 },
    secondary: { usedPercent: 47, windowDurationMins: 10080 } } } });
  assert.equal(result.mode, 'dual');
  assert.deepEqual(result.rings.map(r => r.percent), [95, 53]);
});

test('reset labels show local HH:mm and MM-DD, retaining full tooltip times', () => {
  const data = { rateLimits: { planType: 'plus',
    primary: { usedPercent: 5, windowDurationMins: 300, resetsAt: new Date(2026,10,9,18,30).getTime()/1000 },
    secondary: { usedPercent: 47, windowDurationMins: 10080, resetsAt: new Date(2026,10,10,8,5).getTime()/1000 } } };
  const value = formatRateLimits(data);
  assert.deepEqual(value.rings.map(r => r.resetText), ['18:30', '11-10']);
  assert.match(value.rings[1].title, /08:05/);
  assert.equal(value.resetText, '18:30');
  data.rateLimits.planType = 'pro';
  assert.equal(formatRateLimits(data).resetText, '11-10');
});

test('reset labels follow the computer timezone across midnight and DST', () => {
  const { execFileSync } = require('node:child_process');
  const script = `const {formatRateLimits}=require(${JSON.stringify(require.resolve('../agent.cjs'))});
    console.log(JSON.stringify(process.argv.slice(1).map(iso => {
      const resetsAt=Date.parse(iso)/1000;
      return formatRateLimits({rateLimits:{planType:'plus',
        primary:{usedPercent:0,windowDurationMins:300,resetsAt},
        secondary:{usedPercent:0,windowDurationMins:10080,resetsAt}}}).rings.map(r=>r.resetText);
    })));`;
  for (const [tz, dates, expected] of [
    ['Asia/Shanghai', ['2026-11-09T23:30:00Z'], [['07:30','11-10']]],
    ['America/Los_Angeles', ['2026-11-09T23:30:00Z'], [['15:30','11-09']]],
    ['UTC', ['2026-11-09T00:05:00Z'], [['00:05','11-09']]],
    ['America/New_York', ['2026-03-08T06:30:00Z','2026-03-08T07:30:00Z'], [['01:30','03-08'],['03:30','03-08']]]
  ]) {
    const output = execFileSync(process.execPath, ['-e',script,...dates], {
      env:{...process.env,TZ:tz}, encoding:'utf8', windowsHide:true });
    assert.deepEqual(JSON.parse(output), expected, tz);
  }
});

test('missing, invalid, unavailable and stale reset data cannot retain old labels', () => {
  const snapshot = resetsAt => ({ rateLimits: { planType:'plus',
    primary:{usedPercent:0,windowDurationMins:300,resetsAt},
    secondary:{usedPercent:0,windowDurationMins:10080,resetsAt} } });
  for (const resetsAt of [undefined,null,0,-1,NaN,Infinity,1e30,'1800000000']) {
    const value = formatRateLimits(snapshot(resetsAt));
    assert.equal(value.resetText, null);
    assert.deepEqual(value.rings.map(r=>r.resetText), [null,null]);
  }
  const data = snapshot(1800000000);
  delete data.rateLimits.primary.usedPercent;
  assert.equal(formatRateLimits(data).rings[0].resetText, null);
  const fresh = formatRateLimits(snapshot(1800000000));
  const stale = unavailableValue(fresh);
  assert.equal(stale.resetText, null);
  assert.deepEqual(stale.rings.map(r=>r.resetText), [null,null]);
  const changed = mergeRateLimitsResponse({accountId:'old',...snapshot(1800000000)},
    {accountId:'new', rateLimits:{planType:'plus',primary:{usedPercent:0,windowDurationMins:300}}});
  assert.deepEqual(formatRateLimits(changed).rings.map(r=>r.resetText), [null,null]);
});
test('account changes cannot reuse a previous account weekly window', () => {
  const result = mergeRateLimitsResponse({ accountId: 'old', rateLimits: {
    primary: { usedPercent: 12, windowDurationMins: 300 }, secondary: { usedPercent: 42, windowDurationMins: 10080 }
  } }, { accountId: 'new', rateLimits: { primary: { usedPercent: 0, windowDurationMins: 300 } } });
  assert.equal(result.rateLimits.secondary, null);
});
test('unavailable data clears both ring percentages', () => {
  const result = unavailableValue({ percent: 90, rings: [{ percent: 90 }, { percent: 40 }] });
  assert.equal(result.stale, true);
  assert.equal(result.percent, null);
  assert.deepEqual(result.rings.map(r => r.percent), [null, null]);
});
test('only the main Codex renderer is eligible for injection', () => {
  assert.equal(isMainWindow({ url: 'app://-/index.html#/codex' }), true);
  for (const url of ['https://chatgpt.com', 'app://-/index.html#overlay', 'app://other/index.html', 'invalid']) {
    assert.equal(isMainWindow({ url }), false);
  }
});
test('CDP rejects remote hosts, wrong ports, credentials and secure-socket redirects', async () => {
  for (const url of ['ws://example.com:39222/a', 'ws://127.0.0.1:9222/a',
    'ws://user:password@127.0.0.1:39222/a', 'wss://127.0.0.1:39222/a']) {
    await assert.rejects(new CdpSession({ webSocketDebuggerUrl: url }).connect(), /configured loopback port/);
  }
});
test('Windows CLI discovery selects an existing native executable', { skip: process.platform !== 'win32' }, () => {
  assert.match(resolveCodexBin(), /codex\.exe$/i);
});
test('app-server process handles initialization, rate limits and clean EOF', async () => {
  const fixture = require('node:path').join(__dirname, 'fake-app-server.cjs');
  const client = new AppServerClient({ command: process.execPath, args: [fixture], requestTimeoutMs: 2000 });
  try {
    await client.start();
    assert.equal(formatRateLimits(client.rateLimits).percent, 75);
    const exited = new Promise(resolve => client.child.once('exit', resolve));
    client.stop();
    await exited;
    assert.equal(client.pending.size, 0);
  } finally { client.stop(); }
});
