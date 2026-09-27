# DevFleet source part 110

Full-source UTF-8 byte interval [5068500, 5115000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 73fe69958d118296984f6808b51875be5648275d9c4b56a737fcd8fc5490e3db

<!-- BEGIN SOURCE SLICE -->
{break}
        $attemptsRemaining=$MaximumAttempts-$attempt+1
        $probeTimeout=[math]::Max(1,[math]::Min(20,[int][math]::Floor($remainingSeconds/$attemptsRemaining)))
        try {
            $last=if($StatusProvider){& $StatusProvider $Dependency $deadline $probeTimeout}else{Get-DependencyStatus -Dependency $Dependency -ProbeTimeoutSeconds $probeTimeout -DeadlineUtc $deadline}
        } catch {
            $last=[pscustomobject]@{Status='Broken';Path='';Version=$null;Detail='Bounded dependency status provider failed.'}
        }
        if($last -and [string]$last.Status -cne 'Broken'){return $last}
        if($attempt -ge $MaximumAttempts){break}
        $remainingAfter=[math]::Floor(($deadline-(& $now).ToUniversalTime()).TotalSeconds)
        if($remainingAfter -le 0){break}
        & $sleep ([math]::Min(1,$remainingAfter))
    }
    if($last){return $last}
    return [pscustomobject]@{Status='Broken';Path='';Version=$null;Detail='Dependency status deadline expired before a bounded probe completed.'}
}

function Get-DevFleetDependencyProbeAttemptLimit {
    param([Parameter(Mandatory)]$Dependency)
    # Multipass may still be bringing its daemon/backend online immediately
    # after a restored Windows checkpoint. Give only that proven transient gate
    # five additional bounded probes; the existing dependencyProbe deadline,
    # trusted-path checks, version policy, and fail-closed result handling stay
    # unchanged.
    if ([string]$Dependency.id -ceq 'multipass') { return 8 }
    return 3
}


function Get-TailscaleExe {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe')
    )) { if ($candidate -and (Test-TrustedExecutableCandidate $candidate)) { return $candidate } }
    throw 'Tailscale is not installed in a trusted machine location.'
}

function Get-VsCodeCli {
    param([switch]$AllowPerUser)
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\bin\code.cmd')
    )) { if ($candidate -and (Test-TrustedExecutableCandidate $candidate)) { return $candidate } }
    if ($AllowPerUser) {
        $user = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
        if ($user -and (Test-Path -LiteralPath $user -PathType Leaf) -and -not ((Get-Item -LiteralPath $user -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $user }
    }
    return $null
}

function Get-MultipassExe {
    # Multipass is intentionally allowed to be unsigned after installation only
    # when the canonical dependency policy binds it to a signed installer and a
    # locked machine path.  Resolve through that same policy as Ensure-Dependency
    # so runtime helpers cannot reject a legitimate install (or invent a weaker
    # trust rule of their own).
    $packageRoot = Get-DevFleetPackageRoot
    $manifest = Get-CanonicalDependencyManifest -PackageRoot $packageRoot
    $dependency = @($manifest.dependencies | Where-Object id -eq 'multipass' | Select-Object -First 1)
    if (-not $dependency) { throw 'Canonical Multipass dependency policy is missing.' }
    $cachedVariable=Get-Variable -Scope Script -Name DevFleetMultipassResolution -ErrorAction SilentlyContinue
    if($cachedVariable -and $cachedVariable.Value){
        $cached=$cachedVariable.Value
        try {
            if((Test-TrustedExecutableCandidate ([string]$cached.Path) -Dependency $dependency) -and (Get-FileHash -LiteralPath ([string]$cached.Path) -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$cached.Sha256){return [string]$cached.Path}
        } catch {}
        $script:DevFleetMultipassResolution=$null
    }
    $deadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'dependencyProbe'))
    $deadlineContext=Get-DevFleetDeadlineContext
    if($deadlineContext -and ([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime() -lt $deadline){$deadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
    $status = Wait-DevFleetDependencyStatus -Dependency $dependency -DeadlineUtc $deadline -MaximumAttempts (Get-DevFleetDependencyProbeAttemptLimit -Dependency $dependency)
    if ($status.Status -eq 'Compatible' -and $status.Path) {
        $script:DevFleetMultipassResolution=[pscustomobject]@{Path=[string]$status.Path;Sha256=(Get-FileHash -LiteralPath ([string]$status.Path) -Algorithm SHA256).Hash.ToLowerInvariant();Version=[string]$status.Version}
        return [string]$status.Path
    }
    throw "Multipass is not installed in a trusted machine location or compatible state: $($status.Status)."
}


function Assert-MultipassIsolation {
    param([string[]]$InstanceNames = @())
    $mp = Get-MultipassExe
    $setting = Invoke-External $mp @('get','local.privileged-mounts') -Capture
    if ($setting.Trim().ToLowerInvariant() -ne 'false') {
        throw 'Multipass host mounts are not disabled. Run: multipass set local.privileged-mounts=false'
    }
    foreach ($name in $InstanceNames) {
        if (-not $name -or -not (Test-MultipassInstance $name)) { continue }
        $raw = Invoke-External $mp @('info',$name,'--format','json') -Capture
        $data = $raw | ConvertFrom-Json
        $prop = $data.info.PSObject.Properties[$name]
        if (-not $prop) { throw "Multipass info did not contain instance $name." }
        $info = $prop.Value
        if ($info.PSObject.Properties.Name -contains 'mounts' -and $null -ne $info.mounts) {
            $mountCount = 0
            if ($info.mounts -is [System.Array]) {
                $mountCount = @($info.mounts).Count
            } elseif ($info.mounts -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace([string]$info.mounts)) { $mountCount = 1 }
            } else {
                $mountCount = @($info.mounts.PSObject.Properties).Count
            }
            if ($mountCount -gt 0) { throw "$name has one or more host mounts. Remove them before using DevFleet." }
        }
    }
}

function Get-MultipassInstances {
    $mp = Get-MultipassExe
    $raw = Invoke-External $mp @('list','--format','json') -Capture
    if (-not $raw) { return @() }
    $data = $raw | ConvertFrom-Json
    @($data.list)
}

function Test-MultipassInstance { param([string]$Name) [bool](Get-MultipassInstances | Where-Object name -eq $Name) }

function Wait-MultipassReady {
    param([string]$Name,[int]$TimeoutSeconds=600,[datetime]$DeadlineUtc=[datetime]::MinValue)
    $mp = Get-MultipassExe
    if($TimeoutSeconds -le 0){throw 'Multipass readiness timeout must be positive.'}
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $context = Get-DevFleetDeadlineContext
    if($DeadlineUtc -gt [datetime]::MinValue -and $DeadlineUtc.ToUniversalTime() -lt $deadline){$deadline=$DeadlineUtc.ToUniversalTime()}
    elseif($context -and [datetime]$context.StageDeadlineUtc -lt $deadline){$deadline=[datetime]$context.StageDeadlineUtc.ToUniversalTime()}
    $attempt=0
    while([DateTime]::UtcNow -lt $deadline) {
        $attempt++
        $out = $null
        try {
            # Probe without --wait so the outer deadline remains authoritative. Newer
            # cloud-init versions expose JSON; older versions use the normalized text
            # fallback below. Exit code 2 is not itself a readiness result.
            $remaining=[int][math]::Floor(($deadline-[DateTime]::UtcNow).TotalSeconds)
            if($remaining -le 0){break}
            $out = Invoke-External $mp @('exec',$Name,'--','bash','-lc','cloud-init status --format=json 2>&1 || cloud-init status 2>&1') -Capture -IgnoreExitCode -TimeoutSeconds ([math]::Min(900,$remaining)) -DeadlineUtc $deadline
        } catch {
            $remaining=[math]::Max(0,($deadline-[DateTime]::UtcNow).TotalSeconds)
            Write-Verbose "Multipass readiness probe $attempt failed for $Name; retrying with $([math]::Round($remaining,1)) seconds remaining."
            if($remaining -le 0){break}
            Start-Sleep -Milliseconds ([int][math]::Min(5000,[math]::Max(100,$remaining*1000)))
            continue
        }
        $normalized=[regex]::Replace([string]$out,'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\a]*(?:\a|\x1B\\))','')
        $normalized=$normalized -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',''
        $state=$null
        try {
            $structured=$normalized.Trim() | ConvertFrom-Json
            if($structured -and $structured.PSObject.Properties.Name -contains 'status'){$state=[string]$structured.status}
            if($structured -and $structured.PSObject.Properties.Name -contains 'extended_status' -and [string]$structured.extended_status -match '(?i)error|degraded|fail'){$state='error'}
        } catch { }
        if(-not $state){
            if($normalized -match '(?im)^\s*status:\s*done\s*$'){$state='done'}
            elseif($normalized -match '(?im)^\s*status:\s*(error|degraded|failed)\s*$'){$state='error'}
            elseif($normalized -match '(?im)^\s*status:\s*(running|pending|not\s+started)\s*$'){$state='running'}
        }
        if($state -eq 'done'){return}
        if($state -eq 'error'){throw "cloud-init failed in $Name`n$normalized"}
        $remaining=[math]::Max(0,($deadline-[DateTime]::UtcNow).TotalSeconds)
        $summary=($normalized -replace '\s+',' ')
        if($summary.Length -gt 240){$summary=$summary.Substring([math]::Max(0,$summary.Length-240))}
        Write-Verbose "Multipass readiness probe $attempt for $Name returned: $summary; $([math]::Round($remaining,1)) seconds remaining."
        if($remaining -le 0){break}
        Start-Sleep -Milliseconds ([int][math]::Min(5000,[math]::Max(100,$remaining*1000)))
    }
    throw "Instance $Name did not become ready within $TimeoutSeconds seconds."
}

function Invoke-MultipassInventoryWithBoundedRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$InventoryScript,
        [datetime]$DeadlineUtc = [datetime]::MinValue,
        [ValidateRange(1,5)][int]$MaximumAttempts = 3
    )
    $deadline = if ($DeadlineUtc -gt [datetime]::MinValue) { $DeadlineUtc.ToUniversalTime() } else { [datetime]::UtcNow.AddSeconds(60) }
    $lastError = $null
    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        $remaining = [int][math]::Floor(($deadline - [datetime]::UtcNow).TotalSeconds)
        if ($remaining -le 0) { break }
        $attemptsRemaining = $MaximumAttempts - $attempt + 1
        $probeTimeout = [math]::Max(1, [math]::Min(60, [int][math]::Floor($remaining / $attemptsRemaining)))
        try {
            return @(& $InventoryScript $probeTimeout)
        } catch {
            $lastError = $_.Exception
        }
        $remainingAfter = [math]::Floor(($deadline - [datetime]::UtcNow).TotalSeconds)
        if ($attempt -lt $MaximumAttempts -and $remainingAfter -gt 0) {
            Start-Sleep -Seconds ([int][math]::Min(1, $remainingAfter))
        }
    }
    if ($lastError) { throw "Multipass inventory retry exhausted: $($lastError.Message)" }
    throw 'Multipass inventory retry exhausted before a bounded probe completed.'
}

function Invoke-DevFleetMultipassControlPlaneRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$MultipassPath,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [scriptblock]$ServiceLookupProvider = { Get-CimInstance Win32_Service -Filter "Name='Multipass'" -ErrorAction Stop },
        [scriptblock]$ServiceControlProvider = { param($Action) $sc=Join-Path $env:SystemRoot 'System32\sc.exe'; if(-not(Test-Path -LiteralPath $sc -PathType Leaf)){throw 'Trusted Windows service controller is missing.'}; & $sc $Action Multipass 2>&1 | Out-Null },
        [scriptblock]$DaemonLookupProvider = { param($Id) Get-Process -Id $Id -ErrorAction Stop },
        [scriptblock]$DaemonStopProvider = { param($Id) Stop-Process -Id $Id -Force -ErrorAction Stop },
        [scriptblock]$ClockProvider = { [datetime]::UtcNow },
        [scriptblock]$SleepProvider = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    )
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Multipass control-plane recovery requires a failure reason.' }
    $deadline = $OwnerDeadlineUtc.ToUniversalTime()
    if ([datetime](& $ClockProvider) -ge $deadline) { throw 'Multipass control-plane recovery owner deadline is already exhausted.' }
    $expectedDaemon = Join-Path (Split-Path -Parent $MultipassPath) 'multipassd.exe'
    $services = @(& $ServiceLookupProvider)
    if ($services.Count -ne 1) { throw "Expected exactly one Multipass service; found $($services.Count)." }
    $service = $services[0]
    if ([string]$service.Name -cne 'Multipass') { throw 'Multipass service lookup returned the wrong service identity.' }
    $serviceCommand = [Environment]::ExpandEnvironmentVariables([string]$service.PathName)
    if ($serviceCommand -notmatch [regex]::Escape($expectedDaemon)) { throw 'Multipass service executable does not match the trusted installation.' }
    if ([string]$service.StartName -notin @('LocalSystem','NT AUTHORITY\SYSTEM')) { throw 'Multipass service identity is not LocalSystem.' }

    $stateBefore = [string]$service.State
    $initialDaemonPid = [int]$service.ProcessId
    $forced = $false
    if ($stateBefore -ne 'Stopped') { & $ServiceControlProvider 'stop' }
    $stopDeadline = ([datetime](& $ClockProvider)).AddSeconds(20)
    if ($deadline -lt $stopDeadline) { $stopDeadline = $deadline }
    do {
        $services = @(& $ServiceLookupProvider)
        if ($services.Count -ne 1) { throw "Expected exactly one Multipass service during stop; found $($services.Count)." }
        $service = $services[0]
        if ([string]$service.State -eq 'Stopped') { break }
        & $SleepProvider 250
    } while ([datetime](& $ClockProvider) -lt $stopDeadline)

    if ([string]$service.State -ne 'Stopped') {
        $daemonPid = [int]$service.ProcessId
        if ($daemonPid -le 0) { $daemonPid = $initialDaemonPid }
        if ($daemonPid -le 0) { throw "Multipass service remained $([string]$service.State) without an exact daemon PID." }
        $daemon = & $DaemonLookupProvider $daemonPid
        if ([string]$daemon.ProcessName -cne 'multipassd') { throw 'Multipass service PID did not identify the exact multipassd process.' }
        $daemonPath = ''
        try { $daemonPath = [string]$daemon.Path } catch { }
        if (-not [string]::IsNullOrWhiteSpace($daemonPath) -and [IO.Path]::GetFullPath($daemonPath) -cne [IO.Path]::GetFullPath($expectedDaemon)) {
            throw 'Multipass daemon PID resolved outside the trusted installation.'
        }
        & $DaemonStopProvider $daemonPid
        $forced = $true
        $forcedDeadline = ([datetime](& $ClockProvider)).AddSeconds(10)
        if ($deadline -lt $forcedDeadline) { $forcedDeadline = $deadline }
        do {
            & $SleepProvider 250
            $services = @(& $ServiceLookupProvider)
            if ($services.Count -ne 1) { throw "Expected exactly one Multipass service after daemon termination; found $($services.Count)." }
            $service = $services[0]
        } while ([string]$service.State -ne 'Stopped' -and [datetime](& $ClockProvider) -lt $forcedDeadline)
        if ([string]$service.State -ne 'Stopped') { throw "Multipass service did not reach Stopped after exact daemon termination; state=$([string]$service.State)." }
    }

    if ([datetime](& $ClockProvider) -ge $deadline) { throw 'Multipass control-plane recovery exhausted its owner deadline before restart.' }
    & $ServiceControlProvider 'start'
    $startDeadline = ([datetime](& $ClockProvider)).AddSeconds(45)
    if ($deadline -lt $startDeadline) { $startDeadline = $deadline }
    do {
        $services = @(& $ServiceLookupProvider)
        if ($services.Count -ne 1) { throw "Expected exactly one Multipass service during start; found $($services.Count)." }
        $service = $services[0]
        if ([string]$service.State -eq 'Running') { break }
        & $SleepProvider 250
    } while ([datetime](& $ClockProvider) -lt $startDeadline)
    if ([string]$service.State -ne 'Running') { throw "Multipass service did not return to Running before its owner deadline; state=$([string]$service.State)." }

    return [pscustomobject]@{
        status = 'PASS'
        service = 'Multipass'
        reason = $Reason
        stateBefore = $stateBefore
        stateAfter = [string]$service.State
        forcedDaemonTermination = $forced
        trustedDaemonPath = $expectedDaemon
        ownerDeadlineUtc = $deadline.ToString('o')
    }
}

function Invoke-MultipassLaunchWithReadinessRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstanceName,
        [Parameter(Mandatory)][string[]]$LaunchArguments,
        [Parameter(Mandatory)][int]$ReadinessTimeoutSeconds,
        [int]$LaunchTimeoutSeconds = 900,
        [datetime]$DeadlineUtc = [datetime]::MinValue,
        [scriptblock]$OnInstanceEstablished,
        [scriptblock]$ControlPlaneRecoveryProvider
    )
    if ($InstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'Multipass launch recovery instance identity is malformed.' }
    $launchArgs = @($LaunchArguments | ForEach-Object { [string]$_ })
    if ($launchArgs.Count -lt 2 -or $launchArgs[0] -cne 'launch') { throw 'Multipass launch recovery requires a launch argument vector.' }
    $nameIndex = [Array]::IndexOf([string[]]$launchArgs, '--name')
    if ($nameIndex -lt 0 -or $nameIndex + 1 -ge $launchArgs.Count -or [string]$launchArgs[$nameIndex + 1] -cne $InstanceName) {
        throw 'Multipass launch recovery refused an argument vector that is not bound to the exact instance name.'
    }
    if ($ReadinessTimeoutSeconds -le 0 -or $LaunchTimeoutSeconds -le 0) { throw 'Multipass launch and readiness deadlines must be positive.' }

    $mp = Get-MultipassExe
    $inventory = {
        param([int]$TimeoutSeconds)
        $raw = Invoke-External -FilePath $mp -ArgumentList @('list','--format','json') -Capture -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $DeadlineUtc
        try {
            $parsed = $raw | ConvertFrom-Json
            return @($parsed.list)
        } catch {
            throw 'Multipass inventory returned malformed JSON during fresh-instance recovery.'
        }
    }
    # This helper is only for the fresh-launch branch. Existing DevFleet
    # instances use their separate backup-preserving refresh path below; a
    # second inventory check prevents a recovery command from being aimed at a
    # pre-existing instance if the caller's earlier snapshot was stale.
    # Reserve a finite recovery slice inside the existing compute/vault stage
    # budget. The normal 900-second operation maximum therefore leaves 600
    # seconds for the initial launch and 300 seconds for one exact recovery.
    $recoveryBudgetSeconds = 300
    $supervisorGraceSeconds = 30
    $minimumOperationSeconds = 60
    if (@($launchArgs | Where-Object { $_ -ieq '--timeout' -or $_ -imatch '^--timeout=' }).Count -gt 0) {
        throw 'Multipass launch recovery rejects caller-supplied --timeout so the inner operation and supervisor deadlines remain separated.'
    }
    $before = @(Invoke-MultipassInventoryWithBoundedRetry -InventoryScript $inventory -DeadlineUtc $DeadlineUtc -MaximumAttempts 3 | Where-Object { [string]$_.name -ceq $InstanceName })
    if ($before.Count -ne 0) { throw "Fresh Multipass launch recovery refused existing instance $InstanceName." }
    $launchBudgetRemaining = $LaunchTimeoutSeconds
    if ($DeadlineUtc -gt [datetime]::MinValue) {
        $launchBudgetRemaining = [math]::Min($launchBudgetRemaining, [int][math]::Floor(($DeadlineUtc.ToUniversalTime() - [datetime]::UtcNow).TotalSeconds))
    }
    $minimumEnvelopeSeconds = $recoveryBudgetSeconds + $supervisorGraceSeconds + $minimumOperationSeconds
    if ($launchBudgetRemaining -lt $minimumEnvelopeSeconds) {
        throw "Multipass launch recovery requires at least $minimumEnvelopeSeconds seconds of remaining bounded stage time; only $launchBudgetRemaining remain."
    }
    $launchAttemptSeconds = [Math]::Min(600, $launchBudgetRemaining - $recoveryBudgetSeconds - $supervisorGraceSeconds)
    $launchSupervisorSeconds = $launchAttemptSeconds + $supervisorGraceSeconds
    $tail = if ($launchArgs.Count -gt 1) { @($launchArgs[1..($launchArgs.Count - 1)]) } else { @() }
    $launchArgs = @('launch','--timeout',[string]$launchAttemptSeconds) + $tail

    $launchSucceeded = $false
    $launchError = $null
    try {
        Invoke-External -FilePath $mp -ArgumentList $launchArgs -TimeoutSeconds $launchSupervisorSeconds -DeadlineUtc $DeadlineUtc
        $launchSucceeded = $true
    } catch {
        $launchError = $_.Exception.Message
    }

    if ($launchSucceeded) {
        if ($OnInstanceEstablished) { & $OnInstanceEstablished ([pscustomobject]@{ recovery = 'none'; launchTimedOut = $false }) }
        Wait-MultipassReady -Name $InstanceName -TimeoutSeconds $ReadinessTimeoutSeconds -DeadlineUtc $DeadlineUtc
        return [pscustomobject]@{ instanceName = $InstanceName; launchTimedOut = $false; recovery = 'none'; ready = $true }
    }

    # Multipass can leave the exact new Hyper-V VM running after its client
    # launch operation times out, while the management IP/SSH path is absent.
    # Confirm one exact post-launch instance before any recovery and surface the
    # original launch error if the instance was never established.
    $recoveryDeadlineUtc = [datetime]::UtcNow.AddSeconds($recoveryBudgetSeconds)
    if ($DeadlineUtc -gt [datetime]::MinValue -and $DeadlineUtc.ToUniversalTime() -lt $recoveryDeadlineUtc) {
        $recoveryDeadlineUtc = $DeadlineUtc.ToUniversalTime()
    }
    $controlPlaneRecovery = $null
    $postLaunchProbeDeadline = [datetime]::UtcNow.AddSeconds(60)
    if ($recoveryDeadlineUtc -lt $postLaunchProbeDeadline) { $postLaunchProbeDeadline = $recoveryDeadlineUtc }
    try {
        $after = @(Invoke-MultipassInventoryWithBoundedRetry -InventoryScript $inventory -DeadlineUtc $postLaunchProbeDeadline -MaximumAttempts 1 | Where-Object { [string]$_.name -ceq $InstanceName })
    } catch {
        $postLaunchInventoryError = $_.Exception.Message
        if ($postLaunchInventoryError -notmatch '(?i)(timed out|cannot connect|connection|socket|failed with exit code)') {
            throw "Multipass launch failed after bounded fresh-instance inventory recovery. Original launch error: $launchError. Post-launch inventory error: $postLaunchInventoryError"
        }
        $recoveryInvoker = if ($ControlPlaneRecoveryProvider) { $ControlPlaneRecoveryProvider } else { ${function:Invoke-DevFleetMultipassControlPlaneRecovery} }
        try {
            $controlPlaneRecovery = & $recoveryInvoker 'POST_LAUNCH_INVENTORY_TRANSPORT_FAILURE' $mp $recoveryDeadlineUtc
            if (-not $controlPlaneRecovery -or [string]$controlPlaneRecovery.status -cne 'PASS') { throw 'Multipass service recovery did not return PASS.' }
        } catch {
            throw "Multipass launch failed and exact control-plane recovery failed. Original launch error: $launchError. Post-launch inventory error: $postLaunchInventoryError. Control-plane recovery error: $($_.Exception.Message)"
        }
        $remainingAfterControlPlaneRecovery = [int][math]::Floor(($recoveryDeadlineUtc - [datetime]::UtcNow).TotalSeconds)
        $instanceRecoveryReserveSeconds = $minimumOperationSeconds + $supervisorGraceSeconds
        if ($remainingAfterControlPlaneRecovery -le $instanceRecoveryReserveSeconds) {
            throw "Multipass launch failed and exact control-plane recovery left insufficient time for exact-instance recovery. Original launch error: $launchError. Post-launch inventory error: $postLaunchInventoryError"
        }
        $inventoryReprobeSeconds = [math]::Min(60, $remainingAfterControlPlaneRecovery - $instanceRecoveryReserveSeconds)
        $inventoryReprobeDeadline = [datetime]::UtcNow.AddSeconds($inventoryReprobeSeconds)
        if ($recoveryDeadlineUtc -lt $inventoryReprobeDeadline) { $inventoryReprobeDeadline = $recoveryDeadlineUtc }
        try {
            $after = @(Invoke-MultipassInventoryWithBoundedRetry -InventoryScript $inventory -DeadlineUtc $inventoryReprobeDeadline -MaximumAttempts 1 | Where-Object { [string]$_.name -ceq $InstanceName })
        } catch {
            throw "Multipass launch failed and inventory remained unavailable after exact control-plane recovery. Original launch error: $launchError. Initial inventory error: $postLaunchInventoryError. Re-probe error: $($_.Exception.Message)"
        }
    }
    if ($after.Count -ne 1) {
        throw "Multipass launch failed without establishing exactly one $InstanceName instance: $launchError"
    }
    if ($OnInstanceEstablished) { & $OnInstanceEstablished ([pscustomobject]@{ recovery = $(if($controlPlaneRecovery){'control-plane-recovered-pending-instance-recovery'}else{'pending'}); launchTimedOut = $true; controlPlaneRecovery = $controlPlaneRecovery }) }

    try {
        # The instance is known to be newly established by this invocation, so
        # one graceful exact stop/start is safe and does not touch any existing
        # deployment or unrelated VM. Both calls inherit the owning deadline.
        $remainingRecoverySeconds = [int][math]::Floor(($recoveryDeadlineUtc - [datetime]::UtcNow).TotalSeconds)
        $startMinimumSeconds = $minimumOperationSeconds + $supervisorGraceSeconds
        if ($remainingRecoverySeconds -lt $startMinimumSeconds) {
            throw "Multipass launch timed out and bounded fresh-instance recovery has insufficient remaining time for stop/start. Original launch error: $launchError"
        }
        $stopTimeoutSeconds = [math]::Min(120, $remainingRecoverySeconds - $startMinimumSeconds)
        Invoke-External -FilePath $mp -ArgumentList @('stop',$InstanceName) -TimeoutSeconds $stopTimeoutSeconds -DeadlineUtc $recoveryDeadlineUtc
        $remainingAfterStopSeconds = [int][math]::Floor(($recoveryDeadlineUtc - [datetime]::UtcNow).TotalSeconds)
        if ($remainingAfterStopSeconds -lt $startMinimumSeconds) {
            throw "Multipass launch timed out and bounded fresh-instance recovery exhausted its stop budget. Original launch error: $launchError"
        }
        $startInnerSeconds = [math]::Min(150, $remainingAfterStopSeconds - $supervisorGraceSeconds)
        $startSupervisorSeconds = $startInnerSeconds + $supervisorGraceSeconds
        Invoke-External -FilePath $mp -ArgumentList @('start','--timeout',[string]$startInnerSeconds,$InstanceName) -TimeoutSeconds $startSupervisorSeconds -DeadlineUtc $recoveryDeadlineUtc
    } catch {
        if ($_.Exception.Message -match 'Original launch error:') { throw }
        throw "Multipass launch timed out and bounded fresh-instance recovery failed for ${InstanceName}. Original launch error: $launchError. Recovery error: $($_.Exception.Message)"
    }
    Wait-MultipassReady -Name $InstanceName -TimeoutSeconds $ReadinessTimeoutSeconds -DeadlineUtc $DeadlineUtc
    return [pscustomobject]@{ instanceName = $InstanceName; launchTimedOut = $true; recovery = $(if($controlPlaneRecovery){'multipass-service-and-instance-stop-start'}else{'multipass-stop-start'}); controlPlaneRecovery = $controlPlaneRecovery; ready = $true }
}

function Get-InstanceIPv4 {
    param([string]$Name,[switch]$PreferTailscale)
    $mp = Get-MultipassExe
    if ($PreferTailscale) {
        $ts = Invoke-External $mp @('exec',$Name,'--','bash','-lc','tailscale ip -4 2>/dev/null | head -n1') -Capture -IgnoreExitCode
        $tsIp = @($ts -split "`r?`n") | Where-Object { $_ -match '^100\.' } | Select-Object -First 1
        if ($tsIp) { return $tsIp.Trim() }
    }
    $raw = Invoke-External $mp @('info',$Name,'--format','json') -Capture
    $obj = $raw | ConvertFrom-Json
    $prop = $obj.info.PSObject.Properties[$Name]
    if (-not $prop) { throw "Multipass info did not contain instance $Name." }
    $ips = @($prop.Value.ipv4) | Where-Object { $_ }
    $preferred = $ips | Where-Object { $_ -notmatch '^(127\.|169\.254\.)' -and $_ -notmatch '^172\.' } | Select-Object -First 1
    if ($preferred) { return $preferred }
    $ips | Where-Object { $_ -notmatch '^(127\.|169\.254\.)' } | Select-Object -First 1
}

function Test-PendingRebootState {
    param(
        [bool]$CbsPending,
        [bool]$WindowsUpdatePending,
        [AllowNull()][object[]]$PendingFileRenameOperations
    )
    if ($CbsPending -or $WindowsUpdatePending) { return $true }
    $meaningful = @($PendingFileRenameOperations | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    })
    $meaningful.Count -gt 0
}

function Get-DevFleetPendingRebootSnapshot {
    $cbsPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $windowsUpdatePending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $session = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    # An if-expression can unwrap a singleton array during assignment. Keep
    # the pending-rename inventory explicitly array-shaped before reading
    # Count so one pending pair remains a valid scalar-safe collection.
    $raw = @()
    if ($null -ne $session) { $raw = @($session.PendingFileRenameOperations) }
    $pairs = [Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $raw.Count; $i += 2) {
        $source = [string]$raw[$i]
        $destination = if ($i + 1 -lt $raw.Count) { [string]$raw[$i + 1] } else { '' }
        if ($source -or $destination) { [void]$pairs.Add("$source`n$destination") }
    }
    [pscustomobject]@{
        CbsPending = [bool]$cbsPending
        WindowsUpdatePending = [bool]$windowsUpdatePending
        PendingPairs = [string[]]$pairs
    }
}

function Set-DevFleetPendingRebootBaseline {
    param([switch]$ResumedTransaction)
    $global:DevFleetPendingRebootBaseline = if ($ResumedTransaction) { Get-DevFleetPendingRebootSnapshot } else { $null }
    return $global:DevFleetPendingRebootBaseline
}

function Test-PendingReboot {
    $current = Get-DevFleetPendingRebootSnapshot
    $baselineVariable = Get-Variable -Name DevFleetPendingRebootBaseline -Scope Global -ErrorAction SilentlyContinue
    $baseline = if ($baselineVariable) { $baselineVariable.Value } else { $null }
    if ($baseline) {
        if ([bool]$current.CbsPending -and -not [bool]$baseline.CbsPending) { return $true }
        if ([bool]$current.WindowsUpdatePending -and -not [bool]$baseline.WindowsUpdatePending) { return $true }
        return @($current.PendingPairs | Where-Object { @($baseline.PendingPairs) -notcontains $_ }).Count -gt 0
    }
    return Test-PendingRebootState -CbsPending:$current.CbsPending -WindowsUpdatePending:$current.WindowsUpdatePending -PendingFileRenameOperations $current.PendingPairs
}

function Install-WingetPackage {
    param([Parameter(Mandatory)][string]$Id,[switch]$Upgrade)
    $health = Get-WingetHealth
    if ($health.Status -ne 'Healthy') { throw "WinGet is not healthy ($($health.Status)); use repair or official vendor fallback." }
    $common = @('--id',$Id,'--exact','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity')
    if ($Upgrade) {
        Invoke-External -FilePath $health.Path -ArgumentList (@('upgrade') + $common) -TimeoutSeconds 600 -AllowedExitCodes @(0,-1978335189) | Out-Null
    } else {
        Invoke-External -FilePath $health.Path -ArgumentList (@('install') + $common) -TimeoutSeconds 600 -AllowedExitCodes @(0,-1978335189) | Out-Null
    }
}

function Get-WingetHealth {
    $candidates = @(Get-TrustedWingetPackageCandidates)
    if($candidates.Count -eq 0){ return [pscustomobject]@{ Status='Missing'; Path=''; Version=''; Detail='No exact physical Microsoft.DesktopAppInstaller x64 package with winget.exe was found.' } }
    if($candidates.Count -ne 1){ return [pscustomobject]@{ Status='Broken'; Path=''; Version=''; Detail='WinGet package identity was ambiguous; exactly one physical package is required.' } }
    $wingetPath = [string]$candidates[0].Path
    if(-not (Test-TrustedExecutableCandidate $wingetPath)){ return [pscustomobject]@{ Status='Missing'; Path=''; Version=''; Detail='The physical WinGet package failed trusted-root or ACL validation.' } }
    try { $versionText = Invoke-External -FilePath $wingetPath -ArgumentList @('--version') -TimeoutSeconds 60 -Capture }
    catch { return [pscustomobject]@{ Status='Broken'; Path=$wingetPath; Version=''; Detail="winget --version could not start: $($_.Exception.Message)" } }
    $version = ([regex]::Match($versionText, '(?<!\d)(\d+\.\d+(?:\.\d+){0,2})')).Groups[1].Value
    try { Invoke-External -FilePath $wingetPath -ArgumentList @('source','list','--disable-interactivity') -TimeoutSeconds 60 | Out-Null }
    catch { return [pscustomobject]@{ Status='Broken'; Path=$wingetPath; Version=$version; Detail="winget source list could not start: $($_.Exception.Message)" } }
    try { Invoke-External -FilePath $wingetPath -ArgumentList @('search','--id','Microsoft.PowerShell','--exact','--source','winget','--disable-interactivity') -TimeoutSeconds 60 | Out-Null }
    catch { return [pscustomobject]@{ Status='Broken'; Path=$wingetPath; Version=$version; Detail="winget package search could not start: $($_.Exception.Message)" } }
    return [pscustomobject]@{ Status='Healthy'; Path=$wingetPath; Version=$version; Detail='version, source list, and package search succeeded.' }
}

function Repair-Winget {
    $repair = 'Install-PackageProvider -Name NuGet -Force | Out-Null; Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null; Repair-WinGetPackageManager -Force -Latest'
    $powershell=Get-DevFleetPowerShell
    Invoke-External -FilePath $powershell -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',$repair) -TimeoutSeconds 600 | Out-Null
    $health = Get-WingetHealth
    if ($health.Status -ne 'Healthy') { throw "WinGet remained unhealthy after repair: $($health.Status)" }
    return $health
}

function Get-AuthenticityStrategy {
    param([Parameter(Mandatory)]$Policy)
    if ($Policy.PSObject.Properties.Name -contains 'strategy' -and $Policy.strategy) { return [string]$Policy.strategy }
    return 'Authenticode'
}

function Test-FileSha256 {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Expected)
    if ($Expected -notmatch '^[0-9a-fA-F]{64}$') { throw "Expected vendor release digest is not a SHA-256 value for $([IO.Path]::GetFileName($Path))." }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if (-not $actual.Equals($Expected, [StringComparison]::OrdinalIgnoreCase)) { throw "Vendor release SHA-256 mismatch for $([IO.Path]::GetFileName($Path)): expected $Expected, got $actual." }
    return $actual.ToLowerInvariant()
}

function Test-OfficialSigner {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Policy)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $strategy = Get-AuthenticityStrategy $Policy
    if ($strategy -eq 'VendorReleaseSha256') { throw "VendorReleaseSha256 requires release metadata digest validation, not Authenticode, for $([IO.Path]::GetFileName($Path))." }
    if ($signature.Status -ne 'Valid' -and $strategy -eq 'Authenticode') { throw "Authenticode verification failed for $([IO.Path]::GetFileName($Path)): $($signature.Status)" }
    if ($signature.Status -ne 'Valid' -and $strategy -eq 'AuthenticodeOrVendorReleaseSha256') { throw "AuthenticodeOrVendorReleaseSha256 requires a valid fallback digest for $([IO.Path]::GetFileName($Path))." }
    $exact=@($Policy.allowedSignerSubjectsExact)
    if(@($exact).Count -gt 0 -and -not (Test-ExactSignerIdentity ([string]$signature.SignerCertificate.Subject) $exact)){throw "Unexpected signer for $([IO.Path]::GetFileName($Path)): $($signature.SignerCertificate.Subject)"}
    if(@($exact).Count -eq 0 -and @($Policy.allowedSignerPatterns).Count -gt 0){throw "Legacy substring signer policy is rejected for $([IO.Path]::GetFileName($Path)); release policy must provide allowedSignerSubjectsExact."}
}

function Save-AllowlistedHttpsDownload {
    param([Parameter(Mandatory)][Uri]$Uri,[Parameter(Mandatory)][string[]]$AllowedHosts,[Parameter(Mandatory)][string]$Path)
    $current=$Uri
    for($hop=0;$hop -le 5;$hop++){
        if($current.Scheme -ne 'https' -or $current.UserInfo -or $current.Host -notin $AllowedHosts){throw "Download redirect left the allowlisted HTTPS boundary: $current"}
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
        $handler=[System.Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false;$client=[System.Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(60);$response=$null;$input=$null;$output=$null
        try{
            $response=$client.GetAsync($current).GetAwaiter().GetResult()
            if([int]$response.StatusCode -ge 300 -and [int]$response.StatusCode -le 399){
                $location=$response.Headers.Location;$response.Dispose();$response=$null
                if(-not $location){throw 'Allowlisted download redirect omitted Location.'}
                $current=[Uri]::new($current,$location);continue
            }
            if(-not $response.IsSuccessStatusCode){throw "Allowlisted download failed with HTTP $([int]$response.StatusCode)."}
            $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult();$output=[IO.File]::Open($Path,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None);$input.CopyTo($output);$output.Flush();return
        } finally {
            if($output){$output.Dispose()};if($input){$input.Dispose()};if($response){$response.Dispose()};$client.Dispose();$handler.Dispose()
        }
    }
    throw 'Allowlisted download exceeded the redirect limit.'
}

function Install-OfficialDependency {
    param([Parameter(Mandatory)]$Dependency)
    if ($Dependency.directOfficialVendorResolver.type -eq 'windows-capability') {
        $capability = Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Client*' | Select-Object -First 1
        if (-not $capability) { throw 'Official OpenSSH Windows capability was not found.' }
        if ($capability.State -ne 'Installed') { Add-WindowsCapability -Online -Name $capability.Name | Out-Null }
        return
    }
    $resolver = $Dependency.directOfficialVendorResolver
    $assetName = $null
    $assetUri = $null
    $expectedDigest = $null
    if ($resolver.type -eq 'github-release') {
        $metadata = Invoke-RestMethod -UseBasicParsing -TimeoutSec 60 -Uri $resolver.metadataUri -Headers @{ 'User-Agent'='DevFleet-Setup/1.4.1' }
        if ($resolver.PSObject.Properties.Name -contains 'expectedOwner' -and $resolver.expectedOwner) {
            if ([string]$metadata.author.login -ne [string]$resolver.expectedOwner) { throw "Official release owner mismatch for $($Dependency.displayName)." }
        }
        if ($resolver.PSObject.Properties.Name -contains 'expectedRepository' -and $resolver.expectedRepository) {
            if ([string]$metadata.html_url -notmatch ("/" + [regex]::Escape([string]$resolver.expectedOwner) + "/" + [regex]::Escape([string]$resolver.expectedRepository) + "/releases/")) { throw "Official release repository mismatch for $($Dependency.displayName)." }
        }
        $pageAssetName = $null
        if ($resolver.PSObject.Properties.Name -contains 'officialPageUri' -and $resolver.officialPageUri) {
            $page = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $resolver.officialPageUri -Headers @{ 'User-Agent'='DevFleet-Setup/1.4.1' }).Content
            $pageLinks = [regex]::Matches($page, '(?i)href\s*=\s*["''](?<href>[^"'']+)["'']') | ForEach-Object { $_.Groups['href'].Value }
            $tag = [string]$metadata.tag_name
            $pageAsset = $null
            foreach ($href in $pageLinks) {
                if ($href -match ("/releases/download/(?<tag>[^/]+)/(?<file>[^?#]+)$") -and $Matches.tag -eq $tag -and $Matches.file -match $resolver.officialPageAssetRegex) { $pageAsset = $href; break }
            }
            if (-not $pageAsset) { throw "Official 7-Zip page did not identify an asset matching the API release tag for $($Dependency.displayName)." }
            $pageAssetName = [IO.Path]::GetFileName(([Uri]$pageAsset).AbsolutePath)
        }
        $asset = @($metadata.assets) | Where-Object { $_.name -match $resolver.assetRegex -and (-not $pageAssetName -or $_.name -eq $pageAssetName) }
        if (@($asset).Count -ne 1) { throw "Expected exactly one official x64 release asset for $($Dependency.displayName), found $(@($asset).Count)." }
        $asset = @($asset)[0]
        $assetName=[string]$asset.name; $assetUri=[Uri]$asset.browser_download_url
        $expectedOwner = if ($resolver.PSObject.Properties.Name -contains 'expectedOwner') { [string]$resolver.expectedOwner } else { '' }
        $expectedRepository = if ($resolver.PSObject.Properties.Name -contains 'expectedRepository') { [string]$resolver.expectedRepository } else { '' }
        if ($expectedOwner -and $expectedRepository -and $assetUri.AbsolutePath -notmatch ("/" + [regex]::Escape($expectedOwner) + "/" + [regex]::Escape($expectedRepository) + "/releases/download/" + [regex]::Escape([string]$metadata.tag_name) + "/")) { throw "Official release asset path/tag mismatch for $($Dependency.displayName)." }
        if ($asset.PSObject.Properties.Name -contains 'digest') { $expectedDigest = ([string]$asset.digest -replace '^sha256:','') }
    } elseif ($resolver.type -eq 'official-download-page') {
        if ($resolver.PSObject.Properties.Name -contains 'directUri' -and $resolver.directUri) {
            $probe = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Method Head -MaximumRedirection 5 -Uri $resolver.directUri -Headers @{ 'User-Agent'='DevFleet-Setup/1.4.1' }
            $candidate = [Uri]$probe.BaseResponse.RequestMessage.RequestUri
            if ($candidate.Host -in @($resolver.allowedHosts) -and ([IO.Path]::GetFileName($candidate.AbsolutePath) -match $resolver.assetRegex)) { $assetUri=$candidate; $assetName=[IO.Path]::GetFileName($candidate.AbsolutePath) }
        } else {
            $page = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $resolver.metadataUri -Headers @{ 'User-Agent'='DevFleet-Setup/1.4.1' }).Content
            $links = [regex]::Matches($page, '(?i)href\s*=\s*["''](?<href>[^"'']+)["'']') | ForEach-Object { $_.Groups['href'].Value }
            foreach ($href in $links) {
                try { $candidate=[Uri]::new([Uri]$resolver.metadataUri,$href) } catch { continue }
                if ($candidate.Host -in @($resolver.allowedHosts) -and ([IO.Path]::GetFileName($candidate.AbsolutePath) -match $resolver.assetRegex)) { $assetUri=$candidate; $assetName=[IO.Path]::GetFileName($candidate.AbsolutePath); break }
            }
        }
    } else { throw "No implemented authenticated direct resolver for $($Dependency.displayName); official source: $($resolver.metadataUri)" }
    if (-not $assetUri -or $assetUri.Host -notin @($resolver.allowedHosts)) { throw "No authenticated official asset matched for $($Dependency.displayName)." }
    $cache = Join-Path (Get-DevFleetStateRoot) 'InstallerCache\Dependencies'; New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $path = Join-Path $cache $assetName
    $downloaded = $false
    for($attempt=1;$attempt -le 3;$attempt++) { try { Save-AllowlistedHttpsDownload -Uri $assetUri -AllowedHosts @($resolver.allowedHosts) -Path $path; $downloaded=$true; break } catch { if($attempt -eq 3){throw}; Start-Sleep -Seconds $attempt } }
    if (-not $downloaded -or -not (Test-Path -LiteralPath $path)) { throw "Official download did not complete for $($Dependency.displayName)." }
    if ($Dependency.installerAuthenticityPolicy.extensions -notcontains ([IO.Path]::GetExtension($path).ToLowerInvariant())) { throw "Unexpected installer file type for $($Dependency.displayName)." }
    $strategy = Get-AuthenticityStrategy $Dependency.installerAuthenticityPolicy
    if ($strategy -eq 'VendorReleaseSha256' -or $strategy -eq 'AuthenticodeOrVendorReleaseSha256') {
        if (-not $expectedDigest) { throw "Official vendor release did not provide a SHA-256 digest for $($Dependency.displayName)." }
        Test-FileSha256 -Path $path -Expected $expectedDigest | Out-Null
        Write-Host "Verified $($Dependency.displayName) using VendorReleaseSha256 (Authenticode status: $((Get-AuthenticodeSignature -LiteralPath $path).Status))." -ForegroundColor Green
        if ($strategy -eq 'AuthenticodeOrVendorReleaseSha256') {
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            if ($signature.Status -eq 'Valid') { Test-OfficialSigner -Path $path -Policy $Dependency.installerAuthenticityPolicy }
        }
    } else {
        Test-OfficialSigner -Path $path -Policy $Dependency.installerAuthenticityPolicy
    }
    $args = @($Dependency.silentInstallArguments)
    if ([IO.Path]::GetExtension($path).ToLowerInvariant() -eq '.msi') { $msiexec=Join-Path $env:WINDIR 'System32\msiexec.exe';if(-not (Test-TrustedExecutableCandidate $msiexec)){throw 'Trusted Windows Installer executable was not found.'};Invoke-External -FilePath $msiexec -ArgumentList (@('/i',$path)+$args) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') | Out-Null } else { Invoke-External -FilePath $path -ArgumentList $args -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') | Out-Null }
}

function Convert-SecureStringToBundlePassword {
    param([Parameter(Mandatory)][Security.SecureString]$SecureString)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function New-EncryptedBundle {
    param(
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$OutputPath,
        [Security.SecureString]$Passphrase
    )
    # A supplied SecureStr