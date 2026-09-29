# DevFleet source part 023

Full-source UTF-8 byte interval [1023000, 1069500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 50840ab12f413a73e7976e45352e992ace056f6a1c12e330bf05ad2823d3b842

<!-- BEGIN SOURCE SLICE -->
epare|resume|cleanup)\z'){throw 'REAL_USE_DRIVER_UNIT_NAME_INVALID'}
                $probe=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','systemctl','show',$Unit,'--property=LoadState','--property=ActiveState','--property=MainPID') -TimeoutSeconds 30
                if($probe.exitCode-ne 0){throw 'REAL_USE_DRIVER_UNIT_OBSERVATION_FAILED'}
                $fields=@{};foreach($line in @($probe.stdout)){if([string]$line-cnotmatch'\A(LoadState|ActiveState|MainPID)=(.*)\z'-or$fields.ContainsKey($matches[1])){throw 'REAL_USE_DRIVER_UNIT_STATE_INVALID'};$fields[$matches[1]]=$matches[2]}
                if($fields.Count-ne 3-or-not$fields.ContainsKey('LoadState')-or-not$fields.ContainsKey('ActiveState')-or-not$fields.ContainsKey('MainPID')-or[string]$fields.MainPID-cnotmatch'\A[0-9]+\z'){throw 'REAL_USE_DRIVER_UNIT_STATE_INVALID'}
                $load=[string]$fields.LoadState;$active=[string]$fields.ActiveState;$mainPid=[int64]$fields.MainPID
                if($load-ceq'not-found'){if($active-cne'inactive'-or$mainPid-ne 0){throw 'REAL_USE_DRIVER_UNIT_STATE_INVALID'};return [pscustomobject]@{loadState=$load;activeState=$active;mainPid=$mainPid;exists=$false}}
                if($load-cne'loaded'-or$active-notin@('active','activating','reloading','deactivating','inactive','failed','dead')){throw 'REAL_USE_DRIVER_UNIT_STATE_INVALID'}
                return [pscustomobject]@{loadState=$load;activeState=$active;mainPid=$mainPid;exists=$true}
            }
            function Confirm-DriverUnitQuiescent([string]$Unit,[switch]$StopIfRunning){$observation=Get-DriverUnitState $Unit;if($observation.activeState-in@('active','activating','reloading','deactivating')-or$observation.mainPid-ne 0){if(-not$StopIfRunning){throw 'REAL_USE_DRIVER_UNIT_STILL_ACTIVE'};$stop=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','systemctl','stop',$Unit) -TimeoutSeconds 120;if($stop.exitCode-ne 0){throw 'REAL_USE_DRIVER_UNIT_STOP_FAILED'}};$deadline=[datetime]::UtcNow.AddSeconds(60);do{$observation=Get-DriverUnitState $Unit;if((-not$observation.exists-or$observation.activeState-in@('inactive','failed','dead'))-and$observation.mainPid-eq 0){return $true};Start-Sleep -Seconds 2}while([datetime]::UtcNow-lt$deadline);throw 'REAL_USE_DRIVER_UNIT_QUIESCENCE_UNPROVEN'}
            function Invoke-DriverStage([string]$Stage,[string]$Output,[int]$Timeout){$unit="devfleet-real-use-$unitHash-$Stage";$driverUnits.Add($unit)|Out-Null;$runtime=[Math]::Max(1,$Timeout-60);try{$call=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','systemd-run','--wait','--pipe','--collect','--quiet',"--unit=$unit",'-p','Type=exec','-p','User=devfleet-control','-p','Group=devfleet-control','-p','SupplementaryGroups=devrunner','-p',"RuntimeMaxSec=${runtime}s",'-p','TimeoutStopSec=30s','-p','KillMode=control-group','/usr/bin/env','-i','PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','LANG=C.UTF-8','/bin/bash','-c',$driverWrapper,'devfleet-real-use-driver',$l2Runner,'--stage',$Stage,'--input',$inputPath,'--state',$statePath,'--output',$Output) -TimeoutSeconds $Timeout;Confirm-DriverUnitQuiescent $unit|Out-Null;return $call}catch{$stageError=$_.Exception;try{Confirm-DriverUnitQuiescent $unit -StopIfRunning|Out-Null}catch{throw 'REAL_USE_DRIVER_UNIT_QUIESCENCE_FAILED'};throw $stageError}}
            function Read-Report([string]$Path,[string]$Code){$value=Invoke-RequiredMultipass @('exec',$compute,'--','sudo','cat',$Path) 60 $Code;try{return (($value.stdout-join"`n")|ConvertFrom-Json -ErrorAction Stop)}catch{throw $Code}}
            function Test-DriverCleanupProven([AllowNull()][object]$Report){
                if(-not$Report-or[int]$Report.schemaVersion-ne 1-or[string]$Report.contract-cne'devfleet-real-use-acceptance-v1'-or[string]$Report.runId-cne[string]$request.runId-or[string]$Report.phaseId-cne'REAL-USE-ACCEPTANCE'-or[string]$Report.runnerSha256-cne[string]$expectedRunnerHash){return $false}
                if([string]$Report.stage-notin@('prepare','resume','cleanup')-or[string]$Report.cleanup.status-cne'PASS'-or$Report.cleanup.ownedOnly-isnot[bool]-or-not[bool]$Report.cleanup.ownedOnly-or@($Report.cleanup.errors).Count-ne 0-or$null-ne$Report.cleanupFailure){return $false}
                if(([string]$Report.stage-ceq'resume'-and[string]$Report.status-cne'PASS')-or([string]$Report.stage-ceq'cleanup'-and[string]$Report.status-cne'BLOCKED')-or([string]$Report.stage-ceq'prepare'-and[string]$Report.status-cne'BLOCKED')){return $false}
                foreach($resource in @($Report.cleanup.resources)){if([string]::IsNullOrWhiteSpace([string]$resource.kind)-or[string]::IsNullOrWhiteSpace([string]$resource.path)-or[string]$resource.status-notin@('ABSENT','REMOVED')){return $false}}
                return $true
            }
            try{
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','install','-d','-o','root','-g','root','-m','0755','/var/lib/devfleet/e2e-real-use') 60 'REAL_USE_PARENT_ROOT_CREATE_FAILED')
                $parentStat=Read-MultipassLine @('exec',$compute,'--','sudo','stat','-c','%U:%G:%a:%F','/var/lib/devfleet/e2e-real-use') 'REAL_USE_PARENT_ROOT_POLICY_INVALID';if($parentStat-cne'root:root:755:directory'){throw 'REAL_USE_PARENT_ROOT_POLICY_INVALID'}
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','mkdir','--',$l2Root) 60 'REAL_USE_L2_ROOT_COLLISION_OR_CREATE_FAILED');$l2RootOwned=$true
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chown','root:devfleet-control','--',$l2Root) 60 'REAL_USE_OWNED_ROOT_OWNER_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chmod','0750','--',$l2Root) 60 'REAL_USE_OWNED_ROOT_MODE_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','mkdir','--',$incoming) 60 'REAL_USE_INCOMING_COLLISION_OR_CREATE_FAILED');$incomingOwned=$true
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chown','ubuntu:ubuntu','--',$incoming) 60 'REAL_USE_INCOMING_OWNER_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chmod','0700','--',$incoming) 60 'REAL_USE_INCOMING_MODE_FAILED')
                [void](Invoke-RequiredMultipass @('transfer',$runner,"$compute`:$incomingRunner") 300 'REAL_USE_RUNNER_TRANSFER_FAILED')
                $incomingHash=(Read-MultipassLine @('exec',$compute,'--','sha256sum',$incomingRunner) 'REAL_USE_INCOMING_RUNNER_HASH_MISSING').Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant();if($incomingHash-cne$expectedRunnerHash){throw 'REAL_USE_INCOMING_RUNNER_HASH_MISMATCH'}
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chown','-R','root:root','--',$incoming) 60 'REAL_USE_INCOMING_LOCK_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','install','-T','-o','root','-g','root','-m','0555',$incomingRunner,$l2Runner) 60 'REAL_USE_RUNNER_PROMOTION_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','rm','-rf','--',$incoming) 60 'REAL_USE_INCOMING_CLEANUP_FAILED');$incomingOwned=$false
                $l2RunnerHash=(Read-MultipassLine @('exec',$compute,'--','sudo','sha256sum',$l2Runner) 'REAL_USE_L2_RUNNER_HASH_MISSING').Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant();if($l2RunnerHash-cne$expectedRunnerHash){throw 'REAL_USE_L2_RUNNER_HASH_MISMATCH'}
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','install','-d','-o','devfleet-control','-g','devfleet-control','-m','0700',$stateDir) 60 'REAL_USE_STATE_DIRECTORY_INVALID')
                $input=[ordered]@{schemaVersion=1;runId=[string]$request.runId;deadlineUtc=[string]$request.deadlineUtc;runnerSha256=$expectedRunnerHash;candidate=$request.candidate;execution=[ordered]@{role='Laptop / Surrogate';vmName=[string]$request.vmName;vmId=[string]$request.vmId;computeInstanceName=$compute;vaultInstanceName=$vault;deploymentId=[string]$computeIdentity.deployment_id;nodeId=[string]$computeIdentity.node_id;nodeName=[string]$computeIdentity.node_name;transactionId=[string]$request.transactionId;invocationId=[string]$request.invocationId;surrogateEvidenceSha256=[string]$request.surrogateEvidenceSha256};paths=[ordered]@{workspaces=[string]$computeConfig.workspaces;quarantine=[string]$computeConfig.quarantine;runtimeRoot=[string]$computeConfig.runtime_root};baseUrl=('http://127.0.0.1:{0}'-f[int]$computeConfig.portal_port)}
                $inputJson=$input|ConvertTo-Json -Depth 12 -Compress;$inputBytes=[Text.Encoding]::UTF8.GetBytes($inputJson);$inputBase64=[Convert]::ToBase64String($inputBytes);$sha=[Security.Cryptography.SHA256]::Create();try{$inputHash=($sha.ComputeHash($inputBytes)|ForEach-Object{$_.ToString('x2')})-join''}finally{$sha.Dispose()}
                $writeScript='set -Eeuo pipefail; umask 027; printf %s "$1" | base64 -d > "$2"; chown root:devfleet-control "$2"; chmod 0640 "$2"'
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','bash','-c',$writeScript,'devfleet-real-use-input',$inputBase64,$inputPath) 60 'REAL_USE_INPUT_WRITE_FAILED')
                $remoteInputHash=(Read-MultipassLine @('exec',$compute,'--','sudo','sha256sum',$inputPath) 'REAL_USE_INPUT_HASH_MISSING').Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant();if($remoteInputHash-cne$inputHash){throw 'REAL_USE_INPUT_HASH_MISMATCH'}
                $preflight=[ordered]@{laptopInstalled=$true;failoverReady=$true;vaultReady=$true;brokerReady=$true;tailscaleReady=$true;secretFilePolicy=$true;credentialBoundary=$true}
                $stageEvidence=[ordered]@{l1Sha256=$expectedRunnerHash;l2Sha256=$l2RunnerHash;inputSha256=$inputHash;onlyRunnerStaged=$true}
                $remaining=[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)-[int]$request.cleanupReserveSeconds;if($remaining-lt 1){throw 'REAL_USE_OWNER_DEADLINE_EXHAUSTED'};$prepareBudget=[Math]::Min([int]$request.prepareTimeoutSeconds,$remaining);$prepareCall=Invoke-DriverStage 'prepare' $preparePath $prepareBudget;$prepareExit=$prepareCall.exitCode;$prepareReport=Read-Report $preparePath 'REAL_USE_PREPARE_REPORT_INVALID'
                if($prepareCall.exitCode-ne 0-or[string]$prepareReport.status-cne'PREPARED'){
                    $cleanupRemaining=[Math]::Max(1,[Math]::Min([int]$request.cleanupReserveSeconds,[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)));$cleanupCall=Invoke-DriverStage 'cleanup' $cleanupPath $cleanupRemaining;$cleanupExit=$cleanupCall.exitCode;try{$cleanupReport=Read-Report $cleanupPath 'REAL_USE_CLEANUP_REPORT_INVALID'}catch{}
                    $transportResult=[pscustomobject][ordered]@{input=$input;preflight=$preflight;stage=$stageEvidence;prepareReport=$prepareReport;prepareExitCode=$prepareExit;restart=$null;resumeReport=$null;resumeExitCode=$null;cleanupReport=$cleanupReport;cleanupExitCode=$cleanupExit;ownedRootRemoved=$false}
                }else{
                    $before=Read-MultipassLine @('exec',$compute,'--','systemctl','show','devfleet.service','--property=InvocationID','--value') 'REAL_USE_SERVICE_INVOCATION_MISSING';if($before-cnotmatch'^[0-9a-f]{32}$'){throw 'REAL_USE_SERVICE_INVOCATION_INVALID'}
                    [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','systemctl','restart','devfleet.service') 120 'REAL_USE_EXACT_SERVICE_RESTART_FAILED')
                    $restartDeadline=[datetime]::UtcNow.AddSeconds(120);$after='';do{$active=Invoke-RealUseMultipass @('exec',$compute,'--','systemctl','is-active','--quiet','devfleet.service') 30;if($active.exitCode-eq 0){try{$after=Read-MultipassLine @('exec',$compute,'--','systemctl','show','devfleet.service','--property=InvocationID','--value') 'REAL_USE_SERVICE_INVOCATION_MISSING'}catch{$after=''};if($after-match'^[0-9a-f]{32}$'-and$after-cne$before){break}};Start-Sleep -Seconds 2}while([datetime]::UtcNow-lt$restartDeadline)
                    if($after-cnotmatch'^[0-9a-f]{32}$'-or$after-ceq$before){throw 'REAL_USE_EXACT_SERVICE_RESTART_UNPROVEN'};$restartEvidence=[ordered]@{unit='devfleet.service';invocationChanged=($after-cne$before);otherUnitsRestarted=$false}
                    $remaining=[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)-[int]$request.cleanupReserveSeconds;if($remaining-lt 1){throw 'REAL_USE_OWNER_DEADLINE_EXHAUSTED'};$resumeCall=Invoke-DriverStage 'resume' $resumePath $remaining;$resumeExit=$resumeCall.exitCode;$resumeReport=Read-Report $resumePath 'REAL_USE_RESUME_REPORT_INVALID'
                    if($resumeCall.exitCode-ne 0-or[string]$resumeReport.status-cne'PASS'){$cleanupRemaining=[Math]::Max(1,[Math]::Min([int]$request.cleanupReserveSeconds,[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)));$cleanupCall=Invoke-DriverStage 'cleanup' $cleanupPath $cleanupRemaining;$cleanupExit=$cleanupCall.exitCode;try{$cleanupReport=Read-Report $cleanupPath 'REAL_USE_CLEANUP_REPORT_INVALID'}catch{}}
                    $transportResult=[pscustomobject][ordered]@{input=$input;preflight=$preflight;stage=$stageEvidence;prepareReport=$prepareReport;prepareExitCode=$prepareExit;restart=$restartEvidence;resumeReport=$resumeReport;resumeExitCode=$resumeExit;cleanupReport=$cleanupReport;cleanupExitCode=$cleanupExit;ownedRootRemoved=$false}
                }
            }catch{
                $primaryError=$_.Exception
                if($input){
                    # An interrupted prepare/resume may have created product
                    # fixtures before its terminal report.  Prove every exact
                    # transient unit quiescent, then use the driver's explicit
                    # cleanup stage against the preserved ownership journal.
                    $recoveryQuiescent=$true
                    try{foreach($unit in $driverUnits){Confirm-DriverUnitQuiescent $unit -StopIfRunning|Out-Null}}catch{$recoveryQuiescent=$false;$cleanupError=$_.Exception}
                    if($recoveryQuiescent-and-not(Test-DriverCleanupProven $prepareReport)-and-not(Test-DriverCleanupProven $resumeReport)-and-not(Test-DriverCleanupProven $cleanupReport)){
                        $cleanupRemaining=[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)
                        if($cleanupRemaining-gt 60){
                            $cleanupRemaining=[Math]::Min([int]$request.cleanupReserveSeconds,$cleanupRemaining)
                            try{$cleanupCall=Invoke-DriverStage 'cleanup' $cleanupPath $cleanupRemaining;$cleanupExit=$cleanupCall.exitCode;$cleanupReport=Read-Report $cleanupPath 'REAL_USE_CLEANUP_REPORT_INVALID'}catch{if(-not$cleanupError){$cleanupError=$_.Exception}}
                        }elseif(-not$cleanupError){$cleanupError=[Exception]::new('REAL_USE_CLEANUP_DEADLINE_EXHAUSTED')}
                    }
                    if(-not$prepareReport){try{$prepareReport=Read-Report $preparePath 'REAL_USE_PREPARE_REPORT_SALVAGE_FAILED'}catch{}}
                    if(-not$resumeReport){try{$resumeReport=Read-Report $resumePath 'REAL_USE_RESUME_REPORT_SALVAGE_FAILED'}catch{}}
                    if(-not$cleanupReport){try{$cleanupReport=Read-Report $cleanupPath 'REAL_USE_CLEANUP_REPORT_SALVAGE_FAILED'}catch{}}
                    $transportResult=[pscustomobject][ordered]@{input=$input;preflight=$preflight;stage=$stageEvidence;prepareReport=$prepareReport;prepareExitCode=$prepareExit;restart=$restartEvidence;resumeReport=$resumeReport;resumeExitCode=$resumeExit;cleanupReport=$cleanupReport;cleanupExitCode=$cleanupExit;ownedRootRemoved=$false}
                }
            }finally{
                try{
                    foreach($unit in $driverUnits){Confirm-DriverUnitQuiescent $unit -StopIfRunning|Out-Null}
                    if($incomingOwned){$removeIncoming=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','rm','-rf','--',$incoming) -TimeoutSeconds 120;if($removeIncoming.exitCode-ne 0){throw 'REAL_USE_INCOMING_FINAL_CLEANUP_FAILED'};$incomingGone=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','test','!','-e',$incoming) -TimeoutSeconds 60;if($incomingGone.exitCode-ne 0){throw 'REAL_USE_INCOMING_FINAL_CLEANUP_UNPROVEN'}}
                    $cleanupProven=(Test-DriverCleanupProven $prepareReport)-or(Test-DriverCleanupProven $resumeReport)-or(Test-DriverCleanupProven $cleanupReport)
                    if($l2RootOwned-and($driverUnits.Count-eq 0-or$cleanupProven)){$remove=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','rm','-rf','--',$l2Root) -TimeoutSeconds 120;if($remove.exitCode-ne 0){throw 'REAL_USE_OWNED_ROOT_FINAL_CLEANUP_FAILED'};$rootGone=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','test','!','-e',$l2Root) -TimeoutSeconds 60;if($rootGone.exitCode-ne 0){throw 'REAL_USE_OWNED_ROOT_FINAL_CLEANUP_UNPROVEN'};$l2RootRemoved=$true}
                    elseif($l2RootOwned){$retainL2Root=$true;if(-not$cleanupError){$cleanupError=[Exception]::new('REAL_USE_OWNED_ROOT_RETAINED_FOR_RECOVERY')}}
                }catch{if(-not$cleanupError){$cleanupError=$_.Exception};if($l2RootOwned-and-not$l2RootRemoved){$retainL2Root=$true}}
            }
            function Get-FixedTransportCode([Exception]$ErrorValue,[string]$Fallback){if(-not$ErrorValue){return''};$match=[regex]::Match([string]$ErrorValue.Message,'REAL_USE_[A-Z0-9_]+');if($match.Success){return$match.Value};return$Fallback}
            if($transportResult){
                $transportResult.ownedRootRemoved=[bool]$l2RootRemoved
                if($primaryError){$transportResult|Add-Member -NotePropertyName transportError -NotePropertyValue (Get-FixedTransportCode $primaryError 'REAL_USE_TRANSPORT_FAILED') -Force}
                if($cleanupError){$transportResult|Add-Member -NotePropertyName transportCleanupError -NotePropertyValue (Get-FixedTransportCode $cleanupError 'REAL_USE_TRANSPORT_CLEANUP_BLOCKED') -Force}
                return $transportResult
            }
            if($primaryError){throw (Get-FixedTransportCode $primaryError 'REAL_USE_TRANSPORT_FAILED')}
            if($cleanupError){throw (Get-FixedTransportCode $cleanupError 'REAL_USE_TRANSPORT_CLEANUP_BLOCKED')}
            return $transportResult
        } -ArgumentList $remoteRunner,[string]$Request.runnerSha256,$Request
        if (-not $result) { throw 'REAL_USE_TRANSPORT_RETURNED_NO_RESULT' }
    } catch {
        $outerError = $_.Exception
    } finally {
        if ($session) {
            try {
                if($l1RootOwned){
                    Invoke-Command -Session $session -ScriptBlock {
                        param($path)
                        if($path -notlike 'C:\Users\Public\DevFleet-E2E\*\REAL-USE-ACCEPTANCE'){throw 'REAL_USE_L1_ROOT_INVALID'}
                        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop}
                        if(Test-Path -LiteralPath $path){throw 'REAL_USE_L1_ROOT_CLEANUP_FAILED'}
                    } -ArgumentList $remoteRoot
                    $l1RootRemoved = $true
                }
            } catch {
                $l1CleanupError = $_.Exception
            } finally {
                Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue
            }
        }
    }
    $fixedCode = {
        param([AllowNull()][Exception]$ErrorValue,[string]$Fallback)
        if(-not$ErrorValue){return ''}
        $match=[regex]::Match([string]$ErrorValue.Message,'REAL_USE_[A-Z0-9_]+')
        if($match.Success){return $match.Value}
        return $Fallback
    }
    if($result){
        if($result.stage){
            $result.stage | Add-Member -NotePropertyName l1Path -NotePropertyValue $remoteRunner -Force
            $result.stage | Add-Member -NotePropertyName ownedRootsRemoved -NotePropertyValue ([bool]($l1RootRemoved -and [bool]$result.ownedRootRemoved)) -Force
        }
        if($outerError -and -not $result.PSObject.Properties['transportError']){$result|Add-Member -NotePropertyName transportError -NotePropertyValue (&$fixedCode $outerError 'REAL_USE_L1_TRANSPORT_FAILED') -Force}
        if($l1CleanupError){$result|Add-Member -NotePropertyName transportCleanupError -NotePropertyValue (&$fixedCode $l1CleanupError 'REAL_USE_L1_ROOT_CLEANUP_FAILED') -Force}
        return $result
    }
    if($outerError){throw (&$fixedCode $outerError 'REAL_USE_L1_TRANSPORT_FAILED')}
    if($l1CleanupError){throw (&$fixedCode $l1CleanupError 'REAL_USE_L1_ROOT_CLEANUP_FAILED')}
    throw 'REAL_USE_TRANSPORT_RETURNED_NO_RESULT'
}

function Invoke-RealUseAcceptancePhase {
    param(
        [Parameter(Mandatory)][object]$Context,
        [scriptblock]$TransportProvider
    )
    $binding = Get-RealUseAcceptanceSurrogateBinding -Context $Context
    $candidateItem = Get-Item -LiteralPath ([string]$Context.candidate.candidate.path) -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $candidateItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$binding.candidate.exeSha256 -or [int64]$candidateItem.Length -ne [int64]$Context.candidate.candidate.bytes) { throw 'REAL-USE-ACCEPTANCE exact candidate changed before execution.' }
    $runnerPath = Join-Path ([string]$Context.workspaceRoot) 'automation\release-e2e\modules\executors\Invoke-RealUseAcceptance.py'
    if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) { throw 'REAL-USE-ACCEPTANCE runner is missing.' }
    $runnerHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $timeoutSeconds = $script:RealUseAcceptanceOwnerTimeoutSeconds
    if ($Context.config -and $Context.config.PSObject.Properties['RealUseAcceptance'] -and $Context.config.RealUseAcceptance.PSObject.Properties['TimeoutSeconds']) { $timeoutSeconds = [int]$Context.config.RealUseAcceptance.TimeoutSeconds }
    if ($timeoutSeconds -lt 27000 -or $timeoutSeconds -gt $script:RealUseAcceptanceOwnerTimeoutSeconds) { throw 'REAL-USE-ACCEPTANCE timeout policy is outside the bounded supported range.' }
    $deadlineUtc = [datetime]::UtcNow.AddSeconds($timeoutSeconds).ToString('o')
    $request = [pscustomobject][ordered]@{
        runId=$binding.runId;phaseId=$script:RealUseAcceptancePhase;vmName=$binding.vmName;vmId=$binding.vmId;candidate=$binding.candidate
        transactionId=$binding.transactionId;invocationId=$binding.invocationId;computeInstanceName=$binding.computeInstanceName;vaultInstanceName=$binding.vaultInstanceName
        deploymentId=$binding.deploymentId;nodeId=$binding.nodeId;primaryNodeId=$binding.primaryNodeId;vaultNodeId=$binding.vaultNodeId
        clusterJoinEvidencePath=$binding.clusterJoinEvidencePath;clusterJoinEvidenceSha256=$binding.clusterJoinEvidenceSha256;primaryPairingEvidencePath=$binding.primaryPairingEvidencePath;primaryPairingEvidenceSha256=$binding.primaryPairingEvidenceSha256
        surrogateEvidenceSha256=$binding.surrogateEvidenceSha256;runnerPath=$runnerPath;runnerSha256=$runnerHash;deadlineUtc=$deadlineUtc
        ownerTimeoutSeconds=$timeoutSeconds;prepareTimeoutSeconds=$script:RealUseAcceptancePrepareTimeoutSeconds;cleanupReserveSeconds=$script:RealUseAcceptanceCleanupReserveSeconds
    }
    $transport = if ($TransportProvider) { & $TransportProvider $request } else { Invoke-RealUseAcceptanceTransport -Request $request }
    if (-not $transport -or -not $transport.input) { throw 'REAL-USE-ACCEPTANCE transport returned no request-bound input evidence.' }
    Assert-RealUseAcceptanceInput -Input $transport.input -Request $request | Out-Null
    $transportError = if ($transport.PSObject.Properties['transportError']) { [string]$transport.transportError } else { '' }
    $transportCleanupError = if ($transport.PSObject.Properties['transportCleanupError']) { [string]$transport.transportCleanupError } else { '' }
    foreach ($code in @($transportError,$transportCleanupError) | Where-Object { $_ }) { if ($code -cnotmatch '^REAL_USE_[A-Z0-9_]+$') { throw 'REAL-USE-ACCEPTANCE transport returned an unsafe failure classification.' } }
    $cleanupEvidence = $null
    if (-not $transport.prepareReport) {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        throw "REAL-USE-ACCEPTANCE transport returned no prepare report${cleanupSuffix}."
    }
    $preparePath = Join-Path ([string]$Context.runDir) 'real-use-acceptance-prepare.json'
    $prepareEvidence = Write-RealUseAcceptanceDriverEvidence -Report $transport.prepareReport -AcceptanceInput $transport.input -ExpectedStage prepare -AllowedStatus @('PREPARED','BLOCKED') -Path $preparePath -AllowInitializationEnvelope
    $prepareHash = [string]$prepareEvidence.sha256
    if ([int]$transport.prepareExitCode -ne 0 -or [string]$transport.prepareReport.status -cne 'PREPARED') {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        $transportSuffix = if ($transportError) { "; transport=$transportError" } else { '' }
        if ($transportCleanupError) { $transportSuffix += "; transportCleanup=$transportCleanupError" }
        throw "REAL-USE-ACCEPTANCE prepare did not reach its restart boundary; evidence=$preparePath; sha256=$prepareHash${transportSuffix}${cleanupSuffix}."
    }
    if (-not $transport.restart -or [string]$transport.restart.unit -cne 'devfleet.service' -or -not [bool]$transport.restart.invocationChanged -or [bool]$transport.restart.otherUnitsRestarted) {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        $transportSuffix = if ($transportError) { "; transport=$transportError" } else { '' }
        if ($transportCleanupError) { $transportSuffix += "; transportCleanup=$transportCleanupError" }
        throw "REAL-USE-ACCEPTANCE exact service restart was not proven; prepareEvidence=$preparePath; prepareSha256=$prepareHash${transportSuffix}${cleanupSuffix}."
    }
    if (-not $transport.resumeReport) {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        throw "REAL-USE-ACCEPTANCE resume returned no report${cleanupSuffix}."
    }
    $reportPath = Join-Path ([string]$Context.runDir) 'real-use-acceptance-report.json'
    $reportEvidence = Write-RealUseAcceptanceDriverEvidence -Report $transport.resumeReport -AcceptanceInput $transport.input -ExpectedStage resume -AllowedStatus @('PASS','BLOCKED') -Path $reportPath -AllowInitializationEnvelope
    $reportHash = [string]$reportEvidence.sha256
    if ([int]$transport.resumeExitCode -ne 0 -or [string]$transport.resumeReport.status -cne 'PASS' -or $transportError) {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        $transportSuffix = if ($transportError) { "; transport=$transportError" } else { '' }
        if ($transportCleanupError) { $transportSuffix += "; transportCleanup=$transportCleanupError" }
        throw "REAL-USE-ACCEPTANCE resume did not reach PASS; evidence=$reportPath; sha256=$reportHash${transportSuffix}${cleanupSuffix}."
    }
    Assert-RealUseAcceptanceReport -Report $transport.resumeReport -Input $transport.input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass | Out-Null
    foreach ($field in @('laptopInstalled','failoverReady','vaultReady','brokerReady','tailscaleReady','secretFilePolicy','credentialBoundary')) { if (-not [bool]$transport.preflight.$field) { throw 'REAL-USE-ACCEPTANCE installed prerequisite evidence is incomplete.' } }
    if (-not [bool]$transport.stage.onlyRunnerStaged -or [string]$transport.stage.l1Sha256 -cne $runnerHash -or [string]$transport.stage.l2Sha256 -cne $runnerHash -or [string]$transport.stage.inputSha256 -cnotmatch '^[0-9a-f]{64}$' -or -not [bool]$transport.stage.ownedRootsRemoved -or -not [bool]$transport.ownedRootRemoved) { throw 'REAL-USE-ACCEPTANCE runner transport or owned-root cleanup is incomplete.' }
    $bindingPath = Join-Path ([string]$Context.runDir) 'real-use-acceptance-binding.json'
    $bindingEvidence = [ordered]@{schemaVersion=1;contract=$script:RealUseAcceptanceContract;runId=$binding.runId;phaseId=$script:RealUseAcceptancePhase;precedingPhase='SURROGATE-DISPOSABLE';candidate=$transport.input.candidate;execution=$transport.input.execution;deadlineUtc=$deadlineUtc;runner=[ordered]@{path=$runnerPath;sha256=$runnerHash};surrogate=[ordered]@{evidencePath=$binding.surrogateEvidencePath;evidenceSha256=$binding.surrogateEvidenceSha256;phaseRecordsPath=$binding.phaseRecordsPath;phaseRecordsSha256=$binding.phaseRecordsSha256};clusterJoin=[ordered]@{evidencePath=$binding.clusterJoinEvidencePath;evidenceSha256=$binding.clusterJoinEvidenceSha256;primaryPairingEvidencePath=$binding.primaryPairingEvidencePath;primaryPairingEvidenceSha256=$binding.primaryPairingEvidenceSha256};installedPaths=$transport.input.paths;baseUrl=$transport.input.baseUrl}
    Write-EvidenceJson -Path $bindingPath -Value $bindingEvidence
    $bindingHash = (Get-FileHash -LiteralPath $bindingPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $summaryPath = Join-Path ([string]$Context.runDir) 'real-use-acceptance-evidence.json'
    $summary = [ordered]@{schemaVersion=1;contract='devfleet-real-use-acceptance-evidence-v1';status='PASS';runId=$binding.runId;phaseId=$script:RealUseAcceptancePhase;candidate=$transport.input.candidate;execution=$transport.input.execution;preflight=$transport.preflight;transport=$transport.stage;restart=$transport.restart;journeys=@($transport.resumeReport.journeys|ForEach-Object{[ordered]@{id=[string]$_.id;status=[string]$_.status}});cleanup=[ordered]@{status=[string]$transport.resumeReport.cleanup.status;ownedOnly=[bool]$transport.resumeReport.cleanup.ownedOnly;vaultSnapshots=[string]$transport.resumeReport.cleanup.vaultSnapshots};evidence=[ordered]@{binding=[ordered]@{path=$bindingPath;sha256=$bindingHash};prepare=[ordered]@{path=$preparePath;sha256=$prepareHash};report=[ordered]@{path=$reportPath;sha256=$reportHash}};credentialsStoredInEvidence=$false;internalPromotionAllowed=$false}
    Write-EvidenceJson -Path $summaryPath -Value $summary
    $summaryHash = (Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    return [ordered]@{status='REAL E2E PASS';phase=$script:RealUseAcceptancePhase;contract='devfleet-real-use-acceptance-phase-v1';candidate=$transport.input.candidate;binding=$bindingEvidence;report=$transport.resumeReport;preflight=$transport.preflight;transport=$transport.stage;restart=$transport.restart;evidence=[ordered]@{bindingPath=$bindingPath;bindingSha256=$bindingHash;preparePath=$preparePath;prepareSha256=$prepareHash;reportPath=$reportPath;reportSha256=$reportHash;summaryPath=$summaryPath;summarySha256=$summaryHash};credentialsStoredInEvidence=$false;internalPromotionAllowed=$false}
}

function Assert-RealUseAcceptancePhaseEvidence {
    param([Parameter(Mandatory)][object]$PhaseResult, [Parameter(Mandatory)][object]$Context)
    $phaseFields = @('status','phase','contract','candidate','binding','report','preflight','transport','restart','evidence','credentialsStoredInEvidence','internalPromotionAllowed')
    Assert-RealUseAcceptanceKeys -Value $PhaseResult -Allowed $phaseFields -Required $phaseFields -Label 'REAL-USE-ACCEPTANCE phase result' | Out-Null
    if ([string]$PhaseResult.status -cne 'REAL E2E PASS' -or [string]$PhaseResult.phase -cne $script:RealUseAcceptancePhase -or [string]$PhaseResult.contract -cne 'devfleet-real-use-acceptance-phase-v1' -or $PhaseResult.credentialsStoredInEvidence -isnot [bool] -or [bool]$PhaseResult.credentialsStoredInEvidence -or $PhaseResult.internalPromotionAllowed -isnot [bool] -or [bool]$PhaseResult.internalPromotionAllowed) { throw 'FullRelease rejected incomplete REAL-USE-ACCEPTANCE phase evidence.' }

    $bindingFields = @('schemaVersion','contract','runId','phaseId','precedingPhase','candidate','execution','deadlineUtc','runner','surrogate','clusterJoin','installedPaths','baseUrl')
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.binding -Allowed $bindingFields -Required $bindingFields -Label 'REAL-USE-ACCEPTANCE phase binding' | Out-Null
    if ([int]$PhaseResult.binding.schemaVersion -ne 1 -or [string]$PhaseResult.binding.contract -cne $script:RealUseAcceptanceContract -or [string]$PhaseResult.binding.runId -cne [string]$Context.runId -or [string]$PhaseResult.binding.phaseId -cne $script:RealUseAcceptancePhase -or [string]$PhaseResult.binding.precedingPhase -cne 'SURROGATE-DISPOSABLE') { throw 'FullRelease rejected unbound REAL-USE-ACCEPTANCE phase evidence.' }
    $contextCandidate = [ordered]@{
        repositoryHead=[string]$Context.candidate.repositoryHead;candidateCommit=[string]$Context.candidate.gitCommit
        shippingInputIdentity=[string]$Context.candidate.shippingInputIdentity;releaseFingerprintId=[string]$Context.candidate.releaseFingerprintId
        toolingFingerprintId=[string]$Context.candidate.toolingFingerprintId;exeSha256=[string]$Context.candidate.candidate.sha256;tarSha256=[string]$Context.candidate.tar.sha256
    }
    Assert-RealUseAcceptanceCandidate -Actual $PhaseResult.candidate -Expected $contextCandidate -Label 'REAL-USE-ACCEPTANCE phase candidate' | Out-Null
    Assert-RealUseAcceptanceCandidate -Actual $PhaseResult.binding.candidate -Expected $contextCandidate -Label 'REAL-USE-ACCEPTANCE phase binding candidate' | Out-Null
    Assert-RealUseAcceptanceExecution -Actual $PhaseResult.binding.execution -Expected $PhaseResult.binding.execution -Label 'REAL-USE-ACCEPTANCE phase binding execution' | Out-Null
    if ([string]$PhaseResult.binding.execution.vmName -cne [string]$Context.vmName -or [string]$PhaseResult.binding.execution.vmId -cne [string]$Context.vmId) { throw 'FullRelease rejected REAL-USE-ACCEPTANCE VM identity drift.' }

    Assert-RealUseAcceptanceKeys -Value $PhaseResult.binding.runner -Allowed @('path','sha256') -Required @('path','sha256') -Label 'REAL-USE-ACCEPTANCE runner binding' | Out-Null
    $expectedRunnerPath = [IO.Path]::GetFullPath((Join-Path ([string]$Context.workspaceRoot) 'automation\release-e2e\modules\executors\Invoke-RealUseAcceptance.py'))
    $boundRunnerPath = [IO.Path]::GetFullPath([string]$PhaseResult.binding.runner.path)
    if (-not $boundRunnerPath.Equals($expectedRunnerPath,[StringComparison]::OrdinalIgnoreCase) -or [string]$PhaseResult.binding.runner.sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $boundRunnerPath -PathType Leaf) -or (Get-FileHash -LiteralPath $boundRunnerPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$PhaseResult.binding.runner.sha256) { throw 'FullRelease rejected changed REAL-USE-ACCEPTANCE runner evidence.' }

    Assert-RealUseAcceptanceKeys -Value $PhaseResult.binding.surrogate -Allowed @('evidencePath','evidenceSha256','phaseRecordsPath','phaseRecordsSha256') -Required @('evidencePath','evidenceSha256','phaseRecordsPath','phaseRecordsSha256') -Label 'REAL-USE-ACCEPTANCE Surrogate binding' | Out-Null
    $surrogatePath = Assert-RealUseAcceptanceContainedPath -Root ([string]$Context.runDir) -Path ([string]$PhaseResult.binding.surrogate.evidencePath) -Label 'REAL-USE-ACCEPTANCE Surrogate authority'
    $recordsPath = Assert-RealUseAcceptanceCanonicalEvidencePath -Root ([string]$Context.runDir) -Path ([string]$PhaseResult.binding.surrogate.phaseRecordsPath) -LeafName 'fullrelease-phase-records.json'
    if (-not (Test-Path -LiteralPath $surrogatePath -PathType Leaf) -or (Get-FileHash -LiteralPath $surrogatePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$PhaseResult.binding.surrogate.evidenceSha256 -or [string]$PhaseResult.binding.surrogate.phaseRecordsSha256 -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $recordsPath -PathType Leaf)) { throw 'FullRelease rejected changed REAL-USE-ACCEPTANCE Surrogate authority.' }
    $surrogateAuthority = Get-Content -LiteralPath $surrogatePath -Raw | ConvertFrom-Json -ErrorAction Stop
    if ([string]$surrogateAuthority.status -cne 'REAL E2E PASS' -or [string]$surrogateAuthority.contract -cne 'product-lifecycle-completion-authority' -or [string]$surrogateAuthority.role -cne 'Laptop / Surrogate' -or -not [bool]$surrogateAuthority.completionVerified -or -not [bool]$surrogateAuthority.authenticatedHealth -or [string]$surrogateAuthority.transactionId -cne [string]$PhaseResult.binding.execution.transactionId -or [string]$surrogateAuthority.invocationId -cne [string]$PhaseResult.binding.execution.invocationId -or [string]$surrogateAuthority.payloadSha256 -cne [string]$contextCandidate.tarSha256) { throw 'FullRelease rejected divergent REAL-USE-ACCEPTANCE Surrogate authority.' }

    Assert-RealUseAcceptanceKeys -Value $PhaseResult.binding.clusterJoin -Allowed @('evidencePath','evidenceSha256','primaryPairingEvidencePath','primaryPairingEvidenceSha256') -Required @('evidencePath','evidenceSha256','primaryPairingEvidencePath','primaryPairingEvidenceSha256') -Label 'REAL-USE-ACCEPTANCE cluster-join binding' | Out-Null
    $joinBinding=Assert-RealUseAcceptanceClusterJoinEvidence -Context $Context -Candidate ([pscustomobject]$contextCandidate) -SurrogateProduct $surrogateAuthority
    if([string]$PhaseResult.binding.clusterJoin.evidencePath-cne[string]$joinBinding.evidencePath-or[string]$PhaseResult.binding.clusterJoin.evidenceSha256-cne[string]$joinBinding.evidenceSha256-or[string]$PhaseResult.binding.clusterJoin.primaryPairingEvidencePath-cne[string]$joinBinding.capturePath-or[string]$PhaseResult.binding.clusterJoin.primaryPairingEvidenceSha256-cne[string]$joinBinding.captureSha256-or[string]$PhaseResult.binding.execution.deploymentId-cne[string]$joinBinding.evidence.compute.deploymentId-or[string]$PhaseResult.binding.execution.nodeId-cne[string]$joinBinding.evidence.compute.nodeId){throw 'FullRelease rejected divergent REAL-USE-ACCEPTANCE cluster-join binding.'}

    $input = [pscustomobject][ordered]@{schemaVersion=1;runId=[string]$PhaseResult.binding.runId;deadlineUtc=[string]$PhaseResult.binding.deadlineUtc;runnerSha256=[string]$PhaseResult.binding.runner.sha256;candidate=$PhaseResult.binding.candidate;execution=$PhaseResult.binding.execution;paths=$PhaseResult.binding.installedPaths;baseUrl=[string]$PhaseResult.binding.baseUrl}
    $inputRequest = [pscustomobject][ordered]@{runId=[string]$Context.runId;deadlineUtc=[string]$PhaseResult.binding.deadlineUtc;runnerSha256=[string]$PhaseResult.binding.runner.sha256;candidate=$contextCandidate;vmName=[string]$Context.vmName;vmId=[string]$Context.vmId;computeInstanceName=[string]$PhaseResult.binding.execution.computeInstanceName;vaultInstanceName=[string]$PhaseResult.binding.execution.vaultInstanceName;deploymentId=[string]$joinBinding.evidence.compute.deploymentId;nodeId=[string]$joinBinding.evidence.compute.nodeId;transactionId=[string]$PhaseResult.binding.execution.transactionId;invocationId=[string]$PhaseResult.binding.execution.invocationId;surrogateEvidenceSha256=[string]$PhaseResult.binding.surrogate.evidenceSha256}
    Assert-RealUseAcceptanceInput -Input $input -Request $inputRequest | Out-Null
    Assert-RealUseAcceptanceReport -Report $PhaseResult.report -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass | Out-Null
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.preflight -Allowed @('laptopInstalled','failoverReady','vaultReady','brokerReady','tailscaleReady','secretFilePolicy','credentialBoundary') -Required @('laptopInstalled','failoverReady','vaultReady','brokerReady','tailscaleReady','secretFilePolicy','credentialBoundary') -Label 'REAL-USE-ACCEPTANCE preflight evidence' | Out-Null
    foreach ($field in @('laptopInstalled','failoverReady','vaultReady','brokerReady','tailscaleReady','secretFilePolicy','credentialBoundary')) { if ($PhaseResult.preflight.$field -isnot [bool] -or -not [bool]$PhaseResult.preflight.$field) { throw 'FullRelease rejected incomplete REAL-USE-ACCEPTANCE prerequisite evidence.' } }
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.transport -Allowed @('l1Sha256','l2Sha256','inputSha256','onlyRunnerStaged','l1Path','ownedRootsRemoved') -Required @('l1Sha256','l2Sha256','inputSha256','onlyRunnerStaged','l1Path','ownedRootsRemoved') -Label 'REAL-USE-ACCEPTANCE transport evidence' | Out-Null
    if ([string]$PhaseResult.transport.l1Sha256 -cne [string]$PhaseResult.binding.runner.sha256 -or [string]$PhaseResult.transport.l2Sha256 -cne [string]$PhaseResult.binding.runner.sha256 -or [string]$PhaseResult.transport.inputSha256 -cnotmatch '^[0-9a-f]{64}$' -or $PhaseResult.transport.onlyRunnerStaged -isnot [bool] -or -not [bool]$PhaseResult.transport.onlyRunnerStaged -or $PhaseResult.transport.ownedRootsRemoved -isnot [bool] -or -not [bool]$PhaseResult.transport.ownedRootsRemoved -or [string]$PhaseResult.transport.l1Path -notlike 'C:\Users\Public\DevFleet-E2E\*\REAL-USE-ACCEPTANCE\Invoke-RealUseAcceptance.py') { throw 'FullRelease rejected incomplete REAL-USE-ACCEPTANCE transport evidence.' }
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.restart -Allowed @('unit','invocationChanged','otherUnitsRestarted') -Required @('unit','invocationChanged','otherUnitsRestarted') -Label 'REAL-USE-ACCEPTANCE restart evidence' | Out-Null
    if ([string]$PhaseResult.restart.unit -cne 'devfleet.service' -or $PhaseResult.restart.invocationChanged -isnot [bool] -or -not [bool]$PhaseResult.restart.invocationChanged -or $PhaseResult.restart.otherUnitsRestarted -isnot [bool] -or [bool]$PhaseResult.restart.otherUnitsRestarted) { throw 'FullRelease rejected substituted REAL-USE-ACCEPTANCE restart evidence.' }

    $evidenceFields = @('bindingPath','bindingSha256','preparePath','prepareSha256','reportPath','reportSha256','summaryPath','summarySha256')
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.evidence -Allowed $evidenceFields -Required $evidenceFields -Label 'REAL-USE-ACCEPTANCE evidence index' | Out-Null
    $leafNames = [ordered]@{binding='real-use-acceptance-binding.json';prepare='real-use-acceptance-prepare.json';report='real-use-acceptance-report.json';summary='real-use-acceptance-evidence.json'}
    $resolved = [ordered]@{}
    foreach ($name in $leafNames.Keys) {
        $pathName="${name}Path";$hashName="${name}Sha256";$path=Assert-RealUseAcceptanceCanonicalEvidencePath -Root ([string]$Context.runDir) -Path ([string]$PhaseResult.evidence.$pathName) -LeafName ([string]$leafNames[$name])
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$PhaseResult.evidence.$hashName) { throw "FullRelease rejected changed REAL-USE-ACCEPTANCE $name evidence." }
        $resolved[$name] = $path
    }
    $durableBinding = Get-Content -LiteralPath $resolved.binding -Raw | ConvertFrom-Json -ErrorAction Stop
    if (-not (Test-RealUseAcceptanceJsonEqual $durableBinding $PhaseResult.binding)) { throw 'FullRelease rejected divergent durable REAL-USE-ACCEPTANCE binding evidence.' }
    $durablePrepare = Get-Content -LiteralPath $resolved.prepare -Raw | ConvertFrom-Json -ErrorAction Stop
    Assert-RealUseAcceptanceReport -Report $durablePrepare -Input $input -ExpectedStage prepare -AllowedStatus @('PREPARED') | Out-Null
    $durableReport = Get-Content -LiteralPath $resolved.report -Raw | ConvertFrom-Json -ErrorAction Stop
    Assert-RealUseAcceptanceReport -Report $durableReport -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass | Out-Null
    if (-not (Test-RealUseAcceptanceJsonEqual $durableReport $PhaseResult.report)) { throw 'FullRelease rejected divergent durable REAL-USE-ACCEPTANCE report evidence.' }

    $durableSummary = Get-Content -LiteralPath $resolved.summary -Raw | ConvertFrom-Json -ErrorAction Stop
    $summaryFields = @('schemaVersion','contract','status','runId','phaseId','candidate','execution','preflight','transport','restart','journeys','cleanup','evidence','credentialsStoredInEvidence','internalPromotionAllowed')
    Assert-RealUseAcceptanceKeys -Value $durableSummary -Allowed $summaryFields -Required $summaryFields -Label 'REAL-USE-ACCEPTANCE durable summary' | Out-Null
    if ([int]$durableSummary.schemaVersion -ne 1 -or [string]$durableSummary.contract -cne 'devfleet-real-use-acceptance-evidence-v1' -or [string]$durableSummary.status -cne 'PASS' -or [string]$durableSummary.runId -cne [string]$Context.runId -or [string]$durableSummary.phaseId -cne $script:RealUseAcceptancePhase -or $durableSummary.credentialsStoredInEvidence -isnot [bool] -or [bool]$durableSummary.credentialsStoredInEvidence -or $durableSummary.internalPromotionAllowed -isnot [bool] -or [bool]$durableSummary.internalPromotionAllowed) { throw 'FullRelease rejected incomplete durable REAL-USE-ACCEPTANCE summary eviden