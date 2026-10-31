param([string]$ClientShortcut='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\icon.ps1')
$fixture=Join-Path (Split-Path -Parent $PSScriptRoot) ('test-results\taskbar-repair-'+[guid]::NewGuid().ToString())
$pins=Join-Path $fixture 'pins'
New-Item -ItemType Directory -Path $pins -Force | Out-Null
$shell=New-Object -ComObject WScript.Shell
# A real client-created link retains its actual grouping ID through WScript.Save.
if(!$ClientShortcut) {
    $directory=Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    $folder=(New-Object -ComObject Shell.Application).NameSpace($directory)
    $ClientShortcut=@(Get-ChildItem -LiteralPath $directory -Filter '*.lnk' | Where-Object { $folder.ParseName($_.Name).ExtendedProperty('System.AppUserModel.ID') -eq 'com.openai.codex' } | Select-Object -First 1 -ExpandProperty FullName)[0]
}
if(!$ClientShortcut -or !(Test-Path -LiteralPath $ClientShortcut)){throw 'Provide -ClientShortcut with a client-created taskbar shortcut fixture.'}
$pin=Join-Path $pins 'ChatGPT.lnk'
Copy-Item -LiteralPath $ClientShortcut -Destination $pin
$link=$shell.CreateShortcut($pin)
$package=Get-AppxPackage OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
$app=Join-Path $package.InstallLocation 'app\ChatGPT.exe'
$link.TargetPath=$app;$link.Arguments='';$link.IconLocation=',0';$link.Save()
$desktop=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Usage Card.lnk'
$source=$shell.CreateShortcut($desktop)
$folder=(New-Object -ComObject Shell.Application).NameSpace($pins)
$id=$folder.ParseName('ChatGPT.lnk').ExtendedProperty('System.AppUserModel.ID')
$oldTarget=$link.TargetPath;$oldArgs=$link.Arguments
Set-UsageCardTaskbarIcon $app $source.IconLocation -Directory $pins -DesktopPath $desktop
$saved=$shell.CreateShortcut($pin)
if($saved.TargetPath -cne $oldTarget -or $saved.Arguments -cne $oldArgs){throw 'Ordinary icon refresh changed the route'}
Set-UsageCardTaskbarIcon $app $source.IconLocation -RestoreQuotaLaunch -Directory $pins -DesktopPath $desktop -BackupDirectory (Join-Path $fixture 'backups')
$saved=$shell.CreateShortcut($pin)
if($saved.TargetPath -cne $source.TargetPath -or $saved.Arguments -cne $source.Arguments -or $saved.IconLocation -cne $source.IconLocation){throw 'Repair differs from desktop quota launch/icon'}
if($folder.ParseName('ChatGPT.lnk').ExtendedProperty('System.AppUserModel.ID') -cne $id){throw 'Grouping identity changed'}
Copy-Item -LiteralPath $pin -Destination (Join-Path $pins 'Duplicate.lnk')
$before=(Get-FileHash -LiteralPath $pin).Hash
$rejected=$false
try {Set-UsageCardTaskbarIcon $app $source.IconLocation -RestoreQuotaLaunch -Directory $pins -DesktopPath $desktop -BackupDirectory (Join-Path $fixture 'backups')}catch{$rejected=$true}
if(!$rejected -or (Get-FileHash -LiteralPath $pin).Hash -cne $before){throw 'Ambiguous pins were not rejected without mutation'}
'PASS: icon-only preservation; repaired quota command + white icon; original grouping ID retained; ambiguous pins rejected. Real taskbar unchanged.'
