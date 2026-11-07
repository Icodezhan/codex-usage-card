# Changelog

## 0.9.4-windows.14 (local reset-time labels, 2026-11-04)

- Show five-hour reset time as HH:mm and weekly reset date as MM-DD below the quota labels, using the computer's local timezone.
- Adapt the reset labels and subtle background tags from [NANAiiiii's Windows fork](https://github.com/NANAiiiii/codex-usage-card/tree/60cfd75eacc07bf2bdeeafb761570dbfea4f8495/windows) (MIT). Retain full reset timestamps in hover details.
- Clear reset labels for missing/invalid data, unavailable quota and expired snapshots. Keep native update-button clearance with the taller card. UI component version: 55.
- Verify timezone rollover, 24-hour formatting, daylight saving changes, stale-data recovery and browser layout.

## 0.9.4-windows.13 (preserve native sidebar controls, 2026-11-04)

- Keep the quota card in normal flow before the native footer, including its update button.
- Hide the card when it would overlap a native control, push the footer outside the visible rail, or leave less than one navigation row; restore it when space returns.
- React to native footer size changes and class/style/hidden changes. Ignore clipped scroll-list content when checking overlaps. UI component version: 54.
- Real Chromium regression checks cover dynamic update buttons, small windows, automatic recovery, and single/dual quota layouts.

## 0.9.4-windows.12 (hide launcher consoles, 2026-10-31)

- Use the GUI Windows Script Host as the desktop, Startup and owned taskbar entry, creating PowerShell hidden from launch.
- Start the icon helper with UseShellExecute=false and CreateNoWindow=true. Preserve quota grouping and the existing white icon behavior.
- Migrate only taskbar shortcuts already owned by the quota launcher; ordinary app shortcuts remain untouched.


## 0.9.4-windows.11 (authorized runtime white icon synchronization, 2026-10-31)

- Restore the tested desktop/window quota identity and official white icon synchronization. The client may initially show its executable icon before synchronization; the user accepted this behavior.
- Keep the existing quota desktop launch command, pair taskbar relaunch metadata with it, and do not modify the signed client package.


## 0.9.4-windows.6 (portable installer ZIP, 2026-10-31)

- Add an allowlisted Windows x64 ZIP with Install, Diagnose and Uninstall commands, Chinese instructions, SHA-256 checksums and a signed Node.js 24 runtime plus its complete license.
- Copy the bundled runtime into the permanent per-user installation, so moving the extracted package after installation does not break the desktop launcher.
- Keep the desktop-only startup behavior and official transparent white icon; exclude login data, chat history, local installation metadata and logs from the package.

## 0.9.4-windows.5 (restore desktop-only launcher, 2026-10-30)

- Reuse the official transparent white `chatgpt-app-dark.ico` without redrawing or recolouring. Apply it to the desktop launcher and matching existing taskbar icon while preserving launch targets and arguments.

- Withdraw taskbar integration and remove duplicate Start menu/Desktop entries. Restore the taskbar target to the original client without debug arguments.
- Keep only the explicitly named desktop Codex Usage Card launcher plus the hidden background startup entry.
- Remove the native launcher integration from source and archive inactive installed files. State the remaining startup-port requirement explicitly.

## 0.9.4-windows.4 (taskbar integration, 2026-10-30)

- Add a native, console-free Codex launcher and normal Codex shortcuts that retain the original application ID and icon for taskbar grouping.
- Support replacing the pinned Store entry with the usage-enabled launcher; activate an existing window without restarting its main process.
- Preserve integration across reinstall and restore owned normal shortcuts to the real client on uninstall.
- Validate the installed taskbar target, application ID, executable launch result and unchanged main process.

## 0.9.4-windows.3 (MSIX visibility fix, 2026-10-30)

- Move runtime files out of virtualized AppData into the current user's `.codex/addons/codex-usage-card`; broker installation and background startup through Explorer.
- Verify actual physical paths of runtime scripts and all three shortcuts, rather than relying on the Store app's merged filesystem view.
- Record launch stages and wait for a real Codex main-window CDP endpoint before reporting application launch success.

## 0.9.4-windows.2 (local fix, 2026-10-30)

- Replace the WSH/VBScript shortcut entry with a directly quoted, hidden PowerShell launcher; migrate all three owned shortcuts during reinstall.
- Validate saved shortcut targets and script paths. Show concrete launch failures and save a launcher error log.
- Add a Windows regression test that executes the installed Startup shortcut through ShellExecute and verifies a fresh, healthy agent process.

## v0.9.4 Beta — first public release (macOS, 2026-10-28)

- Usage-only sidebar card with remaining-rate-limit ring(s); separate 5-hour and weekly rings when the rate-limit response supports them.
- Light/dark theme, keyboard focus and tooltips. UI component version: 53.
- Protected original-icon launch handoff, including a fix to allow a single hidden relaunch after a successful guarded quit even when subsequent input prevents focus stealing.
- This version has been installed and checked on one Mac: launch from the original Codex icon, automatic Ring display, usage readings and UI VERSION 53 all passed. Startup takes a few seconds longer than the previous version; this is a known experience difference. Other devices and future Codex versions remain unverified.
- Manager CDP connections now require the WebSocket protocol, a loopback host and the expected debugging port.
- Installation no longer calls legacy launcher cleanup: no automatic Dock/Launchpad changes, Dock restart or shortcut moves. Compatibility cleanup code is retained.
- No active auto-update mechanism; legacy update shortcuts and old update metadata are omitted. Safety migration modules are retained. Future updates require a manually obtained and checked package.
- Public English/Chinese documentation and the original MIT license are included; the old cover, Windows and historical development documents are omitted.
- No project size, folder-color or conversation-token feature in the current usage-only agent.

**Compatibility and security:** Not Apple-notarized. Uses a local debugging interface with significant privileges. See [SECURITY.md](SECURITY.md).

The applicable MIT license and original copyright notice are preserved in [LICENSE](LICENSE).
# 0.9.4-windows.1 (local adaptation, 2026-10-30)

- Add per-user Windows installation, hidden background agent, login startup shortcut, desktop/Start menu launcher, status, usage probe and ownership-checked uninstall.
- Detect Store installations and managed Windows Codex CLI versions without modifying the application bundle or signature.
- Preserve the upstream usage rings; validate CDP ports, provide sanitized agent state, singleton locking and clean app-server shutdown.
- Keep existing sessions running. First activation requires quitting Codex and opening the new shortcut.
- Add Node regression tests and a real Chromium rendering test; retain the original MIT license.
