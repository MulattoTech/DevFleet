[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [switch]$LiveGuestAuth,
    [string]$FreshLedgerPath,
    [string]$FreshRunId,
    [int]$BootTimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
Set-Location -LiteralPath $WorkspaceRoot

# RDC shells can omit ordinary Windows environment variables. Normalize only
# this process; never persist a machine-wide environment change.
if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
    $env:COMPUTERNAME = [Environment]::MachineName
}
if ([string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
    ${env:ProgramFiles(x86)} = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
}

Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\Candidate.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\HostSafety.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\GuestSession.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\BaselineLineage.psm1') -Force

$expectedL1Name = 'DevFleet-E2E-Win11-01'
$expectedL1Id = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$expectedL2Name = 'DevFleet-E2E-Linux-01'
$candidatePath = Join-Path $WorkspaceRoot 'outputs\DevFleet-Setup-v1.2.13-win-x64.exe'
$fingerprint = Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath $candidatePath
$baseline = Get-DevFleetAcceptedBaseline -WorkspaceRoot $WorkspaceRoot -Fingerprint $fingerprint
$expectedCleanName = [string]$baseline.name
$expectedCleanId = [guid][string]$baseline.id
$standardPath = Join-Path $WorkspaceRoot 'evidence\CURRENT-STANDARD-TOKEN.json'
$standard = if (Test-Path -LiteralPath $standardPath -PathType Leaf) {
    Get-Content -LiteralPath $standardPath -Raw | ConvertFrom-Json
} else { $null }

$vm = Get-VM -ComputerName localhost -Id $expectedL1Id -ErrorAction Stop
$cleanRows = @(Get-VMSnapshot -ComputerName localhost -VMName $expectedL1Name -Name $expectedCleanName -ErrorAction Stop)
if($cleanRows.Count -ne 1){throw 'Accepted CLEAN checkpoint name is missing or ambiguous.'}
$clean = $cleanRows[0]
$hostSafety = Get-HostSafetySnapshot -Vm $vm
$credential = $null
# Static readiness inspects only the store's filesystem metadata. It must not
# deserialize the record or ask DPAPI to load the protected password.
$credentialPath = Join-Path $env:LOCALAPPDATA 'DevFleet\E2E\secrets.json'
$credentialStorePresent = $false
$credentialStoreError = $null
try {
    $credentialItem = Get-Item -LiteralPath $credentialPath -Force -ErrorAction Stop
    $credentialStorePresent = -not $credentialItem.PSIsContainer -and
        ($credentialItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
        $credentialItem.Length -gt 0
} catch {
    $credentialStoreError = 'CREDENTIAL_STORE_METADATA_UNAVAILABLE'
}

$tupleCurrent = $false
if ($standard) {
    $tupleCurrent =
        [string]$standard.repositoryHead -ceq [string]$fingerprint.repositoryHead -and
        [string]$standard.candidateBuildCommit -ceq [string]$fingerprint.gitCommit -and
        [string]$standard.shippingInputIdentity -ceq [string]$fingerprint.shippingInputIdentity -and
        [string]$standard.releaseFingerprintId -ceq [string]$fingerprint.releaseFingerprintId -and
        [string]$standard.toolingFingerprintId -ceq [string]$fingerprint.toolingFingerprintId -and
        [string]$standard.exe.sha256 -ceq [string]$fingerprint.candidate.sha256
}

$result = [ordered]@{
    schemaVersion = 1
    observedUtc = (Get-Date).ToUniversalTime().ToString('o')
    scope = if ($LiveGuestAuth) { 'READINESS_WITH_EXACT_CLEAN_GUEST_AUTH' } else { 'READ_ONLY_READINESS' }
    certificationCredit = $false
    tuple = [ordered]@{
        repositoryHead = [string]$fingerprint.repositoryHead
        candidateBuildCommit = [string]$fingerprint.gitCommit
        shippingInputIdentity = [string]$fingerprint.shippingInputIdentity
        releaseFingerprintId = [string]$fingerprint.releaseFingerprintId
        toolingFingerprintId = [string]$fingerprint.toolingFingerprintId
        candidateSha256 = [string]$fingerprint.candidate.sha256
    }
    standardToken = [ordered]@{
        present = [bool]$standard
        runId = if ($standard) { [string]$standard.runId } else { $null }
        status = if ($standard) { [string]$standard.status } else { 'MISSING' }
        standardNonAdministratorToken = if ($standard) { [bool]$standard.standardNonAdministratorToken } else { $false }
        tupleCurrent = [bool]$tupleCurrent
    }
    lab = [ordered]@{
        l1Name = [string]$vm.Name
        l1Id = $vm.Id.ToString()
        l1State = [string]$vm.State
        cleanName = [string]$clean.Name
        cleanId = $clean.Id.ToString()
        baselineReceiptSha256 = $baseline.receiptSha256
        predecessorCleanId = $baseline.predecessorId
        exactIdentity = ($vm.Name -ceq $expectedL1Name -and $vm.Id -eq $expectedL1Id -and $clean.Name -ceq $expectedCleanName -and $clean.Id -eq $expectedCleanId -and $clean.VMId -eq $expectedL1Id -and ($baseline.legacyOriginal -or $clean.ParentSnapshotId -eq [guid][string]$baseline.predecessorId))
        hostSafetyStartSafe = [bool]$hostSafety.startSafe
        availableMemoryGiB = $hostSafety.availableMemoryGiB
        projectedPostStartAvailableMemoryGiB = $hostSafety.projectedPostStartAvailableMemoryGiB
    }
    credential = [ordered]@{
        storePresent = [bool]$credentialStorePresent
        available = $false
        exactUser = $null
        error = $credentialStoreError
        secretPrinted = $false
    }
    liveGuestAuth = [ordered]@{
        requested = [bool]$LiveGuestAuth
        attempted = $false
        cleanRestored = $false
        connected = $false
        guestComputer = $null
        failureClass = $null
        failureMessage = $null
        nestedL2 = $null
        startGate = $null
        finalL1State = [string]$vm.State
    }
    blockers = [System.Collections.Generic.List[string]]::new()
    readyForProofReservation = $false
}

if (-not $result.lab.exactIdentity) { [void]$result.blockers.Add('EXACT_LAB_IDENTITY_MISMATCH') }
if ([string]$vm.State -cne 'Off') { [void]$result.blockers.Add('L1_NOT_OFF_AT_PREFLIGHT') }
if (-not [bool]$hostSafety.startSafe) { [void]$result.blockers.Add('HOST_SAFETY_NOT_START_SAFE') }
if (-not $standard) { [void]$result.blockers.Add('STANDARD_TOKEN_MISSING') }
elseif ([string]$standard.status -cne 'PASS' -or -not [bool]$standard.standardNonAdministratorToken) {
    [void]$result.blockers.Add('STANDARD_TOKEN_NOT_GENUINE_PASS')
} elseif (-not $tupleCurrent) { [void]$result.blockers.Add('STANDARD_TOKEN_STALE_TUPLE') }
if (-not $credentialStorePresent) { [void]$result.blockers.Add('E2E_CREDENTIAL_STORE_UNAVAILABLE') }
$staticPrerequisitesPass = ($result.blockers.Count -eq 0)

if ($LiveGuestAuth -and $staticPrerequisitesPass) {
    if (-not $FreshLedgerPath -or -not $FreshRunId) {
        [void]$result.blockers.Add('NATIVE_DIAGNOSTIC_ADMISSION_UNVERIFIED')
    } else {
        try {
            . (Join-Path $PSScriptRoot 'FreshAttemptAdmission.ps1')
            $admission = Get-FreshDiagnosticAdmission -LedgerPath $FreshLedgerPath -RunId $FreshRunId -WorkspaceRoot $WorkspaceRoot -ScriptPath $PSCommandPath
            $result.admission = [ordered]@{runId=$admission.runId;operation=$admission.operation;certificationCredit=$false}
        } catch {
            [void]$result.blockers.Add('FRESH_DIAGNOSTIC_ADMISSION_INVALID')
        }
    }
}

if ($LiveGuestAuth -and $result.blockers.Count -eq 0) {
    Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\Secrets.psm1') -Force
    try {
        $credential = Get-DevFleetE2ECredential
        $result.credential.available = ($null -ne $credential)
        $result.credential.exactUser = ([string]$credential.UserName -ceq 'E2EAdmin')
        if (-not $result.credential.exactUser) {
            [void]$result.blockers.Add('E2E_USERNAME_NOT_EXACT')
        }
    } catch {
        $result.credential.error = 'CREDENTIAL_LOAD_FAILED'
        [void]$result.blockers.Add('E2E_CREDENTIAL_UNAVAILABLE')
    }
}

$session = $null
if ($LiveGuestAuth -and $result.blockers.Count -eq 0) {
    try {
        $result.liveGuestAuth.attempted = $true
        Restore-VMSnapshot -VMSnapshot $clean -Confirm:$false -ErrorAction Stop
        $result.liveGuestAuth.cleanRestored = $true
        $startVm = Get-VM -ComputerName localhost -Id $expectedL1Id -ErrorAction Stop
        $startClean = @(Get-VMSnapshot -ComputerName localhost -VMName $expectedL1Name -Name $expectedCleanName -ErrorAction Stop)
        if ($startVm.Name -cne $expectedL1Name -or $startVm.Id -ne $expectedL1Id -or
            [string]$startVm.State -cne 'Off' -or $startClean.Count -ne 1 -or
            $startClean[0].Id -ne $expectedCleanId -or $startClean[0].VMId -ne $expectedL1Id -or
            (-not $baseline.legacyOriginal -and $startClean[0].ParentSnapshotId -ne [guid][string]$baseline.predecessorId)) {
            [void]$result.blockers.Add('EXACT_LAB_IDENTITY_OR_STATE_CHANGED_AFTER_RESTORE')
            throw 'Exact L1/CLEAN identity or L1 Off state changed after restore.'
        }
        $startSafety = Get-HostSafetySnapshot -Vm $startVm
        $result.liveGuestAuth.startGate = [ordered]@{
            observedUtc = (Get-Date).ToUniversalTime().ToString('o')
            l1Id = $startVm.Id.ToString()
            cleanId = $startClean[0].Id.ToString()
            l1State = [string]$startVm.State
            hostSafetyStartSafe = [bool]$startSafety.startSafe
            availableMemoryGiB = $startSafety.availableMemoryGiB
            projectedPostStartAvailableMemoryGiB = $startSafety.projectedPostStartAvailableMemoryGiB
        }
        if (-not [bool]$startSafety.startSafe) {
            [void]$result.blockers.Add('HOST_SAFETY_NOT_START_SAFE_AFTER_RESTORE')
            throw 'HostSafety is not start safe immediately before exact L1 start.'
        }
        Start-VM -VM $startVm -ErrorAction Stop | Out-Null
        $deadline = (Get-Date).AddSeconds([Math]::Max(30,$BootTimeoutSeconds))
        $heartbeatReady = $false
        do {
            Start-Sleep -Seconds 3
            $heartbeat = Get-VMIntegrationService -VMName $expectedL1Name -Name 'Heartbeat' -ErrorAction SilentlyContinue
            if ($heartbeat -and [string]$heartbeat.PrimaryStatusDescription -match 'OK|Operating normally') {
                $heartbeatReady = $true
                break
            }
        } while ((Get-Date) -lt $deadline)
        if (-not $heartbeatReady) { throw 'Exact CLEAN L1 heartbeat did not become healthy before the bounded deadline.' }
        Start-Sleep -Seconds 12

        $session = New-PSSession -VMId $expectedL1Id -Credential $credential -ErrorAction Stop
        $result.liveGuestAuth.connected = $true
        $guest = Invoke-Command -Session $session -ScriptBlock { $env:COMPUTERNAME }
        $result.liveGuestAuth.guestComputer = [string]$guest
        if ([string]$guest -cne 'DEVFLEET-E2E-01') { throw 'Authenticated session reached an unexpected guest computer.' }

        $nested = Get-DevFleetNestedL2State -Session $session -ExpectedName $expectedL2Name
        $result.liveGuestAuth.nestedL2 = [ordered]@{
            status = [string]$nested.status
            present = $nested.present
            verification = [string]$nested.verification
            exactMatchCount = $nested.exactMatchCount
            inventoryCount = $nested.inventoryCount
            observedUtc = [string]$nested.observedUtc
        }
        if ([string]$nested.status -eq 'UNVERIFIED') { [void]$result.blockers.Add('NESTED_L2_INVENTORY_UNVERIFIED') }
        elseif ([string]$nested.status -eq 'PRESENT') { [void]$result.blockers.Add('NESTED_L2_PRESENT_BEFORE_PROOF') }
        elseif ([string]$nested.status -cne 'ABSENT' -or $nested.present -isnot [bool] -or
            $nested.present -ne $false -or [string]$nested.expectedName -cne $expectedL2Name -or
            [int]$nested.exactMatchCount -ne 0 -or [string]::IsNullOrWhiteSpace([string]$nested.verification)) {
            [void]$result.blockers.Add('NESTED_L2_NOT_PROVEN_ABSENT_BEFORE_PROOF')
        }
    } catch {
        $result.liveGuestAuth.failureClass = $_.Exception.GetType().FullName
        $message = [string]$_.Exception.Message
        if ($message -match 'credential is invalid|user name or password|logon failure') {
            $result.liveGuestAuth.failureMessage = 'EXACT_CLEAN_GUEST_AUTH_REJECTED'
            [void]$result.blockers.Add('E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN')
        } elseif (-not $result.blockers.Contains('EXACT_LAB_IDENTITY_OR_STATE_CHANGED_AFTER_RESTORE') -and
            -not $result.blockers.Contains('HOST_SAFETY_NOT_START_SAFE_AFTER_RESTORE')) {
            $result.liveGuestAuth.failureMessage = 'EXACT_CLEAN_GUEST_SESSION_FAILED'
            [void]$result.blockers.Add('EXACT_CLEAN_GUEST_SESSION_FAILED')
        }
    } finally {
        if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        $live = Get-VM -ComputerName localhost -Id $expectedL1Id -ErrorAction SilentlyContinue
        if ($live -and [string]$live.State -ne 'Off') {
            Stop-VM -VM $live -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        $stopDeadline = (Get-Date).AddSeconds(45)
        do {
            $live = Get-VM -ComputerName localhost -Id $expectedL1Id -ErrorAction SilentlyContinue
            if ($live -and [string]$live.State -eq 'Off') { break }
            Start-Sleep -Seconds 1
        } while ((Get-Date) -lt $stopDeadline)
        $result.liveGuestAuth.finalL1State = if ($live) { [string]$live.State } else { 'UNAVAILABLE' }
        if ([string]$result.liveGuestAuth.finalL1State -cne 'Off') {
            [void]$result.blockers.Add('L1_NOT_OFF_AFTER_LIVE_PREFLIGHT')
        }
    }
} elseif ($LiveGuestAuth) {
    [void]$result.blockers.Add('LIVE_GUEST_AUTH_SKIPPED_DUE_TO_STATIC_BLOCKER')
}

$result.blockers = @($result.blockers | Select-Object -Unique)
$result.staticPrerequisitesPass = [bool]$staticPrerequisitesPass
$result.readyForProofReservation =
    [bool]$LiveGuestAuth -and
    $result.blockers.Count -eq 0 -and
    [bool]$result.liveGuestAuth.connected -and
    [string]$result.liveGuestAuth.nestedL2.status -ceq 'ABSENT' -and
    $result.liveGuestAuth.nestedL2.present -is [bool] -and
    $result.liveGuestAuth.nestedL2.present -eq $false
$result.status = if ($result.readyForProofReservation) {
    'PASS_READY_FOR_PROOF_RESERVATION'
} elseif (-not $LiveGuestAuth -and $result.staticPrerequisitesPass) {
    'PASS_STATIC_REQUIRES_LIVE_GUEST_AUTH'
} else {
    'BLOCKED'
}
$result | ConvertTo-Json -Depth 15
if ($LiveGuestAuth -and -not $result.readyForProofReservation) { exit 2 }
if (-not $LiveGuestAuth -and -not $result.staticPrerequisitesPass) { exit 2 }
