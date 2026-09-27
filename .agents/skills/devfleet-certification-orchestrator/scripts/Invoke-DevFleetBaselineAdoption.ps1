[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][string]$ProposalPath,
    [Parameter(Mandatory)][string]$ApprovalPath,
    [Parameter(Mandatory)][string]$AuthenticatedGuestEvidencePath,
    [Parameter(Mandatory)][string]$FreshLedgerPath
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)){$env:COMPUTERNAME=[Environment]::MachineName}
if([string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})){${env:ProgramFiles(x86)}=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)}
$WorkspaceRoot=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$expectedRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
if($WorkspaceRoot -ine $expectedRoot){throw 'WORKSPACE_IDENTITY_MISMATCH'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if([Environment]::MachineName -ine 'MULATTOTECHBOX' -or $identity.Name -cne 'MULATTOTECHBOX\Dylan' -or -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'ELEVATED_DYLAN_REQUIRED'}
foreach($path in @($ProposalPath,$ApprovalPath,$AuthenticatedGuestEvidencePath,$FreshLedgerPath)){
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 4MB){throw 'BASELINE_SOURCE_FILE_INVALID'}
}
$ledger=(Get-Content -LiteralPath $FreshLedgerPath -Raw|ConvertFrom-Json -ErrorAction Stop)
if([string]$ledger.policyId -cne 'DF-FRESH-CERTIFICATION-20260926-R2' -or $null -ne $ledger.activeRunId){throw 'R2_TERMINAL_LEDGER_REQUIRED'}
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\Candidate.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'tools\PythonRuntime.psm1') -Force
$fingerprint=Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath (Join-Path $WorkspaceRoot 'outputs\DevFleet-Setup-v1.2.13-win-x64.exe')
$tuple=[ordered]@{
    repositoryHead=[string]$fingerprint.repositoryHead
    candidateBuildCommit=[string]$fingerprint.gitCommit
    shippingInputIdentity=[string]$fingerprint.shippingInputIdentity
    releaseFingerprintId=[string]$fingerprint.releaseFingerprintId
    toolingFingerprintId=[string]$fingerprint.toolingFingerprintId
    candidateSha256=[string]$fingerprint.candidate.sha256
}
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$vm=Get-VM -ComputerName localhost -Id $vmId -ErrorAction Stop
if([string]$vm.Name -cne 'DevFleet-E2E-Win11-01' -or $vm.Id -ne $vmId -or [string]$vm.State -cne 'Off'){throw 'EXACT_L1_OFF_REQUIRED_FOR_BASELINE_ADOPTION'}
$snapshots=@(Get-VMSnapshot -VM $vm -ErrorAction Stop|ForEach-Object{
    [ordered]@{name=[string]$_.Name;id=$_.Id.ToString().ToLowerInvariant();vmId=$_.VMId.ToString().ToLowerInvariant();parentSnapshotId=if($_.ParentSnapshotId){$_.ParentSnapshotId.ToString().ToLowerInvariant()}else{$null}}
})
$live=[ordered]@{scope='NATIVE_EXACT_L1_CHECKPOINT_INVENTORY';observedUtc=[datetimeoffset]::UtcNow.ToString('o');vm=[ordered]@{name=[string]$vm.Name;id=$vm.Id.ToString().ToLowerInvariant();state=[string]$vm.State};snapshots=$snapshots}
$captureRoot=Join-Path $env:LOCALAPPDATA (Join-Path 'DevFleet\BaselineAdoption' ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Force -Path $captureRoot|Out-Null
$livePath=Join-Path $captureRoot 'native-checkpoint-inventory.json'
$tuplePath=Join-Path $captureRoot 'current-candidate-tuple.json'
[IO.File]::WriteAllText($livePath,(($live|ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($tuplePath,(($tuple|ConvertTo-Json -Depth 8)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
$python=Resolve-DevFleetPython -Workspace $WorkspaceRoot
$tool=Join-Path $WorkspaceRoot 'tools\baseline_lineage.py'
$out=@(& $python $tool adopt --root $WorkspaceRoot --proposal $ProposalPath --approval $ApprovalPath --auth $AuthenticatedGuestEvidencePath --live $livePath --tuple $tuplePath --ledger $FreshLedgerPath)
if($LASTEXITCODE -ne 0){throw 'NATIVE_BASELINE_ADOPTION_REJECTED'}
$out -join "`n"
