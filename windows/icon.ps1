param([switch]$RestoreQuotaLaunch)
# Reuse the official transparent white icon byte-for-byte.
# Never recolour it, add a background, or modify the application package.
function New-UsageCardIcon([string]$AppPath) {
    $root = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\addons\codex-usage-card'
    $officialIcon = Join-Path (Split-Path -Parent $AppPath) 'resources\chatgpt-app-dark.ico'
    if (!(Test-Path -LiteralPath $officialIcon -PathType Leaf)) { throw 'Official transparent white icon was not found in the installed client.' }
    $iconPath = Join-Path $root 'usage-card-official-white.ico'
    Copy-Item -LiteralPath $officialIcon -Destination $iconPath -Force
    return $iconPath + ',0'
}

function Notify-UsageCardIcon([string]$ShortcutPath) {
    if (!('UsageCardOfficialIconRefresh' -as [type])) {
        Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class UsageCardOfficialIconRefresh { [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern void SHChangeNotify(uint e, uint f, string p1, string p2); }'
    }
    [UsageCardOfficialIconRefresh]::SHChangeNotify(0x2000, 0x5, $ShortcutPath, $null)
}

function Set-UsageCardTaskbarIcon([string]$AppPath, [string]$IconLocation,
    [switch]$RestoreQuotaLaunch,
    [string]$Directory=(Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'),
    [string]$DesktopPath=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Usage Card.lnk'),
    [string]$BackupDirectory='') {
    if (!(Test-Path -LiteralPath $Directory -PathType Container)) { throw 'Taskbar shortcut directory not found.' }
    $shell = New-Object -ComObject WScript.Shell
    $shellFolder = (New-Object -ComObject Shell.Application).NameSpace($Directory)
    $manager = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\addons\codex-usage-card\windows\manage.ps1'
    $desktop = $shell.CreateShortcut($DesktopPath)
    $isDesktopQuota = [IO.Path]::GetFileName($desktop.TargetPath) -ieq 'powershell.exe' -and $desktop.Arguments.Contains('"'+$manager+'"') -and $desktop.Arguments -match '-Action\s+launch'
    if ($RestoreQuotaLaunch -and !$isDesktopQuota) { throw 'The desktop quota launcher is missing or invalid. Install first.' }
    $package = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    $appId = if ($package) { $package.PackageFamilyName + '!App' } else { '' }
    $matches = @(foreach ($file in @(Get-ChildItem -LiteralPath $Directory -Filter '*.lnk' -File)) {
        $shortcut = $shell.CreateShortcut($file.FullName)
        $item = $shellFolder.ParseName($file.Name)
        $sameAppId = $appId -and $item -and ($item.ExtendedProperty('System.AppUserModel.ID') -eq $appId)
        $isQuota = [IO.Path]::GetFileName($shortcut.TargetPath) -ieq 'powershell.exe' -and $shortcut.Arguments.Contains('"'+$manager+'"') -and $shortcut.Arguments -match '-Action\s+launch'
        if ($shortcut.TargetPath -ieq $AppPath -or $sameAppId -or $isQuota) { $file }
    })
    if ($RestoreQuotaLaunch -and $matches.Count -ne 1) { throw 'Pin the running quota-enabled Codex window first. Keep exactly one Codex taskbar pin, then run RepairTaskbar.cmd again.' }
    foreach ($file in $matches) {
        $shortcut = $shell.CreateShortcut($file.FullName)
        $item = $shellFolder.ParseName($file.Name)
        $identity = $item.ExtendedProperty('System.AppUserModel.ID')
        $launchMetadata = @($item.ExtendedProperty('System.AppUserModel.RelaunchCommand'),$item.ExtendedProperty('System.AppUserModel.RelaunchDisplayNameResource')) | ConvertTo-Json -Compress
        $before = @($shortcut.TargetPath,$shortcut.Arguments,$shortcut.WorkingDirectory,$shortcut.Description) | ConvertTo-Json -Compress
        if ($RestoreQuotaLaunch) {
            if (!$BackupDirectory) { $BackupDirectory = Join-Path (Split-Path -Parent $manager) '..\entrypoint-backups' }
            New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $backupDirectory ('pin-before-repair-'+[guid]::NewGuid().ToString()+'.lnk'))
            $shortcut.TargetPath=$desktop.TargetPath
            $shortcut.Arguments=$desktop.Arguments
            $shortcut.WorkingDirectory=$desktop.WorkingDirectory
            $shortcut.Description=$desktop.Description
            $shortcut.WindowStyle=$desktop.WindowStyle
        }
        $shortcut.IconLocation=$IconLocation
        $shortcut.Save()
        $saved=$shell.CreateShortcut($file.FullName)
        $savedItem=$shellFolder.ParseName($file.Name)
        if ($savedItem.ExtendedProperty('System.AppUserModel.ID') -cne $identity) { throw 'Taskbar grouping identity changed unexpectedly.' }
        $savedMetadata=@($savedItem.ExtendedProperty('System.AppUserModel.RelaunchCommand'),$savedItem.ExtendedProperty('System.AppUserModel.RelaunchDisplayNameResource')) | ConvertTo-Json -Compress
        if ($savedMetadata -cne $launchMetadata) { throw 'Taskbar relaunch metadata changed unexpectedly.' }
        if ($RestoreQuotaLaunch) {
            if ($saved.TargetPath -cne $desktop.TargetPath -or $saved.Arguments -cne $desktop.Arguments -or $saved.IconLocation -cne $desktop.IconLocation) { throw 'Taskbar quota launch/icon verification failed.' }
        } else {
            $after=@($saved.TargetPath,$saved.Arguments,$saved.WorkingDirectory,$saved.Description) | ConvertTo-Json -Compress
            if ($before -cne $after) { throw 'Unexpected change to taskbar launch properties.' }
        }
        Notify-UsageCardIcon $file.FullName
        Write-Output ('Updated taskbar shortcut: '+$file.FullName)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $root = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\addons\codex-usage-card'
    $installation = Get-Content -LiteralPath (Join-Path $root 'installation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($installation.product -ne 'CodexUsageCard-Windows' -or $installation.installRoot -ne $root) { throw 'Unexpected installation owner.' }
    $package = Get-AppxPackage OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
    $app = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Usage Card.lnk'
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    if (!$shortcut.Arguments.Contains('"' + (Join-Path $root 'windows\manage.ps1') + '"')) { throw 'The desktop shortcut is not owned by this add-on.' }
    $iconLocation = New-UsageCardIcon $app
    $shortcut.IconLocation = $iconLocation
    $shortcut.Save()
    Notify-UsageCardIcon $shortcutPath
    Set-UsageCardTaskbarIcon $app $iconLocation -RestoreQuotaLaunch:$RestoreQuotaLaunch
    [UsageCardOfficialIconRefresh]::SHChangeNotify(0x08000000, 0, $null, $null)
    Write-Output ('Updated desktop icon: ' + $iconLocation)
}
