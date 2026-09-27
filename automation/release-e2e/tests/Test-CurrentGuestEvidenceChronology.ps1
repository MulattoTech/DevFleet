[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
# Exercise the unchanged production evidence-building body, replacing only OS/guest I/O.
# Host identity/admission checks are covered elsewhere; this is never lab admission.
$workspace=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$path=Join-Path $workspace '.agents/skills/devfleet-certification-orchestrator/scripts/Test-CurrentGuestAccess.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Production collector parse failure'}
$statements=@($ast.EndBlock.Statements)
$start=@($statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -ceq '$result'})[0]
$finish=@($statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[-1]
if(-not $start -or -not $finish){throw 'Production evidence-body boundary missing'}
$body=[scriptblock]::Create(($statements|Where-Object {$_.Extent.StartOffset -ge $start.Extent.StartOffset -and $_.Extent.EndOffset -le $finish.Extent.EndOffset}|ForEach-Object {$_.Extent.Text}) -join "`n")
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-guest-evidence-'+[guid]::NewGuid().ToString('N'))
$oldAppData=$env:LOCALAPPDATA
$passes=0
function Assert-That([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:passes++}
try {
 New-Item -ItemType Directory -Path (Join-Path $fixture 'DevFleet/E2E') -Force|Out-Null
 $env:LOCALAPPDATA=$fixture
 [IO.File]::WriteAllText((Join-Path $fixture 'DevFleet/E2E/secrets.json'),'TEST METADATA ONLY - NOT A CREDENTIAL')
 $mockSecrets=New-Module -Name Secrets -ScriptBlock {function Get-DevFleetE2ECredential {[pscustomobject]@{UserName='E2EAdmin'}};Export-ModuleMember -Function Get-DevFleetE2ECredential}
 Import-Module $mockSecrets -Force
 $RunId='r2-fixture-chronology';$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
 $vm=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=$vmId}
 $fingerprint=[pscustomobject]@{repositoryHead=('1'*40);gitCommit=('2'*40);shippingInputIdentity=('3'*64);releaseFingerprintId=('4'*64);toolingFingerprintId=('5'*64);candidate=[pscustomobject]@{sha256=('6'*64)}}
 $script:removed=0;$script:failOpen=$false
 function New-PSSession {param($VMId,$Credential,$ErrorAction) if($script:failOpen){throw 'Synthetic guest transport failure'};[pscustomobject]@{InstanceId='fixture'}}
 function Remove-PSSession {param($Session,$ErrorAction) $script:removed++}
 function Invoke-Command {param($Session,$ScriptBlock) [pscustomobject]@{computerName='DEVFLEET-E2E-01';principal='DEVFLEET-E2E-01\E2EAdmin';accountEnabled=$true;passwordLastSetUtc=[datetimeoffset]::UtcNow.AddMinutes(-20).ToString('o');passwordExpiresUtc=[datetimeoffset]::UtcNow.AddDays(30).ToString('o')}}
 function Get-DevFleetNestedL2State {param($Session,$ExpectedName)
  Start-Sleep -Milliseconds 30
  [pscustomobject]@{status='ABSENT';present=$false;expectedName=$ExpectedName;verification='SYNTHETIC TEST ONLY';observedUtc=[datetimeoffset]::UtcNow.ToString('o');exactMatchCount=0;backendInventories=@([pscustomobject]@{provider='Hyper-V';status='PASS';names=@();verification='SYNTHETIC'},[pscustomobject]@{provider='VirtualBox';status='PASS';names=@();verification='SYNTHETIC'})}
 }
 . $body
 Assert-That ($result.status -ceq 'AUTHENTICATED_CURRENT_GUEST_NOT_CLEAN_PROOF') 'Fixture failed before chronology assertion'
 if($OutputPath){[IO.File]::WriteAllText($OutputPath,($result|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
 Assert-That ([datetimeoffset]$result.observedUtc -ge [datetimeoffset]$result.nestedL2.observedUtc) 'Report observedUtc precedes collected nested inventory: adoption will reject it'
 Assert-That ($script:removed -eq 1) 'Collector did not close its fixture session'
 Assert-That ($result.certificationCredit -eq $false -and $result.vmMutationPerformed -eq $false) 'Diagnostic claimed certification/mutation'
 $script:failOpen=$true
 . $body
 Assert-That ($result.status -ceq 'BLOCKED' -and -not $result.connected) 'Transport failure did not stay blocked'
 Assert-That ($null -eq $result.nestedL2 -and $null -eq $result.guest) 'Failure invented guest evidence'
 Assert-That (-not [string]::IsNullOrWhiteSpace($result.observedUtc)) 'Failure lost observation timestamp'
 Assert-That ($script:removed -eq 1) 'Failure tried to close a nonexistent session'
 [pscustomobject]@{status='PASS';assertions=$passes;vmOperations=0;realCredentialReads=0;scope='PRODUCTION_EVIDENCE_BODY_WITH_MOCKED_OS_IO'}|ConvertTo-Json -Compress
} finally {
 $env:LOCALAPPDATA=$oldAppData
 if($mockSecrets){Remove-Module $mockSecrets -ErrorAction SilentlyContinue}
 Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
