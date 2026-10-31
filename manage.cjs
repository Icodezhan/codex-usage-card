'use strict';
// Windows entry point. The unmodified macOS manager remains in the release ZIP.
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const action = process.argv[2] || 'status';
if (process.platform !== 'win32') {
  console.error('Use the original macOS release on macOS. This manager targets Windows.');
  process.exitCode = 1;
} else if (!['install', 'launch', 'status', 'doctor', 'stop', 'uninstall'].includes(action)) {
  console.error('Usage: node manage.cjs install|launch|status|doctor|stop|uninstall');
  process.exitCode = 1;
} else {
  const result = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', path.join(__dirname, 'windows', 'manage.ps1'), '-Action', action,
    '-NodePath', process.execPath], { stdio: 'inherit', windowsHide: true });
  if (result.error) console.error(result.error.message);
  process.exitCode = result.status ?? 1;
}
