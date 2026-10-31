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

function Set-UsageCardTaskbarIcon([string]$AppPath, [string]$IconLocation) {
    $directory = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    if (!(Test-Path -LiteralPath $directory -PathType Container)) { return }
    $shell = New-Object -ComObject WScript.Shell
    $shellFolder = (New-Object -ComObject Shell.Application).NameSpace($directory)
    $package = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    $appId = if ($package) { $package.PackageFamilyName + '!App' } else { '' }
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.lnk' -File)) {
        $shortcut = $shell.CreateShortcut($file.FullName)
        $item = $shellFolder.ParseName($file.Name)
        $sameAppId = $appId -and $item -and ($item.ExtendedProperty('System.AppUserModel.ID') -eq $appId)
        if ($shortcut.TargetPath -ine $AppPath -and !$sameAppId) { continue }
        $before = @($shortcut.TargetPath, $shortcut.Arguments, $shortcut.WorkingDirectory, $shortcut.Description) | ConvertTo-Json -Compress
        $shortcut.IconLocation = $IconLocation
        $shortcut.Save()
        $saved = $shell.CreateShortcut($file.FullName)
        $after = @($saved.TargetPath, $saved.Arguments, $saved.WorkingDirectory, $saved.Description) | ConvertTo-Json -Compress
        if ($before -cne $after) { throw 'Unexpected change to taskbar launch properties.' }
        Notify-UsageCardIcon $file.FullName
        Write-Output ('Updated taskbar icon only: ' + $file.FullName)
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
    Set-UsageCardTaskbarIcon $app $iconLocation
    [UsageCardOfficialIconRefresh]::SHChangeNotify(0x08000000, 0, $null, $null)
    Write-Output ('Updated desktop icon: ' + $iconLocation)
}
