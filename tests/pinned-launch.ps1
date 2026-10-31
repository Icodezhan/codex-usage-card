param([string]$InstallRoot=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\addons\codex-usage-card'),
      [string]$TestRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'test-results\pinned-launch'))
$ErrorActionPreference='Stop'
# Test the exact shortcut command used when the desktop entry is pinned,
# without replacing or creating any of the user's real taskbar items.
$desktop=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Usage Card.lnk'
$shell=New-Object -ComObject WScript.Shell
$source=$shell.CreateShortcut($desktop)
$script=Join-Path $InstallRoot 'windows\manage.ps1'
if([IO.Path]::GetFileName($source.TargetPath) -ine 'powershell.exe' -or !$source.Arguments.Contains('"'+$script+'"') -or $source.Arguments -notmatch '-Action\s+launch'){
    throw 'The desktop entry does not call the usage-card launch script.'
}
$before=Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object CommandLine -NotMatch '--type=' | Select-Object -First 1
if(!$before -or $before.CommandLine -notmatch '--remote-debugging-port=39222'){throw 'This test needs an already-open usage-enabled client; it will not close the active client.'}
$helper=Join-Path $InstallRoot 'windows\WindowIconGuard.cs'
Add-Type -Path $helper
$window=(Get-Process -Id $before.ProcessId).MainWindowHandle
$appId=[CodexUsageCard.WindowIconSession]::ReadProperty($window,5)
$relaunch=[CodexUsageCard.WindowIconSession]::ReadProperty($window,2)
$name=[CodexUsageCard.WindowIconSession]::ReadProperty($window,4)
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null
$pin=Join-Path $TestRoot 'Codex Usage Card.lnk'
Copy-Item -LiteralPath $desktop -Destination $pin -Force
$saved=$shell.CreateShortcut($pin)
if($saved.TargetPath -cne $source.TargetPath -or $saved.Arguments -cne $source.Arguments){throw 'The copied fixed-entry command differs from the desktop launcher.'}
$log=Join-Path $InstallRoot 'launcher.log'
$beforeLines=@(Get-Content -LiteralPath $log -Encoding UTF8).Count
$process=Start-Process -FilePath $saved.TargetPath -ArgumentList $saved.Arguments -WorkingDirectory $saved.WorkingDirectory -WindowStyle Hidden -PassThru
if(!$process.WaitForExit(20000) -or $process.ExitCode -ne 0){throw 'The pinned-equivalent shortcut command did not complete successfully.'}
$newLog=@(Get-Content -LiteralPath $log -Encoding UTF8 | Select-Object -Skip $beforeLines)
if(!($newLog -match 'Action=launch;') -or !($newLog -match 'Existing Codex session activated without restarting')){throw 'The shortcut did not reach the quota launch path.'}
$after=Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object CommandLine -NotMatch '--type=' | Select-Object -First 1
if($after.ProcessId -ne $before.ProcessId -or $after.CommandLine -notmatch '--remote-debugging-port=39222'){throw 'Active client process or usage port changed'}
if([CodexUsageCard.WindowIconSession]::ReadProperty($window,5) -ne $appId -or [CodexUsageCard.WindowIconSession]::ReadProperty($window,2) -ne $relaunch -or [CodexUsageCard.WindowIconSession]::ReadProperty($window,4) -ne $name){throw 'Icon synchronization changed the application identity or relaunch metadata'}
$originalAfter=$shell.CreateShortcut($desktop)
if($originalAfter.TargetPath -cne $source.TargetPath -or $originalAfter.Arguments -cne $source.Arguments){throw 'Desktop launcher routing was modified'}
'PASS: fixed-entry command reaches Codex Usage Card, preserves its script/arguments and client port, and does not modify window launch identity.'
'NOTE: this verifies the pinned-equivalent command with an existing client; it does not claim a full client shutdown/reopen test.'
