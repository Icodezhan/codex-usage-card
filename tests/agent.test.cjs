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
