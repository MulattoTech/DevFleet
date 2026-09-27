param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $WorkspaceRoot 'installer-source/Build-Release.ps1') -Raw
$start=$source.IndexOf('  [string[]]$authorizedPaths=@(')
$end=$source.IndexOf('  foreach($authorizedPath', $start)
if($start-lt0-or$end-le$start){throw 'Native correction path construction was not found.'}
$priorState=[pscustomobject]@{authorized_correction=[pscustomobject]@{shipping_paths=@('source/app/z.py','source/CHECKSUMS.sha256','installer-source/Build-Release.ps1','source/app/z.py')}}
. ([scriptblock]::Create($source.Substring($start,$end-$start)))
if(($authorizedPaths-join ',')-cne'installer-source/Build-Release.ps1,source/CHECKSUMS.sha256,source/app/z.py'){throw 'Native correction inventory is not unique and ordinal-sorted.'}
[ordered]@{status='PASS';realNativeConstruction=$true;buildInvoked=$false;runtime=$PSVersionTable.PSVersion.ToString()}|ConvertTo-Json
