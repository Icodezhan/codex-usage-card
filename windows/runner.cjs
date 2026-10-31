'use strict';
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');
const { main } = require('../agent.cjs');
const root = path.resolve(__dirname, '..');
const pipe = '\\\\.\\pipe\\codex-usage-card-' + crypto.createHash('sha256').update(root.toLowerCase()).digest('hex').slice(0, 20);
const stopFile = path.join(root, 'stop.request');
const stateFile = path.join(root, 'agent-state.json');
// A named pipe is an OS-held singleton: stale PID files cannot allow duplicates.
const lock = net.createServer(socket => socket.end());
lock.on('error', error => { process.exitCode = error.code === 'EADDRINUSE' ? 0 : 1; });
lock.listen(pipe, async () => {
  let control;
  let timer;
  let stopping = false;
  const write = state => {
    const temp = stateFile + '.tmp';
    fs.writeFileSync(temp, JSON.stringify({ pid: process.pid, heartbeat: new Date().toISOString(), ...state }, null, 2));
    fs.renameSync(temp, stateFile);
  };
  const stop = () => {
    if (stopping) return;
    stopping = true;
    clearInterval(timer);
    control?.shutdown();
    write({ state: 'stopped', connectedWindows: 0 });
    fs.rmSync(stopFile, { force: true });
    lock.close();
  };
  try {
    write({ state: 'starting', connectedWindows: 0 });
    control = await main({ onState: write, exitOnShutdown: false });
    timer = setInterval(() => { if (fs.existsSync(stopFile)) stop(); }, 500);
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
  } catch {
    write({ state: 'error', connectedWindows: 0 });
    control?.shutdown();
    lock.close();
    process.exitCode = 1;
  }
});
