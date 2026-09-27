$ErrorActionPreference='Stop'
$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$source=Join-Path $PSScriptRoot '../scripts/Test-CurrentGuestAccess.ps1'
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$t,[ref]$e)
if($e){throw 'Diagnostic source parse failed'}
$imports=$ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Import-Module'},$true)
foreach($node in $imports){. ([scriptblock]::Create($node.Extent.Text))}
$getter=$ast.Find({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '(^|\\)Get-DevFleetE2ECredential$'},$true)
if(-not $getter){throw 'Native credential getter was not found in production path'}
$command=Get-Command $getter.GetCommandName() -ErrorAction Stop
if($command.ModuleName -cne 'Secrets'){throw 'Credential getter resolved outside the native Secrets module'}
'PASS production import sequence resolves native credential getter; secret loads 0; VM operations 0'
