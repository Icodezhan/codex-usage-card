'use strict';
const lines = require('node:readline').createInterface({ input: process.stdin });
lines.on('line', line => {
  const request = JSON.parse(line);
  if (request.id === undefined) return;
  const result = request.method === 'account/rateLimits/read'
    ? { rateLimits: { planType: 'plus', primary: { usedPercent: 25, windowDurationMins: 300 } } } : {};
  process.stdout.write(JSON.stringify({ id: request.id, result }) + '\n');
});
