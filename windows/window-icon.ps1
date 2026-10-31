param([Parameter(Mandatory=$true)][int]$AgentPid,
      [Parameter(Mandatory=$true)][int]$TargetPid,
      [Parameter(Mandatory=$true)][string]$AppPath,
      [Parameter(Mandatory=$true)][string]$IconPath,
      [Parameter(Mandatory=$true)][string]$StatePath)
$ErrorActionPreference='Stop'
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'WindowIconGuard.cs')
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $manager=Join-Path $PSScriptRoot 'manage.ps1'
    $relaunch='"'+$powershell+'" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$manager+'" -Action launch -FromShortcut'
    [CodexUsageCard.WindowIconGuard]::Run($AgentPid,$TargetPid,$AppPath,$IconPath,$StatePath,$relaunch)
} catch {
    $result=@{state='error';targetPid=$TargetPid;message=$_.Exception.Message;checkedAt=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($StatePath,($result|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
    exit 1
}
