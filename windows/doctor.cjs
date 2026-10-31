'use strict';
const { AppServerClient, resolveCodexBin, formatRateLimits } = require('../agent.cjs');
(async () => {
  const client = new AppServerClient({ command: resolveCodexBin(), requestTimeoutMs: 20000 });
  try {
    await client.start();
    const value = formatRateLimits(client.rateLimits);
    // Deliberately omit account identifiers, tokens and the raw server response.
    console.log(JSON.stringify({ usageProbe: 'ok', mode: value.mode, percent: value.percent,
      rings: value.rings?.map(({ label, percent }) => ({ label, percent })) ?? null }, null, 2));
  } finally { client.stop(); }
})().catch(() => { console.error('Usage probe failed. Check the existing Codex login and network connection.'); process.exitCode = 1; });
