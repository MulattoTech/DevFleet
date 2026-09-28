# DevFleet source part 014

Full-source UTF-8 byte interval [604500, 651000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 96775a41bdad0d0284057c43dde5e9388bec934d9aa649b35aeb272413dbee38

<!-- BEGIN SOURCE SLICE -->
Prepare
    # only the run-owned nested prerequisite before publishing the checkpoint.
    if(-not(Get-Command Initialize-MaintenanceVaultFixture -ErrorAction SilentlyContinue)){Import-Module (Join-Path $PSScriptRoot 'MaintenanceVault.psm1') -Scope Local -DisableNameChecking}
    $vault=Initialize-MaintenanceVaultFixture -Context ([pscustomobject]$maintenanceContext)
    if([string]$vault.status-cne'PASS'-or-not[bool]$vault.configurationPresent-or[bool]$vault.proofCredit){throw 'Configured Primary Vault prerequisite did not pass.'}
    $currentVm=Get-AssertedDisposableVm -ExpectedVm $Vm
    if($currentVm.State -ne 'Off'){Stop-VM -VM $currentVm -Force -Confirm:$false -ErrorAction Stop}
    $deadline=(Get-Date).AddMinutes(2);do{Start-Sleep -Seconds 2;$currentVm=Get-AssertedDisposableVm -ExpectedVm $Vm}while($currentVm.State -ne 'Off' -and (Get-Date)-lt $deadline)
    if($currentVm.State -ne 'Off'){throw 'MAINTENANCE-READY reprovision could not reach a safe Off state.'}
    if($oldSnapshot){Remove-VMSnapshot -VMSnapshot $oldSnapshot -Confirm:$false -ErrorAction Stop}
    Checkpoint-VM -VM $currentVm -SnapshotName 'DevFleet-E2E-MAINTENANCE-READY' -ErrorAction Stop|Out-Null
    $newSnapshot=@(Get-VMSnapshot -VM (Get-AssertedDisposableVm -ExpectedVm $Vm)|Where-Object{$_.Name -ceq 'DevFleet-E2E-MAINTENANCE-READY'})
    if($newSnapshot.Count -ne 1){throw 'MAINTENANCE-READY reprovision did not create exactly one current checkpoint.'}
    $snapshot=$newSnapshot[0]
    $provenance=[ordered]@{schemaVersion=1;contract='maintenance-ready-provenance-v1';createdUtc=(Get-Date).ToUniversalTime().ToString('o');sourceRunId=$RunId;vmName=$Vm.Name;vmId=$Vm.Id.ToString();checkpointName=$snapshot.Name;checkpointId=$snapshot.Id.ToString();candidate=[ordered]@{gitCommit=$Fingerprint.gitCommit;releaseVersion=$Fingerprint.releaseVersion;installerVersion=$Fingerprint.installerVersion;releaseFingerprintId=$Fingerprint.releaseFingerprintId;toolingFingerprintId=$Fingerprint.toolingFingerprintId;payloadSha256=$Fingerprint.tar.sha256};install=[ordered]@{installationGeneration=$guest.installationGeneration;devFleetVersion=$guest.devFleetVersion;installerVersion=$guest.installerVersion;packageSha256=$guest.packageSha256;ledgerSha256=$guest.installLedgerSha256};ownership=[ordered]@{schemaVersion=$guest.ownershipSchemaVersion;installationGeneration=$guest.installationGeneration;ledgerSha256=$guest.ownershipLedgerSha256;bindingCount=$guest.bindingCount}}
    $provenance.vault=$vault
    [IO.File]::WriteAllText($provenancePath,(($provenance|ConvertTo-Json -Depth 16)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    $restored=Restore-ExactCheckpoint -Vm $Vm -Name 'DevFleet-E2E-MAINTENANCE-READY' -StartAfterRestore
    Assert-MaintenanceReadyProvenance -Provenance $provenance -Vm (Get-AssertedDisposableVm -ExpectedVm $Vm) -Snapshot (Get-ExactCheckpoint -Vm $Vm -Name 'DevFleet-E2E-MAINTENANCE-READY') -Fingerprint $Fingerprint|Out-Null
    $postRestoreGuest=Invoke-MaintenanceReadyGuestValidation -VmId ([guid][string]$Vm.Id) -Fingerprint $Fingerprint
    if([string]$postRestoreGuest.installationGeneration -ne [string]$guest.installationGeneration){throw 'MAINTENANCE-READY restored checkpoint changed installation ownership identity.'}
    return [ordered]@{status='PASS';reprovisioned=$true;staleReason=$staleReason;rebootFeature=$rebootFeature;checkpoint=$restored;guest=$postRestoreGuest;provenancePath=$provenancePath;freshInstall=$freshEvidence;resumeInstall=$resumeEvidence;vault=$vault}
}

function Restore-MaintenanceReadyCheckpoint {
    param([Parameter(Mandatory)][psobject]$Vm,[Parameter(Mandatory)][psobject]$Fingerprint,[Parameter(Mandatory)][string]$WorkspaceRoot)
    $provenancePath=Join-Path $WorkspaceRoot 'audit\automation-harness\maintenance-ready-provenance.json'
    if(-not(Test-Path -LiteralPath $provenancePath -PathType Leaf)){throw 'MAINTENANCE-READY provenance sidecar is missing; fixture must be reprovisioned.'}
    $currentVm=Get-AssertedDisposableVm -ExpectedVm $Vm
    $snapshot=Get-ExactCheckpoint -Vm $Vm -Name 'DevFleet-E2E-MAINTENANCE-READY'
    $provenance=Get-Content -LiteralPath $provenancePath -Raw|ConvertFrom-Json -ErrorAction Stop
    Assert-MaintenanceReadyProvenance -Provenance $provenance -Vm $currentVm -Snapshot $snapshot -Fingerprint $Fingerprint|Out-Null
    $restored=Restore-ExactCheckpoint -Vm $Vm -Name 'DevFleet-E2E-MAINTENANCE-READY' -StartAfterRestore
    $guest=Invoke-MaintenanceReadyGuestValidation -VmId ([guid][string]$Vm.Id) -Fingerprint $Fingerprint
    if([string]$guest.installationGeneration -cne [string]$provenance.install.installationGeneration){throw 'MAINTENANCE-READY restored guest ownership identity differs from the sidecar.'}
    return [ordered]@{checkpoint=$restored;provenancePath=$provenancePath;guest=$guest}
}

function Ensure-FullReleaseInteractiveDesktop {
    param([Parameter(Mandatory)][guid]$VmId)
    try {
        $existing=Assert-DevFleetE2EInteractiveDesktopAfterDisarm -VmId $VmId
        return [pscustomobject]@{status='PASS';contract='devfleet-disposable-l1-interactive-logon-v1';mode='already-active';desktop=$existing.desktop;survivesDisarm=$existing}
    } catch {
        # A checkpoint restore may have booted without an interactive shell.
        # Only that bounded negative probe authorizes the one-shot arm below.
    }
    $arm=$null;$disarm=$null
    try {
        $arm=Arm-DevFleetE2EInteractiveLogon -VmId $VmId
        Restart-DevFleetE2EL1 -ArmState $arm | Out-Null
        $desktop=Wait-DevFleetE2EInteractiveDesktop -VmId $VmId -TimeoutSeconds 300
        $disarm=Disarm-DevFleetE2EInteractiveLogon -ArmState $arm
        $survival=Assert-DevFleetE2EInteractiveDesktopAfterDisarm -VmId $VmId
        [pscustomobject]@{status='PASS';contract='devfleet-disposable-l1-interactive-logon-v1';arm=$arm;desktop=$desktop;disarm=$disarm;survivesDisarm=$survival}
    } finally {
        if($arm -and -not $disarm){try{Disarm-DevFleetE2EInteractiveLogon -ArmState $arm|Out-Null}catch{}}
    }
}
function Restore-ExactCheckpoint {
    param([Parameter(Mandatory)][psobject]$Vm,[Parameter(Mandatory)][string]$Name,[switch]$StartAfterRestore)
    Assert-FullReleaseDisposableOwnership -Vm $Vm | Out-Null
    $currentVm=Get-AssertedDisposableVm -ExpectedVm $Vm
    if ($currentVm.State -ne 'Off') {
        Stop-VM -VM $currentVm -Force -Confirm:$false -ErrorAction Stop
        $deadline=(Get-Date).AddMinutes(2)
        do { Start-Sleep -Seconds 2; $current=(Get-AssertedDisposableVm -ExpectedVm $Vm).State.ToString() } while ($current -ne 'Off' -and (Get-Date) -lt $deadline)
        if ($current -ne 'Off') { throw "Disposable VM '$($Vm.Name)' did not reach Off before checkpoint restore." }
    }
    $snapshot = Get-ExactCheckpoint -Vm $Vm -Name $Name
    Restore-VMSnapshot -VMSnapshot $snapshot -Confirm:$false -ErrorAction Stop
    $afterVm = Get-AssertedDisposableVm -ExpectedVm $Vm
    $after = Get-VMSnapshot -VM $afterVm -ErrorAction Stop | Where-Object { $_.Id -eq $snapshot.Id }
    if (-not $after) { throw "Checkpoint restore did not preserve exact snapshot identity $($snapshot.Id)." }
    # Hyper-V can materialize a restored checkpoint as Saved before it settles.
    # Memory topology cannot be changed in that state; transition only the owned
    # disposable VM to Off and verify the transition before any correction.
    $settleDeadline = (Get-Date).AddMinutes(2)
    $stableOffPolls = 0
    do {
        $settled = Get-AssertedDisposableVm -ExpectedVm $Vm
        if ($settled.State -eq 'Saved') {
            Stop-VM -VM $settled -Force -Confirm:$false -ErrorAction Stop
            $stableOffPolls = 0
        } elseif ($settled.State -eq 'Off') {
            # A restored checkpoint can report Off briefly before becoming Saved;
            # require a stable observation window before changing its topology.
            $stableOffPolls++
            if ($stableOffPolls -ge 6) { break }
        } else {
            $stableOffPolls = 0
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $settleDeadline)
    $settled = Get-AssertedDisposableVm -ExpectedVm $Vm
    if ($settled.State -ne 'Off') { throw "Disposable VM '$($Vm.Name)' did not settle Off after exact checkpoint restore; observed state $($settled.State)." }
    $topology=Get-AssertedDisposableVm -ExpectedVm $Vm
    if ([int64]$topology.MemoryStartup -ne 16GB -or [bool]$topology.DynamicMemoryEnabled) {
        # The owned L1 is contractually fixed at 16 GiB with Dynamic Memory
        # disabled. Snapshots may carry older VM configuration; correct only
        # this exact disposable target and verify before starting it.
        $topologyError=$null
        for($attempt=1;$attempt -le 6;$attempt++) {
            try {
                $topology=Get-AssertedDisposableVm -ExpectedVm $Vm
                if ([bool]$topology.DynamicMemoryEnabled) { Set-VMMemory -VM $topology -DynamicMemoryEnabled $false -Confirm:$false -ErrorAction Stop }
                $topology=Get-AssertedDisposableVm -ExpectedVm $Vm
                if ([int64]$topology.MemoryStartup -ne 16GB) { Set-VMMemory -VM $topology -StartupBytes 16GB -Confirm:$false -ErrorAction Stop }
                $topology=Get-AssertedDisposableVm -ExpectedVm $Vm
                $topologyError=$null;break
            } catch { $topologyError=$_.Exception; if($attempt -lt 6){Start-Sleep -Seconds $attempt} }
        }
        if($topologyError){throw $topologyError}
    }
    if ([int64]$topology.MemoryStartup -ne 16GB -or [bool]$topology.DynamicMemoryEnabled) { throw "Disposable VM topology is not the required fixed 16 GiB / Dynamic Memory OFF contract." }
    if ($StartAfterRestore) {
        $topology=Get-AssertedDisposableVm -ExpectedVm $Vm
        Start-VM -VM $topology -ErrorAction Stop | Out-Null
        $deadline=(Get-Date).AddMinutes(2)
        do { Start-Sleep -Seconds 2; $current=(Get-AssertedDisposableVm -ExpectedVm $Vm).State.ToString() } while ($current -ne 'Running' -and (Get-Date) -lt $deadline)
        if ($current -ne 'Running') { throw "Disposable VM '$($Vm.Name)' did not reach Running after exact checkpoint restore." }
        $heartbeatDeadline = (Get-Date).AddMinutes(3)
        $heartbeat = $null
        do {
            $heartbeatVm = Get-AssertedDisposableVm -ExpectedVm $Vm
            $heartbeat = Get-VMIntegrationService -VM $heartbeatVm -Name 'Heartbeat' -ErrorAction Stop
            if ($heartbeat.PrimaryStatusDescription -eq 'OK') { break }
            Start-Sleep -Seconds 5
        } while ((Get-Date) -lt $heartbeatDeadline)
        if ($heartbeat.PrimaryStatusDescription -ne 'OK') { throw "Disposable VM '$($Vm.Name)' did not report Hyper-V Heartbeat OK before guest-session use." }
        Start-Sleep -Seconds 5
        # Product lifecycle callers establish and authenticate the interactive
        # desktop inside their bounded worker before invoking WPF. Keep restore
        # itself free of a duplicate guest reboot/session transition so a
        # remoting teardown cannot terminate the proof coordinator.
    }
    [pscustomobject]@{ name=$snapshot.Name; id=$snapshot.Id.ToString(); restored=$true; started=[bool]$StartAfterRestore; vmName=$Vm.Name; memoryStartupBytes=[int64]$topology.MemoryStartup; dynamicMemory=[bool]$topology.DynamicMemoryEnabled }
}

function Get-ExecutorPath {
    param([Parameter(Mandatory)][psobject]$Config,[Parameter(Mandatory)][string]$PhaseId,[Parameter(Mandatory)][string]$WorkspaceRoot)
    if (-not $Config.PSObject.Properties['FullReleaseExecutors']) { return $null }
    $entry = $Config.FullReleaseExecutors.PSObject.Properties[$PhaseId]
    if (-not $entry -or [string]::IsNullOrWhiteSpace([string]$entry.Value)) { return $null }
    $candidate = [IO.Path]::GetFullPath((Join-Path $WorkspaceRoot ([string]$entry.Value)))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "Configured FullRelease executor is missing for ${PhaseId}: $candidate" }
    return $candidate
}

function Invoke-ConfiguredExecutor {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][psobject]$Context)
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -notin @('.ps1','.psm1')) { throw "FullRelease executor must be a PowerShell script: $Path" }
    $shell = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $shell) { $shell = Get-Command powershell.exe -ErrorAction SilentlyContinue }
    if (-not $shell) { throw 'No supported PowerShell executable is available for FullRelease executor dispatch.' }
    $contextJson = $Context | ConvertTo-Json -Depth 32 -Compress
    $policy=Get-HarnessBudgetPolicy -Config $Context.config
    $watchdogSeconds=[int]$policy.fullReleaseWatchdogSeconds
    if($watchdogSeconds -le [int]$policy.observerAbsoluteBudgetSeconds){throw 'FullRelease executor watchdog must strictly exceed the observer absolute deadline.'}
    $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$shell.Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Path)){$psi.ArgumentList.Add([string]$arg)}
    $psi.Environment['DEVFLEET_FULLRELEASE_CONTEXT_JSON']=$contextJson
    $child=[Diagnostics.Process]::new();$child.StartInfo=$psi
    if(-not $child.Start()){throw "Could not start FullRelease executor for $($Context.phaseId)."}
    $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
    $completed=$child.WaitForExit($watchdogSeconds*1000)
    $drained=$false
    try{$drained=[Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5))}catch{$drained=$false}
    $stdoutText=if($stdout.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdout.GetAwaiter().GetResult()}else{''}
    $stderrText=if($stderr.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderr.GetAwaiter().GetResult()}else{''}
    if(-not $completed){try{$child.Kill($true)}catch{};try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5)))}catch{};$stdoutText=if($stdout.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdout.GetAwaiter().GetResult()}else{$stdoutText};$stderrText=if($stderr.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderr.GetAwaiter().GetResult()}else{$stderrText};$rawOutput="HARNESS_WATCHDOG_EXPIRED`n$stdoutText`n$stderrText"; $rawPath=Join-Path ([string]$Context.runDir) "$($Context.phaseId)-executor-output.txt"; $rawOutput|Set-Content -LiteralPath $rawPath -Encoding UTF8; $child.Dispose(); throw "HARNESS_WATCHDOG_EXPIRED for $($Context.phaseId) after ${watchdogSeconds}s; evidence=$rawPath"}
    $exitCode=$child.ExitCode;$output=@($stdoutText -split "`r?`n")+@($stderrText -split "`r?`n");$child.Dispose()
    $rawOutput = ($output -join "`n")
    $rawPath = Join-Path ([string]$Context.runDir) "$($Context.phaseId)-executor-output.txt"
    $rawOutput | Set-Content -LiteralPath $rawPath -Encoding UTF8
    if ($exitCode -ne 0) { throw "FullRelease executor failed for $($Context.phaseId) with exit code ${exitCode}: $rawOutput" }
    $lines = @($output | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -eq 0) { throw "FullRelease executor returned no evidence for $($Context.phaseId)." }
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
        $candidateJson = $lines[$index].Trim()
        if (-not ($candidateJson.StartsWith('{') -or $candidateJson.StartsWith('['))) { continue }
        try { return ($candidateJson | ConvertFrom-Json -ErrorAction Stop) } catch { continue }
    }
    throw "FullRelease executor returned invalid JSON for $($Context.phaseId); raw evidence=$rawPath."
}

function Invoke-DisposablePrivateSignatureVerification {
    param(
        [Parameter(Mandatory)][psobject]$Fingerprint,
        [Parameter(Mandatory)][psobject]$Vm,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RunDir
    )
    if([string]$Fingerprint.privateSigningProfile -ne 'PRIVATE_SELF_SIGNED'){return $null}
    Assert-FullReleaseDisposableOwnership -Vm $Vm|Out-Null
    $thumbprint=[string]$Fingerprint.privateSigningCertificateThumbprint
    $publicCertificate=[string]$Fingerprint.publicCertificate.path
    if(-not(Test-Path -LiteralPath $publicCertificate -PathType Leaf)){throw 'Private signing public certificate is unavailable for disposable verification.'}
    $session=$null
    try{
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Vm.Id)
        $remoteRoot="C:\Users\Public\DevFleet-E2E\$RunId\private-signature-verification"
        $remoteExe=Join-Path $remoteRoot (Split-Path -Leaf ([string]$Fingerprint.candidate.path))
        $remoteCertificate=Join-Path $remoteRoot 'DevFleet-Private-Personal-Code-Signing.cer'
        Invoke-Command -Session $session -ScriptBlock{param($root)New-Item -ItemType Directory -Path $root -Force|Out-Null}-ArgumentList $remoteRoot
        $exeStage=Get-StageIntegrity -LocalPath ([string]$Fingerprint.candidate.path) -Session $session -RemotePath $remoteExe
        $certificateStage=Get-StageIntegrity -LocalPath $publicCertificate -Session $session -RemotePath $remoteCertificate
        if(-not $exeStage.equal -or -not $certificateStage.equal){throw 'Private signature verifier staging identity mismatch.'}
        $verification=Invoke-Command -Session $session -ScriptBlock{
            param($exe,$cer,$expectedThumbprint,$root)
            $ErrorActionPreference='Stop'
            if($env:COMPUTERNAME -match 'SURFACE'){throw 'Disposable signature verification refused a Surface host.'}
            $tampered=Join-Path $root 'tampered-copy.exe';$trustedCertificate=$null;$chain=$null
            try{
                $trustedCertificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($cer)
                if($trustedCertificate.Thumbprint -cne $expectedThumbprint){throw 'Disposable verifier public certificate thumbprint mismatch.'}
                $signature=Get-AuthenticodeSignature -LiteralPath $exe
                if(-not $signature.SignerCertificate){throw 'Disposable verifier found no Authenticode signer certificate.'}
                if($signature.SignerCertificate.Thumbprint -cne $expectedThumbprint){throw 'Disposable verifier signer thumbprint mismatch.'}
                if([Convert]::ToBase64String($signature.SignerCertificate.RawData) -cne [Convert]::ToBase64String($trustedCertificate.RawData)){throw 'Disposable verifier signer differs from the exact supplied public certificate.'}
                if([string]$signature.Status -notin @('Valid','UnknownError')){throw "Disposable verifier returned an unexpected Authenticode status: $($signature.Status)."}
                if([string]$signature.Status -eq 'UnknownError' -and [string]$signature.StatusMessage -notmatch '(?i)trust|root|certificate chain'){throw "Disposable verifier UnknownError was not solely an untrusted-root condition: $($signature.StatusMessage)"}
                if('1.3.6.1.5.5.7.3.3' -notin @($signature.SignerCertificate.EnhancedKeyUsageList|ForEach-Object{[string]$_.ObjectId})){throw 'Disposable verifier signer lacks Code Signing EKU.'}
                $chain=[Security.Cryptography.X509Certificates.X509Chain]::new()
                $chain.ChainPolicy.RevocationMode=[Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
                $chain.ChainPolicy.VerificationFlags=[Security.Cryptography.X509Certificates.X509VerificationFlags]::AllowUnknownCertificateAuthority
                $null=$chain.ChainPolicy.ExtraStore.Add($trustedCertificate)
                if(-not $chain.Build($signature.SignerCertificate)){throw "Disposable exact-certificate chain validation failed: $(@($chain.ChainStatus|ForEach-Object Status) -join ', ')"}
                $unexpectedChainStatus=@($chain.ChainStatus|Where-Object{[string]$_.Status -notin @('NoError','UntrustedRoot')})
                if($unexpectedChainStatus.Count){throw "Disposable verifier chain has unexpected status: $(@($unexpectedChainStatus|ForEach-Object Status) -join ', ')"}
                Copy-Item -LiteralPath $exe -Destination $tampered
                $stream=[IO.File]::Open($tampered,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                try{$stream.Position=4096;$byte=$stream.ReadByte();$stream.Position=4096;$stream.WriteByte(($byte -bxor 1))}finally{$stream.Dispose()}
                $tamperedStatus=[string](Get-AuthenticodeSignature -LiteralPath $tampered).Status
                if($tamperedStatus -ne 'HashMismatch'){throw "Disposable tampered-copy verification returned $tamperedStatus instead of HashMismatch."}
                [pscustomobject]@{status='PASS';computer=$env:COMPUTERNAME;signerThumbprint=$signature.SignerCertificate.Thumbprint;signatureStatus=[string]$signature.Status;signatureStatusMessage=[string]$signature.StatusMessage;codeSigningEkuVerified=$true;exactCertificateMatch=$true;explicitTrustValidation='PASS';trustMode='IN_MEMORY_EXACT_CERTIFICATE';chainStatuses=@($chain.ChainStatus|ForEach-Object{[string]$_.Status});tamperedCopyStatus=$tamperedStatus;trustStores=@();trustInstalledForRun=@();privateKeyPresent=$false;physicalSurfaceTouched=$false}
            }finally{
                Remove-Item -LiteralPath $tampered -Force -ErrorAction SilentlyContinue
                if($chain){$chain.Dispose()}
                if($trustedCertificate){$trustedCertificate.Dispose()}
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }-ArgumentList $remoteExe,$remoteCertificate,$thumbprint,$remoteRoot
        $evidencePath=Join-Path $RunDir 'private-signature-disposable-verifier.json'
        [IO.File]::WriteAllText($evidencePath,(($verification|ConvertTo-Json -Depth 8)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
        return [ordered]@{status='PASS';expectedThumbprint=$thumbprint;exeStage=$exeStage;certificateStage=$certificateStage;guest=$verification;evidencePath=$evidencePath;trustCleanup='no persistent guest trust mutation performed'}
    }finally{if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}}
}

function Invoke-FullReleaseCleanup {
    param(
        [Parameter(Mandatory)][psobject]$Vm,
        [Parameter(Mandatory)][psobject]$Fingerprint,
        [Parameter(Mandatory)][psobject]$Config,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RunDir
    )
    $manifest=New-CleanupManifest -Vm $Vm -RunId $RunId
    if(-not(Test-CleanupManifest $manifest)){throw 'Final cleanup manifest failed exact disposable ownership validation.'}
    $session=$null;$guestCleanup=$null;$logonCleanup=$null
    try{
        $cleanupVm=Get-AssertedDisposableVm -ExpectedVm $Vm
        if($cleanupVm.State -ne 'Running'){throw 'FullRelease cleanup requires the existing exact L1 session; it will not start an already-Off L1 to refresh evidence.'}
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Vm.Id)
        $logonCleanup=Clear-DevFleetE2EInteractiveLogonState -VmId ([guid][string]$Vm.Id)
        if([string]$logonCleanup.status -ne 'PASS' -or -not [bool]$logonCleanup.registryCleanupPersisted -or -not [bool]$logonCleanup.temporaryDefaultPasswordRemovalPersisted -or [bool]$logonCleanup.ordinaryDefaultPasswordPresent){throw 'Final cleanup durable interactive-login preconditions were not satisfied.'}
        $guestCleanup=Invoke-Command -Session $session -ScriptBlock{
            param($runId)
            $ErrorActionPreference='Stop'
            $runRoot="C:\Users\Public\DevFleet-E2E\$runId"
            if(Test-Path -LiteralPath $runRoot){Remove-Item -LiteralPath $runRoot -Recurse -Force}
            if(Test-Path -LiteralPath $runRoot){throw 'Run-scoped candidate staging directory remains after cleanup.'}
            $tasks=@(Get-ScheduledTask -TaskName 'DevFleet-E2E-UIA-*' -ErrorAction Stop)
            if($tasks.Count -gt 0){throw "E2E UI scheduled tasks remain after executor cleanup: $($tasks.TaskName -join ', ')"}
            [pscustomobject]@{status='PASS';computer=$env:COMPUTERNAME;runRootAbsent=$true;uiaTasksAbsent=$true;foreignResourcesMutated=$false}
        }-ArgumentList $RunId
        $nestedName=[string]$Config.NestedLinux.Name
        if([string]::IsNullOrWhiteSpace($nestedName) -or $nestedName -notlike 'DevFleet-E2E-*' -or $nestedName -ceq 'DevFleet-H10-Linux'){throw 'FullRelease cleanup has an invalid exact nested L2 target.'}
        $nestedObservation=Get-DevFleetNestedL2State -Session $session -ExpectedName $nestedName
        if([string]$nestedObservation.status -eq 'UNVERIFIED' -or $nestedObservation.present -isnot [bool]){throw 'FullRelease cleanup cannot certify a missing, denied, malformed, or incomplete nested inventory.'}
        if([string]$nestedObservation.status -eq 'PRESENT'){
            if([string]$nestedObservation.verification -cne 'Bounded Multipass JSON inventory inside exact L1'){throw 'FullRelease cleanup found a nested resource outside the bounded owned Multipass cleanup contract; it was preserved.'}
            $null=Invoke-Command -Session $session -ScriptBlock{
                param($runId,$nestedName)
                $ErrorActionPreference='Stop'
                $candidates=@((Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe'))|Where-Object{$_ -and(Test-Path -LiteralPath $_ -PathType Leaf)}
                $multipass=$candidates|Select-Object -First 1
                if(-not $multipass){$command=Get-Command multipass.exe -ErrorAction Stop;if(-not $command){throw 'Bounded Multipass inventory executable disappeared.'};$multipass=$command.Source}
                $raw=(& $multipass list --format json 2>&1)-join "`n";if($LASTEXITCODE -ne 0){throw 'Final cleanup could not enumerate Multipass ownership state.'}
                try{$inventory=$raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Final cleanup received malformed Multipass ownership inventory.'}
                if($null -eq $inventory.PSObject.Properties['list'] -or $inventory.list -isnot [array]){throw 'Final cleanup received an incomplete Multipass ownership inventory.'}
                $matches=@($inventory.list|Where-Object{[string]$_.name -ceq $nestedName})
                if($matches.Count -ne 1){throw 'Nested Multipass identity is no longer unique; cleanup refused it.'}
                & $multipass exec $nestedName -- test -f "/etc/devfleet-e2e-run-$runId" 2>&1|Out-Null
                if($LASTEXITCODE -ne 0){throw "Nested VM $nestedName exists without this RunId marker; cleanup refused it."}
                & $multipass delete --purge $nestedName 2>&1|Out-Null
                if($LASTEXITCODE -ne 0){throw "Run-owned nested VM $nestedName could not be deleted."}
            }-ArgumentList $RunId,$nestedName
            $nestedObservation=Get-DevFleetNestedL2State -Session $session -ExpectedName $nestedName
        }
        if([string]$nestedObservation.status -cne 'ABSENT' -or $nestedObservation.present -ne $false){throw 'FullRelease cleanup did not establish nested L2 absence from a complete in-L1 inventory.'}
        $guestCleanup|Add-Member -NotePropertyName nestedName -NotePropertyValue $nestedName -Force
        $guestCleanup|Add-Member -NotePropertyName nestedAbsent -NotePropertyValue $true -Force
        $guestCleanup|Add-Member -NotePropertyName nestedObservationUtc -NotePropertyValue ([string]$nestedObservation.observedUtc) -Force
    }finally{if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}}
    Stop-ManifestVm -Manifest $manifest
    $stopDeadline=(Get-Date).AddMinutes(2)
    do{$finalVm=Get-AssertedDisposableVm -ExpectedVm $Vm;if($finalVm.State -eq 'Off'){break};Start-Sleep -Seconds 2}while((Get-Date)-lt $stopDeadline)
    if($finalVm.Id.ToString() -ne $Vm.Id.ToString() -or $finalVm.State -ne 'Off'){throw 'Final cleanup did not leave the exact disposable L1 powered off.'}
    $terminal = Write-TerminalVmEvidence -Vm $Vm -RunDir $RunDir -L2Name ([string]$Config.NestedLinux.Name) -RunId $RunId -NestedL2Observation $nestedObservation -Candidate $Fingerprint -EvidenceClass 'FullRelease run-bound nested observation'
    if([string]$terminal.l2.status -cne 'ABSENT' -or $terminal.l2.present -ne $false){throw 'FullRelease cleanup terminal writer did not preserve the exact nested absence observation.'}
    $evidence=[ordered]@{status='PASS';runId=$RunId;candidate=[ordered]@{repositoryHead=[string]$Fingerprint.repositoryHead;candidateCommit=[string]$Fingerprint.gitCommit;shippingInputIdentity=[string]$Fingerprint.shippingInputIdentity;releaseFingerprintId=[string]$Fingerprint.releaseFingerprintId;toolingFingerprintId=[string]$Fingerprint.toolingFingerprintId};manifest=$manifest;interactiveLogonCleanup=$logonCleanup;guest=$guestCleanup;l1=[ordered]@{name=$finalVm.Name;id=$finalVm.Id.ToString();state=[string]$finalVm.State;deleted=$false};productionTouched=$false;physicalSurfaceTouched=$false}
    $evidence.terminal=$terminal
    $evidencePath=Join-Path $RunDir 'final-cleanup.json'
    Write-EvidenceJson -Path $evidencePath -Value $evidence
    $evidence.evidencePath=$evidencePath
    return $evidence
}

function Write-PostCleanupFinalization {
    param([Parameter(Mandatory)][psobject]$State,[Parameter(Mandatory)][psobject]$Vm,[Parameter(Mandatory)][psobject]$Config,[Parameter(Mandatory)][string]$RunDir,[Parameter(Mandatory)][object[]]$Records,[Parameter(Mandatory)][string]$WorkspaceRoot)
    $cleanup = @($Records | Where-Object { [string]$_.id -eq 'CLEANUP' }) | Select-Object -Last 1
    if(-not $cleanup -or [string]$cleanup.status -ne 'PASS' -or -not $cleanup.evidence){throw 'Post-cleanup finalization requires a passing current CLEANUP record.'}
    $runId=[string]$State.runId
    if([string]::IsNullOrWhiteSpace($runId) -or -not $State.candidateHashes){throw 'Post-cleanup finalization requires an exact RunId and candidate tuple.'}
    $workspace=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $WorkspaceRoot -ErrorAction Stop).Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $resolvedRunDir=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RunDir -ErrorAction Stop).Path)
    $expectedRunDir=[IO.Path]::GetFullPath((Join-Path $workspace (Join-Path 'audit/automation-harness/runs' $runId)))
    if(-not $resolvedRunDir.Equals($expectedRunDir,[StringComparison]::OrdinalIgnoreCase)){throw 'Post-cleanup evidence directory is outside the exact current FullRelease RunId root.'}
    foreach($relative in @('audit','audit/automation-harness','audit/automation-harness/runs',("audit/automation-harness/runs/"+$runId))){
        $directory=Join-Path $workspace $relative
        $item=Get-Item -LiteralPath $directory -Force -ErrorAction Stop
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Post-cleanup run path contains a missing or disallowed reparse directory.'}
    }
    $boundStreams=[Collections.Generic.List[IO.FileStream]]::new()
    try {
        $readBoundJson={
            param([string]$Path)
            $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Post-cleanup evidence input is not a regular non-reparse file.'}
            $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try {
                $memory=[IO.MemoryStream]::new()
                try {$stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$memory.Dispose()}
                $encoding=[Text.UTF8Encoding]::new($false,$true)
                $text=$encoding.GetString($bytes)
                if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
                $value=$text|ConvertFrom-Json -ErrorAction Stop
                $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
                $boundStreams.Add($stream)
                return [pscustomobject]@{value=$value;sha256=$hash}
            }catch{$stream.Dispose();throw}
        }
        $paths=@{cleanup=(Join-Path $resolvedRunDir 'final-cleanup.json');l1=(Join-Path $resolvedRunDir 'l1-terminal-state.json');l2=(Join-Path $resolvedRunDir 'l2-terminal-state.json');nested=(Join-Path $resolvedRunDir 'nested-l2-terminal-observation.json')}
        $bound=@{}
        foreach($key in $paths.Keys){if(-not(Test-Path -LiteralPath $paths[$key] -PathType Leaf)){throw "Post-cleanup finalization is missing $($paths[$key])."};$bound[$key]=&$readBoundJson $paths[$key]}
        $cleanupValue=$bound.cleanup.value;$l1=$bound.l1.value;$l2=$bound.l2.value;$nested=$bound.nested.value
        if([string]$cleanupValue.status -ne 'PASS' -or [string]$cleanupValue.runId -cne $runId -or [string]$cleanupValue.l1.state -ne 'Off' -or -not [bool]$cleanupValue.guest.runRootAbsent -or -not [bool]$cleanupValue.guest.nestedAbsent -or [bool]$cleanupValue.guest.foreignResourcesMutated){throw 'Post-cleanup finalization rejected incomplete or unsafe cleanup evidence.'}
        if([string]$l1.name -cne [string]$Vm.Name -or [string]$l1.id -cne [string]$Vm.Id -or [string]$l1.state -ne 'Off'){throw 'Post-cleanup L1 terminal evidence is not the exact powered-off disposable VM.'}
        $expectedL2=[string]$Config.NestedLinux.Name
        if([string]::IsNullOrWhiteSpace($expectedL2) -or $expectedL2 -ceq 'DevFleet-H10-Linux' -or [string]$l2.expectedName -cne $expectedL2 -or [string]$l2.status -cne 'ABSENT' -or $l2.present -isnot [bool] -or $l2.present -ne $false){throw 'Post-cleanup L2 terminal evidence is not a validated nested absence observation.'}
        if([string]$l1.runId -cne $runId -or [string]$l2.runId -cne $runId -or [string]$l2.sourceRunId -cne $runId){throw 'Post-cleanup terminal evidence is not bound to the current FullRelease RunId.'}
        if([string]$l2.sourceEvidence -cne 'nested-l2-terminal-observation.json' -or [string]$l2.nestedScope -cne 'inside the exact L1 guest session' -or [string]$l2.evidenceClass -cne 'FullRelease run-bound nested observation' -or [string]$l2.l1Name -cne [string]$Vm.Name -or [string]$l2.l1Id -cne [string]$Vm.Id){throw 'Post-cleanup L2 provenance is missing the exact run, nested scope, or exact L1 binding.'}
        if($bound.nested.sha256 -cne [string]$l2.sourceEvidenceSha256){throw 'Post-cleanup nested observation source hash changed after publication.'}
        $toUtcText={param($value)if($value -is [datetimeoffset]){return $value.UtcDateTime.ToString('o')}if($value -is [datetime]){return $value.ToUniversalTime().ToString('o')}return [string]$value}
        $nestedUtcText=&$toUtcText $nested.observedUtc;$l1UtcText=&$toUtcText $l1.timestampUtc;$l2UtcText=&$toUtcText $l2.timestampUtc
        $nestedUtc=[datetimeoffset]::MinValue;$l1Utc=[datetimeoffset]::MinValue
        $roundtrip=[Globalization.DateTimeStyles]::RoundtripKind;$invariant=[Globalization.CultureInfo]::InvariantCulture
        if(-not[datetimeoffset]::TryParse($nestedUtcText,$invariant,$roundtrip,[ref]$nestedUtc)-or$nestedUtc.Offset-ne[timespan]::Zero-or-not[datetimeoffset]::TryParse($l1UtcText,$invariant,$roundtrip,[ref]$l1Utc)-or$l1Utc.Offset-ne[timespan]::Zero-or$nestedUtc-gt$l1Utc){throw 'Post-cleanup nested and L1 observations have invalid or out-of-order UTC timestamps.'}
        if([string]$nested.runId -cne $runId -or [string]$nested.status -cne 'ABSENT' -or $nested.present -isnot [bool] -or $nested.present -ne $false -or [string]$nested.expectedName -cne $expectedL2 -or [string]$nested.nestedScope -cne 'inside the exact L1 guest session' -or [string]$nested.observer -cne 'Get-DevFleetNestedL2State' -or [string]$nested.l1.name -cne [string]$Vm.Name -or [string]$nested.l1.id -cne [string]$Vm.Id){throw 'Post-cleanup nested observation source does not match the terminal claim.'}
        if(($nested.exactMatchCount -isnot [int] -and $nested.exactMatchCount -isnot [long]) -or [long]$nested.exactMatchCount -ne 0){throw 'Post-cleanup nested observation exact-match result is absent or invalid.'}
        $candidateTuplePatterns=[ordered]@{
            repositoryHead='^[0-9a-f]{40}$'
            candidateCommit='^[0-9a-f]{40}$'
            shippingInputIdentity='^[0-9a-f]{64}$'
            releaseFingerprintId='^[0-9a-f]{64}$'
            toolingFingerprintId='^[0-9a-f]{64}$'
        }
        foreach($key in $candidateTuplePatterns.Keys){
            $tupleValue=''
            if($State.candidateHashes -is [System.Collections.IDictionary]){$tupleValue=[string]$State.candidateHashes[$key]}
            elseif($State.candidateHashes){$tupleProperty=$State.candidateHashes.PSObject.Properties[$key];if($tupleProperty){$tupleValue=[string]$tupleProperty.Value}}
            if($tupleValue -cnotmatch $candidateTuplePatterns[$key]){throw 'Post-cleanup finalization candidate tuple is malformed or incomplete.'}
        }
        foreach($key in $candidateTuplePatterns.Keys){
            if([string]$l2.candidate.$key -cne [string]$State.candidateHashes.$key -or [string]$nested.candidate.$key -cne [string]$State.candidateHashes.$key -or [string]$cleanupValue.candidate.$key -cne [string]$State.candidateHashes.$key){throw "Post-cleanup nested evidence is stale for candidate field $key."}
        }
        if($l2UtcText -cne $nestedUtcText -or [string]$l2.verificationMethod -cne [string]$nested.verification -or [string]::IsNullOrWhiteSpace([string]$nested.verification)){throw 'Post-cleanup nested observation verification method or timestamp is absent or changed.'}
        if([string]$nested.verification -ceq 'Bounded Multipass JSON inventory inside exact L1'){
            if(($nested.inventoryCount -isnot [int] -and $nested.inventoryCount -isnot [long]) -or [long]$nested.inventoryCount -lt 0){throw 'Post-cleanup Multipass inventory completeness is missing.'}
        }elseif([string]$nested.verification -ceq 'Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend'){
            $backendRows=@($nested.backendInventories)
            if($backendRows.Count -ne 2){throw 'Post-cleanup nested absence is missing a supported backend inventory.'}
            foreach($provider in @('Hyper-V','VirtualBox')){
                $rows=@($backendRows|Where-Object{[string]$_.provider -ceq $provider})
                if($rows.Count -ne 1 -or [string]$rows[0].status -cne 'PASS' -or $rows[0].names -isnot [array] -or [string]::IsNullOrWhiteSpace([string]$rows[0].verification)){throw "Post-cleanup $provider nested inventory is incomplete or ambiguous."}
                $instanceNames=[Collections.Generic.List[string]]::new()
                foreach($instanceName in $rows[0].names){
                    if($instanceName -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$instanceName)){throw "Post-cleanup $provider nested inventory contains an invalid instance name."}
                    if($instanceNames.Contains([string]$instanceName)){throw "Post-cleanup $provider nested inventory contains a duplicate instance name."}
                    if([string]$instanceName -ceq $expectedL2){throw "Post-cleanup $provider nested inventory still contains the exact L2 target."}
                    $instanceNames.Add([string]$instanceName)
                }
            }
        }else{throw 'Post-cleanup nested absence uses an unsupported inventory method.'}
        # The host-side exact-name lookup is only an additional foreign-resource exclusion.
        $live=Get-VM -Id ([guid][string]$Vm.Id) -ErrorAction Stop
        if($live.Name -cne [string]$Vm.Name -or [guid][string]$live.Id -ne [guid][string]$Vm.Id -or [string]$live.State -ne 'Off'){throw 'Post-cleanup live L1 verification failed.'}
        $hostL2Exclusion=Get-DevFleetHostNameExclusion -Name $expectedL2
        if([string]$hostL2Exclusion.name -cne $expectedL2 -or [string]$hostL2Exclusion.inventoryScope -cne 'host Hyper-V exact-name exclusion only' -or $hostL2Exclusion.present -isnot [bool]){throw 'Post-cleanup host exclusion result is malformed or has the wrong scope.'}
        $hostRows=@($hostL2Exclusion.resources)
        if(($hostL2Exclusion.present -eq $false -and ([string]$hostL2Exclusion.status -cne 'ABSENT' -or $hostRows.Count -ne 0)) -or ($hostL2Exclusion.present -eq $true -and ([string]$hostL2Exclusion.status -cne 'PRESENT' -or $hostRows.Count -lt 1))){throw 'Post-cleanup host exclusion result is incomplete or inconsistent.'}
        if($hostL2Exclusion.present){throw 'Post-cleanup host inventory found a same-name resource; it was preserved and nested evidence cannot override the host conflict.'}
        $value=[ordered]@{schemaVersion=3;status='PASS';contract='authoritative-post-cleanup-finalization';runId=$runId;cleanupConsumed=$true;cleanupRecordStatus=[string]$cleanup.status;cleanupEvidenceHash=$bound.cleanup.sha256;terminalL1='l1-terminal-state.json';terminalL1Hash=$bound.l1.sha256;terminalL1Timestamp=[string]$l1.timestampUtc;terminalL2='l2-terminal-state.json';terminalL2Hash=$bound.l2.sha256;terminalL2Timestamp=$nestedUtcText;nestedL2Observation='nested-l2-terminal-observation.json';nestedL2ObservationSha256=$bound.nested.sha256;expectedL2Name=$expectedL2;candidate=$l2.candidate;liveChecks=[ordered]@{l1ExactOff=$true;l2ExactAbsent=$true;hostSameNameL2Absent=$true;foreignResourcesMutated=$false};reconcileAfterCleanup=$true;timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
        Write-EvidenceJson -Path (Join-Path $resolvedRunDir 'post-cleanup-finalization.json') -Value $value
        return $value
    } finally { foreach($stream in $boundStreams){$stream.Dispose()} }
}

function Set-FullReleasePassState {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$FinalizationState,
        [Parameter(Mandatory)][psobject]$Result,
        [Parameter(Mandatory)][string]$ExpectedRunId
    )
    if ([string]::IsNullOrWhiteSpace($ExpectedRunId)) { throw 'FullRelease PASS cannot be promoted without a RunId.' }
    if ([string]$Result.status -cne 'PASS') { throw 'FullRelease PASS promotion requires a PASS result.' }
    if ([string]$Result.runId -cne $ExpectedRunId) { throw 'FullRelease PASS result RunId does not match the current authority RunId.' }
    $postCleanup = $Result.postCleanupFinalization
    if (-not $postCleanup -or [string]$postCleanup.status -cne 'PASS' -or -not [bool]$postCleanup.cleanupConsumed -or -not [bool]$postCleanup.reconcileAfterCleanup) {
        throw 'FullRelease PASS promotion requires current post-cleanup finalization evidence.'
    }
    $liveChecks = $postCleanup.liveChecks
    if (-not $liveChecks -or -not [bool]$liveChecks.l1ExactOff -or -not [bool]$liveChecks.l2ExactAbsent) {
        throw 'FullRelease PASS promotion requires exact L1 OFF and L2 ABSENT live checks.'
    }
    $FinalizationState['full_release_run_id'] = $ExpectedRunId
    $FinalizationState['full_release_current'] = $true
    $FinalizationState['full_release_passed'] = $true
    $FinalizationState['validation_evidence_current'] = $true
    $FinalizationState['internal_promotion_allowed'] = $false
    $FinalizationState['public_promotion_allowed'] = $false
    $FinalizationState['public_publisher_trust'] = $false
    $FinalizationState['release_status'] = 'BLOCKED'
    $FinalizationState['status'] = 'BLOCKED — FullRelease PASS recorded; exact proofs and remaining acceptance gates required'
    $FinalizationState['current_phase'] = 'FULLRELEASE-PASS'
    $FinalizationState['last_completed_phase'] = 'CLEANUP'
    return $FinalizationState
}

function Invoke-FullReleaseRun {
    param(
        [Parameter(Mandatory)][psobject]$State,
        [Parameter(Mandatory)][psobject]$Fingerprint,
        [Parameter(Mandatory)][psobject]$Vm,
        [Parameter(Mandatory)][psobject]$Config,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][psobject]$HostSnapshot,
        [Parameter(Mandatory)][psobject]$SelfTest
    )
    $effectiveStartAuthorized = if($HostSnapshot.PSObject.Properties['effectiveE2EStartAuthorized']){[bool]$HostSnapshot.effectiveE2EStartAuthorized}else{[bool]$HostSnapshot.startSafe}
    if (-not $effectiveStartAuthorized) { throw 'USER ACTION REQUIRED — FREE HOST RAM' }
    $baseline=Set-DevFleetBaselineBinding -WorkspaceRoot $WorkspaceRoot -Fingerprint $Fingerprint
    $phases=Get-FullReleasePhasePlan
    $records = [System.Collections.Generic.List[object]]::new()
    $context = [ordered]@{ runId=$State.runId; phaseId=''; label=''; checkpoint=$null; destructive=$false; candidate=$Fingerprint; vmName=$Vm.Name; vmId=$Vm.Id.ToString(); statePath=$StatePath; runDir=$RunDir; workspaceRoot=$WorkspaceRoot; config=$Config }
    $realUsePairingCapture = $null
    $realUsePairingPrivateState = $null
    $realUseSurrogateEvidence = $null
    foreach ($phase in $phases) {
        $context.phaseId=$phase.id
        $context.label=$phase.label;$context.checkpoint=$phase.checkpoint;$context.destructive=[bool]$phase.destructive
        $State.currentPhase=$phase.id
        Save-RunState -State $State -Path $StatePath
        $record = [ordered]@{ id=$phase.id; label=$phase.label; checkpoint=$phase.checkpoint; destructive=[bool]$phase.destructive; status='NOT RUN'; evidence=$null; startedAt=(Get-Date).ToUniversalTime().ToString('o') }
        try {
            if ($phase.id -eq 'HOST-SAFETY') {
                if (-not $effectiveStartAuthorized) { throw 'Host safety threshold was not met.' }
                $record.status='PASS';$record.evidence=$HostSnapshot
            } elseif ($phase.id -eq 'CANDIDATE-VERIFY') {
                $checks=$SelfTest.requiredChecks
                $bad=if ($checks -is [System.Collections.IDictionary]) { @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value }) } else { @($checks.PSObject.Properties | Where-Object { -not [bool]$_.Value }) }
                if ($SelfTest.result -ne 'PASS' -or @($bad).Count -gt 0) { throw 'Candidate self-test is not a complete PASS.' }
                $record.status='PASS';$record.evidence=[ordered]