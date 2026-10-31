param([Parameter(Mandatory=$true)][string]$PackageRoot,
      [Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference='Stop'
$parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PackageRoot 'windows\manage.ps1'),[ref]$null,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors|Out-String)}
$definition=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-BundledNode'},$true)
if(!$definition){throw 'Bundled runtime installer function is missing'}
. ([scriptblock]::Create($definition.Extent.Text))
$sourceNode=Join-Path $PackageRoot 'runtime\node.exe'
$installed=Install-BundledNode $PackageRoot $TestRoot $sourceNode
$expected=Join-Path $TestRoot 'runtime\node.exe'
if($installed -ne $expected -or !(Test-Path -LiteralPath $expected -PathType Leaf)){throw 'The runtime path still depends on the extraction directory'}
if(!(Test-Path -LiteralPath (Join-Path $TestRoot 'runtime\LICENSE'))){throw 'Runtime license was not installed'}
if((Get-FileHash -LiteralPath $sourceNode).Hash -ne (Get-FileHash -LiteralPath $installed).Hash){throw 'Installed runtime bytes differ'}
$nodeVersion=& $installed --version
if($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v24\.'){throw 'Installed runtime did not execute'}
$same=Install-BundledNode $TestRoot $TestRoot $installed
if($same -ne $installed){throw 'In-place reinstall changed the runtime path'}
$external=Install-BundledNode (Join-Path $TestRoot 'no-bundle') (Join-Path $TestRoot 'unused') $sourceNode
if($external -ne $sourceNode){throw 'Source checkout installation did not retain the supplied runtime'}
Write-Output 'PASS: bundled runtime and license copy to a permanent path; Unicode/spaces, source checkout and in-place reinstall work.'
