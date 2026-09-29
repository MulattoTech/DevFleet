# DevFleet source part 014

Full-source UTF-8 byte interval [604500, 651000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: c221a6ba88de9d3ec6be3eb728bc823ea3cf285fde7dbc6d386138b10b1b357a

<!-- BEGIN SOURCE SLICE -->
g $binding))|Out-Null
            }
            foreach($binding in @($ownership.Services)) {
                $service=Get-CimInstance Win32_Service -Filter "Name='$([string]$binding.Name)'" -ErrorAction Stop
                if(-not $service){throw "MAINTENANCE-READY owned service is missing: $([string]$binding.Name)"}
                $actual=@{Name=[string]$service.Name;ImagePath=[string]$service.PathName;Account=[string]$service.StartName;StartMode=[string]$service.StartMode;Generation=[string]$binding.Generation}
                Assert-DevFleetServiceBinding -Expected $binding -Actual $actual|Out-Null
            }
            # Re-prove authenticated Host Agent health at the maintenance
            # boundary. A restored checkpoint can report Hyper-V Heartbeat
            # before the SYSTEM scheduled task has bound HttpListener 8790.
            # Retry only connection-level WebException failures within a
            # finite readiness window; authentication, HTTP, and identity
            # failures remain fail-closed. The token is read and used only
            # inside the guest and is never returned in evidence.
            $protocol='C:\ProgramData\DevFleetHostAgent\DevFleet-HostAgentProtocol.psm1';$tokenPath='C:\ProgramData\DevFleetHostAgent\token.txt'
            if(-not(Test-Path -LiteralPath $protocol -PathType Leaf)-or-not(Test-Path -LiteralPath $tokenPath -PathType Leaf)){throw 'MAINTENANCE-READY authenticated Host Agent health prerequisites are missing.'}
            foreach($path in @($env:ProgramData,(Split-Path -Parent $protocol),$protocol,$tokenPath)){
                if((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'MAINTENANCE-READY health input is a reparse point.'}
            }
            $actualProtocol=(Get-FileHash -LiteralPath $protocol -Algorithm SHA256).Hash.ToLowerInvariant()
            if($actualProtocol-cne[string]$request.protocolSha256){throw 'MAINTENANCE-READY health protocol differs from the exact shipping input.'}
            Import-Module $protocol -Force
            function Invoke-MaintenanceReadyAuthenticatedHealth {
                param([Parameter(Mandatory)][string]$ProtocolTokenPath,[ValidateRange(1,120)][int]$WaitSeconds=60)
                $healthDeadline=[datetime]::UtcNow.AddSeconds($WaitSeconds);$attempts=0
                do {
                    $attempts++
                    try {
                        $currentToken=(Get-Content -LiteralPath $ProtocolTokenPath -Raw).Trim();if(-not $currentToken){throw 'MAINTENANCE-READY Host Agent token is empty.'}
                        try{$currentHealth=Invoke-HostAgentAuthenticatedJson -Uri 'http://127.0.0.1:8790/healthz' -Method GET -Key $currentToken -ExpectedHost $env:COMPUTERNAME;return [pscustomobject]@{health=$currentHealth;attempts=$attempts}}finally{$currentToken=$null}
                    } catch [Net.WebException] {
                        if([datetime]::UtcNow-ge$healthDeadline){throw}
                        Start-Sleep -Seconds 1
                    }
                } while($true)
            }
            $healthProbe=Invoke-MaintenanceReadyAuthenticatedHealth -ProtocolTokenPath $tokenPath -WaitSeconds 60;$health=$healthProbe.health
            if($health.ok-isnot[bool]-or-not$health.ok){throw 'MAINTENANCE-READY authenticated Host Agent health returned invalid or false ok.'}
            [ordered]@{
                status='PASS';computer=$env:COMPUTERNAME;installLedgerPath=$installPath;ownershipLedgerPath=$ownershipPath
                installLedgerSha256=(Get-FileHash -LiteralPath $installPath -Algorithm SHA256).Hash.ToLowerInvariant()
                ownershipLedgerSha256=(Get-FileHash -LiteralPath $ownershipPath -Algorithm SHA256).Hash.ToLowerInvariant()
                devFleetVersion=[string]$install.DevFleetVersion;installerVersion=[string]$install.InstallerVersion;packageSha256=[string]$install.PackageSha256
                installationGeneration=[string]$install.InstallationGeneration;ownershipSchemaVersion=[int]$ownership.SchemaVersion;bindingCount=$bindings.Count
                firewallConvergence=@($firewallConvergence)
                runtimeVersion=$PSVersionTable.PSVersion.ToString();protocolSha256=$actualProtocol
                hostAgentHealth=[ordered]@{authenticated=$true;ok=$true;hostName=[string]$health.host_name;hostId=[string]$health.host_id};hostAgentHealthProbeAttempts=[int]$healthProbe.attempts
            }
        }
        $request=[ordered]@{version=[string]$Fingerprint.releaseVersion;installer=[string]$Fingerprint.installerVersion;payload=[string]$Fingerprint.tar.sha256;protocolSha256=$protocolSha256}|ConvertTo-Json -Compress
        $requestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
        $body="& {"+$validationScript.ToString()+"} ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+$requestBase64+"'))) | ConvertTo-Json -Depth 8 -Compress"
        $body='try {'+$body+'} catch {$safe=([string]$_.FullyQualifiedErrorId-replace''[^A-Za-z0-9_. ,:-]'','''');[ordered]@{status=''BLOCKED'';failureId=$safe.Substring(0,[math]::Min(160,$safe.Length))}|ConvertTo-Json -Compress}'
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
        $remaining=[int][math]::Floor(($deadline-[datetime]::UtcNow).TotalSeconds)
        if($remaining-le10){throw 'MAINTENANCE-READY collection margin is exhausted.'}
        $childDeadline=[datetime]::UtcNow.AddSeconds([math]::Min(120,$remaining-10))
        $process=Invoke-DevFleetBoundedGuestProcess -Session $Session -FilePath 'C:\Program Files\PowerShell\7\pwsh.exe' -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -OwnerDeadlineUtc $childDeadline
        if([datetime]::UtcNow-gt$childDeadline){throw 'MAINTENANCE-READY result arrived after its child deadline.'}
        if([string]$process.outcome-cne'PASS'-or$process.outputComplete-isnot[bool]-or-not$process.outputComplete){throw 'MAINTENANCE-READY bounded PowerShell7 validation failed or returned incomplete output.'}
        $value=[string]$process.stdout|ConvertFrom-Json -ErrorAction Stop
        if([string]$value.status-ceq'BLOCKED'){
            $safe=([string]$value.failureId-replace'[^A-Za-z0-9_. ,:-]','')
            throw ('MAINTENANCE-READY child validation failed: '+$safe.Substring(0,[math]::Min(160,$safe.Length)))
        }
        $runtime=$null
        if([string]$value.status-cne'PASS'-or-not[version]::TryParse([string]$value.runtimeVersion,[ref]$runtime)-or$runtime.Major-lt7-or[string]$value.protocolSha256-cne$protocolSha256){throw 'MAINTENANCE-READY result runtime/protocol identity is invalid.'}
        if($value.hostAgentHealth.authenticated-isnot[bool]-or-not$value.hostAgentHealth.authenticated-or$value.hostAgentHealth.ok-isnot[bool]-or-not$value.hostAgentHealth.ok){throw 'MAINTENANCE-READY result does not prove authenticated health.'}
        if([string]$value.devFleetVersion-cne[string]$Fingerprint.releaseVersion-or[string]$value.installerVersion-cne[string]$Fingerprint.installerVersion-or[string]$value.packageSha256-cne[string]$Fingerprint.tar.sha256){throw 'MAINTENANCE-READY result candidate identity changed.'}
        return $value
    } finally { if($ownsSession-and$Session){Remove-DevFleetGuestSession -Session $Session -ErrorAction SilentlyContinue} }
}

function Ensure-MaintenanceReadyFixture {
    param(
        [Parameter(Mandatory)][psobject]$Vm,[Parameter(Mandatory)][psobject]$Fingerprint,
        [Parameter(Mandatory)][psobject]$Config,[Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$RunDir
    )
    $baseline=Set-DevFleetBaselineBinding -WorkspaceRoot $WorkspaceRoot -Fingerprint $Fingerprint
    $provenancePath=Join-Path $WorkspaceRoot 'audit\automation-harness\maintenance-ready-provenance.json'
    $currentVm=Get-AssertedDisposableVm -ExpectedVm $Vm
    $snapshots=@(Get-VMSnapshot -VM $currentVm -ErrorAction Stop|Where-Object{$_.Name -ceq 'DevFleet-E2E-MAINTENANCE-READY'})
    if($snapshots.Count -gt 1){throw 'MAINTENANCE-READY checkpoint identity is ambiguous; refusing adoption or cleanup.'}
    $snapshot=if($snapshots.Count -eq 1){$snapshots[0]}else{$null}
    $provenance=$null;$staleReason='missing provenance sidecar'
    if(Test-Path -LiteralPath $provenancePath -PathType Leaf){
        try{$provenance=Get-Content -LiteralPath $provenancePath -Raw|ConvertFrom-Json -ErrorAction Stop;if($snapshot){Assert-MaintenanceReadyProvenance -Provenance $provenance -Vm $currentVm -Snapshot $snapshot -Fingerprint $Fingerprint|Out-Null;$staleReason='guest validation required'}}catch{$staleReason=$_.Exception.Message;$provenance=$null}
    }
    if($provenance -and $snapshot){
        $restored=Restore-ExactCheckpoint -Vm $Vm -Name 'DevFleet-E2E-MAINTENANCE-READY' -StartAfterRestore
        $guest=Invoke-MaintenanceReadyGuestValidation -VmId ([guid][string]$Vm.Id) -Fingerprint $Fingerprint
        if([string]$guest.status -ne 'PASS' -or [string]$guest.installationGeneration -ne [string]$provenance.install.installationGeneration){throw 'MAINTENANCE-READY guest provenance did not match the current sidecar.'}
        return [ordered]@{status='PASS';reprovisioned=$false;checkpoint=$restored;guest=$guest;provenancePath=$provenancePath;vault=$provenance.vault}
    }
    $oldSnapshot=$snapshot
    Restore-ExactCheckpoint -Vm $Vm -Name ([string]$baseline.name) -StartAfterRestore|Out-Null
    # Reprovision through the pure product lifecycle. MAINTENANCE-READY must
    # not rerun the unrelated synthetic PFRO probe; the fixture layer only
    # validates the resulting durable installation ledger.
    $maintenanceContext=[ordered]@{runId=$RunId;phaseId='MAINTENANCE-READY-PROVISION';label='MAINTENANCE-READY PROVISION';checkpoint=[string]$baseline.name;destructive=$true;candidate=$Fingerprint;vmName=$Vm.Name;vmId=$Vm.Id.ToString();runDir=$RunDir;config=$Config;workspaceRoot=$WorkspaceRoot}
    $resumeEvidence=Invoke-MaintenanceReadyProductLifecycle -WorkspaceRoot $WorkspaceRoot -Context ([pscustomobject]$maintenanceContext)
    if([string]$resumeEvidence.status -notin @('PASS','REAL E2E PASS')){throw 'MAINTENANCE-READY supported reboot/resume install did not pass.'}
    $productProperty=$resumeEvidence.PSObject.Properties['product']
    $productValue=if($productProperty){$productProperty.Value}else{$null}
    $legsProperty=if($productValue){$productValue.PSObject.Properties['legs']}else{$null}
    $freshEvidence=if($legsProperty -and @($legsProperty.Value).Count -gt 0){$legsProperty.Value[0]}else{$resumeEvidence}
    $syntheticProperty=$resumeEvidence.PSObject.Properties['synthetic']
    $rebootFeature=if($syntheticProperty -and $syntheticProperty.Value){$syntheticProperty.Value}else{'PURE_PRODUCT_LIFECYCLE'}
    $guest=Invoke-MaintenanceReadyGuestValidation -VmId ([guid][string]$Vm.Id) -Fingerprint $Fingerprint
    if([string]$guest.status -ne 'PASS'){throw 'MAINTENANCE-READY guest validation did not pass.'}
    # Positive destructive scenarios require a configured authenticated Vault;
    # an ordinary bundle-free Desktop install intentionally has none. Prepare
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
        $roundtrip=[Globalization.DateTimeStyles]::RoundtripKind;$inv