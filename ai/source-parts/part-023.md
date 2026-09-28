# DevFleet source part 023

Full-source UTF-8 byte interval [1023000, 1069500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 1d5a6c6f252b7475f790e1d2afa14028179fbc44c21b30a28656b466c71fa2e7

<!-- BEGIN SOURCE SLICE -->
rty=InvocationID','--value') 'REAL_USE_SERVICE_INVOCATION_MISSING';if($before-cnotmatch'^[0-9a-f]{32}$'){throw 'REAL_USE_SERVICE_INVOCATION_INVALID'}
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
    if ([int]$durableSummary.schemaVersion -ne 1 -or [string]$durableSummary.contract -cne 'devfleet-real-use-acceptance-evidence-v1' -or [string]$durableSummary.status -cne 'PASS' -or [string]$durableSummary.runId -cne [string]$Context.runId -or [string]$durableSummary.phaseId -cne $script:RealUseAcceptancePhase -or $durableSummary.credentialsStoredInEvidence -isnot [bool] -or [bool]$durableSummary.credentialsStoredInEvidence -or $durableSummary.internalPromotionAllowed -isnot [bool] -or [bool]$durableSummary.internalPromotionAllowed) { throw 'FullRelease rejected incomplete durable REAL-USE-ACCEPTANCE summary evidence.' }
    Assert-RealUseAcceptanceCandidate -Actual $durableSummary.candidate -Expected $contextCandidate -Label 'REAL-USE-ACCEPTANCE summary candidate' | Out-Null
    Assert-RealUseAcceptanceExecution -Actual $durableSummary.execution -Expected $PhaseResult.binding.execution -Label 'REAL-USE-ACCEPTANCE summary execution' | Out-Null
    if (-not (Test-RealUseAcceptanceJsonEqual $durableSummary.preflight $PhaseResult.preflight) -or -not (Test-RealUseAcceptanceJsonEqual $durableSummary.transport $PhaseResult.transport) -or -not (Test-RealUseAcceptanceJsonEqual $durableSummary.restart $PhaseResult.restart)) { throw 'FullRelease rejected divergent durable REAL-USE-ACCEPTANCE execution evidence.' }
    $summaryJourneys = @($durableSummary.journeys)
    if ($summaryJourneys.Count -ne 5 -or @('U01','U02','U03','U04','U05' | Where-Object { $id=$_; @($summaryJourneys | Where-Object { [string]$_.id -ceq $id -and [string]$_.status -ceq 'PASS' }).Count -ne 1 }).Count) { throw 'FullRelease rejected incomplete durable REAL-USE-ACCEPTANCE journey summary.' }
    Assert-RealUseAcceptanceKeys -Value $durableSummary.cleanup -Allowed @('status','ownedOnly','vaultSnapshots') -Required @('status','ownedOnly','vaultSnapshots') -Label 'REAL-USE-ACCEPTANCE summary cleanup' | Out-Null
    if ([string]$durableSummary.cleanup.status -cne 'PASS' -or $durableSummary.cleanup.ownedOnly -isnot [bool] -or -not [bool]$durableSummary.cleanup.ownedOnly -or [string]$durableSummary.cleanup.vaultSnapshots -cne 'RETAINED_APPEND_ONLY_IN_DISPOSABLE_VAULT') { throw 'FullRelease rejected incomplete durable REAL-USE-ACCEPTANCE cleanup summary.' }
    Assert-RealUseAcceptanceKeys -Value $durableSummary.evidence -Allowed @('binding','prepare','report') -Required @('binding','prepare','report') -Label 'REAL-USE-ACCEPTANCE summary evidence links' | Out-Null
    foreach ($name in @('binding','prepare','report')) {
        Assert-RealUseAcceptanceKeys -Value $durableSummary.evidence.$name -Allowed @('path','sha256') -Required @('path','sha256') -Label "REAL-USE-ACCEPTANCE summary $name link" | Out-Null
        $pathName="${name}Path";$hashName="${name}Sha256"
        if ([string]$durableSummary.evidence.$name.path -cne [string]$PhaseResult.evidence.$pathName -or [string]$durableSummary.evidence.$name.sha256 -cne [string]$PhaseResult.evidence.$hashName) { throw "FullRelease rejected divergent REAL-USE-ACCEPTANCE summary $name link." }
    }
    return $true
}

Export-ModuleMember -Function New-RealUseAcceptancePrimaryPairingCapture,Complete-RealUseAcceptanceClusterJoin,Remove-RealUseAcceptancePrivateState,Get-RealUseAcceptanceSurrogateBinding,Assert-RealUseAcceptanceInput,Assert-RealUseAcceptanceReport,Invoke-RealUseAcceptancePhase,Assert-RealUseAcceptancePhaseEvidence

```


## FILE: automation/release-e2e/modules/ResumeState.psm1

SHA256: b8ce4a186694603ff0e7eb246f39052e2ee335f002b10bd55ad9c8014eb2f661 | Bytes: 2459 | Git mode: 100644

```
Set-StrictMode -Version Latest

function Write-AtomicJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Value)
    $full = [IO.Path]::GetFullPath($Path)
    $dir = Split-Path -Parent $full
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $tmp = "$full.$([guid]::NewGuid().ToString('N')).tmp"
    $json = $Value | ConvertTo-Json -Depth 32
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stream = [IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    try {
        for($attempt=1;$attempt -le 4;$attempt++) {
            try {
                Move-Item -LiteralPath $tmp -Destination $full -Force
                return
            } catch {
                if($attempt -eq 4){throw}
                Start-Sleep -Milliseconds (100*$attempt)
            }
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Read-StrictJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "State file not found: $Path" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "State file is empty: $Path" }
    try { $raw | ConvertFrom-Json -ErrorAction Stop } catch { throw "Invalid JSON state: $Path" }
}

function New-HarnessRunId { "e2e-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))-$([guid]::NewGuid().ToString('N').Substring(0,8))" }

function Save-RunState { param([Parameter(Mandatory)][psobject]$State,[Parameter(Mandatory)][string]$Path); Write-AtomicJson -Path $Path -Value $State }

function Assert-ResumeIdentity {
    param([Parameter(Mandatory)][psobject]$State,[Parameter(Mandatory)][psobject]$Fingerprint,[psobject]$Vm)
    if ($State.candidateHashes -and $State.candidateHashes.exe -ne $Fingerprint.candidate.sha256) { throw 'Resume refused: candidate hash changed.' }
    if ($State.candidateHashes -and $State.candidateHashes.tar -ne $Fingerprint.tar.sha256) { throw 'Resume refused: TAR hash changed.' }
    if ($State.vmId -and $Vm -and $State.vmId -ne $Vm.Id.ToString()) { throw 'Resume refused: disposable VM identity changed.' }
    $true
}

Export-ModuleMember -Function Write-AtomicJson,Read-StrictJson,New-HarnessRunId,Save-RunState,Assert-ResumeIdentity

```


## FILE: automation/release-e2e/modules/Secrets.psm1

SHA256: 52c0820d2047f6839ad319170045f06ec65726fc1b8bb0ec977d007792182f53 | Bytes: 7992 | Git mode: 100644

```
Set-StrictMode -Version Latest

function Get-DevFleetE2ESecretPath {
    Join-Path $env:LOCALAPPDATA 'DevFleet\E2E\secrets.json'
}

function Protect-DevFleetE2ESecretFile {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $security = [Security.AccessControl.FileSecurity]::new()
        $security.SetAccessRuleProtection($true,$false)
        $security.SetOwner($identity)
        foreach($rule in @(
            [Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','Allow'),
            [Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators','FullControl','Allow'),
            [Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM','FullControl','Allow')
        )) { $security.AddAccessRule($rule) | Out-Null }
        Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
    } catch { throw 'Secure E2E credential store ACL could not be established.' }
}

function Write-DevFleetE2ESecretRecord {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Data)
    $parent=Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        # The temporary file is ACL'd before credential bytes are written.
        [IO.File]::WriteAllText($temporary,'',[Text.UTF8Encoding]::new($false))
        Protect-DevFleetE2ESecretFile -Path $temporary
        [IO.File]::WriteAllText($temporary,(($Data|ConvertTo-Json -Depth 8)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
        Protect-DevFleetE2ESecretFile -Path $Path
        [IO.File]::SetAttributes($Path,[IO.FileAttributes]::Hidden)
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Read-DevFleetE2ESecretRecord {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Secure E2E credential store is a reparse point.' }
    Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Save-DevFleetE2ECredential {
    param([Parameter(Mandatory)][pscredential]$Credential)
    $path = Get-DevFleetE2ESecretPath
    $existing = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { $existing = Read-DevFleetE2ESecretRecord -Path $path } catch { throw 'Secure E2E credential store is corrupt; repair it before replacing the interactive credential.' }
    }
    $data = [ordered]@{ schemaVersion=2; username=$Credential.UserName; passwordDpapi=$Credential.Password | ConvertFrom-SecureString; createdAt=(Get-Date).ToUniversalTime().ToString('o') }
    if ($existing) {
        foreach ($name in @('tailscaleOAuthClientId','tailscaleOAuthClientSecretDpapi')) {
            if ($existing.PSObject.Properties[$name]) { $data[$name] = $existing.$name }
        }
    }
    Write-DevFleetE2ESecretRecord -Path $path -Data $data
    $path
}

function ConvertTo-DevFleetPlainSecret {
    param([Parameter(Mandatory)][securestring]$Secret)
    $bstr=[IntPtr]::Zero
    try { $bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret);return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { if($bstr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)} }
}

function Save-DevFleetTailscaleOAuthCredential {
    [CmdletBinding()]
    param([Parameter(Mandatory)][securestring]$ClientSecret,[string]$ClientId='')
    if($ClientId -and ($ClientId.Length -gt 256 -or $ClientId -match '[\r\n]')){throw 'Tailscale OAuth client ID is malformed.'}
    $plain=ConvertTo-DevFleetPlainSecret -Secret $ClientSecret
    try {
        if([string]::IsNullOrWhiteSpace($plain) -or $plain.IndexOfAny([char[]]"`0`r`n") -ge 0 -or $plain.Length -gt 2048){throw 'Tailscale OAuth client secret is empty or malformed.'}
    } finally { $plain=$null }
    $path=Get-DevFleetE2ESecretPath;$existing=$null
    try {$existing=Read-DevFleetE2ESecretRecord -Path $path} catch { throw 'Secure E2E credential store is corrupt; repair it before adding Tailscale OAuth.' }
    $data=[ordered]@{schemaVersion=2;createdAt=(Get-Date).ToUniversalTime().ToString('o')}
    if($existing){foreach($name in @('username','passwordDpapi','createdAt')){if($existing.PSObject.Properties[$name]){$data[$name]=$existing.$name}}}
    if(-not $data.Contains('username')){$data.username='';$data.passwordDpapi=''}
    $data.tailscaleOAuthClientId=$ClientId
    $data.tailscaleOAuthClientSecretDpapi=($ClientSecret | ConvertFrom-SecureString)
    Write-DevFleetE2ESecretRecord -Path $path -Data $data
    $path
}

function Get-DevFleetTailscaleOAuthCredential {
    $path=Get-DevFleetE2ESecretPath;$data=$null
    try {$data=Read-DevFleetE2ESecretRecord -Path $path} catch { return [pscustomobject]@{available=$false;provider='OAuthClientSecretStore';reason='secure E2E credential store is corrupt';secret=$null;clientId='';path=$path;invalid=$true} }
    $clientId=if($data -and $data.PSObject.Properties['tailscaleOAuthClientId']){[string]$data.tailscaleOAuthClientId}else{''}
    if(-not $data -or -not $data.PSObject.Properties['tailscaleOAuthClientSecretDpapi'] -or [string]::IsNullOrWhiteSpace([string]$data.tailscaleOAuthClientSecretDpapi)){return [pscustomobject]@{available=$false;provider='OAuthC