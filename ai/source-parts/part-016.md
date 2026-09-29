# DevFleet source part 016

Full-source UTF-8 byte interval [697500, 744000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 54460392e4dbe4535a811d9cfd24ba31c7328519412ec199f75c4d19277c3d5d

<!-- BEGIN SOURCE SLICE -->
-and $configured.PSObject.Properties['OperationMaximumsSeconds']) {
        foreach ($property in $configured.OperationMaximumsSeconds.PSObject.Properties) {
            $key = [string]$property.Name
            if ($operation.Contains($key) -and $key -ne 'guestBootstrap') { $operation[$key] = [int]$property.Value }
            elseif ($key -eq 'guestBootstrap' -and [int]$property.Value -ne $derivedGuestBootstrap) { throw "guestBootstrap must equal the sum of GuestBootstrapComponentsSeconds ($derivedGuestBootstrap); refusing an un-derived timeout override." }
        }
    }
    $derivedPrerequisites = (6 * ([int]$operation.dependencyProbe + [int]$operation.dependencyHealth + [int]$operation.dependencyInstall + [int]$operation.dependencyVerification)) + [int]$operation.windowsCapability + [int]$operation.windowsFeature + (4 * [int]$operation.multipassConfiguration) + (3 * [int]$operation.vscodeExtension)
    if ($configured -and $configured.OperationMaximumsSeconds -and $configured.OperationMaximumsSeconds.PSObject.Properties['prerequisites'] -and [int]$configured.OperationMaximumsSeconds.prerequisites -ne $derivedPrerequisites) { throw "prerequisites must equal the sum of its finite operation maxima ($derivedPrerequisites); refusing an un-derived timeout override." }
    $operation.prerequisites = $derivedPrerequisites
    foreach ($entry in $operation.GetEnumerator()) {
        if ([int]$entry.Value -le 0) { throw "Deadline policy operation maximum '$($entry.Key)' must be positive." }
    }

    $stage = [ordered]@{
        compute = [int]$operation.multipassLaunch + [int]$operation.multipassReadiness + [int]$operation.payloadTransfer + [int]$operation.guestBootstrap + [int]$operation.sshAndMarker
        vault = [int]$operation.vaultSnapshot + [int]$operation.multipassLaunch + [int]$operation.multipassReadiness + [int]$operation.payloadTransfer + [int]$operation.vaultBootstrap + [int]$operation.sshAndMarker
    }
    $desktop = [int]$operation.bootstrap + [int]$operation.preflight + [int]$operation.prerequisites + [int]$operation.windowsTailscale + [int]$operation.hostAgent + $stage.compute + [int]$operation.tailscale + [int]$operation.shortcuts + [int]$operation.export + [int]$operation.verification
    $laptop = [int]$operation.bootstrap + [int]$operation.preflight + [int]$operation.prerequisites + [int]$operation.windowsTailscale + [int]$operation.hostAgent + $stage.compute + $stage.vault + ([int]$operation.tailscale * 2) + [int]$operation.vaultClient + [int]$operation.shortcuts + [int]$operation.export + [int]$operation.verification
    $transactionMargin = 600
    $observerMargin = 600
    $fullReleaseMargin = 600
    $exactProofMargin = 600
    $maxRebootBoundaries = 3
    $observerNoProgress = 1800
    if ($configured) {
        foreach ($name in @('TransactionTerminalizationMarginSeconds','ObserverTerminalizationMarginSeconds','FullReleaseTerminalizationMarginSeconds','ExactProofTerminalizationMarginSeconds','MaxRebootBoundaries','ObserverNoProgressBudgetSeconds')) {
            if ($configured.PSObject.Properties[$name]) {
                $value = [int]$configured.$name
                if ($value -le 0 -and $name -ne 'MaxRebootBoundaries') { throw "Deadline policy '$name' must be positive." }
                if ($name -eq 'TransactionTerminalizationMarginSeconds') { $transactionMargin = $value }
                elseif ($name -eq 'ObserverTerminalizationMarginSeconds') { $observerMargin = $value }
                elseif ($name -eq 'FullReleaseTerminalizationMarginSeconds') { $fullReleaseMargin = $value }
                elseif ($name -eq 'ExactProofTerminalizationMarginSeconds') { $exactProofMargin = $value }
                elseif ($name -eq 'MaxRebootBoundaries') { $maxRebootBoundaries = $value }
                elseif ($name -eq 'ObserverNoProgressBudgetSeconds') { $observerNoProgress = $value }
            }
        }
    }
    if ($maxRebootBoundaries -lt 1) { throw 'Deadline policy must permit at least one bounded reboot boundary.' }
    $transaction = [ordered]@{ Desktop = $desktop + $transactionMargin; Laptop = $laptop + $transactionMargin }
    $observerAbsoluteByRole = [ordered]@{
        Desktop = [int]$transaction.Desktop + $observerMargin
        Laptop = [int]$transaction.Laptop + $observerMargin
    }
    # Keep legacy scalar consumers conservative: the scalar is the largest
    # role budget, while lifecycle callers select the exact role value.
    $productTransaction = [int]($transaction.Values | Measure-Object -Maximum).Maximum
    $observerAbsolute = [int]($observerAbsoluteByRole.Values | Measure-Object -Maximum).Maximum
    $wpfAction = 600
    $rebootBoundary = 420
    $servicingSettlement = 180
    $interactiveDesktop = 300
    $checkpointPolling = 900
    $lifecycleInner = $wpfAction + (($maxRebootBoundaries + 1) * $observerAbsolute) + ($maxRebootBoundaries * ($wpfAction + $rebootBoundary + $servicingSettlement + $interactiveDesktop)) + $checkpointPolling + $transactionMargin
    $fullReleaseInner = $lifecycleInner
    $fullReleaseWatchdog = $fullReleaseInner + $fullReleaseMargin
    $exactProofInner = 300 + $fullReleaseInner
    $exactProofOuter = $exactProofInner + $exactProofMargin
    $maximumOuter = 90000
    if ($configured -and $configured.PSObject.Properties['MaximumExactProofOuterWatchdogSeconds']) { $maximumOuter = [int]$configured.MaximumExactProofOuterWatchdogSeconds }
    $policy = [pscustomobject][ordered]@{
        version = $script:DeadlinePolicyVersion
        operationMaximumsSeconds = [pscustomobject]$operation
        guestBootstrapComponentsSeconds = [pscustomobject]$guestBootstrapComponents
        stageBudgetsSeconds = [pscustomobject]$stage
        transactionBudgetsSeconds = [pscustomobject]$transaction
        transactionTerminalizationMarginSeconds = $transactionMargin
        observerTerminalizationMarginSeconds = $observerMargin
        fullReleaseTerminalizationMarginSeconds = $fullReleaseMargin
        exactProofTerminalizationMarginSeconds = $exactProofMargin
        observerNoProgressBudgetSeconds = $observerNoProgress
        observerAbsoluteBudgetSeconds = $observerAbsolute
        observerAbsoluteBudgetsSeconds = [pscustomobject]$observerAbsoluteByRole
        productTransactionAbsoluteBudgetSeconds = $productTransaction
        productLifecycleInnerBoundSeconds = $lifecycleInner
        fullReleaseInnerBoundSeconds = $fullReleaseInner
        fullReleaseWatchdogSeconds = $fullReleaseWatchdog
        exactProofInnerBoundSeconds = $exactProofInner
        exactProofOuterWatchdogSeconds = $exactProofOuter
        maximumExactProofOuterWatchdogSeconds = $maximumOuter
        maxRebootBoundaries = $maxRebootBoundaries
        inequalities = [ordered]@{
            stageDominatesOperations = ([int]$stage.compute -gt ([int]$operation.guestBootstrap + [int]$operation.sshAndMarker))
            stageDominatesComputeOperations = ([int]$stage.compute -gt ([int]$operation.guestBootstrap + [int]$operation.sshAndMarker))
            stageDominatesVaultOperations = ([int]$stage.vault -gt ([int]$operation.vaultBootstrap + [int]$operation.sshAndMarker))
            observerDominatesDesktopTransaction = ([int]$observerAbsoluteByRole.Desktop -gt [int]$transaction.Desktop)
            observerDominatesLaptopTransaction = ([int]$observerAbsoluteByRole.Laptop -gt [int]$transaction.Laptop)
            observerDominatesTransaction = (($observerAbsoluteByRole.Values | Where-Object { $_ -gt 0 }).Count -eq 2 -and [int]$observerAbsoluteByRole.Desktop -gt [int]$transaction.Desktop -and [int]$observerAbsoluteByRole.Laptop -gt [int]$transaction.Laptop)
            fullReleaseDominatesObserver = ($fullReleaseWatchdog -gt $observerAbsolute)
            exactProofDominatesInner = ($exactProofOuter -gt $exactProofInner)
        }
    }
    Assert-HarnessBudgetPolicy -Policy $policy | Out-Null
    return $policy
}

function Assert-HarnessBudgetPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Policy)
    foreach ($name in @('productTransactionAbsoluteBudgetSeconds','observerAbsoluteBudgetSeconds','fullReleaseWatchdogSeconds','exactProofInnerBoundSeconds','exactProofOuterWatchdogSeconds')) {
        if (-not $Policy.PSObject.Properties[$name] -or [int]$Policy.$name -le 0) { throw "Deadline policy is missing a finite positive '$name'." }
    }
    foreach ($role in @('Desktop','Laptop')) {
        if (-not $Policy.observerAbsoluteBudgetsSeconds.PSObject.Properties[$role]) { throw "Deadline policy is missing observer absolute budget for $role." }
        if ([int]$Policy.observerAbsoluteBudgetsSeconds.$role -le [int]$Policy.transactionBudgetsSeconds.$role) { throw "Invalid deadline hierarchy: observer absolute must strictly exceed $role transaction." }
    }
    if ([int]$Policy.observerAbsoluteBudgetSeconds -lt [int]$Policy.observerAbsoluteBudgetsSeconds.Laptop) { throw 'Legacy observer absolute scalar must conservatively cover Laptop.' }
    if ([int]$Policy.fullReleaseWatchdogSeconds -le [int]$Policy.observerAbsoluteBudgetSeconds) { throw 'Invalid deadline hierarchy: FullRelease watchdog must strictly exceed observer absolute.' }
    if ([int]$Policy.exactProofOuterWatchdogSeconds -le [int]$Policy.exactProofInnerBoundSeconds) { throw 'Invalid deadline hierarchy: exact-proof outer watchdog must strictly exceed its calculated inner bound.' }
    if ([int]$Policy.exactProofOuterWatchdogSeconds -gt [int]$Policy.maximumExactProofOuterWatchdogSeconds) { throw "Deadline policy requires exact-proof outer watchdog $($Policy.exactProofOuterWatchdogSeconds)s, exceeding configured maximum $($Policy.maximumExactProofOuterWatchdogSeconds)s; refusing to truncate." }
    return $true
}

function Get-DeadlineRemainingSeconds {
    param([Parameter(Mandatory)][datetime]$DeadlineUtc, [datetime]$NowUtc = ([datetime]::UtcNow))
    [int][math]::Floor(($DeadlineUtc.ToUniversalTime() - $NowUtc.ToUniversalTime()).TotalSeconds)
}

function Get-EffectiveDeadlineTimeoutSeconds {
    param([Parameter(Mandatory)][int]$OperationMaximumSeconds, [Parameter(Mandatory)][datetime]$DeadlineUtc, [datetime]$NowUtc = ([datetime]::UtcNow))
    if ($OperationMaximumSeconds -le 0) { throw 'Operation maximum must be positive.' }
    $remaining = Get-DeadlineRemainingSeconds -DeadlineUtc $DeadlineUtc -NowUtc $NowUtc
    if ($remaining -le 0) { throw 'Owning deadline has expired; refusing to start another child operation.' }
    [math]::Min($OperationMaximumSeconds, $remaining)
}

Export-ModuleMember -Function Get-HarnessBudgetPolicy,Assert-HarnessBudgetPolicy,Get-DeadlineRemainingSeconds,Get-EffectiveDeadlineTimeoutSeconds

```


## FILE: automation/release-e2e/modules/HostSafety.psm1

SHA256: 9dcbac957f5aa060f0441eb8d372e39a190aab54cbf9af718a05368e567cb6c1 | Bytes: 8910 | Git mode: 100644

```
Set-StrictMode -Version Latest

function Get-DisposableVm {
    param([string]$VmName,[string]$Pattern = 'DevFleet-E2E-*')
    if ($VmName) { $vms = @(Get-VM -Name $VmName -ErrorAction Stop) } else { $vms = @(Get-VM | Where-Object { $_.Name -like $Pattern }) }
    if ($vms.Count -eq 0) { throw 'No ownership-scoped disposable DevFleet-E2E VM was found.' }
    if ($vms.Count -gt 1 -and -not $VmName) { throw "Disposable VM discovery is ambiguous: $($vms.Name -join ', ')." }
    $vm = $vms[0]
    if ($vm.Name -notlike 'DevFleet-E2E-*') { throw "Refusing non-disposable VM target: $($vm.Name)" }
    $vm
}

function Get-ProjectedHostMemorySafety {
    param(
        [Parameter(Mandatory)][double]$AvailableMemoryGiB,
        [Parameter(Mandatory)][double]$ExpectedVmStartCostGiB,
        [double]$MinimumPostStartMemoryGiB = -1,
        [double]$InstalledUsableMemoryGiB = 64,
        [double]$CommitLimitGiB = 64,
        [double]$CommittedGiB = 0,
        [bool]$ResourceExhaustion = $false,
        [bool]$VmAlreadyRunning = $false
    )
    if ($AvailableMemoryGiB -lt 0 -or $ExpectedVmStartCostGiB -lt 0 -or $InstalledUsableMemoryGiB -lt 0 -or $CommitLimitGiB -lt 0 -or $CommittedGiB -lt 0) {
        throw 'Host memory safety values must be non-negative.'
    }
    $physicalFloorGiB = [math]::Max(8.0, $InstalledUsableMemoryGiB * 0.10)
    $commitFloorGiB = [math]::Max(16.0, $CommitLimitGiB * 0.20)
    $effectiveStartCostGiB = if ($VmAlreadyRunning) { 0.0 } else { $ExpectedVmStartCostGiB }
    $projectedPostStartGiB = [math]::Round($AvailableMemoryGiB - $effectiveStartCostGiB, 2)
    $projectedCommitHeadroomGiB = [math]::Round($CommitLimitGiB - $CommittedGiB - $effectiveStartCostGiB, 2)
    $commitUsagePercent = if ($CommitLimitGiB -gt 0) { [math]::Round(($CommittedGiB / $CommitLimitGiB) * 100, 2) } else { 100 }
    [pscustomobject]@{
        policyVersion = '1.0.0'
        expectedVmStartCostGiB = [math]::Round($effectiveStartCostGiB, 2)
        projectedPostStartAvailableMemoryGiB = $projectedPostStartGiB
        physicalFloorGiB = [math]::Round($physicalFloorGiB, 2)
        commitHeadroomFloorGiB = [math]::Round($commitFloorGiB, 2)
        projectedCommitHeadroomGiB = $projectedCommitHeadroomGiB
        currentCommitUsagePercent = $commitUsagePercent
        resourceExhaustion = $ResourceExhaustion
        pagingPressureTelemetryOnly = $true
        startSafe = ($projectedPostStartGiB -ge $physicalFloorGiB -and $projectedCommitHeadroomGiB -ge $commitFloorGiB -and $commitUsagePercent -lt 80 -and -not $ResourceExhaustion)
    }
}

function Get-HostSafetySnapshot {
    param(
        [Parameter(Mandatory)][psobject]$Vm,
        [double]$MinimumAvailableMemoryGiB = -1,
        [double]$ExpectedVmStartCostGiB = -1
    )
    $os = Get-CimInstance Win32_OperatingSystem
    $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
    $processor = Get-VMProcessor -VMName $Vm.Name
    $adapter = Get-VMNetworkAdapter -VMName $Vm.Name
    $availableMemoryGiB = [math]::Round([double]$memory.AvailableBytes / 1GB, 2)
    $totalMemoryGiB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $commitLimitGiB = [math]::Round([double]$memory.CommitLimit / 1GB, 2)
    $committedGiB = [math]::Round([double]$memory.CommittedBytes / 1GB, 2)
    if ($ExpectedVmStartCostGiB -lt 0) {
        $ExpectedVmStartCostGiB = [math]::Round([double]$Vm.MemoryStartup / 1GB, 2)
    }
    $resourceExhaustion = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Resource-Exhaustion-Detector'; StartTime=(Get-Date).AddMinutes(-10)} -ErrorAction SilentlyContinue).Count -gt 0
    $memorySafety = Get-ProjectedHostMemorySafety -AvailableMemoryGiB $availableMemoryGiB -ExpectedVmStartCostGiB $ExpectedVmStartCostGiB -InstalledUsableMemoryGiB $totalMemoryGiB -CommitLimitGiB $commitLimitGiB -CommittedGiB $committedGiB -ResourceExhaustion $resourceExhaustion -VmAlreadyRunning ($Vm.State.ToString() -eq 'Running')
    $production = @(Get-VM | Where-Object { $_.Name -in @('devfleet-primary','devfleet-project-m-techlabs-job-finder','MulattoTechSurface','MULATTOTECHBOX') } | ForEach-Object {
        [pscustomobject]@{ name=$_.Name; id=$_.Id.ToString(); state=$_.State.ToString(); memoryStartupBytes=[int64]$_.MemoryStartup }
    })
    [pscustomobject]@{
        host = $env:COMPUTERNAME
         availableMemoryGiB = $availableMemoryGiB
         availableBytes = [int64]$memory.AvailableBytes
         totalMemoryGiB = $totalMemoryGiB
         commitLimitGiB = $commitLimitGiB
         committedGiB = $committedGiB
         currentCommitUsagePercent = $memorySafety.currentCommitUsagePercent
         physicalFloorGiB = $memorySafety.physicalFloorGiB
         commitHeadroomFloorGiB = $memorySafety.commitHeadroomFloorGiB
         minimumPreferredGiB = $memorySafety.physicalFloorGiB
        expectedVmStartCostGiB = $memorySafety.expectedVmStartCostGiB
        projectedPostStartAvailableMemoryGiB = $memorySafety.projectedPostStartAvailableMemoryGiB
        minimumPostStartMemoryGiB = $memorySafety.physicalFloorGiB
        vm = [pscustomobject]@{
            name=$Vm.Name; id=$Vm.Id.ToString(); state=$Vm.State.ToString(); memoryStartupBytes=[int64]$Vm.MemoryStartup
            dynamicMemory=[bool]$Vm.DynamicMemoryEnabled; nestedVirtualization=[bool]$processor.ExposeVirtualizationExtensions
            macAddressSpoofing=$adapter.MacAddressSpoofing.ToString()
        }
        productionReadOnly=$production
         resourceExhaustion = $resourceExhaustion
         paging = [pscustomobject]@{ pagesPerSec=[double]$memory.PagesPerSec; pageReadsPerSec=[double]$memory.PageReadsPerSec; blockingGate=$false }
         startSafe = $memorySafety.startSafe
    }
}

function Assert-DisposableOwnership {
    param([Parameter(Mandatory)][psobject]$Vm,[string]$ExpectedId)
    if ($Vm.Name -notlike 'DevFleet-E2E-*') { throw "Ownership check failed for $($Vm.Name)." }
    if ($ExpectedId -and $Vm.Id.ToString() -ne $ExpectedId) { throw "VM identity mismatch: expected $ExpectedId, got $($Vm.Id)." }
    $true
}

function Confirm-PostStartHostMemorySafety {
    param(
        [Parameter(Mandatory)][psobject]$InitialSnapshot,
        [int]$SampleSeconds = 60,
        [int]$IntervalSeconds = 5
    )
    $samples = [System.Collections.Generic.List[object]]::new()
    $count = [math]::Max(1, [math]::Ceiling($SampleSeconds / [math]::Max(1, $IntervalSeconds)))
    for ($i = 0; $i -lt $count; $i++) {
        $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
        $available = [math]::Round([double]$memory.AvailableBytes / 1GB, 2)
        $commitLimit = [math]::Round([double]$memory.CommitLimit / 1GB, 2)
        $committed = [math]::Round([double]$memory.CommittedBytes / 1GB, 2)
        $samples.Add([pscustomobject]@{ availableMemoryGiB=$available; commitLimitGiB=$commitLimit; committedGiB=$committed; commitUsagePercent=if($commitLimit -gt 0){[math]::Round($committed/$commitLimit*100,2)}else{100}; sampledAt=(Get-Date).ToUniversalTime().ToString('o') })
        if ($i -lt ($count - 1)) { Start-Sleep -Seconds ([math]::Max(1, $IntervalSeconds)) }
    }
    $floor = [double]$InitialSnapshot.physicalFloorGiB
    $commitFloor = [double]$InitialSnapshot.commitHeadroomFloorGiB
    $safe = @($samples | Where-Object { $_.availableMemoryGiB -lt $floor -or $_.commitUsagePercent -ge 80 -or ($_.commitLimitGiB - $_.committedGiB) -lt $commitFloor }).Count -eq 0
    [pscustomobject]@{ status=if($safe){'PASS'}else{'BLOCKED'}; sampleSeconds=$SampleSeconds; samples=$samples; physicalFloorGiB=$floor; commitHeadroomFloorGiB=$commitFloor; postStartSafe=$safe; resourceExhaustion=$false }
}

function Apply-RamPressureOverride {
    param([Parameter(Mandatory)][psobject]$Snapshot,[switch]$AllowRamPressure)
    $raw = [bool]$Snapshot.startSafe
    $resourceExhaustion = [bool]$Snapshot.resourceExhaustion
    $ramOnlyFailure = (-not $raw) -and (-not $resourceExhaustion)
    $authorized = [bool]$AllowRamPressure -and $ramOnlyFailure
    $Snapshot | Add-Member -NotePropertyName rawHostSafetyStartSafe -NotePropertyValue $raw -Force
    $Snapshot | Add-Member -NotePropertyName ramPressureOverrideAuthorized -NotePropertyValue $authorized -Force
    $Snapshot | Add-Member -NotePropertyName ramPressureOverrideScope -NotePropertyValue 'THIS OVERNIGHT DISPOSABLE E2E RUN ONLY' -Force
    $Snapshot | Add-Member -NotePropertyName nonRamSafetyPassed -NotePropertyValue (-not $resourceExhaustion) -Force
    $Snapshot | Add-Member -NotePropertyName effectiveE2EStartAuthorized -NotePropertyValue ($raw -or $authorized) -Force
    $Snapshot | Add-Member -NotePropertyName effectiveStartSafe -NotePropertyValue ($raw -or $authorized) -Force
    $Snapshot
}

Export-ModuleMember -Function Get-DisposableVm,Get-ProjectedHostMemorySafety,Get-HostSafetySnapshot,Confirm-PostStartHostMemorySafety,Apply-RamPressureOverride,Assert-DisposableOwnership

```


## FILE: automation/release-e2e/modules/InteractiveLogon.psm1

SHA256: 0d845ac096e13d8bd1f8c7020f6c5d6de17bc3a19d514ba6c1e89dbc30318591 | Bytes: 71931 | Git mode: 100644

```
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Secrets.psm1') -Force

$script:DevFleetE2EL1Name = 'DevFleet-E2E-Win11-01'
$script:DevFleetE2EL1Id = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$script:DevFleetE2EUser = 'E2EAdmin'
$script:DevFleetE2EDomain = 'DEVFLEET-E2E-01'
$script:DevFleetE2EGuestComputer = 'DEVFLEET-E2E-01'
$script:InteractiveLogonContract = 'devfleet-disposable-l1-interactive-logon-v1'
# Native console AutoLogon is the historically proven mechanism for this exact
# disposable L1. The ordinary Winlogon DefaultPassword exception is implemented
# only by Set-DevFleetE2EWinlogonAutologon and is armed for one host reboot.
$script:InteractiveLogonMode = 'native-winlogon'
$script:ActiveInteractiveLogonArm = $null
$script:InteractiveLogonRestartRequested = $false
$script:ActiveInteractiveLogonPolicyBaseline = $null
$script:RdpCredentialTarget = $null
$script:RdpClientProcessId = $null

function Get-DevFleetSafeException {
    param([Parameter(Mandatory)][System.Exception]$Exception)
    $message=([string]$Exception.Message -replace '\r?\n',' ')
    $message=([regex]::Replace($message,'(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>'))
    if($message.Length -gt 320){$message=$message.Substring(0,320)}
    [ordered]@{type=$Exception.GetType().FullName;message=$message}
}

function Invoke-DevFleetE2ERegistryPersistenceBarrier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][ValidateSet('Winlogon','PoliciesSystem')][string[]]$PathLabel
    )
    $labels=@($PathLabel|ForEach-Object{[string]$_}|Select-Object -Unique)
    if($labels.Count -eq 0){throw 'Registry persistence barrier received no allowlisted path.'}
    $result=Invoke-Command -Session $Session -ArgumentList (,$labels) -ScriptBlock {
        param([string[]]$requestedLabels)
        if([string]$env:COMPUTERNAME -cne 'DEVFLEET-E2E-01'){throw 'Registry persistence barrier reached an unexpected guest computer.'}
        $allowlist=[ordered]@{Winlogon='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';PoliciesSystem='SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'}
        $rows=@()
        foreach($label in @($requestedLabels)){
            if(-not $allowlist.Contains($label)){throw "Registry persistence barrier refused non-allowlisted path label '$label'."}
            $key=$null
            try{
                $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey([string]$allowlist[$label],$true)
                if($null -eq $key){throw "Registry persistence barrier could not open allowlisted path '$label'."}
                $key.Flush()
                $rows+=[ordered]@{success=$true;pathLabel=[string]$label;timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
            }catch{throw "Registry persistence barrier failed for allowlisted path '$label'."}
            finally{if($key){$key.Dispose()}}
        }
        [pscustomobject]@{success=(@($rows|Where-Object{[bool]$_.success}).Count -eq $rows.Count);paths=$rows}
    }
    if(-not [bool]$result.success){throw 'Registry persistence barrier did not report success.'}
    [pscustomobject]@{success=$true;paths=@($result.paths|ForEach-Object{[pscustomobject]@{success=[bool]$_.success;pathLabel=[string]$_.pathLabel;timestampUtc=[string]$_.timestampUtc}})}
}

function Test-DevFleetE2EGuestCredential {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][securestring]$CredentialPassword)
    $result=Invoke-Command -Session $Session -ArgumentList $CredentialPassword -ScriptBlock {
        param([securestring]$securePassword)
        if([string]$env:COMPUTERNAME -cne 'DEVFLEET-E2E-01'){throw 'Guest credential validation reached an unexpected guest computer.'}
        if(-not ([System.Management.Automation.PSTypeName]'DevFleetE2ELogonProbe').Type){
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DevFleetE2ELogonProbe {
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="LogonUserW")]
    static extern bool LogonUser(string user, string domain, IntPtr password, int logonType, int provider, out IntPtr token);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
    public static int Attempt(string user, string domain, IntPtr password, out bool tokenClosed) {
        IntPtr token=IntPtr.Zero; tokenClosed=false;
        bool ok=LogonUser(user,domain,password,2,0,out token);
        int error=ok ? 0 : Marshal.GetLastWin32Error();
        if(token!=IntPtr.Zero){tokenClosed=CloseHandle(token); if(!tokenClosed && error==0){error=Marshal.GetLastWin32Error();}}
        return ok ? 0 : error;
    }
}
'@
        }
        $ptr=[IntPtr]::Zero;$tokenClosed=$false
        try{
            if($null -eq $securePassword){throw 'Guest credential validation received no SecureString.'}
            $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            $errorCode=[DevFleetE2ELogonProbe]::Attempt('E2EAdmin','DEVFLEET-E2E-01',$ptr,[ref]$tokenClosed)
            [pscustomobject]@{attempted=$true;success=($errorCode -eq 0 -and $tokenClosed);win32ErrorCode=[int]$errorCode;tokenClosed=[bool]$tokenClosed;secretRecorded=$false}
        }finally{if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)};$ptr=[IntPtr]::Zero}
    }
    if(-not [bool]$result.success){throw "Guest credential validation failed with sanitized Win32 error $([int]$result.win32ErrorCode)."}
    [pscustomobject]@{attempted=[bool]$result.attempted;success=[bool]$result.success;win32ErrorCode=[int]$result.win32ErrorCode;tokenClosed=[bool]$result.tokenClosed;secretRecorded=$false}
}

function Initialize-DevFleetE2ECredentialManager {
    if(-not ([System.Management.Automation.PSTypeName]'DevFleetE2ECredentialManager').Type){
        Add-Type -TypeDefinition @"
using System;
using System.Security;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class DevFleetE2ECredentialManager {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct CREDENTIAL { public uint Flags; public uint Type; public string TargetName; public string Comment; public FILETIME LastWritten; public uint CredentialBlobSize; public IntPtr CredentialBlob; public uint Persist; public uint AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredWrite(ref CREDENTIAL credential, uint flags);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredDelete(string target, uint type, uint flags);
    public static int Write(string target, string user, SecureString password) {
        IntPtr buffer=IntPtr.Zero;
        try {
            buffer=Marshal.SecureStringToBSTR(password);
            CREDENTIAL credential=new CREDENTIAL(); credential.Type=1; credential.TargetName=target; credential.UserName=user; credential.CredentialBlob=buffer; credential.CredentialBlobSize=(uint)(password.Length*2); credential.Persist=1;
            if(CredWrite(ref credential,0)) return 0; return Marshal.GetLastWin32Error();
        } finally { if(buffer!=IntPtr.Zero) Marshal.ZeroFreeBSTR(buffer); }
    }
    public static int Delete(string target) { if(CredDelete(target,1,0)) return 0; int error=Marshal.GetLastWin32Error(); return error==1168 ? 0 : error; }
}
"@
    }
}

function Get-DevFleetE2ERdpBaseline {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    $writeResult=Invoke-Command -Session $Session -ScriptBlock {
        $key='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server';$item=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        $rules=@(Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{name=[string]$_.Name;enabled=[string]$_.Enabled;profile=[string]$_.Profile;direction=[string]$_.Direction;action=[string]$_.Action}})
        [ordered]@{fDenyTSConnectionsPresent=($null -ne $item.PSObject.Properties['fDenyTSConnections']);fDenyTSConnections=if($null -ne $item.PSObject.Properties['fDenyTSConnections']){[int]$item.fDenyTSConnections}else{$null};firewallRules=$rules}
    }
}

function Enable-DevFleetE2ERdp {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][psobject]$Baseline)
    Invoke-Command -Session $Session -ScriptBlock {
        param($saved)
        $key='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server';Set-ItemProperty -LiteralPath $key -Name fDenyTSConnections -Value 0 -Type DWord
        $ruleNames=@($saved.firewallRules|ForEach-Object{[string]$_.name}|Where-Object{$_})
        if($ruleNames.Count -eq 0){throw 'Exact disposable guest did not expose saved Remote Desktop firewall rules.'}
        foreach($ruleName in $ruleNames){Set-NetFirewallRule -Name $ruleName -Enabled True -ErrorAction Stop}
        $ip=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object{$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown'}|Sort-Object InterfaceMetric,PrefixLength|Select-Object -First 1 -ExpandProperty IPAddress)
        if($ip.Count -ne 1){throw 'Exact disposable guest did not expose one unambiguous IPv4 RDP address.'}
        [ordered]@{status='PASS';address=[string]$ip[0];temporaryGuestRdp=$true;baseline=$saved}
    } -ArgumentList $Baseline
}

function Restore-DevFleetE2ERdp {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][psobject]$Baseline)
    Invoke-Command -Session $Session -ScriptBlock {
        param($saved)
        $key='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
        if([bool]$saved.fDenyTSConnectionsPresent){Set-ItemProperty -LiteralPath $key -Name fDenyTSConnections -Value ([int]$saved.fDenyTSConnections) -Type DWord}else{Remove-ItemProperty -LiteralPath $key -Name fDenyTSConnections -ErrorAction SilentlyContinue}
        foreach($rule in @($saved.firewallRules)){Set-NetFirewallRule -Name ([string]$rule.name) -Enabled ([string]$rule.enabled) -ErrorAction SilentlyContinue}
        [pscustomobject]@{status='PASS';temporaryGuestRdpRestored=$true}
    } -ArgumentList $Baseline
}

function Set-DevFleetE2ERdpCredential {
    param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][pscredential]$Credential)
    Initialize-DevFleetE2ECredentialManager
    $rdpUser=if(([string]$Credential.UserName) -match '\\'){[string]$Credential.UserName}else{"$script:DevFleetE2EGuestComputer\$($Credential.UserName)"}
    $code=[DevFleetE2ECredentialManager]::Write($Target,$rdpUser,$Credential.Password)
    if($code -ne 0){throw "Temporary exact-L1 Credential Manager write failed with Win32 error $code."}
    $script:RdpCredentialTarget=$Target
    [pscustomobject]@{status='PASS';target=$Target;plaintextStoredInCommandLine=$false;scope='session'}
}

function Remove-DevFleetE2ERdpCredential {
    param([string]$Target=$script:RdpCredentialTarget)
    if($Target){Initialize-DevFleetE2ECredentialManager;$code=[DevFleetE2ECredentialManager]::Delete($Target);if($code -ne 0){throw "Temporary exact-L1 Credential Manager cleanup failed with Win32 error $code."}}
    $script:RdpCredentialTarget=$null
    [pscustomobject]@{status='PASS';credentialManagerRemoved=$true}
}

function Get-DevFleetE2EInteractiveLogonTarget {
    [pscustomobject]@{ name=$script:DevFleetE2EL1Name; id=$script:DevFleetE2EL1Id; user=$script:DevFleetE2EUser; domain=$script:DevFleetE2EDomain; contract=$script:InteractiveLogonContract }
}

function Assert-DevFleetE2EL1Identity {
    param([Parameter(Mandatory)][psobject]$Vm)
    if ([guid][string]$Vm.Id -ne $script:DevFleetE2EL1Id -or [string]$Vm.Name -cne $script:DevFleetE2EL1Name) {
        throw 'Interactive autologon is restricted to the exact authorized disposable L1 GUID/name.'
    }
    $true
}

function Get-AssertedDevFleetE2EL1 {
    param([Parameter(Mandatory)][guid]$VmId)
    if ($VmId -ne $script:DevFleetE2EL1Id) { throw 'Interactive autologon refused a VM outside the authorized L1 GUID.' }
    $vm = Get-VM -Id $VmId -ErrorAction Stop
    Assert-DevFleetE2EL1Identity -Vm $vm | Out-Null
    $vm
}

function Get-DevFleetE2ELsaScript {
    @'
if (-not ([System.Management.Automation.PSTypeName]'DevFleetE2ELsaV2').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Security;
using System.Runtime.InteropServices;

public static class DevFleetE2ELsaV2 {
    [StructLayout(LayoutKind.Sequential)]
    public struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    public struct LSA_OBJECT_ATTRIBUTES { public uint Length; public IntPtr RootDirectory; public IntPtr ObjectName; public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }
    [DllImport("advapi32.dll", SetLastError=false)] static extern uint LsaOpenPolicy(IntPtr systemName, ref LSA_OBJECT_ATTRIBUTES attributes, uint desiredAccess, out IntPtr policyHandle);
    [DllImport("advapi32.dll", SetLastError=false)] static extern uint LsaStorePrivateData(IntPtr policyHandle, ref LSA_UNICODE_STRING keyName, IntPtr privateData);
    [DllImport("advapi32.dll", SetLastError=false)] static extern uint LsaRetrievePrivateData(IntPtr policyHandle, ref LSA_UNICODE_STRING keyName, out IntPtr privateData);
    [DllImport("advapi32.dll", SetLastError=false)] static extern uint LsaFreeMemory(IntPtr buffer);
    [DllImport("advapi32.dll", SetLastError=false)] static extern uint LsaClose(IntPtr policyHandle);
    [DllImport("advapi32.dll", SetLastError=false)] static extern uint LsaNtStatusToWinError(uint status);

    public struct SecretComparison { public bool secretPresent; public bool secretMatchesCredential; public int expectedLength; public int storedLength; }

    public static int StoreOrClear(string secretName, string value) {
        IntPtr policy = IntPtr.Zero, keyBuffer = IntPtr.Zero, valueBuffer = IntPtr.Zero, privateDataBuffer = IntPtr.Zero;
        try {
            LSA_OBJECT_ATTRIBUTES attributes = new LSA_OBJECT_ATTRIBUTES();
            attributes.Length = 0;
            uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x20, out policy);
            if (status != 0) return (int)LsaNtStatusToWinError(status);
            keyBuffer = Marshal.StringToHGlobalUni(secretName);
            LSA_UNICODE_STRING key = new LSA_UNICODE_STRING();
            key.Length = (ushort)(secretName.Length * 2); key.MaximumLength = (ushort)(key.Length + 2); key.Buffer = keyBuffer;
            if (value != null) {
                valueBuffer = Marshal.StringToHGlobalUni(value);
                LSA_UNICODE_STRING privateData = new LSA_UNICODE_STRING();
                privateData.Length = (ushort)(value.Length * 2); privateData.MaximumLength = (ushort)(privateData.Length + 2); privateData.Buffer = valueBuffer;
                privateDataBuffer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(LSA_UNICODE_STRING)));
                Marshal.StructureToPtr(privateData, privateDataBuffer, false);
                status = LsaStorePrivateData(policy, ref key, privateDataBuffer);
            } else {
                status = LsaStorePrivateData(policy, ref key, IntPtr.Zero);
            }
            return (int)LsaNtStatusToWinError(status);
        } finally {
            if (valueBuffer != IntPtr.Zero) { try { Marshal.ZeroFreeGlobalAllocUnicode(valueBuffer); } catch { Marshal.FreeHGlobal(valueBuffer); } }
            if (privateDataBuffer != IntPtr.Zero) Marshal.FreeHGlobal(privateDataBuffer);
            if (keyBuffer != IntPtr.Zero) Marshal.FreeHGlobal(keyBuffer);
            if (policy != IntPtr.Zero) LsaClose(policy);
        }
    }

    public static int ClearAndProbe(string secretName, out bool present, out int retrieveError) {
        present = false; retrieveError = 0;
        IntPtr policy = IntPtr.Zero, keyBuffer = IntPtr.Zero, data = IntPtr.Zero;
        try {
            LSA_OBJECT_ATTRIBUTES attributes = new LSA_OBJECT_ATTRIBUTES();
            attributes.Length = 0;
            uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x20, out policy);
            if (status != 0) return (int)LsaNtStatusToWinError(status);
            keyBuffer = Marshal.StringToHGlobalUni(secretName);
            LSA_UNICODE_STRING key = new LSA_UNICODE_STRING();
            key.Length = (ushort)(secretName.Length * 2); key.MaximumLength = (ushort)(key.Length + 2); key.Buffer = keyBuffer;
            status = LsaStorePrivateData(policy, ref key, IntPtr.Zero);
            int clearError = (int)LsaNtStatusToWinError(status);
            if (clearError != 0 && clearError != 2 && clearError != 1168) return clearError;
            LsaClose(policy); policy = IntPtr.Zero;
            status = LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x4, out policy);
            if (status != 0) return (int)LsaNtStatusToWinError(status);
            status = LsaRetrievePrivateData(policy, ref key, out data);
            retrieveError = (int)LsaNtStatusToWinError(status);
            present = status == 0 && data != IntPtr.Zero;
            return 0;
        } finally {
            if (data != IntPtr.Zero) LsaFreeMemory(data);
            if (keyBuffer != IntPtr.Zero) Marshal.FreeHGlobal(keyBuffer);
            if (policy != IntPtr.Zero) LsaClose(policy);
        }
    }

    public static int ProbeLength(string secretName) {
        IntPtr policy = IntPtr.Zero, keyBuffer = IntPtr.Zero, data = IntPtr.Zero;
        try {
            LSA_OBJECT_ATTRIBUTES attributes = new LSA_OBJECT_ATTRIBUTES();
            attributes.Length = 0;
            uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x4, out policy);
            if (status != 0) return -(int)LsaNtStatusToWinError(status);
            keyBuffer = Marshal.StringToHGlobalUni(secretName);
            LSA_UNICODE_STRING key = new LSA_UNICODE_STRING();
            key.Length = (ushort)(secretName.Length * 2); key.MaximumLength = (ushort)(key.Length + 2); key.Buffer = keyBuffer;
            status = LsaRetrievePrivateData(policy, ref key, out data);
            if (status != 0) return -(int)LsaNtStatusToWinError(status);
            LSA_UNICODE_STRING value = (LSA_UNICODE_STRING)Marshal.PtrToStructure(data, typeof(LSA_UNICODE_STRING));
            return (int)value.Length;
        } finally {
            if (data != IntPtr.Zero) LsaFreeMemory(data);
            if (keyBuffer != IntPtr.Zero) Marshal.FreeHGlobal(keyBuffer);
            if (policy != IntPtr.Zero) LsaClose(policy);
        }
    }

    public static SecretComparison Compare(string secretName, SecureString expected) {
        IntPtr policy = IntPtr.Zero, keyBuffer = IntPtr.Zero, data = IntPtr.Zero, expectedBuffer = IntPtr.Zero;
        int expectedLength = expected == null ? 0 : expected.Length, storedLength = 0;
        try {
            if (expected == null) return new SecretComparison { secretPresent=false, secretMatchesCredential=false, expectedLength=0, storedLength=0 };
            expectedBuffer = Marshal.SecureStringToBSTR(expected);
            LSA_OBJECT_ATTRIBUTES attributes = new LSA_OBJECT_ATTRIBUTES();
            attributes.Length = 0;
            uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x4, out policy);
            if (status != 0) return new SecretComparison { secretPresent=false, secretMatchesCredential=false, expectedLength=expectedLength, storedLength=0 };
            keyBuffer = Marshal.StringToHGlobalUni(secretName);
            LSA_UNICODE_STRING key = new LSA_UNICODE_STRING();
            key.Length = (ushort)(secretName.Length * 2); key.MaximumLength = (ushort)(key.Length + 2); key.Buffer = keyBuffer;
            status = LsaRetrievePrivateData(policy, ref key, out data);
            if (status != 0 || data == IntPtr.Zero) return new SecretComparison { secretPresent=false, secretMatchesCredential=false, expectedLength=expectedLength, storedLength=0 };
            LSA_UNICODE_STRING value = (LSA_UNICODE_STRING)Marshal.PtrToStructure(data, typeof(LSA_UNICODE_STRING));
            storedLength = value.Length / 2;
            bool matches = value.Length == expectedLength * 2;
            for (int i = 0; matches && i < expectedLength; i++) {
                matches = Marshal.ReadInt16(value.Buffer, i * 2) == Marshal.ReadInt16(expectedBuffer, i * 2);
            }
            return new SecretComparison { secretPresent=true, secretMatchesCredential=matches, expectedLength=expectedLength, storedLength=storedLength };
        } finally {
            if (data != IntPtr.Zero) LsaFreeMemory(data);
            if (expectedBuffer != IntPtr.Zero) Marshal.ZeroFreeBSTR(expectedBuffer);
            if (keyBuffer != IntPtr.Zero) Marshal.FreeHGlobal(keyBuffer);
            if (policy != IntPtr.Zero) LsaClose(policy);
        }
    }
}
"@
}
'@
}

function Invoke-DevFleetE2EGuestLsa {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[AllowNull()][securestring]$Secret=$null,[switch]$Clear)
    $script = Get-DevFleetE2ELsaScript
    $result = Invoke-Command -Session $Session -ScriptBlock {
        param($expectedDomain,$expectedUser,$clear,[securestring]$secureSecret,$lsaSource)
        . ([scriptblock]::Create($lsaSource))
        if ([string]$env:COMPUTERNAME -cne 'DEVFLEET-E2E-01') { throw 'LSA operation reached an unexpected guest computer.' }
        $plain = $null; $ptr = [IntPtr]::Zero
        try {
            if (-not $clear) {
                if ($null -eq $secureSecret) { throw 'LSA arm operation received no in-memory credential material.' }
                $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
                $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
            }
            if (-not $clear) {
                $errorCode = [DevFleetE2ELsaV2]::StoreOrClear('DefaultPassword', $plain)
                $comparison = [DevFleetE2ELsaV2]::Compare('DefaultPassword', $secureSecret)
                if (-not [bool]$comparison.secretPresent -or -not [bool]$comparison.secretMatchesCredential) { throw 'LSA protected autologon secret did not match the canonical credential inside the guest.' }
            } else {
                $probePresent=$false;$probeError=0
                $clearAndProbeError=[DevFleetE2ELsaV2]::ClearAndProbe('DefaultPassword',[ref]$probePresent,[ref]$probeError)
                if($clearAndProbeError -notin @(0,2,1168)){throw "LSA protected autologon clear failed with Win32 error $clearAndProbeError."}
                if($probePresent -or $probeError -notin @(2,1168)){throw 'LSA protected autologon secret remained present after durable clear.'}
                $errorCode=0
                $comparison = [pscustomobject]@{secretPresent=$false;secretMatchesCredential=$false;expectedLength=0;storedLength=0}
            }
            [pscustomobject]@{ status=if($errorCode -eq 0){'PASS'}else{'FAIL'}; errorCode=$errorCode; cleared=[bool]$clear; secretName='DefaultPassword';secretPresent=[bool]$comparison.secretPresent;secretMatchesCredential=[bool]$comparison.secretMatchesCredential;expectedLength=[int]$comparison.expectedLength;storedLength=[int]$comparison.storedLength }
        } finally {
            if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
            $plain = $null
        }
    } -ArgumentList $script:DevFleetE2EDomain,$script:DevFleetE2EUser,$Clear.IsPresent,$Secret,$script
    if ([string]$result.status -ne 'PASS') { throw "LSA protected autologon operation failed with Win32 error $([int]$result.errorCode)." }
    [pscustomobject]@{ status='PASS'; secretName='DefaultPassword'; cleared=[bool]$Clear; errorCode=[int]$result.errorCode;secretPresent=[bool]$result.secretPresent;secretMatchesCredential=[bool]$result.secretMatchesCredential;expectedLength=[int]$result.expectedLength;storedLength=[int]$result.storedLength }
}

function Get-DevFleetE2EWinlogonBaseline {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    Invoke-Command -Session $Session -ScriptBlock {
        $key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; $item=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        [ordered]@{
            AutoAdminLogonPresent=($null -ne $item.PSObject.Properties['AutoAdminLogon']); AutoAdminLogon=if($null -ne $item.PSObject.Properties['AutoAdminLogon']){[string]$item.AutoAdminLogon}else{$null}
            DefaultUserNamePresent=($null -ne $item.PSObject.Properties['DefaultUserName']); DefaultUserName=if($null -ne $item.PSObject.Properties['DefaultUserName']){[string]$item.DefaultUserName}else{$null}
            DefaultDomainNamePresent=($null -ne $item.PSObject.Properties['DefaultDomainName']); DefaultDomainName=if($null -ne $item.PSObject.Properties['DefaultDomainName']){[string]$item.DefaultDomainName}else{$null}
            AutoLogonCountPresent=($null -ne $item.PSObject.Properties['AutoLogonCount']); AutoLogonCount=if($null -ne $item.PSObject.Properties['AutoLogonCount']){[int]$item.AutoLogonCount}else{$null}
            IgnoreShiftOverridePresent=($null -ne $item.PSObject.Properties['IgnoreShiftOverride']); IgnoreShiftOverride=if($null -ne $item.PSObject.Properties['IgnoreShiftOverride']){[int]$item.IgnoreShiftOverride}else{$null}
            ForceAutoLogonPresent=($null -ne $item.PSObject.Properties['ForceAutoLogon']); ForceAutoLogon=if($null -ne $item.PSObject.Properties['ForceAutoLogon']){[string]$item.ForceAutoLogon}else{$null}
            OrdinaryDefaultPasswordPresent=($null -ne $item.PSObject.Properties['DefaultPassword'])
        }
    }
}

function Get-DevFleetE2EPreLogonPolicyState {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    Invoke-Command -Session $Session -ScriptBlock {
        $policyPath='SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System';$winlogonPath='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        $policyKey=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($policyPath,$false);$winlogonKey=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($