$ErrorActionPreference = 'Stop'
$installRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\addons\codex-usage-card'
$shell = New-Object -ComObject WScript.Shell
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; using System.Text; public static class UsageCardTestPath { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern uint GetFinalPathNameByHandle(IntPtr h, StringBuilder b, uint n, uint f); }'
function Assert-PhysicalPath([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object Text.StringBuilder 4096
        $length = [UsageCardTestPath]::GetFinalPathNameByHandle($stream.SafeFileHandle.DangerousGetHandle(),$buffer,4096,0)
        if ($length -eq 0) { throw 'Cannot resolve actual filesystem path.' }
        $physical = $buffer.ToString()
        if ($physical.StartsWith('\\?\')) { $physical = $physical.Substring(4) }
        if ($physical -ine [IO.Path]::GetFullPath($Path)) { throw "MSIX filesystem redirection detected: $Path -> $physical" }
    } finally { $stream.Dispose() }
}
Assert-PhysicalPath (Join-Path $installRoot 'windows\manage.ps1')
$entries = @(
    @{ Directory='Desktop'; Name='Codex Usage Card.lnk'; Action='launch' },
    @{ Directory='Startup'; Name='Codex Usage Card Agent.lnk'; Action='start' }
)
$startupPath = $null
foreach ($entry in $entries) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath($entry.Directory)) $entry.Name
    if (!(Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { throw "Missing shortcut: $shortcutPath" }
    Assert-PhysicalPath $shortcutPath
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if (!(Test-Path -LiteralPath $shortcut.TargetPath -PathType Leaf) -or [IO.Path]::GetFileName($shortcut.TargetPath) -ne 'powershell.exe') { throw 'Shortcut must target an existing PowerShell executable.' }
    $scriptPath = Join-Path $installRoot 'windows\manage.ps1'
    if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf) -or !$shortcut.Arguments.Contains('-File "' + $scriptPath + '"')) { throw 'Shortcut script path is missing or incorrectly quoted.' }
    if (!$shortcut.Arguments.Contains('-Action ' + $entry.Action + ' -FromShortcut')) { throw 'Shortcut action does not match its purpose.' }
    if ($entry.Action -eq 'start') { $startupPath = $shortcutPath }
}
foreach ($entryName in @('Codex.lnk','Codex Usage Card.lnk','ChatGPT.lnk')) {
    if (Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('Programs')) $entryName)) { throw "Unexpected duplicate Start menu shortcut: $entryName" }
}
$pin = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Codex.lnk'
if (Test-Path -LiteralPath $pin) {
    $pinned = $shell.CreateShortcut($pin)
    if ($pinned.TargetPath -like ($installRoot + '\*') -or $pinned.Arguments -match 'remote-debugging|codex-usage-card') { throw 'Taskbar entry still points to the add-on launcher.' }
}
Write-Output 'PASS: desktop launcher and background startup are valid; duplicate Start menu entries and taskbar redirection are absent.'
$manager = Join-Path $installRoot 'manage.cjs'
$node = (Get-Content -LiteralPath (Join-Path $installRoot 'installation.json') -Raw -Encoding UTF8 | ConvertFrom-Json).node
& $node $manager stop
if ($LASTEXITCODE -ne 0) { throw 'Failed to stop the test agent.' }
# Launch the actual installed .lnk through ShellExecute, as Explorer does.
(New-Object -ComObject Shell.Application).ShellExecute($startupPath, '', (Split-Path -Parent $startupPath), 'open', 0)
$started = $false
for ($i = 0; $i -lt 100; $i++) {
    Start-Sleep -Milliseconds 200
    $state = Get-Content -LiteralPath (Join-Path $installRoot 'agent-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $agent = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$state.pid)" -ErrorAction SilentlyContinue
    if ($agent -and $agent.CommandLine.Contains('"' + (Join-Path $installRoot 'windows\runner.cjs') + '"') -and
        $state.state -ne 'stopped' -and ([DateTime]::UtcNow - [DateTime]::Parse($state.heartbeat).ToUniversalTime()).TotalSeconds -lt 10) {
        $started = $true
        break
    }
}
if (!$started) { throw 'The actual installed shortcut did not start a healthy agent.' }
Write-Output 'PASS: physical paths are unredirected and Explorer launches a healthy agent from the installed .lnk.'
