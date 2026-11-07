param(
    [ValidateSet('install','start','launch','status','doctor','stop','uninstall')]
    [string]$Action = 'status',
    [string]$NodePath = '',
    [switch]$FromShortcut,
    [switch]$ExternalInstall,
    [string]$CompletionPath = ''
)
$ErrorActionPreference = 'Stop'
$Product = 'CodexUsageCard-Windows'
$SourceRoot = Split-Path -Parent $PSScriptRoot
$InstallRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\addons\codex-usage-card'
$LegacyRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) $Product
$ManifestPath = Join-Path $InstallRoot 'installation.json'
$StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Usage Card Agent.lnk'
$MenuLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Usage Card.lnk'
$DesktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Usage Card.lnk'
$Port = 39222

trap {
    $message = $_.Exception.Message
    if ($CompletionPath) {
        try { Save-Json $CompletionPath @{ success=$false; error=$message } } catch { }
    }
    try { Write-LaunchLog ('ERROR: ' + $message) } catch { }
    if ($FromShortcut) {
        try {
            if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
                [IO.File]::WriteAllText((Join-Path $InstallRoot 'launcher-error.log'), $message, (New-Object Text.UTF8Encoding($false)))
            }
            Add-Type -AssemblyName PresentationFramework
            [System.Windows.MessageBox]::Show($message, 'Codex Usage Card', 'OK', 'Warning') | Out-Null
        } catch { }
    } else { Write-Error -Message $message -ErrorAction Continue }
    exit 1
}

function Save-Json($File, $Value) {
    [IO.File]::WriteAllText($File, ($Value | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}
function Install-BundledNode([string]$SourceDirectory, [string]$DestinationDirectory, [string]$RequestedNode) {
    $bundledNode = Join-Path $SourceDirectory 'runtime\node.exe'
    if (!(Test-Path -LiteralPath $bundledNode -PathType Leaf) -or
        [IO.Path]::GetFullPath($RequestedNode) -ine [IO.Path]::GetFullPath($bundledNode)) { return $RequestedNode }
    $runtimeDirectory = Join-Path $DestinationDirectory 'runtime'
    New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
    $installedNode = Join-Path $runtimeDirectory 'node.exe'
    if ([IO.Path]::GetFullPath($bundledNode) -ine [IO.Path]::GetFullPath($installedNode)) {
        Copy-Item -LiteralPath $bundledNode -Destination $installedNode -Force
        Copy-Item -LiteralPath (Join-Path $SourceDirectory 'runtime\LICENSE') -Destination (Join-Path $runtimeDirectory 'LICENSE') -Force
    }
    return $installedNode
}
function Write-LaunchLog([string]$Message) {
    if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
        [IO.File]::AppendAllText((Join-Path $InstallRoot 'launcher.log'), ((Get-Date).ToUniversalTime().ToString('o') + ' ' + $Message + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    }
}
function Find-App {
    if ($env:CODEX_BADGE_APP -and (Test-Path -LiteralPath $env:CODEX_BADGE_APP -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $env:CODEX_BADGE_APP).Path
    }
    $packages = @(Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Sort-Object Version -Descending)
    foreach ($package in $packages) {
        foreach ($relative in @('app\ChatGPT.exe','app\Codex.exe','ChatGPT.exe','Codex.exe')) {
            $candidate = Join-Path $package.InstallLocation $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Codex\ChatGPT.exe')
    )) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate } }
    throw 'Codex desktop app not found. Set CODEX_BADGE_APP to its executable path.'
}
function Read-Manifest {
    if (!(Test-Path -LiteralPath $ManifestPath)) { throw 'Not installed. Run: node manage.cjs install' }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.product -ne $Product -or $manifest.installRoot -ne $InstallRoot) { throw 'Installation ownership check failed.' }
    return $manifest
}
function Get-Agent {
    $statePath = Join-Path $InstallRoot 'agent-state.json'
    if (!(Test-Path -LiteralPath $statePath)) { return $null }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $agentProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$state.pid)" -ErrorAction SilentlyContinue
        $expected = Join-Path $InstallRoot 'windows\runner.cjs'
        if ($agentProcess -and $agentProcess.CommandLine -and $agentProcess.CommandLine.Contains('"' + $expected + '"')) { return $agentProcess }
    } catch { }
    return $null
}
function Stop-Agent {
    if (Get-Agent) {
        [IO.File]::WriteAllText((Join-Path $InstallRoot 'stop.request'), 'stop')
        for ($i = 0; $i -lt 100; $i++) {
            Start-Sleep -Milliseconds 100
            if (!(Get-Agent)) { return }
        }
        throw 'Agent did not stop within 10 seconds; refusing to overwrite or remove a running installation.'
    }
}
function Start-Agent {
    $manifest = Read-Manifest
    if (Get-Agent) { return }
    if (!(Test-Path -LiteralPath $manifest.node -PathType Leaf)) { throw 'Installed Node runtime is missing. Reinstall with Node.js 24+.' }
    Remove-Item -LiteralPath (Join-Path $InstallRoot 'stop.request') -Force -ErrorAction SilentlyContinue
    $runner = Join-Path $InstallRoot 'windows\runner.cjs'
    $env:CODEX_BADGE_APP = Find-App
    Start-Process -FilePath $manifest.node -ArgumentList ('"' + $runner + '"') -WorkingDirectory $InstallRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $InstallRoot 'agent.log') -RedirectStandardError (Join-Path $InstallRoot 'agent-error.log') | Out-Null
    for ($i = 0; $i -lt 50; $i++) { Start-Sleep -Milliseconds 100; if (Get-Agent) { return } }
    throw 'Agent failed to start. Inspect agent-error.log in the installation directory.'
}
function Sync-UsageCardWindowIcons([string]$AppPath) {
    $agent = Get-Agent
    if (!$agent) { return }
    $iconPath = Join-Path $InstallRoot 'usage-card-official-white.ico'
    if (!(Test-Path -LiteralPath $iconPath -PathType Leaf)) { throw 'Official window icon is missing. Reinstall the add-on.' }
    $targets = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" | Where-Object {
        $_.ExecutablePath -eq $AppPath -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine -match '--remote-debugging-port=39222'
    })
    foreach ($target in $targets) {
        $helper = Join-Path $InstallRoot 'windows\window-icon.ps1'
        $state = Join-Path $InstallRoot ('window-icon-' + $target.ProcessId + '.json')
        $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $helper + '" -AgentPid ' + $agent.ProcessId + ' -TargetPid ' + $target.ProcessId + ' -AppPath "' + $AppPath + '" -IconPath "' + $iconPath + '" -StatePath "' + $state + '"'
        $hidden=New-Object Diagnostics.ProcessStartInfo
        $hidden.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $hidden.Arguments=$arguments
        $hidden.UseShellExecute=$false
        $hidden.CreateNoWindow=$true
        $hidden.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        [Diagnostics.Process]::Start($hidden) | Out-Null
    }
}
function Write-Link($File, $Target, $Arguments, $Description, $Icon = '') {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($File)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.Description = $Description
    $shortcut.WindowStyle = 7
    if ($Icon) { $shortcut.IconLocation = $Icon }
    $shortcut.Save()
}
function Test-OwnedLink($Shortcut) {
    $legacyEntry = Join-Path $InstallRoot 'windows\entry.vbs'
    $currentEntry = Join-Path $InstallRoot 'windows\manage.ps1'
    $arguments = $Shortcut.Arguments
    $target = [IO.Path]::GetFileName($Shortcut.TargetPath)
    $legacyVbs = Join-Path $LegacyRoot 'windows\entry.vbs'
    $legacyPs = Join-Path $LegacyRoot 'windows\manage.ps1'
    return (($target -ieq 'wscript.exe' -and ($arguments.Contains('"' + $legacyEntry + '"') -or $arguments.Contains('"' + $legacyVbs + '"'))) -or
        ($target -ieq 'powershell.exe' -and ($arguments.Contains('"' + $currentEntry + '"') -or $arguments.Contains('"' + $legacyPs + '"'))))
}
function Remove-OwnedLink($File) {
    if (!(Test-Path -LiteralPath $File -PathType Leaf)) { return }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($File)
    if (Test-OwnedLink $shortcut) {
        Remove-Item -LiteralPath $File -Force
    }
}
function Show-Status {
    $manifest = Read-Manifest
    $app = Find-App
    $agentProcess = Get-Agent
    $state = $null
    if (Test-Path -LiteralPath (Join-Path $InstallRoot 'agent-state.json')) {
        $state = Get-Content -LiteralPath (Join-Path $InstallRoot 'agent-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $listener = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    [ordered]@{
        product = $Product; version = $manifest.version; installed = $true
        installRoot = $InstallRoot; app = $app; agentRunning = [bool]$agentProcess
        startupRegistered = (Test-Path -LiteralPath $StartupLink)
        cdpListening = ($listener.Count -gt 0)
        cdpLoopbackOnly = ($listener.Count -gt 0 -and @($listener | Where-Object LocalAddress -NotIn @('127.0.0.1','::1')).Count -eq 0)
        state = $state
    } | ConvertTo-Json -Depth 8
}

# Installation from the Store app inherits AppData redirection even when a child
# process has no package identity. Ask Explorer to perform the installation in
# the same filesystem context used when the user double-clicks a shortcut.
if ($Action -eq 'install' -and !$ExternalInstall) {
    if (!$NodePath) { $NodePath = (Get-Command node.exe -ErrorAction Stop).Source }
    $resultDirectory = Join-Path $SourceRoot '.installation-results'
    New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
    $resultPath = Join-Path $resultDirectory ([guid]::NewGuid().ToString() + '.json')
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Action ' + $Action + ' -ExternalInstall -NodePath "' + $NodePath + '" -CompletionPath "' + $resultPath + '"'
    (New-Object -ComObject Shell.Application).ShellExecute($powershell, $arguments, $SourceRoot, 'open', 0)
    for ($i=0; $i -lt 300; $i++) {
        Start-Sleep -Milliseconds 200
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (!$result.success) { throw ('External installation failed: ' + $result.error) }
            Show-Status
            return
        }
    }
    throw 'Explorer did not complete installation within 60 seconds. No successful installation was reported.'
}

Write-LaunchLog ('Action=' + $Action + '; PID=' + $PID)
switch ($Action) {
    'install' {
        $app = Find-App
        if (!$NodePath) { $NodePath = (Get-Command node.exe -ErrorAction Stop).Source }
        if ([int]((& $NodePath --version).TrimStart('v').Split('.')[0]) -lt 24) { throw 'Node.js 24+ is required.' }
        if (Test-Path -LiteralPath $InstallRoot) { $null = Read-Manifest; Stop-Agent }
        foreach ($linkPath in @($StartupLink, $MenuLink, $DesktopLink)) {
            if (Test-Path -LiteralPath $linkPath) {
                $existing = (New-Object -ComObject WScript.Shell).CreateShortcut($linkPath)
                if (!(Test-OwnedLink $existing)) { throw "Refusing to replace an unrelated shortcut: $linkPath" }
            }
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot 'windows') | Out-Null
        $NodePath = Install-BundledNode $SourceRoot $InstallRoot $NodePath
        if ([IO.Path]::GetFullPath($SourceRoot) -ne [IO.Path]::GetFullPath($InstallRoot)) {
            foreach ($file in @('agent.cjs','manage.cjs','LICENSE')) { Copy-Item -LiteralPath (Join-Path $SourceRoot $file) -Destination $InstallRoot -Force }
            foreach ($file in @('manage.ps1','runner.cjs','entry.vbs','doctor.cjs','icon.ps1','window-icon.ps1','WindowIconGuard.cs')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $InstallRoot 'windows') -Force }
        }
        Save-Json $ManifestPath ([ordered]@{ product=$Product; version='0.9.4-windows.14'; installRoot=$InstallRoot; node=$NodePath; entryMode='desktop-launcher'; installedAt=(Get-Date).ToUniversalTime().ToString('o') })
        $entry = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $InstallRoot 'windows\manage.ps1') + '"'
        $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $hostPath=Join-Path $env:WINDIR 'System32\wscript.exe'
        $hiddenEntry='//B //Nologo "'+(Join-Path $InstallRoot 'windows\entry.vbs')+'"'
        Write-Link $StartupLink $hostPath ($hiddenEntry + ' start') 'Codex Usage Card background agent'
        Remove-OwnedLink $MenuLink
        . (Join-Path $InstallRoot 'windows\icon.ps1')
        $desktopIcon = New-UsageCardIcon $app
        Write-Link $DesktopLink $hostPath ($hiddenEntry + ' launch') 'Launch Codex with sidebar usage rings' $desktopIcon
        Set-UsageCardDesktopIdentity $DesktopLink $desktopIcon
        $pins=Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        if(Test-Path -LiteralPath $pins){foreach($pin in Get-ChildItem -LiteralPath $pins -Filter '*.lnk' -File){
            $old=(New-Object -ComObject WScript.Shell).CreateShortcut($pin.FullName)
            if(Test-OwnedLink $old){
                Write-Link $pin.FullName $hostPath ($hiddenEntry+' launch') 'Codex Usage Card' $desktopIcon
                Set-UsageCardDesktopIdentity $pin.FullName $desktopIcon
                Notify-UsageCardIcon $pin.FullName
            }
        }}
        Set-UsageCardTaskbarIcon $app $desktopIcon
        foreach ($linkPath in @($StartupLink, $DesktopLink)) {
            $saved = (New-Object -ComObject WScript.Shell).CreateShortcut($linkPath)
            if (!(Test-OwnedLink $saved) -or !(Test-Path -LiteralPath $saved.TargetPath -PathType Leaf) -or
                !(Test-Path -LiteralPath (Join-Path $InstallRoot 'windows\manage.ps1') -PathType Leaf)) {
                throw "Shortcut verification failed: $linkPath"
            }
        }
        Start-Agent
        Sync-UsageCardWindowIcons $app
        Show-Status
        Write-LaunchLog 'Installation completed in Explorer context.'
        if ($CompletionPath) { Save-Json $CompletionPath @{success=$true} }
    }
    'start' { Start-Agent }
    'launch' {
        $null = Read-Manifest
        $app = Find-App
        Start-Agent
        Write-LaunchLog 'Agent is running; checking Codex.'
        $running = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" | Where-Object { $_.ExecutablePath -eq $app -and $_.CommandLine -notmatch '--type=' })
        if ($running.Count -gt 0) {
            $debugEnabled = @($running | Where-Object CommandLine -Match '--remote-debugging-port=39222').Count -gt 0
            if (!$debugEnabled) { throw 'Codex is already running without the usage-card connection. Fully quit Codex (including its tray icon), then open the Codex Usage Card shortcut. Your active session has not been closed.' }
            # Invoke the real application's single-instance activation so a
            # window hidden in the tray is shown, while retaining its flags.
            Start-Process -FilePath $app -WorkingDirectory (Split-Path -Parent $app) -WindowStyle Normal | Out-Null
            Write-LaunchLog 'Existing Codex session activated without restarting.'
            Sync-UsageCardWindowIcons $app
            Write-Output 'Codex is already running with the usage-card connection.'
        } else {
            $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
            if ($listeners.Count -gt 0) { throw "Port $Port is in use. Refusing to launch against another process." }
            $launched = Start-Process -FilePath $app -ArgumentList @('--remote-debugging-address=127.0.0.1', '--remote-debugging-port=39222') -WorkingDirectory (Split-Path -Parent $app) -WindowStyle Normal -PassThru
            Write-LaunchLog ('Codex process requested; PID=' + $launched.Id)
            $ready = $false
            for ($i=0; $i -lt 80; $i++) {
                Start-Sleep -Milliseconds 250
                try {
                    $targets = @(Invoke-RestMethod -Uri ('http://127.0.0.1:' + $Port + '/json/list') -TimeoutSec 1)
                    if (@($targets | Where-Object { $_.type -eq 'page' -and $_.url -match '^app://-/index.html' }).Count -gt 0) { $ready=$true; break }
                } catch { }
            }
            if (!$ready) {
                $launched.Refresh()
                $exitInfo = if ($launched.HasExited) { ' Process exit code: ' + $launched.ExitCode + '.' } else { ' The process is still running.' }
                throw ('Codex did not expose its local usage-card connection within 20 seconds.' + $exitInfo + ' See launcher.log in ' + $InstallRoot)
            }
            Write-LaunchLog 'Codex main window and local debugging connection verified.'
            Sync-UsageCardWindowIcons $app
            Write-Output 'Codex main window and usage-card connection verified.'
        }
    }
    'status' { Show-Status }
    'doctor' {
        $manifest = Read-Manifest
        Show-Status
        $env:CODEX_BADGE_APP = Find-App
        & $manifest.node (Join-Path $InstallRoot 'windows\doctor.cjs')
        if ($LASTEXITCODE -ne 0) { throw 'Usage probe failed.' }
    }
    'stop' { $null = Read-Manifest; Stop-Agent; Write-Output 'Usage-card agent stopped.' }
    'uninstall' {
        $null = Read-Manifest
        Stop-Agent
        # Delete only this add-on's exact directory, never its .codex parent.
        $expected = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\addons\codex-usage-card'))
        $resolved = (Resolve-Path -LiteralPath $InstallRoot).Path
        if ($resolved -ne $expected -or (Get-Item -LiteralPath $InstallRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unsafe uninstall target.' }
        foreach ($linkPath in @($StartupLink,$MenuLink,$DesktopLink)) { Remove-OwnedLink $linkPath }
        $pins=Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        if (Test-Path -LiteralPath $pins) { foreach ($pin in Get-ChildItem -LiteralPath $pins -Filter '*.lnk' -File) { Remove-OwnedLink $pin.FullName } }
        $normalLinks = @(
            (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex.lnk'),
            (Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex.lnk'),
            (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Codex.lnk')
        )
        # Keep a pinned normal Codex icon usable after removing this add-on.
        # Only links still pointing at our launcher are restored.
        $realApp = Find-App
        foreach ($normalLink in $normalLinks) {
            if (Test-Path -LiteralPath $normalLink -PathType Leaf) {
                $existingLink = (New-Object -ComObject WScript.Shell).CreateShortcut($normalLink)
                if ($existingLink.TargetPath -eq (Join-Path $InstallRoot 'CodexLauncher.exe')) {
                    $existingLink.TargetPath = $realApp
                    $existingLink.Arguments = ''
                    $existingLink.WorkingDirectory = Split-Path -Parent $realApp
                    $existingLink.IconLocation = $realApp + ',0'
                    $existingLink.Description = 'Codex'
                    $existingLink.Save()
                } elseif ($existingLink.IconLocation.StartsWith($InstallRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    $officialWhite = Join-Path (Split-Path -Parent $realApp) 'resources\chatgpt-app-dark.ico'
                    $existingLink.IconLocation = if (Test-Path -LiteralPath $officialWhite -PathType Leaf) { $officialWhite + ',0' } else { $realApp + ',0' }
                    $existingLink.Save()
                }
            }
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
        Write-Output 'Codex Usage Card uninstalled. Restart Codex normally to close its debug port.'
    }
}
