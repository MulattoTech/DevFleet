[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Write-AtomicJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 16 -Compress))
        [IO.File]::WriteAllBytes($temporary,$bytes)
        [IO.File]::Move($temporary,$Path,$true)
    } finally {Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}

function Get-ActiveBoundary {
    $root=Join-Path $env:ProgramData 'DevFleet'
    [ordered]@{
        activeTransactionPresent=Test-Path -LiteralPath (Join-Path $root 'active-transaction.json') -PathType Leaf
        stageMarkerCount=@(Get-ChildItem -LiteralPath $root -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count
        activeInstallProcessCount=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{[string]$_.Name-in@('DevFleet.Setup.exe','pwsh.exe','powershell.exe')-and[string]$_.CommandLine-match'(?i)Install-DevFleet|Bootstrap-Install|DevFleet.Setup'}).Count
    }
}

try {
    $requestJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))
    $request=$requestJson|ConvertFrom-Json -ErrorAction Stop
    if([string]$request.runId-notmatch'^[A-Za-z0-9._-]+$'){throw 'Campaign E prerequisite run identity is invalid.'}
    $remoteRoot=[IO.Path]::GetFullPath([string]$request.remoteRoot).TrimEnd('\')
    if($remoteRoot-notlike'C:\Users\Public\DevFleet-E2E\*\Prerequisite'){throw 'Campaign E prerequisite root is outside the run-owned boundary.'}
    $packageRoot=[IO.Path]::GetFullPath([string]$request.packageRoot).TrimEnd('\')
    $resultPath=[IO.Path]::GetFullPath([string]$request.resultPath)
    if(-not$packageRoot.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)-or-not$resultPath.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Campaign E prerequisite worker path escaped the run-owned root.'}
    $ownerDeadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.ownerDeadlineUnixMilliseconds).UtcDateTime
    $started=[datetime]::UtcNow
    if($ownerDeadline-le$started){throw 'Campaign E prerequisite owner deadline expired before the PowerShell worker.'}
    $commonPath=Join-Path $packageRoot 'windows\DevFleet.Common.psm1'
    $diagnosticModule=[IO.Path]::GetFullPath([string]$request.diagnosticModulePath)
    if(-not$diagnosticModule.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Campaign E diagnostic module path escaped the run-owned root.'}
    Import-Module $commonPath -Force -ErrorAction Stop
    Import-Module $diagnosticModule -Force -ErrorAction Stop
    Assert-PowerShell7
    Assert-Administrator
    $plan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot $packageRoot -Role ([string]$request.role)
    foreach($name in @('version','dependencies','config','bootstrap','install','common')){if([string]$plan.inputHashes.$name-cne[string]$request.inputHashes.$name){throw "Extracted candidate prerequisite hash mismatch: $name"}}
    $before=Get-ActiveBoundary
    if([bool]$before.activeTransactionPresent-or[int]$before.stageMarkerCount-ne0-or[int]$before.activeInstallProcessCount-ne0){throw 'Campaign E prerequisite worker requires a transactionless, marker-free, quiescent product boundary.'}
    $remaining=[int][math]::Floor(($ownerDeadline-[datetime]::UtcNow).TotalSeconds)
    if($remaining-le0){throw 'Campaign E prerequisite owner deadline expired before dependency evaluation.'}
    Set-DevFleetDeadlineContext -TransactionDeadlineUtc $ownerDeadline -StageName 'campaign-e-prerequisite-only' -StageBudgetSeconds $remaining|Out-Null
    $manifest=Get-CanonicalDependencyManifest -PackageRoot $packageRoot
    $powerShellDependency=@($manifest.dependencies|Where-Object{[string]$_.id-ceq'powershell7'})
    $multipassDependency=@($manifest.dependencies|Where-Object{[string]$_.id-ceq'multipass'})
    if($powerShellDependency.Count-ne1-or$multipassDependency.Count-ne1){throw 'Candidate prerequisite dependency identity is not unique.'}
    $powerShellStatus=Get-DependencyStatus -Dependency $powerShellDependency[0]
    if([string]$powerShellStatus.Status-cne'Compatible'){throw "PowerShell bootstrap did not reach compatible state: $([string]$powerShellStatus.Status)"}
    $beforeMultipass=Get-DependencyStatus -Dependency $multipassDependency[0]
    if([string]$beforeMultipass.Status-cne'Compatible'){
        if([string]$beforeMultipass.Status-ceq'Unsupported-Major'){throw "Multipass major version is outside the candidate policy: $([string]$beforeMultipass.Version)"}
        $health=Get-WingetHealth
        if([string]$health.Status-ceq'Healthy'-and[string]$multipassDependency[0].wingetPackageId){
            try {Install-WingetPackage -Id ([string]$multipassDependency[0].wingetPackageId) -Upgrade:([string]$beforeMultipass.Status-ceq'Outdated')}
            catch {
                if($_.Exception.Message-notmatch'(?i)External command timed out'-or-not$multipassDependency[0].directOfficialVendorResolver){throw}
                Install-OfficialDependency -Dependency $multipassDependency[0]
            }
        } else {Install-OfficialDependency -Dependency $multipassDependency[0]}
    }
    $afterMultipass=Get-DependencyStatus -Dependency $multipassDependency[0]
    if([string]$afterMultipass.Status-cne'Compatible'){throw "Multipass did not reach compatible state: $([string]$afterMultipass.Status)"}
    $edition=[string](Get-ComputerInfo -Property WindowsProductName).WindowsProductName
    if($edition-notmatch'Pro|Enterprise|Education'){throw "Campaign E prerequisite state requires the candidate Hyper-V mapping; observed edition: $edition"}
    $feature=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
    if([string]$feature.State-cne'Enabled'){throw 'Campaign E prerequisite state will not enable Hyper-V; the exact CLEAN baseline must already provide it.'}
    $multipass=Get-MultipassExe
    if(-not$multipass){throw 'Compatible Multipass was reported but its trusted executable could not be resolved.'}

    function Invoke-ConfigurationProbe {
        param([string[]]$Arguments,[string]$Failure)
        $operationDeadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'multipassConfiguration'))
        if($operationDeadline-gt$ownerDeadline){$operationDeadline=$ownerDeadline}
        do {
            $operationRemaining=[int][math]::Floor(($operationDeadline-[datetime]::UtcNow).TotalSeconds)
            if($operationRemaining-le0){break}
            try{return Invoke-External -FilePath $multipass -ArgumentList $Arguments -Capture -TimeoutSeconds ([math]::Min(60,$operationRemaining)) -DeadlineUtc $operationDeadline}catch{if([datetime]::UtcNow.AddSeconds(1)-ge$operationDeadline){break};Start-Sleep -Seconds 1}
        } while($true)
        throw $Failure
    }

    $null=Invoke-ConfigurationProbe -Arguments @('set','local.driver=hyperv') -Failure 'Multipass Hyper-V driver selection did not complete inside its finite candidate operation budget.'
    $driver=(Invoke-ConfigurationProbe -Arguments @('get','local.driver') -Failure 'Multipass Hyper-V driver verification did not complete inside its finite candidate operation budget.').Trim().ToLowerInvariant()
    if($driver-cne'hyperv'){throw "Multipass driver verification returned an unsupported value: $driver"}
    $null=Invoke-ConfigurationProbe -Arguments @('set','local.privileged-mounts=false') -Failure 'Multipass mount hardening did not complete inside its finite candidate operation budget.'
    $mountText=(Invoke-ConfigurationProbe -Arguments @('get','local.privileged-mounts') -Failure 'Multipass mount hardening verification did not complete inside its finite candidate operation budget.').Trim().ToLowerInvariant()
    if($mountText-notin@('true','false')){throw 'Multipass privileged-mount output was malformed.'}
    if($mountText-cne'false'){throw 'Multipass privileged mounts remained enabled.'}
    $inventoryText=Invoke-ConfigurationProbe -Arguments @('list','--format','json') -Failure 'Multipass empty-inventory verification did not complete inside its finite candidate operation budget.'
    $inventory=$inventoryText|ConvertFrom-Json -ErrorAction Stop
    $instances=@(if($inventory.PSObject.Properties.Name-contains'list'){$inventory.list}elseif($inventory-is[array]){$inventory}else{throw 'Multipass inventory omitted its list.'})
    if($instances.Count-ne0){throw 'Campaign E prerequisite state requires an empty Multipass inventory.'}
    $finalBoundary=Get-ActiveBoundary
    if([bool]$finalBoundary.activeTransactionPresent-or[int]$finalBoundary.stageMarkerCount-ne0-or[int]$finalBoundary.activeInstallProcessCount-ne0){throw 'Campaign E prerequisite worker ended with forbidden product activity.'}
    $currentReboot=Get-DevFleetPendingRebootSnapshot
    $baseline=$request.pendingRebootBaseline
    $newPending=[bool](([bool]$currentReboot.CbsPending-and-not[bool]$baseline.CbsPending)-or([bool]$currentReboot.WindowsUpdatePending-and-not[bool]$baseline.WindowsUpdatePending)-or@($currentReboot.PendingPairs|Where-Object{@($baseline.PendingPairs)-notcontains$_}).Count-gt0)
    $result=[ordered]@{
        schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY';status='PASS';runId=[string]$request.runId;vmId=[string]$request.vmId;payloadSha256=[string]$request.payloadSha256
        role=[string]$request.role;packageVersion=[string]$plan.packageVersion;ownerDeadlineUtc=$ownerDeadline.ToString('o');startedAtUtc=$started.ToString('o');producedAtUtc=[datetime]::UtcNow.ToString('o')
        inputHashes=$plan.inputHashes;systemPolicyChanged=$false;productLifecycleStarted=$false;activeTransactionPresent=[bool]$finalBoundary.activeTransactionPresent;stageMarkerCount=[int]$finalBoundary.stageMarkerCount;activeInstallProcessCount=[int]$finalBoundary.activeInstallProcessCount
        pendingReboot=$newPending;pendingRebootEvidence=[ordered]@{baselineCbs=[bool]$baseline.CbsPending;currentCbs=[bool]$currentReboot.CbsPending;baselineWindowsUpdate=[bool]$baseline.WindowsUpdatePending;currentWindowsUpdate=[bool]$currentReboot.WindowsUpdatePending;newPendingPairCount=@($currentReboot.PendingPairs|Where-Object{@($baseline.PendingPairs)-notcontains$_}).Count}
        powershell=[ordered]@{status=[string]$powerShellStatus.Status;version=[string]$powerShellStatus.Version;pathSha256=(Get-FileHash -LiteralPath ([string]$powerShellStatus.Path) -Algorithm SHA256).Hash.ToLowerInvariant()}
        multipass=[ordered]@{status=[string]$afterMultipass.Status;version=[string]$afterMultipass.Version;pathSha256=(Get-FileHash -LiteralPath ([string]$afterMultipass.Path) -Algorithm SHA256).Hash.ToLowerInvariant();preexisting=([string]$beforeMultipass.Status-ceq'Compatible')}
        backend=[ordered]@{driver=$driver;privilegedMounts=$false;inventoryCount=0;windowsEditionClass='PRO_ENTERPRISE_EDUCATION'}
        l2Status='PENDING_CONTROLLER_VERIFICATION'
    }
    Write-AtomicJson -Path $resultPath -Value $result
    if($newPending){throw 'Prerequisite installation introduced a pending reboot; checkpoint creation is not allowed before exact L1 restart handling.'}
} catch {
    $message=[regex]::Replace([string]$_.Exception.Message,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    [Console]::Error.Write($message)
    exit 1
}
