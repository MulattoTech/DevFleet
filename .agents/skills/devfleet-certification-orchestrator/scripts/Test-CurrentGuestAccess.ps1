[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$LedgerPath,[Parameter(Mandatory)][string]$RunId)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)){$env:COMPUTERNAME=[Environment]::MachineName}
if([string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})){${env:ProgramFiles(x86)}=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)}
$WorkspaceRoot=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$expectedRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
if($WorkspaceRoot -ine $expectedRoot){throw 'WORKSPACE_IDENTITY_MISMATCH'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if([Environment]::MachineName -ine 'MULATTOTECHBOX' -or $identity.Name -cne 'MULATTOTECHBOX\Dylan' -or -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'ELEVATED_DYLAN_REQUIRED'}
. (Join-Path $PSScriptRoot 'FreshAttemptAdmission.ps1')
$admission=Get-FreshDiagnosticAdmission -LedgerPath $LedgerPath -RunId $RunId -WorkspaceRoot $WorkspaceRoot -ScriptPath $PSCommandPath
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$vm=Get-VM -ComputerName localhost -Id $vmId -ErrorAction Stop
if($vm.Name -cne 'DevFleet-E2E-Win11-01' -or [string]$vm.State -cne 'Running'){throw 'EXACT_RUNNING_L1_REQUIRED'}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Candidate.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/BaselineLineage.psm1') -Force
$fingerprint=Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath (Join-Path $WorkspaceRoot 'outputs/DevFleet-Setup-v1.2.13-win-x64.exe')
$baseline=Get-DevFleetAcceptedBaseline -WorkspaceRoot $WorkspaceRoot -Fingerprint $fingerprint
$clean=@(Get-VMSnapshot -VM $vm -Name ([string]$baseline.name) -ErrorAction Stop)
if($clean.Count -ne 1 -or $clean[0].Id -ne [guid][string]$baseline.id -or $clean[0].VMId -ne $vmId -or (-not $baseline.legacyOriginal -and $clean[0].ParentSnapshotId -ne [guid][string]$baseline.predecessorId)){throw 'ACCEPTED_CLEAN_IDENTITY_MISMATCH'}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/GuestSession.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Secrets.psm1') -Global -Force
$result=[ordered]@{runId=$RunId;observedUtc=[datetimeoffset]::UtcNow.ToString('o');scope='CURRENT_RUNNING_GUEST_READ_ONLY';certificationCredit=$false;vmMutationPerformed=$false;connected=$false;guest=$null;credential=$null;nestedL2=$null;status='BLOCKED';failureClass=$null;lastStage='credential-load';exceptionType=$null;errorId=$null}
# Keep entry and completed observation distinct; inventories are collected after entry.
$result['startedUtc']=$result.observedUtc
$result['vm']=[ordered]@{name=[string]$vm.Name;id=$vm.Id.ToString().ToLowerInvariant()}
$result['candidate']=[ordered]@{
 repositoryHead=[string]$fingerprint.repositoryHead;candidateBuildCommit=[string]$fingerprint.gitCommit
 shippingInputIdentity=[string]$fingerprint.shippingInputIdentity;releaseFingerprintId=[string]$fingerprint.releaseFingerprintId
 toolingFingerprintId=[string]$fingerprint.toolingFingerprintId;candidateSha256=[string]$fingerprint.candidate.sha256
}
$session=$null
try {
 $credential=Secrets\Get-DevFleetE2ECredential
 if($credential.UserName -cne 'E2EAdmin'){throw 'E2E_USERNAME_NOT_EXACT'}
 $storeItem=Get-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'DevFleet\E2E\secrets.json') -Force -ErrorAction Stop
 if($storeItem.PSIsContainer -or ($storeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'E2E_CREDENTIAL_STORE_METADATA_INVALID'}
 $result.credential=[ordered]@{storeUser='E2EAdmin';protectedStoreUpdatedUtc=$storeItem.LastWriteTimeUtc.ToString('o');secretValuesRecorded=$false}
 $result.lastStage='session-open'
 $session=New-PSSession -VMId $vmId -Credential $credential -ErrorAction Stop
 $result.connected=$true
 $result.lastStage='guest-identity-inventory'
 $guest=Invoke-Command -Session $session -ScriptBlock {
  $account=Get-LocalUser -Name E2EAdmin -ErrorAction Stop
  [pscustomobject]@{computerName=$env:COMPUTERNAME;principal=[Security.Principal.WindowsIdentity]::GetCurrent().Name;accountEnabled=$account.Enabled;passwordLastSetUtc=if($account.PasswordLastSet){$account.PasswordLastSet.ToUniversalTime().ToString('o')}else{$null};passwordExpiresUtc=if($account.PasswordExpires){$account.PasswordExpires.ToUniversalTime().ToString('o')}else{$null};lastBootUtc=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o');productProcesses=@(Get-Process | Where-Object {$_.Name -match 'DevFleet|msiexec'} | Select-Object Id,Name);runningDevFleetTasks=@(Get-ScheduledTask | Where-Object {$_.TaskName -like '*DevFleet*' -and $_.State -eq 'Running'} | Select-Object TaskName,State)}
 }
 if($guest.computerName -cne 'DEVFLEET-E2E-01'){throw 'AUTHENTICATED_GUEST_IDENTITY_MISMATCH'}
 $result.guest=$guest
 $result.lastStage='nested-inventory'
 $nested=Get-DevFleetNestedL2State -Session $session -ExpectedName 'DevFleet-E2E-Linux-01'
 $result.nestedL2=[ordered]@{status=[string]$nested.status;present=$nested.present;expectedName=[string]$nested.expectedName;verification=[string]$nested.verification;observedUtc=[string]$nested.observedUtc;exactMatchCount=$nested.exactMatchCount;backendInventories=@($nested.backendInventories)}
 $result.status='AUTHENTICATED_CURRENT_GUEST_NOT_CLEAN_PROOF'
} catch {
 $result.exceptionType=$_.Exception.GetType().FullName
 $result.errorId=$_.FullyQualifiedErrorId
 $message=[string]$_.Exception.Message
 $result.failureClass=if($message -match 'credential is invalid|user name or password|logon failure'){'CURRENT_GUEST_AUTH_REJECTED'}elseif($message -match 'IDENTITY_MISMATCH|USERNAME_NOT_EXACT'){'IDENTITY_MISMATCH'}else{'CURRENT_GUEST_INSPECTION_FAILED'}
} finally {
 if($session){Remove-PSSession -Session $session -ErrorAction SilentlyContinue}
 $credential=$null
 # Timestamp the completed collection, including failure/cleanup, not its entry.
 $result.observedUtc=[datetimeoffset]::UtcNow.ToString('o')
}
$result|ConvertTo-Json -Depth 8
if($result.status -eq 'BLOCKED'){exit 2}
