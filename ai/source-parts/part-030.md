# DevFleet source part 030

Full-source UTF-8 byte interval [1348500, 1395000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 57ce20146d8ce639035e97c82074e1155f2f415c727b4013f1c9c2e1e6fa0f29

<!-- BEGIN SOURCE SLICE -->
 -LiteralPath $installPath).LastWriteTimeUtc.ToString('o')}else{$null};ownershipPresent=(Test-Path -LiteralPath $ownershipPath -PathType Leaf);nodeIdentityPresent=(Test-Path -LiteralPath 'C:\ProgramData\DevFleet\node-identity.json' -PathType Leaf);hostAgentPresent=(Test-Path -LiteralPath 'C:\ProgramData\DevFleetHostAgent' -PathType Container);hostAgentTaskPresent=[bool](Get-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue);listenerPresent=[bool](Get-NetTCPConnection -LocalPort 8790 -State Listen -ErrorAction SilentlyContinue);pendingCbs=(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending');pendingWindowsUpdate=(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')}
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
                $authConfig|Add-Member -NotePropertyName Hostname -NotePropertyValue (Get-TailscaleE2EHostname -RunId ([string]$Context.runId) -Role 'windows') -Force
            }
            $tailscaleWaitSeconds=if($tailscaleConfig.PSObject.Properties['PollTimeoutSeconds'] -and [int]$tailscaleConfig.PollTimeoutSeconds -gt 0){[int]$tailscaleConfig.PollTimeoutSeconds}else{120}
            $tailscaleOwnerDeadline=[datetime]::UtcNow.AddSeconds($tailscaleWaitSeconds+30)
            $auth=Invoke-TailscaleAuthentication -Session $session -Config $tailscaleConfig -OwnerDeadlineUtc $tailscaleOwnerDeadline
            if(-not [bool]$auth.authenticationAttempted -and [bool]$auth.userActionRequired) { Write-TailscaleOAuthActionRequired; throw "USER ACTION REQUIRED - TAILSCALE-AUTH: $([string]$auth.reason)." }
            Assert-TailscaleAuthenticationResult -Result $auth | Out-Null
            $productConfigPath=Join-Path ((Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path) 'source\config\devfleet.config.json'
            if(-not(Test-Path -LiteralPath $productConfigPath -PathType Leaf)){throw 'TAILSCALE_CONTROL_PLANE_OFFLINE: product configuration is unavailable for readiness endpoint discovery.'}
            $productConfig=Get-Content -LiteralPath $productConfigPath -Raw|ConvertFrom-Json -ErrorAction Stop
            $expectedPeer=Get-TailscaleE2EHostname -RunId ([string]$Context.runId) -Role 'primary'
            $servicePort=[int]$productConfig.Network.PortalPort
            $servicePath='/healthz'
            $expectedNode=if($provider-in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){Get-TailscaleE2EHostname -RunId ([string]$Context.runId) -Role 'windows'}else{[string]$Context.config.Tailscale.ExpectedGuestNodePattern}
            $expectedTag=if($authConfig.PSObject.Properties['Tag']){[string]$authConfig.Tag}else{''}
            $readiness=Get-TailscaleReadiness -Session $session -ExpectedNodePattern $expectedNode -ExpectedTag $expectedTag -ExpectedPeer $expectedPeer -ServicePort $servicePort -ServicePath $servicePath -OwnerDeadlineUtc $tailscaleOwnerDeadline
            if(-not [bool]$readiness.ready){throw "$([string]$readiness.failureClass): TAILSCALE-AUTH structured readiness did not pass."}
            return [ordered]@{status='REAL E2E PASS';phase=[string]$Context.phaseId;contract=if($provider-in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){'oauth-client-secret-provider-with-layered-readiness'}else{'auth-key-fallback-provider-with-layered-readiness'};configuredMode=$configuredMode;candidate=$candidate;guest=$readiness.layer2;readiness=$readiness;authenticationAttempted=[bool]$auth.authenticationAttempted;authenticationSucceeded=[bool]$auth.authenticationSucceeded;authProvider=$provider;expectedPeer=$expectedPeer;servicePort=$servicePort;servicePath=$servicePath;credentialsStoredInEvidence=$false;userActionRequired=$false}
        }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
    }
    if($configuredMode -ne 'Deferred'){throw 'USER ACTION REQUIRED - configured Tailscale policy requires the official interactive authentication boundary.'}
    $session=$null
    try{
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        $status=Get-TailscaleGuestStatus -Session $session -ExpectedNodePattern ([string]$Context.config.Tailscale.ExpectedGuestNodePattern)
        if([bool]$status.online -or -not[bool]$status.needsLogin){throw 'Deferred Tailscale policy expected an installed but unauthenticated guest.'}
        if([string]::IsNullOrWhiteSpace([string]$status.version) -or [string]$status.version -match 'not recognized|not found'){throw 'Deferred Tailscale policy could not verify the installed Tailscale client.'}
        return [ordered]@{status='REAL E2E PASS';phase=[string]$Context.phaseId;contract=if([string]$Context.phaseId -eq 'TAILSCALE-DEFERRED'){'installed-client-deferred-no-auth'}else{'authentication-explicitly-not-run-by-supported-deferred-policy'};configuredMode=$configuredMode;candidate=$candidate;guest=$status;authenticationAttempted=$false;credentialsStoredInEvidence=$false;userActionRequired=$false}
    }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
}

function ConvertTo-LfShellText([string]$Text) {
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Invoke-LinuxBootstrapPhase {
    param([Parameter(Mandatory)][string]$ContextJson)
    $context = Read-PhaseContext $ContextJson
    $candidate = Assert-ExactCandidate $context
    $tarPath = [string]$context.candidate.tar.path
    if (-not (Test-Path -LiteralPath $tarPath -PathType Leaf)) { throw "Linux phase TAR is missing: $tarPath" }
    $tarHash = (Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($tarHash -ne [string]$context.candidate.tar.sha256) { throw 'Linux phase TAR hash differs from the exact candidate tuple.' }
    $aiBundle = $null
    $aiBundleFound=$false;$aiBundleValue=Get-LifecycleProperty $context 'aiAuditZip' ([ref]$aiBundleFound);if ($aiBundleFound -and $aiBundleValue) {
        $aiPathFound=$false;$aiPathValue=Get-LifecycleProperty $aiBundleValue 'path' ([ref]$aiPathFound);$aiHashFound=$false;$aiHashValue=Get-LifecycleProperty $aiBundleValue 'sha256' ([ref]$aiHashFound);$aiBundlePath = [string]$aiPathValue
        $expectedAiBundleHash = ([string]$aiHashValue).ToLowerInvariant()
        if (-not (Test-Path -LiteralPath $aiBundlePath -PathType Leaf)) { throw "Focused Linux AI audit bundle is missing: $aiBundlePath" }
        if ($expectedAiBundleHash -notmatch '^[0-9a-f]{64}$') { throw 'Focused Linux AI audit bundle is missing an exact SHA-256 identity.' }
        $actualAiBundleHash = (Get-FileHash -LiteralPath $aiBundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualAiBundleHash -ne $expectedAiBundleHash) { throw 'Focused Linux AI audit bundle hash differs from the supplied exact identity.' }
        $aiBundle = [ordered]@{path=(Resolve-Path -LiteralPath $aiBundlePath).Path;sha256=$actualAiBundleHash;bytes=(Get-Item -LiteralPath $aiBundlePath).Length}
    }
    if ([string]$context.vmName -notlike 'DevFleet-E2E-*') { throw 'LINUX phase requires an ownership-scoped disposable L1.' }
    if ($env:COMPUTERNAME -notmatch '^MULATTOTechBOX$|^MULATTOTECHBOX$' -or $env:COMPUTERNAME -match 'SURFACE') { throw 'LINUX phase is not running on the approved MULATTOTECHBOX host.' }
    $l1 = Get-VM -Id ([guid][string]$context.vmId) -ErrorAction Stop
    if ($l1.Name -cne [string]$context.vmName) { throw 'LINUX phase disposable L1 identity/name mismatch.' }
    $vmProcessor = Get-VMProcessor -VM $l1 -ErrorAction Stop
    if (-not [bool]$vmProcessor.ExposeVirtualizationExtensions) { throw 'Disposable L1 does not expose nested virtualization.' }
    $nested = $context.config.NestedLinux
    if (-not $nested) { throw 'E2E config is missing the NestedLinux resource policy.' }
    $l2Name = [string]$nested.Name
    $l2Image = [string]$nested.UbuntuImage
    $l2Cpus = [int]$nested.Cpus
    $l2Memory = [string]$nested.Memory
    $l2Disk = [string]$nested.Disk
    $budgetPolicy = Get-HarnessBudgetPolicy -Config $context.config
    $l2BootstrapTimeout = [int]$budgetPolicy.operationMaximumsSeconds.guestBootstrap
    if ($l2Name -notlike 'DevFleet-E2E-*' -or $l2Name -eq ([string]$context.vmName)) { throw 'Nested Linux identity is outside the disposable E2E namespace.' }
    if ($l2Cpus -lt 1 -or $l2BootstrapTimeout -lt 1) { throw 'Nested Linux resource policy contains an invalid positive integer.' }
    # Each FullRelease phase restores its declared checkpoint independently.
    # The clean checkpoint intentionally has no product prerequisites, so the
    # Linux phase must exercise the candidate's real install path in this same
    # phase before asking the installed L1 to provide Multipass.
    $productInstall = Invoke-SupportedFreshInstallLifecycle -Context $context -Role 'Primary / Desktop' -CompleteLifecycle
    if ([string]$productInstall.status -ne 'REAL E2E PASS' -or -not [bool]$productInstall.guest.completionVerified) {
        throw "LINUX requires a genuine supported FreshInstall lifecycle PASS before Multipass; observed $($productInstall.status)."
    }
    $bootstrapTransactionId = [string]$productInstall.transactionId
    $bootstrapPayloadSha256 = [string]$context.candidate.tar.sha256
    $bootstrapPackageVersion = [string]$context.candidate.releaseVersion
    $bootstrapNodeRole = 'surrogate'
    if ($bootstrapTransactionId -notmatch '^[0-9a-fA-F]{32}$' -or
        $bootstrapPayloadSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $bootstrapPackageVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw 'LINUX product lifecycle did not return an exact bootstrap transaction, payload, or package identity.'
    }
    # The supported Desktop lifecycle leaves its exact product Multipass child
    # running after completion. A fixed 16 GiB nested L1 cannot safely allocate
    # that product child and the independent 4 GiB Linux L2 at the same time.
    # Quiesce only the candidate-bound product identity after its completion
    # authority has passed; never infer ownership from the harness L2 name.
    $productComputeName = Get-DevFleetProductComputeInstanceName -Context $context -Role 'Primary / Desktop'
    if ($productComputeName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$' -or $productComputeName -eq $l2Name -or $productComputeName -like 'DevFleet-E2E-*') {
        throw 'LINUX product compute identity is malformed or overlaps the disposable L2 namespace.'
    }
    $session = $null
    try {
        $session = Connect-DevFleetGuest -VmId ([guid][string]$context.vmId)
        $remoteRoot = "C:\Users\Public\DevFleet-E2E\$($context.runId)\$($context.phaseId)"
        $remoteTar = Join-Path $remoteRoot (Split-Path -Leaf $tarPath)
        Invoke-Command -Session $session -ScriptBlock { param($root) New-Item -ItemType Directory -Force -Path $root | Out-Null } -ArgumentList $remoteRoot
        $stage = Get-StageIntegrity -LocalPath $tarPath -Session $session -RemotePath $remoteTar
        if (-not $stage.equal) { throw 'Exact candidate TAR did not survive host-to-L1 staging.' }
        $remoteAiBundle = $null
        $aiBundleStage = $null
        if ($aiBundle) {
            $remoteAiBundle = Join-Path $remoteRoot (Split-Path -Leaf ([string]$aiBundle.path))
            $aiBundleStage = Get-StageIntegrity -LocalPath ([string]$aiBundle.path) -Session $session -RemotePath $remoteAiBundle
            if (-not $aiBundleStage.equal -or ([string]$aiBundleStage.remoteSha256).ToLowerInvariant() -ne [string]$aiBundle.sha256) { throw 'Exact AI audit ZIP did not survive host-to-L1 staging.' }
        }
        $secretJson = [ordered]@{
            NodeName=$l2Name; NodeRole='surrogate'; FriendlyName='DevFleet E2E Linux'; PortalPort=8787
            DeploymentId=("e2e-$($context.runId)"); NodeId=([guid]::NewGuid().ToString()); CoordinatorNodeId=''
            ProtocolVersion=1; AdminUser='e2e-admin'; AdminPassword=('E2E-' + [guid]::NewGuid().ToString('N')); ApiToken=('e2e-token-' + [guid]::NewGuid().ToString('N'))
            GitName='DevFleet E2E'; GitEmail='e2e@example.invalid'; OllamaBas