# DevFleet source part 109

Full-source UTF-8 byte interval [5022000, 5068500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 47ccb564949636182df1ed65252f3349b908f6ade1ef24e641475d91d3dcb771

<!-- BEGIN SOURCE SLICE -->
econds 'sshAndMarker')
    }
    if ($StageName -eq 'vault') {
        return (Get-DevFleetOperationMaximumSeconds 'vaultSnapshot') + (Get-DevFleetOperationMaximumSeconds 'multipassLaunch') + (Get-DevFleetOperationMaximumSeconds 'multipassReadiness') + (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') + (Get-DevFleetOperationMaximumSeconds 'vaultBootstrap') + (Get-DevFleetOperationMaximumSeconds 'sshAndMarker')
    }
    $budgets = @{
        bootstrap = (Get-DevFleetOperationMaximumSeconds 'bootstrap')
        preflight = (Get-DevFleetOperationMaximumSeconds 'preflight')
        prerequisites = (6 * ((Get-DevFleetOperationMaximumSeconds 'dependencyProbe') + (Get-DevFleetOperationMaximumSeconds 'dependencyHealth') + (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') + (Get-DevFleetOperationMaximumSeconds 'dependencyVerification'))) + (Get-DevFleetOperationMaximumSeconds 'windowsCapability') + (Get-DevFleetOperationMaximumSeconds 'windowsFeature') + (4 * (Get-DevFleetOperationMaximumSeconds 'multipassConfiguration')) + (3 * (Get-DevFleetOperationMaximumSeconds 'vscodeExtension'))
        windowsTailscale = 900
        hostAgent = 300
        tailscale = 900
        vaultClient = 300
        shortcuts = 180
        export = 300
        verification = 300
    }
    if (-not $budgets.ContainsKey($StageName)) { throw "No finite deadline policy exists for stage '$StageName'." }
    return [int]$budgets[$StageName]
}

function Get-DevFleetOperationMaximumSeconds {
    param([Parameter(Mandatory)][ValidateSet('bootstrap','preflight','prerequisites','dependencyProbe','dependencyHealth','dependencyInstall','dependencyVerification','windowsCapability','windowsFeature','multipassConfiguration','vscodeExtension','windowsTailscale','hostAgent','multipassLaunch','multipassReadiness','payloadTransfer','guestBootstrap','vaultBootstrap','sshAndMarker','vaultSnapshot','tailscale','vaultClient','shortcuts','export','verification')][string]$OperationName)
    $operation = [ordered]@{
        bootstrap = 240; preflight = 120; prerequisites = 0; dependencyProbe = 60; dependencyHealth = 180; dependencyInstall = 1800; dependencyVerification = 60; windowsCapability = 900; windowsFeature = 900; multipassConfiguration = 600; vscodeExtension = 300; windowsTailscale = 900; hostAgent = 300
        multipassLaunch = 900; multipassReadiness = 1200; payloadTransfer = 900
        guestBootstrap = (900 + 1200 + 1200 + 600 + 600 + 1200 + 600) + 300
        vaultBootstrap = 3900
        sshAndMarker = 300; vaultSnapshot = 300; tailscale = 900; vaultClient = 300
        shortcuts = 180; export = 300; verification = 300
    }
    $operation.prerequisites = 6 * ($operation.dependencyProbe + $operation.dependencyHealth + $operation.dependencyInstall + $operation.dependencyVerification) + $operation.windowsCapability + $operation.windowsFeature + (4 * $operation.multipassConfiguration) + (3 * $operation.vscodeExtension)
    return [int]$operation[$OperationName]
}

function Get-DevFleetTransactionBudgetSeconds {
    param([Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role)
    $stageNames = if ($Role -eq 'Laptop') {
        @('bootstrap','preflight','prerequisites','windowsTailscale','hostAgent','compute','vault','tailscale','tailscale','vaultClient','shortcuts','export','verification')
    } else {
        @('bootstrap','preflight','prerequisites','windowsTailscale','hostAgent','compute','tailscale','shortcuts','export','verification')
    }
    $total = 0
    foreach ($stage in $stageNames) { $total += Get-DevFleetStageBudgetSeconds $stage }
    return $total + 600
}

function Assert-PowerShell7 {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'PowerShell 7 or newer is required. Re-run Bootstrap-Install.ps1 so the verified local PowerShell payload can be installed.'
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    if (-not (Test-Administrator)) { throw 'Run PowerShell 7 as Administrator.' }
}

function Initialize-DevFleetState {
    param([Parameter(Mandatory)][string]$PackageRoot)
    $root = Get-DevFleetStateRoot
    foreach ($dir in @($root, "$root\exports", "$root\logs", "$root\secrets", "$root\tmp")) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $configPath = Join-Path $root 'devfleet.config.json'
    if (-not (Test-Path $configPath)) {
        Copy-Item (Join-Path $PackageRoot 'config\devfleet.config.json') $configPath
    }
    Set-Content -Path (Join-Path $root 'package-root.txt') -Value $PackageRoot -Encoding utf8
    Protect-DevFleetStateAcl
}

function Get-OrCreateNodeIdentity {
    param([Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role)
    $path = Join-Path (Get-DevFleetStateRoot) 'node-identity.json'
    if (Test-Path -LiteralPath $path) { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    $isPrimary = $Role -eq 'Desktop'
    $identity = [ordered]@{
        schema_version = 1
        deployment_id = if ($isPrimary) { [guid]::NewGuid().ToString() } else { '' }
        node_id = [guid]::NewGuid().ToString()
        node_name = $env:COMPUTERNAME
        node_role = if ($isPrimary) { 'primary' } else { 'surrogate' }
        coordinator_node_id = $null
        protocol_version = 1
        registration_state = if ($isPrimary) { 'coordinator' } else { 'awaiting-primary-join' }
        created_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $identity | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
    Protect-DevFleetStateAcl
    return $identity | ConvertTo-Json | ConvertFrom-Json
}

function Get-OrCreateVaultIdentity {
    $path = Join-Path (Get-DevFleetStateRoot) 'vault-node-identity.json'
    if (Test-Path -LiteralPath $path) {
        $identity = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ([string]$identity.node_role -ne 'vault' -or [string]$identity.node_id -notmatch '^[0-9a-fA-F-]{36}$' -or ([string]$identity.deployment_id -and [string]$identity.deployment_id -notmatch '^[0-9a-fA-F-]{36}$')) { throw 'Vault identity is invalid; explicit recovery is required.' }
        return $identity
    }
    $hostIdentity = Get-OrCreateNodeIdentity -Role Laptop
    $identity = [ordered]@{schema_version=1;deployment_id=[string]$hostIdentity.deployment_id;node_id=[guid]::NewGuid().ToString('D');node_name=(Get-DevFleetConfig).Vault.InstanceName;node_role='vault';created_at=(Get-Date).ToUniversalTime().ToString('o')}
    $identity | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
    Protect-DevFleetStateAcl
    return $identity | ConvertTo-Json | ConvertFrom-Json
}

function Protect-DevFleetStateAcl {
    $root = Get-DevFleetStateRoot
    if (-not (Test-Path $root)) { return }
    $acl = Get-Acl $root
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($existing in @($acl.Access)) { $acl.RemoveAccessRuleAll($existing) }
    foreach ($rule in @(
        [Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow'),
        [Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow'),
        [Security.AccessControl.FileSystemAccessRule]::new("$env:USERDOMAIN\$env:USERNAME",'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    )) { $acl.AddAccessRule($rule) | Out-Null }
    Set-Acl -Path $root -AclObject $acl
}

function Get-DevFleetConfig {
    $path = Join-Path (Get-DevFleetStateRoot) 'devfleet.config.json'
    if (-not (Test-Path $path)) { throw "Missing config: $path" }
    Get-Content $path -Raw | ConvertFrom-Json
}

function Save-DevFleetConfig {
    param([Parameter(Mandatory)]$Config)
    $path = Join-Path (Get-DevFleetStateRoot) 'devfleet.config.json'
    $Config | ConvertTo-Json -Depth 20 | Set-Content $path -Encoding utf8
}

function Get-PackageRootFromState {
    $p = Join-Path (Get-DevFleetStateRoot) 'package-root.txt'
    if (Test-Path $p) { return (Get-Content $p -Raw).Trim() }
    Get-DevFleetPackageRoot
}

function New-RandomSecret {
    param([int]$Bytes = 32)
    $data = New-Object byte[] $Bytes
    [Security.Cryptography.RandomNumberGenerator]::Fill($data)
    [Convert]::ToBase64String($data).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function ConvertTo-YamlSingleQuotedScalar {
    param([AllowNull()][string]$Value)
    $text = if ($null -eq $Value) { '' } else { $Value }
    if ($text.IndexOfAny([char[]]"`0`r`n") -ge 0) { throw 'YAML scalar contains a forbidden control or newline character.' }
    return "'" + $text.Replace("'", "''") + "'"
}

function ConvertTo-ShellSingleQuotedScalar {
    param([AllowNull()][string]$Value)
    $text = if ($null -eq $Value) { '' } else { $Value }
    if ($text.IndexOfAny([char[]]"`0`r`n") -ge 0) { throw 'Shell scalar contains a forbidden control or newline character.' }
    return "'" + $text.Replace("'", "'\''") + "'"
}

function Test-ExistingDeploymentState {
    $root = Get-DevFleetStateRoot
    foreach ($name in @('node-identity.json','deployment.json','host-agent-registry.json','projects.json')) {
        $candidate = Join-Path $root $name
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Get-Item -LiteralPath $candidate).Length -gt 2) { return $true }
    }
    return $false
}

function Test-DevFleetSecretRecord {
    param([Parameter(Mandatory)]$Secrets)
    foreach ($field in @('PortalAdminUser','PortalAdminPassword','NodeApiToken','ResticPassword','VaultRestUser','VaultRestPassword')) {
        if (-not $Secrets.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$Secrets.$field)) { return $false }
    }
    if ([string]$Secrets.PortalAdminPassword -match '[\r\n]' -or [string]$Secrets.NodeApiToken -match '[\r\n]' -or [string]$Secrets.ResticPassword -match '[\r\n]' -or [string]$Secrets.VaultRestPassword -match '[\r\n]') { return $false }
    if ([string]$Secrets.NodeApiToken -notmatch '^[A-Za-z0-9_-]{40,}$' -or [string]$Secrets.ResticPassword -notmatch '^[A-Za-z0-9_-]{40,}$') { return $false }
    if ($Secrets.PSObject.Properties['SecretGeneration'] -and $Secrets.SecretGeneration) {
        $generation = [guid]::Empty
        if (-not [guid]::TryParse([string]$Secrets.SecretGeneration,[ref]$generation) -or $generation -eq [guid]::Empty) { return $false }
    }
    return $true
}

function New-DevFleetSecretRecord {
    param([string]$Generation = ([guid]::NewGuid().ToString('D')))
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Generation,[ref]$parsed) -or $parsed -eq [guid]::Empty) { throw 'Secret generation must be a non-empty UUID.' }
    [ordered]@{
        SchemaVersion = 2
        SecretGeneration = $Generation
        PortalAdminUser = 'dylan'
        PortalAdminPassword = New-RandomSecret 24
        NodeApiToken = New-RandomSecret 32
        ResticPassword = New-RandomSecret 40
        VaultRestUser = "devfleet-client-$($Generation.Substring(0,8))"
        VaultRestPassword = New-RandomSecret 32
        Created = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-OrCreateSecrets {
    $path = Join-Path (Get-DevFleetStateRoot) 'secrets\host-secrets.json'
    if (-not (Test-Path $path)) {
        if (Test-ExistingDeploymentState) { throw 'SECRET RECOVERY REQUIRED: host secrets are missing while existing DevFleet deployment state is present. Use the explicit re-key/repair workflow.' }
        $obj = New-DevFleetSecretRecord
        $obj | ConvertTo-Json | Set-Content $path -Encoding utf8
        Protect-DevFleetStateAcl
    }
    try {
        $secrets = Get-Content $path -Raw | ConvertFrom-Json
        if (-not (Test-DevFleetSecretRecord -Secrets $secrets)) { throw 'Host secret record is incomplete or invalid.' }
        return $secrets
    }
    catch {
        if (Test-ExistingDeploymentState) { throw 'SECRET RECOVERY REQUIRED: host secrets are corrupt while existing DevFleet deployment state is present. Use the explicit re-key/repair workflow.' }
        throw 'Host secrets are corrupt; remove the incomplete fresh-install state and restart setup.'
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @(),
        [Parameter()][int[]]$RedactArgumentIndexes = @(),
        [Parameter()][int]$TimeoutSeconds = 900,
        [Parameter()][int]$MaxDiagnosticChars = 12000,
        [Parameter()][string]$EvidenceLogPath = '',
        [Parameter()][string]$StandardInputText = '',
        [Parameter()][datetime]$DeadlineUtc = [datetime]::MinValue,
        [Parameter()][int[]]$AllowedExitCodes = @(0),
        [switch]$IgnoreExitCode,
        [switch]$Capture
    )
    # Parameter binding may receive a scalar or null when a caller supplies a
    # single/empty argument set. Normalize before indexing or reading Count.
    $ArgumentList = @($ArgumentList)
    $deadlineContext=Get-DevFleetDeadlineContext
    # An explicit child deadline is subordinate to the active owning stage.
    # Taking the minimum here prevents a nested helper (for example readiness
    # or a bounded retry loop) from accidentally escaping its stage merely by
    # supplying its own finite deadline.
    $deadlines = @()
    if ($DeadlineUtc -gt [datetime]::MinValue) { $deadlines += $DeadlineUtc.ToUniversalTime() }
    if ($deadlineContext) { $deadlines += ([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime() }
    $deadline = if ($deadlines.Count -gt 0) { ($deadlines | Measure-Object -Minimum).Minimum } else { [datetime]::MinValue }
    if ($deadline -gt [datetime]::MinValue) {
        $remaining = [int][math]::Floor(($deadline - [datetime]::UtcNow).TotalSeconds)
        if ($remaining -le 0) { throw "Owning deadline expired before starting external command: $FilePath" }
        $TimeoutSeconds = [math]::Min($TimeoutSeconds, $remaining)
    }
    if ($TimeoutSeconds -le 0) { throw 'External command timeout must remain positive after deadline propagation.' }
    # One immutable operation deadline owns process start, stdin delivery and
    # execution.  Do not grant WaitForExit a fresh full timeout after a slow or
    # blocked input write has already consumed owner time.
    $operationDeadlineUtc = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    if ($deadline -gt [datetime]::MinValue -and $deadline -lt $operationDeadlineUtc) { $operationDeadlineUtc = $deadline }
    $remainingMilliseconds = {
        $milliseconds = [math]::Ceiling(($operationDeadlineUtc - [datetime]::UtcNow).TotalMilliseconds)
        if ($milliseconds -le 0) { return 0 }
        return [int][math]::Min([int]::MaxValue, $milliseconds)
    }
    $safeArguments = for($i=0;$i -lt $ArgumentList.Count;$i++){ if($RedactArgumentIndexes -contains $i){ '<redacted-secret>' } else { [string]$ArgumentList[$i] } }
    Write-Verbose ("Executing: {0} {1}" -f $FilePath, ($safeArguments -join ' '))
    $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$FilePath;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.RedirectStandardInput=($null -ne $StandardInputText -and $StandardInputText.Length -gt 0)
    if($psi.RedirectStandardInput){$psi.StandardInputEncoding=[Text.UTF8Encoding]::new($false)}
    foreach($argument in $ArgumentList){[void]$psi.ArgumentList.Add([string]$argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$psi;$stdoutTail=[Text.StringBuilder]::new();$stderrTail=[Text.StringBuilder]::new();$logWriter=$null;$inputError=''
    try {
        if($EvidenceLogPath){$parent=Split-Path -Parent $EvidenceLogPath;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$logWriter=[IO.StreamWriter]::new($EvidenceLogPath,$false,[Text.Encoding]::UTF8)}
        if(-not $process.Start()){throw "Unable to start external command: $FilePath"}
        # Drain both output streams before delivering input.  A child is
        # allowed to write output before reading stdin; reversing this order
        # can deadlock both sides on finite OS pipe buffers.
        $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
        if($psi.RedirectStandardInput){
            $inputTask=$null
            try {$inputTask=$process.StandardInput.WriteAsync($StandardInputText)} catch {$inputError=$_.Exception.GetBaseException().Message}
            if($inputTask){
                $inputCompleted=$false
                try {$inputCompleted=$inputTask.Wait((&$remainingMilliseconds))} catch {$inputCompleted=$true;$inputError=$_.Exception.GetBaseException().Message}
                if(-not $inputCompleted){
                    try{$process.Kill($true)}catch{}
                    try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
                    throw "External command input delivery timed out before the owning deadline: $FilePath $($safeArguments -join ' ')"
                }
                if(-not $inputError){
                    try {[void]$inputTask.GetAwaiter().GetResult();$flushTask=$process.StandardInput.FlushAsync();$flushCompleted=$flushTask.Wait((&$remainingMilliseconds));if(-not $flushCompleted){try{$process.Kill($true)}catch{};throw "External command input flush timed out before the owning deadline: $FilePath $($safeArguments -join ' ')"};[void]$flushTask.GetAwaiter().GetResult()} catch {$inputError=$_.Exception.GetBaseException().Message}
                }
            }
            try {$process.StandardInput.Close()} catch {if(-not $inputError){$inputError=$_.Exception.GetBaseException().Message}}
            if($inputError -and -not $process.HasExited){
                # Give an exiting child a short slice of the existing owner
                # budget so its direct exit code remains the primary result.
                # A child that stays alive after breaking its input pipe is
                # terminated exactly and reported as an input transport fault,
                # not allowed to consume the rest of the deadline and obscure it.
                $exitObservationMilliseconds=[math]::Min(500,(&$remainingMilliseconds))
                if($exitObservationMilliseconds -gt 0){try{[void]$process.WaitForExit($exitObservationMilliseconds)}catch{}}
                if(-not $process.HasExited){
                    try{$process.Kill($true)}catch{}
                    try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
                    throw "External command input delivery failed: $FilePath $($safeArguments -join ' ')`n$inputError"
                }
            }
        }
        $executionRemainingMilliseconds=&$remainingMilliseconds
        if($executionRemainingMilliseconds -le 0 -or -not $process.WaitForExit($executionRemainingMilliseconds)){
            try{$process.Kill($true)}catch{}
            try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
            throw "External command timed out after $TimeoutSeconds seconds: $FilePath $($safeArguments -join ' ')"
        }
        $exitCode=$process.ExitCode
        $outputComplete=$false
        try{$outputComplete=[Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5))}catch{$outputComplete=$false}
        $stdout=if($stdoutTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdoutTask.GetAwaiter().GetResult()}else{''}
        $stderr=if($stderrTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderrTask.GetAwaiter().GetResult()}else{''}
        $combined=($stdout+"`n"+$stderr).Trim()
        if($logWriter){$logWriter.Write($combined);if(-not $outputComplete){$logWriter.Write("`n[DEVFLEET_OUTPUT_INCOMPLETE_AFTER_PROCESS_EXIT]")};$logWriter.Flush()}
        $diagnostic=if($combined.Length -gt $MaxDiagnosticChars){$combined.Substring($combined.Length-$MaxDiagnosticChars)}else{$combined}
        if(-not $outputComplete){
            $message="External command exited with code $exitCode, but redirected output was incomplete after the bounded post-exit drain: $FilePath $($safeArguments -join ' ')"
            if($Capture){throw $message}
            if($exitCode -notin $AllowedExitCodes -and -not $IgnoreExitCode){throw "$message`n$diagnostic"}
            Write-Warning $message
            return
        }
        if($exitCode -notin $AllowedExitCodes -and -not $IgnoreExitCode){throw "$FilePath failed with exit code $exitCode`n$diagnostic"}
        if($inputError){throw "External command input delivery failed: $FilePath $($safeArguments -join ' ')`n$inputError"}
        if($Capture){return $combined}
    } finally {if($logWriter){$logWriter.Dispose()};$process.Dispose()}
}

function Invoke-MultipassWithStandardInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$InstanceName,
        [Parameter(Mandatory)][string[]]$CommandArgumentList,
        [Parameter(Mandatory)][AllowEmptyString()][string]$StandardInputText,
        [int]$TimeoutSeconds=900,
        [datetime]$DeadlineUtc=[datetime]::MinValue,
        [switch]$Capture,
        [string]$ExpectedCompletionMarkerPattern=''
    )
    if($InstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or -not $CommandArgumentList.Count){throw 'Multipass input command identity is malformed.'}
    if([string]::IsNullOrEmpty($StandardInputText)){throw 'Multipass input delivery requires a nonempty byte stream.'}
    $remoteCommand=(@($CommandArgumentList|ForEach-Object{ConvertTo-ShellSingleQuotedScalar $_}) -join ' ')
    $ownerDeadline=[datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    if($DeadlineUtc -gt [datetime]::MinValue -and $DeadlineUtc.ToUniversalTime() -lt $ownerDeadline){$ownerDeadline=$DeadlineUtc.ToUniversalTime()}
    $context=Get-DevFleetDeadlineContext
    if($context -and ([datetime]$context.StageDeadlineUtc).ToUniversalTime() -lt $ownerDeadline){$ownerDeadline=([datetime]$context.StageDeadlineUtc).ToUniversalTime()}
    # Reserve cleanup inside the existing owner; no command receives a fresh
    # full timeout after staging or a slow transfer.
    $workDeadline=$ownerDeadline.AddSeconds(-15)
    $cleanupDeadline=$ownerDeadline.AddSeconds(-5)
    if($workDeadline -le [datetime]::UtcNow){throw 'Insufficient owning deadline for Multipass input delivery and cleanup.'}
    $directory='/run/devfleet-input-'+[guid]::NewGuid().ToString('N')
    $inputPath="$directory/input"
    $quotedDirectory=ConvertTo-ShellSingleQuotedScalar $directory
    $quotedInput=ConvertTo-ShellSingleQuotedScalar $inputPath
    # Windows Multipass exec reads console events, not redirected stdin.
    # SFTP transfer '-' supports a byte stream. Create its destination first
    # in a fresh private tmpfs directory, so no host plaintext file or secret
    # argument is needed and SFTP cannot create a publicly reachable file.
    $prepare=@'
set -Eeuo pipefail; d=__DIRECTORY__; f=__INPUT__; created=0; trap 'rc=$?; if (( created )); then sudo rm -f -- "$f" || true; sudo rmdir -- "$d" || true; fi; exit "$rc"' EXIT; sudo mkdir -m 0700 -- "$d"; created=1; sudo chown "$(id -u):$(id -g)" -- "$d"; umask 077; : > "$f"; chmod 0600 -- "$f"; test ! -L "$d"; test "$(stat -c '%a:%u' -- "$d")" = "700:$(id -u)"; test ! -L "$f"; test "$(stat -c '%a:%u' -- "$f")" = "600:$(id -u)"; trap - EXIT
'@
    $consume=@'
set -Eeuo pipefail; d=__DIRECTORY__; f=__INPUT__; test ! -L "$d"; test -d "$d"; test "$(stat -c '%a:%u' -- "$d")" = "700:$(id -u)"; test ! -L "$f"; test -f "$f"; test -s "$f"; test "$(stat -c '%a:%u' -- "$f")" = "600:$(id -u)"; exec 3< "$f"; rm -f -- "$f"; sudo rmdir -- "$d"; exec 0<&3; exec 3<&-; exec __COMMAND__
'@
    $cleanup=@'
set -Eeuo pipefail; d=__DIRECTORY__; f=__INPUT__; if test -e "$d" || test -L "$d"; then test ! -L "$d"; test -d "$d"; test "$(stat -c '%a:%u' -- "$d")" = "700:$(id -u)"; if test -e "$f" || test -L "$f"; then test ! -L "$f"; test -f "$f"; test "$(stat -c '%u' -- "$f")" = "$(id -u)"; rm -f -- "$f"; fi; sudo rmdir -- "$d"; fi
'@
    $prepare=$prepare.Replace('__DIRECTORY__',$quotedDirectory).Replace('__INPUT__',$quotedInput)
    $consume=$consume.Replace('__DIRECTORY__',$quotedDirectory).Replace('__INPUT__',$quotedInput).Replace('__COMMAND__',$remoteCommand)
    $cleanup=$cleanup.Replace('__DIRECTORY__',$quotedDirectory).Replace('__INPUT__',$quotedInput)
    $acquired=$false;$primaryError=$null;$cleanupError=$null;$output=$null
    try {
        Invoke-External $FilePath @('exec',$InstanceName,'--','bash','-lc',$prepare) -TimeoutSeconds 60 -DeadlineUtc $workDeadline
        $acquired=$true
        Invoke-External $FilePath @('transfer','-',"${InstanceName}:$inputPath") -TimeoutSeconds 60 -DeadlineUtc $workDeadline -StandardInputText $StandardInputText
        if($ExpectedCompletionMarkerPattern){
            if(-not $Capture){throw 'Expected Multipass completion-marker handling requires captured output.'}
            # A guest command that changes its own network can finish the
            # authenticated operation and emit its sentinel while the outer
            # Multipass transport reports a nonzero status as its connection
            # is torn down. Accept that status only for this explicit marker
            # contract; preparation, transfer, cleanup, and all generic
            # callers remain strict about external exit codes.
            $output=Invoke-External $FilePath @('exec',$InstanceName,'--','bash','-lc',$consume) -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $workDeadline -Capture -IgnoreExitCode
            if(-not [regex]::IsMatch([string]$output,$ExpectedCompletionMarkerPattern,[Text.RegularExpressions.RegexOptions]::Multiline)){
                throw 'Multipass input command returned without its expected completion marker.'
            }
        }else{
            $output=Invoke-External $FilePath @('exec',$InstanceName,'--','bash','-lc',$consume) -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $workDeadline -Capture:$Capture
        }
    } catch {$primaryError=$_}
    finally {
        # No secret is sent until preparation acknowledges a fresh private
        # directory. Once acknowledged, cleanup is exact and non-recursive.
        if($acquired){
            try {Invoke-External $FilePath @('exec',$InstanceName,'--','bash','-lc',$cleanup) -TimeoutSeconds 10 -DeadlineUtc $cleanupDeadline}
            catch {$cleanupError=$_}
        }
        $StandardInputText=$null
    }
    if($primaryError){
        if($cleanupError){throw "Multipass input command failed: $($primaryError.Exception.Message)`nGuest input cleanup failed: $($cleanupError.Exception.Message)"}
        $PSCmdlet.ThrowTerminatingError($primaryError)
    }
    if($cleanupError){$PSCmdlet.ThrowTerminatingError($cleanupError)}
    if($Capture){return $output}
}

function New-DevFleetBootstrapBoundary {
    param(
        [Parameter(Mandatory)][ValidateSet('compute','vault')][string]$Kind,
        [Parameter(Mandatory)][string]$InstanceName,
        [Parameter(Mandatory)][string]$TransactionId,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][int]$BootstrapMaxSeconds,
        [Parameter(Mandatory)][string]$PackageVersion,
        [Parameter(Mandatory)][string]$NodeRole
    )
    if($InstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){throw 'Bootstrap instance identity is malformed.'}
    if($TransactionId -notmatch '^[0-9a-fA-F]{32}$' -or $PayloadSha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Bootstrap transaction or payload identity is malformed.'}
    if($BootstrapMaxSeconds -le 0){throw 'Bootstrap maximum must be a positive finite duration.'}
    if($Kind -eq 'compute'){
        if($PackageVersion -notmatch '^\d+\.\d+\.\d+$' -or $NodeRole -notin @('primary','surrogate')){throw 'Compute bootstrap version or role identity is malformed.'}
        $extraction="set -Eeuo pipefail; sudo rm -rf /tmp/devfleet-payload; mkdir /tmp/devfleet-payload; if ! unzip -q /tmp/devfleet-payload.zip -d /tmp/devfleet-payload; then sudo rm -rf /tmp/devfleet-payload /tmp/devfleet-payload.zip; exit 70; fi; test -f /tmp/devfleet-payload/linux/bootstrap-compute.sh"
        $bootstrap="set -Eeuo pipefail; trap 'sudo rm -rf /tmp/devfleet-payload /tmp/devfleet-payload.zip' EXIT; sudo bash /tmp/devfleet-payload/linux/bootstrap-compute.sh /tmp/devfleet-payload --secrets-stdin --transaction-id '$TransactionId' --payload-sha256 '$PayloadSha256' --bootstrap-max-seconds '$BootstrapMaxSeconds' --package-version '$PackageVersion' --node-role '$NodeRole'"
        $prefix="compute-$InstanceName"
    }else{
        if($PackageVersion -cne 'vault' -or $NodeRole -cne 'vault'){throw 'Vault bootstrap version or role identity is malformed.'}
        $extraction="set -Eeuo pipefail; sudo rm -rf /tmp/devfleet-vault-payload; mkdir /tmp/devfleet-vault-payload; if ! unzip -q /tmp/devfleet-vault-payload.zip -d /tmp/devfleet-vault-payload; then sudo rm -rf /tmp/devfleet-vault-payload /tmp/devfleet-vault-payload.zip; exit 70; fi; test -f /tmp/devfleet-vault-payload/linux/bootstrap-vault.sh"
        $bootstrap="set -Eeuo pipefail; trap 'sudo rm -rf /tmp/devfleet-vault-payload /tmp/devfleet-vault-payload.zip' EXIT; sudo bash /tmp/devfleet-vault-payload/linux/bootstrap-vault.sh /tmp/devfleet-vault-payload --secrets-stdin --transaction-id '$TransactionId' --payload-sha256 '$PayloadSha256' --bootstrap-max-seconds '$BootstrapMaxSeconds' --package-version 'vault' --node-role 'vault'"
        $prefix='vault'
    }
    [pscustomobject]@{
        kind=$Kind
        instanceName=$InstanceName
        multipassResolvedStageName="$prefix-multipass-resolved"
        isolationVerifiedStageName="$prefix-isolation-verified"
        instancePresentStageName="$prefix-instance-present"
        instanceAbsentStageName="$prefix-instance-absent"
        instanceStartedStageName="$prefix-instance-started"
        instanceLaunchedStageName="$prefix-instance-launched"
        instanceReadyStageName="$prefix-instance-ready"
        payloadTransferredStageName="$prefix-payload-transferred"
        payloadExtractedStageName="$prefix-payload-extracted"
        completionStageName=$prefix
        extractionCommand=$extraction
        bootstrapCommand=$bootstrap
        remoteCommand="$extraction; $bootstrap"
        bootstrapMaxSeconds=$BootstrapMaxSeconds
    }
}

function Test-CommandExists { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Get-DevFleetPowerShell {
    foreach($candidate in @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
    )) { if($candidate -and (Test-TrustedExecutableCandidate $candidate)){return $candidate} }
    throw 'No trusted machine PowerShell executable was found.'
}

function Get-CanonicalDependencyManifest {
    param([Parameter(Mandatory)][string]$PackageRoot)
    $path = Join-Path $PackageRoot 'dependencies.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Canonical dependency manifest is missing: $path" }
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.manifestVersion -ne (Get-Content (Join-Path $PackageRoot 'VERSION') -Raw).Trim()) { throw 'Canonical dependency manifest schema/version mismatch.' }
    if (-not $manifest.dependencies -or @($manifest.dependencies).Count -lt 1) { throw 'Canonical dependency manifest contains no dependency records.' }
    return $manifest
}

function Expand-DependencyLocation {
    param([Parameter(Mandatory)][string]$Path)
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Resolve-DependencyExecutable {
    param([Parameter(Mandatory)]$Dependency)
    foreach ($candidate in (Get-TrustedDependencyCandidates $Dependency)) { return $candidate }
    return $null
}

function Test-PrimitiveMutationRights {
    param([Parameter(Mandatory)][Security.AccessControl.FileSystemRights]$Rights)
    # Keep this mask primitive-only.  Modify and FullControl are composites;
    # their primitive mutation bits still intersect the mask naturally.
    $mutationMask = [Security.AccessControl.FileSystemRights]::WriteData -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    return (($Rights -band $mutationMask) -ne 0)
}

function Test-BroadUntrustedPrincipal {
    param([Parameter(Mandatory)][string]$Identity)
    return $Identity.Equals('Everyone',[StringComparison]::OrdinalIgnoreCase) -or
        $Identity.EndsWith('\Users',[StringComparison]::OrdinalIgnoreCase) -or
        $Identity.Equals('NT AUTHORITY\Authenticated Users',[StringComparison]::OrdinalIgnoreCase)
}

function Get-TrustedSystemRootForExecutable {
    param([Parameter(Mandatory)][string]$FullPath)
    try {
        $candidate = [IO.Path]::GetFullPath($FullPath).TrimEnd('\')
        $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:WINDIR) |
            Where-Object { $_ } |
            ForEach-Object { [IO.Path]::GetFullPath([string]$_).TrimEnd('\') } |
            Select-Object -Unique |
            Where-Object { $candidate.StartsWith($_ + '\',[StringComparison]::OrdinalIgnoreCase) }
        if (@($roots).Count -ne 1) { return $null }
        return [string]@($roots)[0]
    } catch { return $null }
}

function Get-TrustedWingetPackageCandidates {
    $result = [Collections.Generic.List[object]]::new()
    try {
        $windowsApps = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps')).TrimEnd('\')
        $windowsAppsInfo = Get-Item -LiteralPath $windowsApps -Force -ErrorAction Stop
        if (($windowsAppsInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return @() }
        foreach ($package in @(Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop)) {
            $installLocation = [string]$package.InstallLocation
            if ([string]::IsNullOrWhiteSpace($installLocation)) { continue }
            $root = [IO.Path]::GetFullPath($installLocation).TrimEnd('\')
            $rootInfo = Get-Item -LiteralPath $root -Force -ErrorAction Stop
            $basename = [IO.Path]::GetFileName($root)
            if (-not $package.Name.Equals('Microsoft.DesktopAppInstaller',[StringComparison]::OrdinalIgnoreCase) -or
                -not ([string]$package.PublisherId).Equals('8wekyb3d8bbwe',[StringComparison]::OrdinalIgnoreCase) -or
                -not ([IO.Path]::GetDirectoryName($root)).Equals($windowsApps,[StringComparison]::OrdinalIgnoreCase) -or
                -not $basename.StartsWith('Microsoft.DesktopAppInstaller_',[StringComparison]::OrdinalIgnoreCase) -or
                -not $basename.EndsWith('_x64__8wekyb3d8bbwe',[StringComparison]::OrdinalIgnoreCase) -or
                ($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $version = $basename.Substring('Microsoft.DesktopAppInstaller_'.Length, $basename.Length - 'Microsoft.DesktopAppInstaller_'.Length - '_x64__8wekyb3d8bbwe'.Length)
            if ([string]::IsNullOrWhiteSpace($version) -or @($version.Split('.') | Where-Object { $_ -notmatch '^\d+$' }).Count -gt 0) { continue }
            $candidate = Join-Path $root 'winget.exe'
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
            $candidateInfo = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
            if (($candidateInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $result.Add([pscustomobject]@{ Path = [IO.Path]::GetFullPath($candidate); Root = $root })
        }
        return @($result | Sort-Object Path -Unique)
    } catch { return @() }
}

function Test-TrustedExecutableCandidate {
    param([Parameter(Mandatory)][string]$Path,[Parameter()][object]$Dependency)
    try {
        if ([string]$Path -match '(?i)(^|[\\/])\.\.?([\\/]|$)') { return $false }
        $full = [IO.Path]::GetFullPath($Path)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
        if ([IO.Path]::GetExtension($full).ToLowerInvariant() -in @('.cmd','.bat') -and $Dependency) { return $false }
        $trustedRoot = $null
        if ([IO.Path]::GetFileName($full).Equals('winget.exe',[StringComparison]::OrdinalIgnoreCase)) {
            $wingetCandidates = @(Get-TrustedWingetPackageCandidates | Where-Object { $_.Path.Equals($full,[StringComparison]::OrdinalIgnoreCase) })
            if ($wingetCandidates.Count -ne 1) { return $false }
            $trustedRoot = [string]$wingetCandidates[0].Root
        } else { $trustedRoot = Get-TrustedSystemRootForExecutable $full }
        if ([string]::IsNullOrWhiteSpace($trustedRoot)) { return $false }
        $rootInfo = Get-Item -LiteralPath $trustedRoot -Force -ErrorAction Stop
        if (($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $fileInfo = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if (($fileInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        foreach($entry in @((Get-Acl -LiteralPath $full -ErrorAction Stop).Access)) {
            if($entry.AccessControlType -eq 'Allow' -and (Test-BroadUntrustedPrincipal ([string]$entry.IdentityReference.Value)) -and (Test-PrimitiveMutationRights ([Security.AccessControl.FileSystemRights]$entry.FileSystemRights))){return $false}
        }
        $cursor = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($full))
        $reachedRoot = $false
        while($cursor){
            if(($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
            foreach($entry in @((Get-Acl -LiteralPath $cursor.FullName -ErrorAction Stop).Access)) {
                if($entry.AccessControlType -eq 'Allow' -and (Test-BroadUntrustedPrincipal ([string]$entry.IdentityReference.Value)) -and (Test-PrimitiveMutationRights ([Security.AccessControl.FileSystemRights]$entry.FileSystemRights))){return $false}
            }
            if($cursor.FullName.TrimEnd('\').Equals($trustedRoot.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)){ $reachedRoot = $true; break }
            $cursor=$cursor.Parent
        }
        if (-not $reachedRoot) { return $false }
        $policy=if($null -ne $Dependency){$Dependency.installerAuthenticityPolicy}else{$null}
        $exact=@(if($null -ne $policy){$policy.allowedSignerSubjectsExact})
        $signature=Get-AuthenticodeSignature -LiteralPath $full
        $installedTrust = if($null -ne $policy -and $null -ne $policy.PSObject.Properties['installedExecutableTrust']){[string]$policy.installedExecutableTrust}else{''}
        $allowUnsignedInstalled = $installedTrust -eq 'signed-installer-locked-path' -and $signature.Status -eq 'NotSigned'
        if($signature.Status -ne 'Valid' -and -not $allowUnsignedInstalled){return $false}
        if($signature.Status -eq 'Valid' -and @($exact).Count -gt 0 -and -not (Test-ExactSignerIdentity ([string]$signature.SignerCertificate.Subject) $exact)){return $false}
        if(@($exact).Count -eq 0 -and $null -ne $policy -and @($policy.allowedSignerPatterns).Count -gt 0){return $false}
        return $true
    } catch { return $false }
}

function Normalize-SignerIdentity {
    param([Parameter(Mandatory)][string]$Subject)
    try { return (([Security.Cryptography.X509Certificates.X500DistinguishedName]::new($Subject)).Format($false) -replace '\s','').ToUpperInvariant() }
    catch { return ($Subject -replace '\s','').ToUpperInvariant() }
}
function Test-ExactSignerIdentity {
    param([Parameter(Mandatory)][string]$Subject,[Parameter(Mandatory)][string[]]$Expected)
    $actual=Normalize-SignerIdentity $Subject
    return @($Expected | Where-Object { (Normalize-SignerIdentity ([string]$_)) -ceq $actual }).Count -gt 0
}

function Get-TrustedDependencyCandidates {
    param([Parameter(Mandatory)]$Dependency)
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($probe in @($Dependency.executableProbes)) {
        $pathEntries = ([Environment]::GetEnvironmentVariable('PATH') -split [IO.Path]::PathSeparator) | Where-Object { $_ }
        foreach ($entry in $pathEntries) {
            $candidate = Join-Path $entry.Trim('"') $probe
            if ((Test-Path -LiteralPath $candidate) -and (Test-TrustedExecutableCandidate $candidate -Dependency $Dependency)) { $paths.Add([IO.Path]::GetFullPath($candidate)) }
        }
        foreach ($hive in @('HKLM:')) {
            foreach ($subkey in @("SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$probe", "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$probe")) {
                $key = Get-Item -LiteralPath (Join-Path $hive $subkey) -ErrorAction SilentlyContinue
                $value = if ($key) { $key.GetValue('') } else { $null }
                $candidate = if ($value) { ([string]$value).Trim('"') } else { $null }
                if ($candidate -and (Test-TrustedExecutableCandidate $candidate -Dependency $Dependency)) { $paths.Add([IO.Path]::GetFullPath($candidate)) }
            }
        }
    }
    foreach ($location in @($Dependency.knownVendorInstallLocations)) {
        $expanded = Expand-DependencyLocation $location
        if ((Test-Path -LiteralPath $expanded) -and (Test-TrustedExecutableCandidate $expanded -Dependency $Dependency)) { $paths.Add([IO.Path]::GetFullPath($expanded)) }
    }
    return $paths | Select-Object -Unique
}

function Get-DependencyStatus {
    param(
        [Parameter(Mandatory)]$Dependency,
        [int]$ProbeTimeoutSeconds = (Get-DevFleetOperationMaximumSeconds 'dependencyProbe'),
        [datetime]$DeadlineUtc = [datetime]::MinValue
    )
    if($ProbeTimeoutSeconds -le 0){throw 'Dependency probe timeout must be positive.'}
    $probeDeadline=[datetime]::UtcNow.AddSeconds($ProbeTimeoutSeconds)
    if($DeadlineUtc -gt [datetime]::MinValue -and $DeadlineUtc.ToUniversalTime() -lt $probeDeadline){$probeDeadline=$DeadlineUtc.ToUniversalTime()}
    $deadlineContext=Get-DevFleetDeadlineContext
    if($deadlineContext -and ([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime() -lt $probeDeadline){$probeDeadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
    $args = @($Dependency.versionProbe.arguments)
    $first = $null
    foreach ($path in (Get-TrustedDependencyCandidates $Dependency)) {
        $remaining=[int][math]::Floor(($probeDeadline-[datetime]::UtcNow).TotalSeconds)
        if($remaining -le 0){
            if($null -eq $first){$first=[pscustomobject]@{Status='Broken';Path=$path;Version=$null;Detail='Trusted executable was found but its bounded version probe deadline expired.'}}
            break
        }
        try {
            $output=Invoke-External -FilePath $path -ArgumentList $args -Capture -TimeoutSeconds ([math]::Min($ProbeTimeoutSeconds,$remaining)) -DeadlineUtc $probeDeadline
            $exit=0
        } catch {
            if($null -eq $first){$first=[pscustomobject]@{Status='Broken';Path=$path;Version=$null;Detail='Trusted executable was found but its bounded version probe failed.'}}
            continue
        }
        $match = if ($Dependency.versionProbe.regex) { [regex]::Match($output, [string]$Dependency.versionProbe.regex) } else { $null }
        if ($exit -ne 0 -or -not $match -or -not $match.Success) {
            if ($null -eq $first) { $first = [pscustomobject]@{ Status='Broken'; Path=$path; Version=$null; Detail='Trusted executable was found but version probe failed.' } }
            continue
        }
        $version = [Version]$match.Groups[1].Value
        $minimum = [Version]$Dependency.minimumSupportedVersion
        $status = if ($version -lt $minimum) { 'Outdated' } elseif ($null -ne $Dependency.maximumMajor -and $version.Major -gt [int]$Dependency.maximumMajor) { 'Unsupported-Major' } else { 'Compatible' }
        $result = [pscustomobject]@{ Status=$status; Path=$path; Version=$version; Detail="Resolved trusted executable $path; version $version" }
        if ($status -eq 'Compatible') { return $result }
        if ($null -eq $first) { $first = $result }
    }
    if ($null -ne $first) { return $first }
    return [pscustomobject]@{ Status='Missing'; Path=''; Version=$null; Detail='No trusted machine executable, HKLM App Path, or vendor location matched.' }
}

function Wait-DevFleetDependencyStatus {
    param(
        [Parameter(Mandatory)]$Dependency,
        [datetime]$DeadlineUtc = [datetime]::MinValue,
        [ValidateRange(1,10)][int]$MaximumAttempts = 3,
        [scriptblock]$StatusProvider,
        [scriptblock]$ClockProvider,
        [scriptblock]$SleepProvider
    )
    $now={if($ClockProvider){[datetime](& $ClockProvider)}else{[datetime]::UtcNow}}
    $sleep={param([double]$Seconds)if($SleepProvider){& $SleepProvider $Seconds}else{Start-Sleep -Milliseconds ([int][math]::Ceiling($Seconds*1000))}}
    $start=(& $now).ToUniversalTime()
    $deadline=if($DeadlineUtc -gt [datetime]::MinValue){$DeadlineUtc.ToUniversalTime()}else{$start.AddSeconds((Get-DevFleetOperationMaximumSeconds 'dependencyProbe'))}
    $deadlineContext=Get-DevFleetDeadlineContext
    if($deadlineContext -and ([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime() -lt $deadline){$deadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
    $last=$null
    for($attempt=1;$attempt -le $MaximumAttempts;$attempt++){
        $remainingSeconds=[int][math]::Floor(($deadline-(& $now).ToUniversalTime()).TotalSeconds)
        if($remainingSeconds -le 0)