# DevFleet source part 030

Full-source UTF-8 byte interval [1348500, 1395000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 16039afc830f6a54f695e72a96d36846622e069277d89d7fd92d4a15a9db2b98

<!-- BEGIN SOURCE SLICE -->
ck' -and [string]$existingFirewall[0].Enabled -ieq 'True' -and $profileMatches -and $existingPortFilters.Count -eq 1 -and $protocolMatches -and $localPortText -eq '65535')
            if(-not $firewallMatches){throw 'Foreign firewall sentinel already exists.'}
            # The exact run/phase-derived firewall can survive a product reboot
            # while the other run-owned sentinel objects are torn down. Reuse
            # it only when its immutable definition is exactly our sentinel;
            # any mismatched rule remains a fail-closed collision.
            $reuseExactFirewall=$true
        }
        $taskAction=New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\cmd.exe') -Argument '/d /c exit 0'
        $taskSettings=New-ScheduledTaskSettingsSet -Disable
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Settings $taskSettings -User 'SYSTEM' -RunLevel Highest -Force|Out-Null
        if(-not $reuseExactService){& (Join-Path $env:SystemRoot 'System32\sc.exe') create $serviceName 'binPath=' $serviceCommand 'start=' 'disabled' 'DisplayName=' "DevFleet E2E Foreign Sentinel $suffix"|Out-Null;if($LASTEXITCODE -ne 0){throw 'Foreign service sentinel creation failed.'}}
        if(-not $reuseExactFirewall){New-NetFirewallRule -Name $firewallName -DisplayName $firewallName -Group 'DevFleet E2E Foreign Sentinels' -Direction Inbound -Action Block -Protocol TCP -LocalPort 65535 -Profile Any|Out-Null}
        New-Item -ItemType Directory -Path (Split-Path -Parent $filePath) -Force|Out-Null
        New-Item -Path $registryPath -Force|Out-Null
        New-ItemProperty -Path $registryPath -Name Value -Value $value -PropertyType String -Force|Out-Null
        [IO.File]::WriteAllText($filePath,$value,[Text.UTF8Encoding]::new($false))
        $sha256=[Security.Cryptography.SHA256]::Create()
        try{$valueSha256=($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))|ForEach-Object{$_.ToString('x2')})-join ''}finally{$sha256.Dispose()}
        return [ordered]@{task=$taskName;service=$serviceName;firewall=$firewallName;registry=$registryPath;file=$filePath;valueSha256=$valueSha256;fileSha256=(Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant();serviceReused=$reuseExactService;firewallReused=$reuseExactFirewall}
    } -ArgumentList $RunId,$PhaseId
}

function Test-GuestForeignSentinels {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][psobject]$Sentinels)
    Invoke-Command -Session $Session -ScriptBlock {
        param($sentinels)
        $task=@(Get-ScheduledTask -TaskName ([string]$sentinels.task) -ErrorAction SilentlyContinue)
        $service=@(Get-CimInstance Win32_Service -Filter "Name='$([string]$sentinels.service)'" -ErrorAction SilentlyContinue)
        $firewall=@(Get-NetFirewallRule -Name ([string]$sentinels.firewall) -ErrorAction SilentlyContinue)
        $value=[string](Get-ItemProperty -Path ([string]$sentinels.registry) -Name Value -ErrorAction Stop).Value
        $sha256=[Security.Cryptography.SHA256]::Create()
        try{$valueSha=($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))|ForEach-Object{$_.ToString('x2')})-join ''}finally{$sha256.Dispose()}
        $fileSha=if(Test-Path -LiteralPath ([string]$sentinels.file) -PathType Leaf){(Get-FileHash -LiteralPath ([string]$sentinels.file) -Algorithm SHA256).Hash.ToLowerInvariant()}else{''}
        $checks=[ordered]@{scheduledTask=($task.Count -eq 1);service=($service.Count -eq 1 -and [string]$service[0].StartMode -eq 'Disabled');firewall=($firewall.Count -eq 1 -and [string]$firewall[0].Action -eq 'Block');registry=($valueSha -eq [string]$sentinels.valueSha256);file=($fileSha -eq [string]$sentinels.fileSha256)}
        if(@($checks.GetEnumerator()|Where-Object{-not [bool]$_.Value}).Count){throw 'One or more unrelated Windows sentinels changed during the lifecycle action.'}
        return [ordered]@{status='PASS';checks=$checks;unchanged=$true}
    } -ArgumentList $Sentinels
}

function Remove-GuestForeignSentinels {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][psobject]$Sentinels)
    Invoke-Command -Session $Session -ScriptBlock {
        param($sentinels)
        Unregister-ScheduledTask -TaskName ([string]$sentinels.task) -Confirm:$false -ErrorAction SilentlyContinue
        if(Get-CimInstance Win32_Service -Filter "Name='$([string]$sentinels.service)'" -ErrorAction SilentlyContinue){& (Join-Path $env:SystemRoot 'System32\sc.exe') delete ([string]$sentinels.service)|Out-Null;$serviceDeadline=(Get-Date).AddSeconds(15);do{$serviceStillPresent=$null -ne (Get-CimInstance Win32_Service -Filter "Name='$([string]$sentinels.service)'" -ErrorAction SilentlyContinue);if($serviceStillPresent){Start-Sleep -Milliseconds 250}}while($serviceStillPresent -and (Get-Date)-lt $serviceDeadline)}
        Get-NetFirewallRule -Name ([string]$sentinels.firewall) -ErrorAction SilentlyContinue|Remove-NetFirewallRule -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ([string]$sentinels.registry) -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ([string]$sentinels.file) -Force -ErrorAction SilentlyContinue
        $remaining=[ordered]@{task=[bool](Get-ScheduledTask -TaskName ([string]$sentinels.task) -ErrorAction SilentlyContinue);service=[bool](Get-CimInstance Win32_Service -Filter "Name='$([string]$sentinels.service)'" -ErrorAction SilentlyContinue);firewall=[bool](Get-NetFirewallRule -Name ([string]$sentinels.firewall) -ErrorAction SilentlyContinue);registry=(Test-Path -LiteralPath ([string]$sentinels.registry));file=(Test-Path -LiteralPath ([string]$sentinels.file))}
        if(@($remaining.GetEnumerator()|Where-Object{[bool]$_.Value}).Count){throw 'Run-owned Windows sentinel cleanup was incomplete.'}
        return [ordered]@{status='PASS';absent=$true}
    } -ArgumentList $Sentinels
}

function Invoke-RebootResumeWpfFallback {
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][psobject]$DriverReport
    )
    $expectedPayload = [string]$Context.candidate.tar.sha256
    $expectedCandidatePath = Join-Path "C:\Users\Public\DevFleet-E2E\$($Context.runId)\$($Context.phaseId)" (Split-Path -Leaf ([string]$Context.candidate.candidate.path))
    $candidatePid = 0
    $candidateSessionId = -1
    $driverProcessFound=$false;$driverProcess=Get-LifecycleProperty $DriverReport 'processId' ([ref]$driverProcessFound);if($driverProcessFound){$candidatePid=[int]$driverProcess}
    $driverSessionFound=$false;$driverSession=Get-LifecycleProperty $DriverReport 'sessionId' ([ref]$driverSessionFound);if($driverSessionFound){$candidateSessionId=[int]$driverSession}
    $observationSeconds = 180
    $diagnosticSecondsFound=$false;$diagnosticSeconds=Get-LifecycleProperty $Context 'diagnosticObservationSeconds' ([ref]$diagnosticSecondsFound);if ($diagnosticSecondsFound) {
        $requestedSeconds = 0
        if ([int]::TryParse([string]$diagnosticSeconds, [ref]$requestedSeconds) -and $requestedSeconds -gt 180) {
            $observationSeconds = [Math]::Min($requestedSeconds, 1800)
        }
    }
    $observationPath = Join-Path ([string]$Context.runDir) 'durable-observation-samples.json'
    $observationSamples = [System.Collections.Generic.List[object]]::new()
    $deadline = (Get-Date).AddSeconds($observationSeconds)
    $lastError = 'durable completion not yet observable'
    do {
        try {
            $sample = Invoke-Command -Session $Session -ScriptBlock {
                param($processId,$sessionId,$expectedPath)
                # Preserve the bounded read-error record when completion removes
                # the product checkpoint between the existence check and the
                # file read; do not leak a remoting non-terminating error into
                # the lifecycle observer.
                $ErrorActionPreference='Stop'
                $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
                $ids = [System.Collections.Generic.HashSet[int]]::new()
                if ($processId -gt 0) { [void]$ids.Add($processId) }
                do {
                    $before = $ids.Count
                    foreach ($row in $all) { if ($ids.Contains([int]$row.ParentProcessId)) { [void]$ids.Add([int]$row.ProcessId) } }
                } while ($ids.Count -gt $before)
                $root = $all | Where-Object { [int]$_.ProcessId -eq $processId } | Select-Object -First 1
                $processMeta = $null
                try {
                    $p = Get-Process -Id $processId -ErrorAction Stop
                    $processMeta = [ordered]@{hasExited=$false;responding=[bool]$p.Responding;mainWindowHandle=[int64]$p.MainWindowHandle;cpuSeconds=[double]$p.TotalProcessorTime.TotalSeconds;workingSetBytes=[int64]$p.WorkingSet64;threadCount=[int]$p.Threads.Count;handleCount=[int]$p.HandleCount;startTime=$p.StartTime.ToUniversalTime().ToString('o')}
                } catch { $processMeta = [ordered]@{hasExited=$true} }
                $checkpointPath = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-checkpoint.json'
                $checkpoint = $null
                if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) {
                    try { $v = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json; $checkpoint = [ordered]@{state=$v.state;action=$v.action;transactionId=$v.transactionId;payloadSha256=$v.payloadSha256;checkpointGeneration=$v.checkpointGeneration;completedStages=$v.completedStages;resumeStage=$v.resumeStage;createdUtc=$v.createdUtc;lastWriteUtc=(Get-Item -LiteralPath $checkpointPath).LastWriteTimeUtc.ToString('o')} } catch { $checkpoint = [ordered]@{readError=$_.Exception.Message} }
                }
                $consumedRoot = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-consumed'
                $receipts = @()
                if (Test-Path -LiteralPath $consumedRoot) { $receipts = @(Get-ChildItem -LiteralPath $consumedRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTimeUtc) }
                $installPath = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\install-state.json'
                $ownershipPath = 'C:\ProgramData\DevFleetHostAgent\integration-ownership.json'
                [ordered]@{timestampUtc=(Get-Date).ToUniversalTime().ToString('o');candidate=$processMeta;candidateRow=if($root){[ordered]@{processId=$root.ProcessId;parentProcessId=$root.ParentProcessId;executablePath=$root.ExecutablePath;commandLine=$root.CommandLine;sessionId=$root.SessionId}}else{$null};processTree=@($all | Where-Object { $ids.Contains([int]$_.ProcessId) } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,SessionId);checkpoint=$checkpoint;checkpointPresent=(Test-Path -LiteralPath $checkpointPath -PathType Leaf);receiptFiles=$receipts;installStatePresent=(Test-Path -LiteralPath $installPath -PathType Leaf);installStateLastWriteUtc=if(Test-Path -LiteralPath $installPath){(Get-Item -LiteralPath $installPath).LastWriteTimeUtc.ToString('o')}else{$null};ownershipPresent=(Test-Path -LiteralPath $ownershipPath -PathType Leaf);nodeIdentityPresent=(Test-Path -LiteralPath 'C:\ProgramData\DevFleet\node-identity.json' -PathType Leaf);hostAgentPresent=(Test-Path -LiteralPath 'C:\ProgramData\DevFleetHostAgent' -PathType Container);hostAgentTaskPresent=[bool](Get-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue);listenerPresent=[bool](Get-NetTCPConnection -LocalPort 8790 -State Listen -ErrorAction SilentlyContinue);pendingCbs=(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending');pendingWindowsUpdate=(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')}
            } -ArgumentList $candidatePid,$candidateSessionId,$expectedCandidatePath
            [void]$observationSamples.Add($sample)
            Write-EvidenceJson -Path $observationPath -Value @($observationSamples)
        } catch {
            [void]$observationSamples.Add([ordered]@{timestampUtc=(Get-Date).ToUniversalTime().ToString('o');sampleError=$_.Exception.Message})
            Write-EvidenceJson -Path $observationPath -Value @($observationSamples)
        }
        try {
            $durable = Invoke-MaintenanceReadyGuestValidation -VmId ([guid][string]$Context.vmId) -Fingerprint $Context.candidate -Session $Session -OwnerDeadlineUtc $deadline.ToUniversalTime()
            $receiptSeconds=[int][math]::Floor(($deadline-(Get-Date)).TotalSeconds)
            if($receiptSeconds-le0){throw 'Reboot receipt observation owner deadline is exhausted.'}
            $health = Invoke-DevFleetBoundedGuestCommand -Session $Session -TimeoutSeconds ([math]::Min(10,$receiptSeconds)) -ScriptBlock {
                param($payload)
                $checkpoint = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-checkpoint.json'
                if (Test-Path -LiteralPath $checkpoint -PathType Leaf) { throw 'Reboot checkpoint remains present; completion is not verified.' }
                $consumedRoot = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-consumed'
                $receipt = @(Get-ChildItem -LiteralPath $consumedRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try { $value = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; if ([string]$value.payloadSha256 -ceq $payload) { $_ } } catch { }
                } | Select-Object -Last 1)
                if (-not $receipt) { throw 'No consumed reboot receipt matched the exact candidate payload.' }
                [ordered]@{status='PASS';receiptPath=$receipt.FullName}
            } -ArgumentList @($expectedPayload)
            if([string]$durable.status-cne'PASS'-or$durable.hostAgentHealth.authenticated-isnot[bool]-or-not$durable.hostAgentHealth.authenticated-or$durable.hostAgentHealth.ok-isnot[bool]-or-not$durable.hostAgentHealth.ok-or(Get-Date)-ge$deadline){throw 'Bounded maintenance validation did not establish current authenticated health.'}
            if([string]$health.status-cne'PASS'){throw 'Reboot checkpoint/receipt validation did not pass.'}
            $health=[ordered]@{status='PASS';receiptPath=[string]$health.receiptPath;hostName=[string]$durable.hostAgentHealth.hostName;hostId=[string]$durable.hostAgentHealth.hostId}
            return [ordered]@{status='PASS';mode='DURABLE_REBOOT_RESUME_FALLBACK';driver=$DriverReport;guest=$durable;health=$health;authenticatedHealth=$true;checkpointConsumed=$true}
        } catch { $lastError = $_.Exception.Message }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    $processEvidence = $null
    $cleanupEvidence = $null
    if ($candidatePid -gt 0 -and $candidateSessionId -ge 0) {
        try {
            $processEvidence = Invoke-Command -Session $Session -ScriptBlock {
                param($processId,$sessionId,$expectedPath)
                $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
                $ids = [System.Collections.Generic.HashSet[int]]::new()
                [void]$ids.Add($processId)
                do {
                    $before = $ids.Count
                    foreach ($row in $all) { if ($ids.Contains([int]$row.ParentProcessId)) { [void]$ids.Add([int]$row.ProcessId) } }
                } while ($ids.Count -gt $before)
                $target = @($all | Where-Object { $ids.Contains([int]$_.ProcessId) } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,SessionId)
                $root = $all | Where-Object { [int]$_.ProcessId -eq $processId } | Select-Object -First 1
                $sessionMatch = $false
                try { $sessionMatch = [int](Get-Process -Id $processId -ErrorAction Stop).SessionId -eq $sessionId } catch { }
                $pathMatch = $null -ne $root -and -not [string]::IsNullOrWhiteSpace($expectedPath) -and [string]$root.ExecutablePath -ieq $expectedPath
                [ordered]@{candidatePid=$processId;expectedSessionId=$sessionId;expectedPath=$expectedPath;candidatePresent=($null -ne $root);sessionMatch=$sessionMatch;pathMatch=$pathMatch;processTree=$target}
            } -ArgumentList $candidatePid,$candidateSessionId,$expectedCandidatePath
        } catch { $processEvidence = [ordered]@{captureError=$_.Exception.Message} }
        try {
            $cleanupEvidence = Invoke-Command -Session $Session -ScriptBlock {
                param($processId,$sessionId,$expectedPath)
                $row = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
                $sessionMatch = $false
                try { $sessionMatch = [int](Get-Process -Id $processId -ErrorAction Stop).SessionId -eq $sessionId } catch { }
                $pathMatch = $null -ne $row -and -not [string]::IsNullOrWhiteSpace($expectedPath) -and [string]$row.ExecutablePath -ieq $expectedPath
                if ($row -and $sessionMatch -and $pathMatch) { Stop-Process -Id $processId -Force -ErrorAction Stop; [ordered]@{attempted=$true;stopped=$true;pid=$processId;sessionMatch=$sessionMatch;pathMatch=$pathMatch} }
                else { [ordered]@{attempted=$false;stopped=$false;pid=$processId;present=($null -ne $row);sessionMatch=$sessionMatch;pathMatch=$pathMatch} }
            } -ArgumentList $candidatePid,$candidateSessionId,$expectedCandidatePath
        } catch { $cleanupEvidence = [ordered]@{cleanupError=$_.Exception.Message} }
    } else {
        $cleanupEvidence = [ordered]@{attempted=$false;reason='No exact candidate PID and session identity was present in the driver report.'}
    }
    $details = [ordered]@{lastError=$lastError;observationSeconds=$observationSeconds;observationPath=$observationPath;observationSamples=@($observationSamples);processEvidence=$processEvidence;cleanupEvidence=$cleanupEvidence} | ConvertTo-Json -Depth 12 -Compress
    throw "WPF window disappeared and durable reboot-resume completion did not become verifiable within the bounded fallback window: $details"
}

function Invoke-DevFleetTailscaleOAuthCredentialCleanup {
    param([Parameter(Mandatory)][psobject]$Context,[AllowNull()][System.Management.Automation.Runspaces.PSSession]$Session)
    $cleanupSession=$Session
    $ownsCleanupSession=$false
    try {
        if(-not $cleanupSession -or [string]$cleanupSession.State -ceq 'Closed'){$cleanupSession=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId);$ownsCleanupSession=$true}
        if(-not $cleanupSession){throw 'No exact E2E session was available for OAuth credential cleanup.'}
        $cleanupResult=Remove-StagedTailscaleOAuthCredential -Session $cleanupSession
        if([string]$cleanupResult.status -cne 'PASS'){throw 'Remote OAuth credential cleanup returned a non-PASS result.'}
    } catch {
        if([string]$_.Exception.Message -match '^TAILSCALE_CREDENTIAL_CLEANUP_FAILED:'){throw}
        throw "TAILSCALE_CREDENTIAL_CLEANUP_FAILED: $($_.Exception.Message)"
    } finally {
        if($ownsCleanupSession -and $cleanupSession){Remove-DevFleetGuestSession $cleanupSession -ErrorAction SilentlyContinue}
    }
}

function Invoke-ActualWpfAction {
    param([Parameter(Mandatory)][psobject]$Context,[Parameter(Mandatory)][string]$Action,[string]$Role='Primary / Desktop',[string]$EvidenceLabel,[ValidateSet('direct','initial','resume','fallback')][string]$LaunchMode='direct',[switch]$AllowMutation,[switch]$AllowRebootRequired,[switch]$UseDurableCompletionFallback,[switch]$DeferDurableCompletionFallback,[switch]$DeferOAuthCredentialCleanup,[switch]$ElevatedResume)
    $candidate=Assert-ExactCandidate $Context
    $session=$null;$sentinels=$null;$sentinelVerification=$null;$sentinelCleanup=$null;$oauthStage=$null;$oauthStageAttempted=$false
    try {
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        try{$interactiveState=Get-DevFleetE2EInteractiveDesktopState -Session $session;$interactiveProof=Assert-DevFleetE2EInteractiveDesktop -State $interactiveState}
        catch{Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue;$session=$null;Ensure-FullReleaseInteractiveDesktop -VmId ([guid][string]$Context.vmId)|Out-Null;$session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId);$interactiveState=Get-DevFleetE2EInteractiveDesktopState -Session $session;$interactiveProof=Assert-DevFleetE2EInteractiveDesktop -State $interactiveState}
        if($AllowMutation -and $Context.config -and $Context.config.PSObject.Properties['Tailscale'] -and $Context.config.Tailscale.Authentication -and [string]$Context.config.Tailscale.Authentication.Provider -in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){
            $oauthStageAttempted=$true
            $Context|Add-Member -NotePropertyName oauthCredentialCleanupRequired -NotePropertyValue $true -Force
            $workspaceFound=$false;$workspaceValue=Get-LifecycleProperty $Context 'workspaceRoot' ([ref]$workspaceFound);$workspacePath=if($workspaceFound -and $workspaceValue){(Resolve-Path -LiteralPath ([string]$workspaceValue)).Path}else{(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path}
            $productConfigPath=Join-Path $workspacePath 'source\config\devfleet.config.json'
            if(-not(Test-Path -LiteralPath $productConfigPath -PathType Leaf)){throw 'TAILSCALE_CREDENTIAL_INVALID: product configuration is unavailable for deterministic E2E enrollment identities.'}
            try{$productConfig=Get-Content -LiteralPath $productConfigPath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'TAILSCALE_CREDENTIAL_INVALID: product configuration is unreadable for deterministic E2E enrollment identities.'}
            $oauthStage=Stage-TailscaleOAuthCredential -Session $session -RunId ([string]$Context.runId) -Config $Context.config.Tailscale -ProductConfig $productConfig
            if([string]$oauthStage.status -cne 'PASS' -or -not[bool]$oauthStage.staged){throw 'TAILSCALE_CREDENTIAL_INVALID: E2E OAuth credential staging did not complete.'}
        }
        $remoteRoot="C:\Users\Public\DevFleet-E2E\$($Context.runId)\$($Context.phaseId)"
        $remoteExe=Join-Path $remoteRoot (Split-Path -Leaf $candidate.path)
        $remoteDriver=Join-Path $remoteRoot 'Invoke-WpfUiAutomation.ps1'
        $remoteContract=Join-Path $remoteRoot 'WpfLaunchContract.psm1'
        $launchId=[guid]::NewGuid().ToString('N')
        $remoteReport=Join-Path $remoteRoot "wpf-$launchId-terminal.json"
        $remoteStarted=Join-Path $remoteRoot "wpf-$launchId-driver-bound.json"
        $remoteCheckpoint=Join-Path $remoteRoot "wpf-$launchId-checkpoint.json"
        $remoteWorkerResult=Join-Path $remoteRoot "wpf-$launchId-worker-terminal.json"
        $remoteLaunchRequest=Join-Path $remoteRoot "wpf-$launchId-launch-request.json"
        $safeEvidenceLabel=if([string]::IsNullOrWhiteSpace($EvidenceLabel)){"$($Context.phaseId)-$Action-$launchId"}else{$EvidenceLabel}
        $safeEvidenceLabel=($safeEvidenceLabel -replace '[^A-Za-z0-9._-]','-')
        $localEvidence=Join-Path ([string]$Context.runDir) ("$safeEvidenceLabel-wpf-evidence.json")
        New-Item -ItemType Directory -Force -Path ([string]$Context.runDir)|Out-Null
        Invoke-Command -Session $session -ScriptBlock {param($root)New-Item -ItemType Directory -Force -Path $root|Out-Null} -ArgumentList $remoteRoot
        if($AllowMutation){$sentinels=New-GuestForeignSentinels -Session $session -RunId ([string]$Context.runId) -PhaseId ([string]$Context.phaseId)}
        $stage=Get-StageIntegrity -LocalPath $candidate.path -Session $session -RemotePath $remoteExe
        if(-not $stage.equal){throw 'Candidate stage hash differed on disposable guest.'}
        $driverLocal=Join-Path $PSScriptRoot 'Invoke-WpfUiAutomation.ps1';$contractLocal=Join-Path $PSScriptRoot 'WpfLaunchContract.psm1'
        $driverStage=Get-StageIntegrity -LocalPath $driverLocal -Session $session -RemotePath $remoteDriver
        $contractStage=Get-StageIntegrity -LocalPath $contractLocal -Session $session -RemotePath $remoteContract
        if(-not $driverStage.equal -or -not $contractStage.equal){throw 'WPF driver/contract stage hash differed on disposable guest.'}

        $policy=Get-HarnessBudgetPolicy -Config $Context.config
        $ownerSeconds=if($Role -match '(?i)Laptop'){[int]$policy.observerAbsoluteBudgetsSeconds.Laptop}else{[int]$policy.observerAbsoluteBudgetsSeconds.Desktop}
        $ownerStart=(Get-Date).ToUniversalTime();$invocationStartFound=$false;$invocationStart=Get-LifecycleProperty $Context 'invocationStartUtc' ([ref]$invocationStartFound)
        if($invocationStartFound -and $invocationStart){$ownerStart=ConvertTo-WpfUtcInstant $invocationStart}
        $ownerDeadline=$ownerStart.AddSeconds($ownerSeconds)
        $transactionFound=$false;$transactionValue=Get-LifecycleProperty $Context 'lifecycleTransactionId' ([ref]$transactionFound);$transactionId=if($transactionFound){[string]$transactionValue}else{''}
        $launchSpec=New-WpfLaunchSpecification -DriverPath $remoteDriver -ExePath $remoteExe -Action $Action -Role $Role -OutputPath $remoteReport -StartedPath $remoteStarted -CheckpointPath $remoteCheckpoint -WorkerResultPath $remoteWorkerResult -LaunchRequestPath $remoteLaunchRequest -RunId ([string]$Context.runId) -LaunchId $launchId -TransactionId $transactionId -PayloadSha256 ([string]$Context.candidate.tar.sha256) -LaunchMode $LaunchMode -ExpectedInteractiveSessionId ([int]$interactiveProof.sessionId) -AllowMutation:$AllowMutation -AllowRebootRequired:$AllowRebootRequired -UseDurableCompletionFallback:$UseDurableCompletionFallback -ElevatedResume:$ElevatedResume -OwnerDeadlineUtc $ownerDeadline -SemanticNoProgressSeconds ([int]$policy.observerNoProgressBudgetSeconds) -DriverSha256 ([string]$driverStage.localSha256) -CandidateSha256 ([string]$candidate.sha256) -TaskExecutable 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -SkipPathValidation
        $launchSpec | Add-Member -NotePropertyName contractModulePath -NotePropertyValue $remoteContract -Force
        $launchSpec | Add-Member -NotePropertyName contractModuleSha256 -NotePropertyValue ([string]$contractStage.localSha256) -Force
        $launchSpecJson=$launchSpec|ConvertTo-Json -Depth 24 -Compress
        try {
            $report=Invoke-Command -Session $session -ScriptBlock {
                param($serializedSpec)
                $spec=$serializedSpec|ConvertFrom-Json
                function Get-Sha([string]$Path){$stream=[IO.File]::OpenRead($Path);try{$sha=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}finally{$stream.Dispose()}}
                function Get-TextSha([string]$Value){$sha=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
                function Read-AtomicJson([string]$Path){return([IO.File]::ReadAllText($Path)|ConvertFrom-Json -ErrorAction Stop)}
                function Resolve-TaskSid([string]$Account){$candidates=if($Account-notmatch'[\\@]'-and$env:COMPUTERNAME){@("$env:COMPUTERNAME\$Account",$Account)}else{@($Account)};foreach($candidateName in $candidates){try{return([Security.Principal.NTAccount]::new($candidateName)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{}};throw "Scheduled-task principal did not resolve to a SID: $Account"}
                function Write-Atomic([string]$Path,[object]$Value){$tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp";try{[IO.File]::WriteAllText($tmp,(($Value|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $tmp -Destination $Path -Force}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}}
                foreach($binding in @(@{path=[string]$spec.driverPath;hash=[string]$spec.driverSha256;name='driver'},@{path=[string]$spec.contractModulePath;hash=[string]$spec.contractModuleSha256;name='contract module'},@{path=[string]$spec.exePath;hash=[string]$spec.candidateSha256;name='candidate'})){if(-not(Test-Path -LiteralPath $binding.path -PathType Leaf)-or(Get-Sha $binding.path)-cne $binding.hash){throw "Remote WPF $($binding.name) binding failed before task registration."}}
                Write-Atomic -Path ([string]$spec.launchRequestPath) -Value $spec
                $taskName="DevFleet-E2E-UIA-$([string]$spec.launchId)";$taskStarted=$false
                try {
                    if($env:USERNAME -cne 'E2EAdmin'){throw 'WPF driver launch reached a non-E2EAdmin PowerShell Direct identity.'}
                    $taskAction=New-ScheduledTaskAction -Execute ([string]$spec.taskExecutable) -Argument ([string]$spec.taskArguments)
                    $taskPrincipal=New-ScheduledTaskPrincipal -UserId ([string]$spec.taskPrincipalUserId) -LogonType Interactive -RunLevel Highest
                    $remaining=[Math]::Max(120,[int]([datetimeoffset]::Parse([string]$spec.boundaryDeadlineUtc).UtcDateTime-(Get-Date).ToUniversalTime()).TotalSeconds+60)
                    $taskSettings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds $remaining) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Principal $taskPrincipal -Settings $taskSettings -Force|Out-Null
                    $registered=Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                    $actualActions=@($registered.Actions)
                    $taskBindingReason='';$expectedSid='';$requestedSid='';$actualSid=''
                    try{$expectedSid=Resolve-TaskSid ([string]$spec.taskPrincipalUserId);$requestedSid=Resolve-TaskSid ([string]$taskPrincipal.UserId);$actualSid=Resolve-TaskSid ([string]$registered.Principal.UserId)}catch{$taskBindingReason="principal SID resolution failed: $($_.Exception.Message)"}
                    $requestedLogonType=-1;$actualLogonType=-1;$requestedRunLevel=-1;$actualRunLevel=-1
                    try{$requestedLogonType=[Convert]::ToInt32($taskPrincipal.LogonType,[Globalization.CultureInfo]::InvariantCulture)}catch{};try{$actualLogonType=[Convert]::ToInt32($registered.Principal.LogonType,[Globalization.CultureInfo]::InvariantCulture)}catch{};try{$requestedRunLevel=[Convert]::ToInt32($taskPrincipal.RunLevel,[Globalization.CultureInfo]::InvariantCulture)}catch{};try{$actualRunLevel=[Convert]::ToInt32($registered.Principal.RunLevel,[Globalization.CultureInfo]::InvariantCulture)}catch{}
                    $expectedExecute=[Environment]::ExpandEnvironmentVariables([string]$spec.taskExecutable);$actualExecute=if($actualActions.Count-eq 1){[Environment]::ExpandEnvironmentVariables([string]$actualActions[0].Execute)}else{''}
                    $taskBindingEvidence=[ordered]@{actionCount=$actualActions.Count;requestedExecute=$expectedExecute;registeredExecute=$actualExecute;argumentsMatched=($actualActions.Count-eq 1-and[string]::Equals([string]$actualActions[0].Arguments,[string]$spec.taskArguments,[StringComparison]::Ordinal));expectedUserId=[string]$spec.taskPrincipalUserId;requestedUserId=[string]$taskPrincipal.UserId;registeredUserId=[string]$registered.Principal.UserId;principalSidSha256=if($actualSid){Get-TextSha $actualSid}else{''};requestedLogonTypeValue=$requestedLogonType;registeredLogonTypeValue=$actualLogonType;requestedRunLevelValue=$requestedRunLevel;registeredRunLevelValue=$actualRunLevel;verifiedBeforeStart=$false}
                    if(-not$taskBindingReason){if($actualActions.Count-ne 1){$taskBindingReason='registered task action count diverged'}else{try{$expectedExecute=[IO.Path]::GetFullPath($expectedExecute);$actualExecute=[IO.Path]::GetFullPath($actualExecute)}catch{$taskBindingReason='registered task executable path was malformed'}}}
                    if(-not$taskBindingReason-and-not[string]::Equals($actualExecute,$expectedExecute,[StringComparison]::OrdinalIgnoreCase)){$taskBindingReason='registered task executable identity diverged'}
                    if(-not$taskBindingReason-and-not[string]::Equals([string]$actualActions[0].Arguments,[string]$spec.taskArguments,[StringComparison]::Ordinal)){$taskBindingReason='registered task arguments diverged'}
                    if(-not$taskBindingReason-and($expectedSid-cne$requestedSid-or$expectedSid-cne$actualSid)){$taskBindingReason='registered task principal SID diverged'}
                    if(-not$taskBindingReason-and($requestedLogonType-ne[int]$spec.taskLogonTypeValue-or$actualLogonType-ne[int]$spec.taskLogonTypeValue)){$taskBindingReason='registered task logon type diverged'}
                    if(-not$taskBindingReason-and($requestedRunLevel-ne[int]$spec.taskRunLevelValue-or$actualRunLevel-ne[int]$spec.taskRunLevelValue)){$taskBindingReason='registered task run level diverged'}
                    if($taskBindingReason){
                        $failure=[ordered]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';status='OBSERVER_FAILURE';terminal=$true;completionVerified=$false;failureClass='REGISTERED_TASK_BINDING_MISMATCH';error="Registered WPF task diverged from the immutable launch request before product mutation: $taskBindingReason";runId=[string]$spec.runId;launchId=[string]$spec.launchId;transactionId=[string]$spec.transactionId;payloadSha256=[string]$spec.payloadSha256;candidateSha256=[string]$spec.candidateSha256;sequence=1;phase='TASK_BINDING_VALIDATION';lastDurableStep='LAUNCH_REQUESTED';deadlineUtc=[string]$spec.boundaryDeadlineUtc;cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER';taskBinding=$taskBindingEvidence;timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
                        Write-Atomic -Path ([string]$spec.outputPath) -Value $failure
                        throw $failure.error
                    }
                    $taskBindingEvidence.verifiedBeforeStart=$true
                    Start-ScheduledTask -TaskName $taskName;$taskStarted=$true
                    $deadline=[datetimeoffset]::Parse([string]$spec.boundaryDeadlineUtc).UtcDateTime
                    while(-not(Test-Path -LiteralPath $spec.outputPath -PathType Leaf)-and(Get-Date).ToUniversalTime()-lt $deadline){Start-Sleep -Seconds 1}
                    if(-not(Test-Path -LiteralPath $spec.outputPath -PathType Leaf)){
                        $last=$null;try{if(Test-Path -LiteralPath $spec.checkpointPath -PathType Leaf){$last=Read-AtomicJson $spec.checkpointPath}}catch{}
                        $seq=1;if($last -and $last.sequence){$seq=[int]$last.sequence+1}
                        $failure=[ordered]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';status='OBSERVER_FAILURE';terminal=$true;completionVerified=$false;failureClass='SUPERVISOR_REPORT_DEADLINE';error='Scheduled WPF supervisor did not publish a terminal report within the finite inherited boundary.';runId=[string]$spec.runId;launchId=[string]$spec.launchId;transactionId=[string]$spec.transactionId;payloadSha256=[string]$spec.payloadSha256;candidateSha256=[string]$spec.candidateSha256;sequence=$seq;phase='REMOTE_TASK_SUPERVISOR';lastDurableStep=if($last){[string]$last.phase}else{'LAUNCH_REQUESTED'};deadlineUtc=[string]$spec.boundaryDeadlineUtc;cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER';timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
                        Write-Atomic -Path ([string]$spec.outputPath) -Value $failure
                        if($taskStarted){Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue}
                    }
                    $result=Read-AtomicJson $spec.outputPath
                    $result|Add-Member -NotePropertyName taskPrincipal -NotePropertyValue ([string]$spec.taskPrincipalUserId) -Force
                    $result|Add-Member -NotePropertyName taskBinding -NotePropertyValue $taskBindingEvidence -Force
                    $result|Add-Member -NotePropertyName registeredTaskAction -NotePropertyValue ([ordered]@{execute=[string]$actualActions[0].Execute;arguments=[string]$actualActions[0].Arguments;verifiedBeforeStart=$true}) -Force
                    try {
                        $operatingSystem=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                        $result|Add-Member -NotePropertyName bootIdentity -NotePropertyValue ([ordered]@{status='PASS';computerName=[string]$env:COMPUTERNAME;lastBootUpTimeUtc=$operatingSystem.LastBootUpTime.ToUniversalTime().ToString('o');observedUtc=(Get-Date).ToUniversalTime().ToString('o')}) -Force
                    } catch {
                        $result|Add-Member -NotePropertyName bootIdentity -NotePropertyValue ([ordered]@{status='OBSERVATION_FAILED';error=$_.Exception.Message;observedUtc=(Get-Date).ToUniversalTime().ToString('o')}) -Force
                    }
                    return $result
                } finally {
                    if($taskStarted){$settleDeadline=(Get-Date).AddSeconds(15);do{$task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue;if(-not $task -or [string]$task.State -ne 'Running'){break};Start-Sleep -Milliseconds 500}while((Get-Date)-lt $settleDeadline)}
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                }
            } -ArgumentList $launchSpecJson
        } catch {
            foreach($remotePath in @($remoteReport,$remoteStarted,$remoteCheckpoint,$remoteWorkerResult,$remoteLaunchRequest)){try{Copy-Item -FromSession $session -LiteralPath $remotePath -Destination (Join-Path ([string]$Context.runDir) (Split-Path -Leaf $remotePath)) -Force -ErrorAction Stop}catch{}}
            throw "Remote WPF action $Action failed at the identity-bound task boundary: $($_.Exception.Message); evidenceLocal=$localEvidence"
        }
        if(-not $report){throw "Remote WPF action $Action returned no result; evidenceLocal=$localEvidence"}
        foreach($remotePath in @($remoteReport,$remoteStarted,$remoteCheckpoint,$remoteWorkerResult,$remoteLaunchRequest)){try{Copy-Item -FromSession $session -LiteralPath $remotePath -Destination (Join-Path ([string]$Context.runDir) (Split-Path -Leaf $remotePath)) -Force -ErrorAction Stop}catch{}}
        $bindingReason='';if(-not(Test-WpfTerminalReport -Report $report -Specification $launchSpec -Reason ([ref]$bindingReason))){
            $sequenceFound=$false;$rejectedSequenceValue=Get-LifecycleProperty $report 'sequence' ([ref]$sequenceFound);$rejectedSequence=0;if($sequenceFound){[void][int]::TryParse([string]$rejectedSequenceValue,[ref]$rejectedSequence)}
            $lastStepFound=$false;$rejectedLastStep=Get-LifecycleProperty $report 'lastDurableStep' ([ref]$lastStepFound)
            $parentFailure=[ordered]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';status='OBSERVER_FAILURE';terminal=$true;completionVerified=$false;failureClass='PARENT_REPORT_VALIDATION_FAILURE';error="Remote WPF report failed launch identity validation: $bindingReason";runId=[string]$launchSpec.runId;launchId=[string]$launchSpec.launchId;transactionId=[string]$launchSpec.transactionId;payloadSha256=[string]$launchSpec.payloadSha256;candidateSha256=[string]$launchSpec.candidateSha256;sequence=([Math]::Max(0,$rejectedSequence)+1);phase='PARENT_REPORT_VALIDATION';lastDurableStep=if($lastStepFound -and $rejectedLastStep){[string]$rejectedLastStep}else{'REMOTE_REPORT_RECEIVED'};deadlineUtc=[string]$launchSpec.boundaryDeadlineUtc;cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER';rejectedReportFile=(Split-Path -Leaf $remoteReport);timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
            [IO.File]::WriteAllText($localEvidence,(($parentFailure|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            throw "$($parentFailure.error); evidenceLocal=$localEvidence"
        }
        $report|Add-Member -NotePropertyName evidenceLabel -NotePropertyValue $safeEvidenceLabel -Force
        $report|Add-Member -NotePropertyName phaseId -NotePropertyValue ([string]$Context.phaseId) -Force
        $report|Add-Member -NotePropertyName candidatePath -NotePropertyValue ([string]$candidate.path) -Force
        $report|Add-Member -NotePropertyName interactiveSessionId -NotePropertyValue ([int]$interactiveProof.sessionId) -Force
        $report|Add-Member -NotePropertyName evidenceProvenance -NotePropertyValue 'identity-bound WPF launch request / isolated UIA worker / terminal supervisor' -Force
        [IO.File]::WriteAllText($localEvidence,(($report|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        $reportStatus=[string]$report.status
        if($reportStatus -in @('PASS','REBOOT_REQUIRED','DURABLE_PENDING','OBSERVER_HANDOFF')){
            foreach($identity in @($report.driverIdentity,$report.candidateIdentity)){if(-not $identity -or -not $identity.present -or [string]$identity.domain -cne 'DEVFLEET-E2E-01' -or [string]$identity.user -cne 'E2EAdmin' -or [int]$identity.sessionId -ne [int]$interactiveProof.sessionId -or [int]$identity.sessionId -eq 0){throw 'WPF launch acknowledgement did not preserve exact E2EAdmin interactive identity.'}}
            if(-not [string]$report.processStartTime){throw 'WPF launch acknowledgement did not preserve the exact candidate process start time.'}
            if(-not $report.bootIdentity -or [string]$report.bootIdentity.status -ne 'PASS' -or -not [string]$report.bootIdentity.lastBootUpTimeUtc){throw 'WPF launch acknowledgement did not preserve the exact guest boot identity.'}
        }
        if(-not $DeferDurableCompletionFallback -and $reportStatus -eq 'OBSERVER_HANDOFF'){$fallback=Invoke-RebootResumeWpfFallback -Context $Context -Session $session -DriverReport $report;$report=[pscustomobject]@{status='PASS';action=$Action;role=$Role;candidateSha256=[string]$candidate.sha256;processId=$report.processId;completionVerified=$true;mutationInvoked=$true;fallback=$fallback};$reportStatus='PASS'}
        $accepted=@('PASS');if($AllowRebootRequired){$accepted+='REBOOT_REQUIRED'};if($DeferDurableCompletionFallback){$accepted+='OBSERVER_HANDOFF'}
        if($reportStatus -notin $accepted){$failure=Get-WpfFailureDescriptor -Report $report;throw "Real WPF action did not pass for ${Action}: status=$reportStatus; class=$([string]$failure.failureClass); error=$([string]$failure.error); evidenceLocal=$localEvidence"}
        if($sentinels){$sentinelVerification=Test-GuestForeignSentinels -Session $session -Sentinels $sentinels}
        $overallStatus=switch($reportStatus){'REBOOT_REQUIRED'{'REAL E2E REBOOT REQUIRED';break}'OBSERVER_HANDOFF'{'REAL E2E OBSERVER HANDOFF';break}default{'REAL E2E PASS'}}
        return [ordered]@{status=$overallStatus;phase=$Context.phaseId;action=$Action;role=$Role;candidate=$candidate;stage=$stage;driverStage=$driverStage;contractStage=$contractStage;guest=$report;evidencePath=$localEvidence;remoteEvidencePath=$remoteReport;evidenceLabel=$safeEvidenceLabel;mutationAllowed=[bool]$AllowMutation;foreignSentinels=$sentinelVerification;launchId=$launchId;oauthStaging=$oauthStage}
    } finally {
        if($oauthStageAttempted -and -not $DeferOAuthCredentialCleanup){Invoke-DevFleetTailscaleOAuthCredentialCleanup -Context $Context -Session $session|Out-Null}
        if($session -and $sentinels){$sentinelCleanup=Remove-GuestForeignSentinels -Session $session -Sentinels $sentinels};if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}
    }
}

function Invoke-PrimaryRolePhase {
    param([Parameter(Mandatory)][string]$ContextJson)
    $context = Read-PhaseContext $ContextJson
    $result = Invoke-ActualWpfAction -Context $context -Action 'Diagnostics' -Role 'Primary / Desktop' -AllowMutation:$false
    if ([string]$result.guest.role -ne 'Primary / Desktop') { throw 'Primary phase did not verify the exact Primary / Desktop role.' }
    if ([bool]$result.guest.mutationInvoked) { throw 'Primary phase diagnostics unexpectedly invoked a mutation.' }
    return [ordered]@{ status='REAL E2E PASS'; phase=$context.phaseId; contract='primary-role-diagnostics'; candidate=$result.candidate; role=$result.role; guest=$result.guest; evidencePath=$result.evidencePath }
}

function Invoke-SurrogateDisposablePhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $result = Invoke-SupportedFreshInstallLifecycle -Context $Context -Role 'Laptop / Surrogate' -CompleteLifecycle
    if ([string]$result.guest.role -ne 'Laptop / Surrogate') { throw 'Disposable surrogate phase did not verify the Laptop / Surrogate role.' }
    if (-not [bool]$result.guest.mutationInvoked) { throw 'Disposable surrogate phase did not invoke the real mutation.' }
    if ([string]$result.status -ne 'REAL E2E PASS' -or -not [bool]$result.guest.completionVerified) {
        throw "SURROGATE-DISPOSABLE requires genuine final lifecycle PASS; observed $($result.status)."
    }
    return [ordered]@{status='REAL E2E PASS';phase='SURROGATE-DISPOSABLE';contract='disposable-laptop-surrogate-real-wpf-install';product=$result;candidate=$result.candidate;role=$result.role;guest=$result.guest;evidencePath=$result.evidencePath;physicalSurfaceTouched=$false;testKitEligibility='EVIDENCE INPUT ONLY - RECONCILE DECIDES'}
}

function Invoke-TailscalePolicyPhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $candidate=Assert-ExactCandidate $Context
    $configuredMode=[string]$Context.config.Tailscale.Mode
    if([string]$Context.phaseId -eq 'TAILSCALE-AUTH') {
        $session=$null
        try {
            $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
            $tailscaleConfig=$Context.config.Tailscale|ConvertTo-Json -Depth 16|ConvertFrom-Json
            $authConfig=$tailscaleConfig.Authentication
            $provider=if($authConfig.PSObject.Properties['Provider']){[string]$authConfig.Provider}else{''}
            if($provider-in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){
                $authConfig|Add-Member -NotePropertyName Hostname -NotePropertyValue (Get-TailscaleE2EHo