param([string]$RuntimeRoot=(Split-Path -Parent $PSScriptRoot),
      [string]$NodePath=(Get-Command node.exe).Source)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $RuntimeRoot 'windows\WindowIconGuard.cs')
$testRoot=Join-Path $RuntimeRoot 'test-results\window-icons'
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$package=Get-AppxPackage OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
$officialIcon=Join-Path $package.InstallLocation 'app\resources\chatgpt-app-dark.ico'
$statePath=Join-Path $testRoot 'state.json'
if(Test-Path -LiteralPath $statePath){[IO.File]::WriteAllText($statePath,'{}')}
$fakeParent=Join-Path $testRoot 'parent.cjs'
[IO.File]::WriteAllText($fakeParent,"process.stdin.resume();process.stdin.on('end',()=>process.exit(0));setInterval(()=>{},1000);")
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=$NodePath
$start.Arguments='"'+$fakeParent+'"'
$start.UseShellExecute=$false
$start.CreateNoWindow=$true
$start.RedirectStandardInput=$true
$parent=[Diagnostics.Process]::Start($start)
$first=New-Object Windows.Forms.Form
$first.Text='Codex Usage Card icon fixture 1'
$first.Icon=[Drawing.SystemIcons]::Warning
$first.Width=300;$first.Height=100
$second=$null;$helper=$null
function Read-State {
    try { Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}
function Assert-WhiteIcon([IntPtr]$Window,[int]$Kind) {
    $handle=[CodexUsageCard.WindowIconSession]::ReadIcon($Window,$Kind)
    if($handle -eq [IntPtr]::Zero){throw 'Running window icon is absent'}
    $bitmap=[Drawing.Icon]::FromHandle($handle).ToBitmap()
    try {
        $white=0
        for($x=0;$x -lt $bitmap.Width;$x++){for($y=0;$y -lt $bitmap.Height;$y++){
            $pixel=$bitmap.GetPixel($x,$y)
            if($pixel.A -gt 245){if($pixel.R -ne 255 -or $pixel.G -ne 255 -or $pixel.B -ne 255){throw 'Window icon contains a nonwhite opaque pixel'};$white++}
        }}
        if($white -eq 0 -or $bitmap.GetPixel(0,0).A -ne 0){throw 'Window icon is not a transparent white logo'}
    } finally {$bitmap.Dispose()}
}
try {
    $first.Show()
    [Windows.Forms.Application]::DoEvents()
    $beforeId=[CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,5)
    $beforeCommand=[CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,2)
    $beforeName=[CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,4)
    $targetPath=(Get-Process -Id $PID).Path
    $arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $RuntimeRoot 'windows\window-icon.ps1')+'" -AgentPid '+$parent.Id+' -TargetPid '+$PID+' -AppPath "'+$targetPath+'" -IconPath "'+$officialIcon+'" -StatePath "'+$statePath+'"'
    $helper=Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $ready=$false
    for($i=0;$i -lt 100;$i++){
        [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100
        $state=Read-State
        if($state.state -eq 'error'){throw $state.message}
        if($state.windows -ge 1){$ready=$true;break}
    }
    if(!$ready){throw 'Window icon helper did not synchronize the fixture'}
    Assert-WhiteIcon $first.Handle 0
    Assert-WhiteIcon $first.Handle 1
    if([CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,3) -ne ($officialIcon+',0')){throw 'Taskbar group icon resource was not set'}
    if([CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,5) -ne $beforeId -or [CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,2) -ne $beforeCommand){throw 'Application identity or launch command was modified'}
    if([CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,4) -ne $beforeName){throw 'Relaunch display name was modified'}
    # Simulate the client changing its native icon after startup and opening
    # another window. No taskbar .lnk exists for this fixture process.
    $first.Icon=[Drawing.SystemIcons]::Error
    $second=New-Object Windows.Forms.Form
    $second.Text='Codex Usage Card icon fixture 2';$second.Icon=[Drawing.SystemIcons]::Warning
    $second.Width=300;$second.Height=100;$second.Show()
    for($i=0;$i -lt 30;$i++){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100}
    Assert-WhiteIcon $first.Handle 0
    Assert-WhiteIcon $second.Handle 0
    Assert-WhiteIcon $second.Handle 1
    $parent.StandardInput.Close()
    if(!$parent.WaitForExit(3000)){throw 'Fixture parent did not exit'}
    for($i=0;$i -lt 50 -and !$helper.HasExited;$i++){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100;$helper.Refresh()}
    if(!$helper.HasExited){throw 'Icon helper outlived its parent'}
    if([CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,3) -ne $null){throw 'Taskbar icon property was not restored'}
    $restored=[Drawing.Icon]::FromHandle([CodexUsageCard.WindowIconSession]::ReadIcon($first.Handle,0)).ToBitmap()
    try {
        $coloured=$false
        for($x=0;$x -lt $restored.Width;$x++){for($y=0;$y -lt $restored.Height;$y++){$p=$restored.GetPixel($x,$y);if($p.A -gt 245 -and ($p.R -ne 255 -or $p.G -ne 255 -or $p.B -ne 255)){$coloured=$true}}}
        if(!$coloured){throw 'Original client icon was not restored on shutdown'}
    }finally{$restored.Dispose()}
    if([CodexUsageCard.WindowIconSession]::ReadProperty($first.Handle,5) -ne $beforeId){throw 'Application identity changed during the icon helper lifetime'}
    'PASS: no pinned shortcut required; small/large icons, taskbar resource, theme reset, new window, identity preservation and clean restoration.'
} finally {
    try{$parent.StandardInput.Close()}catch{}
    for($i=0;$i -lt 30 -and $helper -and !$helper.HasExited;$i++){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100;$helper.Refresh()}
    if($second){$second.Close();$second.Dispose()}
    $first.Close();$first.Dispose();$parent.Dispose()
    if($helper){$helper.Dispose()}
}
