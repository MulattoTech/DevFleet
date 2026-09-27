[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $WorkspaceRoot 'tools/Build-AIAuditBundle.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Native packager has parse errors.'}
foreach($name in @('Get-Hash','Add-CompactFile','Add-AstraCausalEvidence')){
 $definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name)
 if($definition.Count -ne 1){throw "Native packaging function is ambiguous: $name"}
 . ([scriptblock]::Create($definition[0].Extent.Text))
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-astra-package-'+[guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[object]]::new()
try {
 foreach($case in @('exact-copy','missing-source','hash-drift','source-traversal','destination-traversal','destination-collision','excluded-destination','missing-manifest','empty-manifest')){
  $root=Join-Path $testRoot $case;$destination=Join-Path $root 'evidence'
  $sourceRelative='audit/automation-harness/runs/e2e-astra-fixture/raw.json'
  $source=Join-Path $root $sourceRelative
  New-Item -ItemType Directory -Path (Split-Path -Parent $source),(Join-Path $root 'tools') -Force|Out-Null
  [IO.File]::WriteAllText($source,'{"status":"BLOCKED","proofCredit":0}',[Text.UTF8Encoding]::new($false))
  $row=[ordered]@{source=$sourceRelative;destination='e2e-astra-fixture/raw.json';sha256=Get-Hash $source}
  $manifest=[ordered]@{schemaVersion=1;records=@($row)}
  switch($case){
   'missing-source' {$row.source='audit/automation-harness/runs/e2e-astra-fixture/missing.json'}
   'hash-drift' {$row.sha256='0'*64}
   'source-traversal' {$row.source='audit/automation-harness/../raw.json'}
   'destination-traversal' {$row.destination='e2e-astra-fixture/../raw.json'}
   'destination-collision' {$manifest.records+=,$row}
   'excluded-destination' {$row.destination='e2e-astra-fixture/snapshots/raw.json'}
   'empty-manifest' {$manifest.records=@()}
  }
  $manifestPath=Join-Path $root 'tools/astra-causal-evidence.json'
  if($case -ne 'missing-manifest'){$manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM}
  $threw=$false;$count=0
  try{$count=Add-AstraCausalEvidence $root $destination}catch{$threw=$true}
  $pass=if($case -eq 'exact-copy'){-not $threw -and $count -eq 1 -and (Get-Hash (Join-Path $destination 'astra-causal/e2e-astra-fixture/raw.json')) -ceq $row.sha256 -and (Get-Hash (Join-Path $destination 'astra-causal/allowlist.json')) -ceq (Get-Hash $manifestPath)}else{$threw}
  $checks.Add([ordered]@{case=$case;pass=[bool]$pass})
 }
 # Exercise the complete frozen real allowlist through the same native function.
 $realDestination=Join-Path $testRoot 'real-evidence'
 $realCount=Add-AstraCausalEvidence $WorkspaceRoot $realDestination
 $checks.Add([ordered]@{case='real-causal-allowlist';pass=($realCount -gt 0);records=$realCount})
} finally {
 $resolved=[IO.Path]::GetFullPath($testRoot);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^devfleet-astra-package-[0-9a-f]{32}$'){throw 'Fixture cleanup escaped its exact temporary root.'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
$failed=@($checks|Where-Object{-not $_.pass})
[ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks);vmOperations=0}|ConvertTo-Json -Depth 6
if($failed.Count){exit 1}
