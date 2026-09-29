# DevFleet source part 114

Full-source UTF-8 byte interval [5254500, 5301000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: a1e6de6499b6ada0b6c14827add0287cc4c7a3586ed60dd1e2ee324b7b19fa3e

<!-- BEGIN SOURCE SLICE -->
       environmentUserInteractive = [Environment]::UserInteractive
        elevated = $elevated
        browserVisibility = 'UNKNOWN'
    }
    $writeEvent = {
        param([string]$EventClass, [hashtable]$Extra = @{})
        $script:DevFleetTailscalePairingEventSequence++
        $event = @{}
        foreach ($key in $eventContext.Keys) { $event[$key] = $eventContext[$key] }
        $event.schemaVersion = 1
        $event.eventSequence = $script:DevFleetTailscalePairingEventSequence
        $event.eventClass = $EventClass
        $event.timestampUtc = [datetime]::UtcNow.ToString('o')
        foreach ($key in $Extra.Keys) { $event[$key] = $Extra[$key] }
        Write-DevFleetTailscalePairingEvent -Path $EvidencePath -Event $event
    }
    $context=Get-DevFleetDeadlineContext
    if($context-and([datetime]$context.StageDeadlineUtc).ToUniversalTime()-lt$DeadlineUtc){$DeadlineUtc=([datetime]$context.StageDeadlineUtc).ToUniversalTime()}
    $eventContext.ownerDeadlineUtc = $DeadlineUtc.ToUniversalTime().ToString('o')
    &$writeEvent 'PAIRING_STARTED' @{ authenticatedState = 'NOT_OBSERVED'; pollCount = 0 }
    $command={
        param([string[]]$Arguments)
        $verb = [string]$Arguments[0]
        $remaining=[int][math]::Floor(($DeadlineUtc-[datetime]::UtcNow).TotalSeconds)-5
        if($remaining-le0){&$writeEvent 'COMMAND_BLOCKED_DEADLINE' @{ command = $verb; commandOutcome = 'BLOCKED'; failureClass = 'OWNER_DEADLINE_EXPIRED'; authenticatedState = 'NOT_OBSERVED' };throw 'Tailscale browser pairing exceeded the owning stage deadline.'}
        $maximum=if($Arguments[0]-ceq'up'){35}else{10}
        if($Arguments[0]-ceq'up'-and$remaining-lt$maximum){&$writeEvent 'COMMAND_BLOCKED_DEADLINE' @{ command = $verb; commandOutcome = 'BLOCKED'; failureClass = 'INSUFFICIENT_HANDOFF_BUDGET'; authenticatedState = 'NOT_OBSERVED' };throw 'Insufficient stage time remains for the bounded Tailscale browser handoff.'}
        $nativeArgs=if($InstanceName){@('exec',$InstanceName,'--','sudo','tailscale')+$Arguments}else{$Arguments}
        &$writeEvent 'COMMAND_STARTED' @{ command = $verb; commandOutcome = 'STARTED' }
        try {
            $output=Invoke-External -FilePath $FilePath -ArgumentList $nativeArgs -Capture -IgnoreExitCode -TimeoutSeconds ([math]::Min($maximum,$remaining)) -DeadlineUtc $DeadlineUtc
            if([datetime]::UtcNow-gt$DeadlineUtc){throw 'Tailscale command returned after the owning stage deadline.'}
            $outputClass = if ($verb -ceq 'up') {
                if (Get-DevFleetTailscaleAuthenticationUri $output) { 'OFFICIAL_URI_PRESENT' } else { 'NO_OFFICIAL_URI' }
            } else {
                (Get-DevFleetTailscaleStatusSummary -StatusJson $output -ExpectedHostname $Hostname).statusClass
            }
            &$writeEvent 'COMMAND_COMPLETED' @{ command = $verb; commandOutcome = 'COMPLETED'; commandOutputClass = $outputClass }
            return $output
        } catch {
            &$writeEvent 'COMMAND_FAILED' @{ command = $verb; commandOutcome = 'FAILED'; failureClass = Get-DevFleetTailscalePairingFailureClass $_.Exception.Message }
            throw
        }
    }
    $pollCount = 0
    $lastStatusClass = ''
    try {
        $status=&$command @('status','--json')
        $summary=Get-DevFleetTailscaleStatusSummary -StatusJson $status -ExpectedHostname $Hostname
        &$writeEvent 'INITIAL_STATUS_OBSERVED' @{ statusClass = $summary.statusClass; authenticated = [bool]$summary.authenticated; authenticatedState = if ($summary.authenticated) { 'AUTHENTICATED' } else { 'NOT_AUTHENTICATED' }; selfHostname = $summary.selfHostname; nodeIdentityMatch = $summary.nodeIdentityMatch; pollCount = 0 }
        $ip=Get-DevFleetAuthenticatedTailscaleIPv4 $status
        if($ip){&$writeEvent 'PAIRING_AUTHENTICATED' @{ statusClass = $summary.statusClass; authenticated = $true; authenticatedState = 'AUTHENTICATED'; authenticatedStateTransition = 'INITIAL_TO_AUTHENTICATED'; selfHostname = $summary.selfHostname; nodeIdentityMatch = $summary.nodeIdentityMatch; pollCount = 0 };return [pscustomobject]@{authenticated=$true;ipv4=$ip;browserOpened=$false}}
        # Return the device URL before waiting for the user. An unbounded `up`
        # hides its redirected URL inside the WPF install child until it exits.
        $output=&$command @('up','--timeout=30s','--accept-dns=false','--hostname',$Hostname)
        $status=&$command @('status','--json')
        $summary=Get-DevFleetTailscaleStatusSummary -StatusJson $status -ExpectedHostname $Hostname
        &$writeEvent 'PRE_LAUNCH_STATUS_OBSERVED' @{ statusClass = $summary.statusClass; authenticated = [bool]$summary.authenticated; authenticatedState = if ($summary.authenticated) { 'AUTHENTICATED' } else { 'NOT_AUTHENTICATED' }; selfHostname = $summary.selfHostname; nodeIdentityMatch = $summary.nodeIdentityMatch; pollCount = 0 }
        $ip=Get-DevFleetAuthenticatedTailscaleIPv4 $status
        if($ip){&$writeEvent 'PAIRING_AUTHENTICATED' @{ statusClass = $summary.statusClass; authenticated = $true; authenticatedState = 'AUTHENTICATED'; authenticatedStateTransition = 'PRE_LAUNCH_TO_AUTHENTICATED'; selfHostname = $summary.selfHostname; nodeIdentityMatch = $summary.nodeIdentityMatch; pollCount = 0 };return [pscustomobject]@{authenticated=$true;ipv4=$ip;browserOpened=$false}}
        $uri=Get-DevFleetTailscaleAuthenticationUri $output
        $output=$null
        if(-not$uri){&$writeEvent 'PAIRING_FAILED' @{ failureClass = 'NO_VALID_OFFICIAL_URI'; authenticatedState = 'NOT_AUTHENTICATED'; pollCount = 0 };throw 'Tailscale did not supply one valid official browser authentication link.'}
        &$writeEvent 'URI_VALIDATED' @{ uriValidated = $true; authenticatedState = 'NOT_AUTHENTICATED'; pollCount = 0 }
        &$writeEvent 'BROWSER_LAUNCH_REQUESTED' @{ uriValidated = $true; browserLaunchRequested = $true; authenticatedState = 'NOT_AUTHENTICATED'; pollCount = 0 }
        try {
            $launch=Open-DevFleetTailscaleAuthenticationPage $uri
            $launchAccepted=$true
            if($launch -and $launch.PSObject.Properties['apiAccepted']){$launchAccepted=[bool]$launch.apiAccepted}
            $browserProcessId=$null;$browserProcessSessionId=$null;$browserProcessObserved=$false
            if($launch -and $launch.PSObject.Properties['processId'] -and $launch.processId){$browserProcessId=[int]$launch.processId;$browserProcessObserved=$browserProcessId-gt0}
            if($launch -and $launch.PSObject.Properties['processSessionId'] -and $null -ne $launch.processSessionId){$browserProcessSessionId=[int]$launch.processSessionId}
            $sessionMatch=$null;if($null -ne $browserProcessSessionId -and $ownerSessionId -gt0){$sessionMatch=[int]$browserProcessSessionId-eq$ownerSessionId}
            &$writeEvent 'BROWSER_LAUNCH_ACCEPTED' @{ uriValidated = $true; browserLaunchRequested = $true; browserLaunchApiAccepted = $launchAccepted; browserProcessObserved = $browserProcessObserved; browserProcessId = $browserProcessId; browserProcessSessionId = $browserProcessSessionId; browserSessionMatchesOwner = $sessionMatch; authenticatedState = 'NOT_AUTHENTICATED'; pollCount = 0 }
        } catch {
            &$writeEvent 'BROWSER_LAUNCH_FAILED' @{ uriValidated = $true; browserLaunchRequested = $true; browserLaunchApiAccepted = $false; browserProcessObserved = $false; authenticatedState = 'NOT_AUTHENTICATED'; failureClass = 'BROWSER_LAUNCH_API_FAILED'; pollCount = 0 }
            throw
        }
        $uri=$null
        Write-Host "Approve Tailscale device $Hostname in the browser. Setup will continue after authentication."
        &$writeEvent 'PAIRING_WAIT_ENTERED' @{ uriValidated = $true; browserLaunchRequested = $true; browserLaunchApiAccepted = $true; authenticatedState = 'WAITING_FOR_AUTHENTICATION'; pollCount = 0 }
        while([datetime]::UtcNow-lt$DeadlineUtc){
            $pollCount++
            $status=&$command @('status','--json')
            $summary=Get-DevFleetTailscaleStatusSummary -StatusJson $status -ExpectedHostname $Hostname
            if($summary.statusClass -cne $lastStatusClass){
                $lastStatusClass=$summary.statusClass
                &$writeEvent 'POLL_STATUS_OBSERVED' @{ statusClass = $summary.statusClass; authenticated = [bool]$summary.authenticated; authenticatedState = if ($summary.authenticated) { 'AUTHENTICATED' } else { 'NOT_AUTHENTICATED' }; selfHostname = $summary.selfHostname; nodeIdentityMatch = $summary.nodeIdentityMatch; pollCount = $pollCount; lastStatusClass = $summary.statusClass }
            }
            $ip=Get-DevFleetAuthenticatedTailscaleIPv4 $status
            if($ip){&$writeEvent 'PAIRING_AUTHENTICATED' @{ statusClass = $summary.statusClass; authenticated = $true; authenticatedState = 'AUTHENTICATED'; authenticatedStateTransition = 'WAITING_TO_AUTHENTICATED'; selfHostname = $summary.selfHostname; nodeIdentityMatch = $summary.nodeIdentityMatch; pollCount = $pollCount; lastStatusClass = $summary.statusClass };return [pscustomobject]@{authenticated=$true;ipv4=$ip;browserOpened=$true}}
            $remaining=($DeadlineUtc-[datetime]::UtcNow).TotalMilliseconds
            if($remaining-gt0){Start-Sleep -Milliseconds ([int][math]::Min(2000,$remaining))}
        }
        &$writeEvent 'PAIRING_FAILED' @{ uriValidated = $true; browserLaunchRequested = $true; browserLaunchApiAccepted = $true; authenticatedState = 'NOT_AUTHENTICATED'; authenticatedStateTransition = 'WAITING_TO_DEADLINE'; pollCount = $pollCount; lastStatusClass = $lastStatusClass; failureClass = 'OWNER_DEADLINE_EXPIRED_AFTER_BROWSER_HANDOFF' }
        throw 'Tailscale browser pairing exceeded the owning stage deadline.'
    } catch {
        &$writeEvent 'PAIRING_FAILED' @{ authenticatedState = 'NOT_AUTHENTICATED'; pollCount = $pollCount; lastStatusClass = $lastStatusClass; failureClass = Get-DevFleetTailscalePairingFailureClass $_.Exception.Message }
        throw
    }
}

Export-ModuleMember -Function Invoke-DevFleetTailscaleBrowserPairing,Invoke-DevFleetTailscaleOAuthPairing,Get-DevFleetTailscaleReadiness,Get-DevFleetTailscaleEnrollmentProfile,Get-DevFleetTailscaleOAuthSecretPath,Set-DevFleetTailscaleOAuthClientSecret

```


## FILE: source/windows/Export-Diagnostics.ps1

SHA256: fd1dbee84b4be48f94162c14e75ed847f6c15a6ed898c08e86ddb0a827437cf3 | Bytes: 1036 | Git mode: 100644

```
[CmdletBinding()]
param([switch]$AllLocalInstances)
$ErrorActionPreference='Continue'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe;$out=Join-Path (Get-DevFleetStateRoot) "exports\diagnostics-$((Get-Date).ToString('yyyyMMdd-HHmmss'))";New-Item -ItemType Directory $out -Force|Out-Null
Get-ComputerInfo|Out-File (Join-Path $out 'computer-info.txt')
& $mp version|Out-File (Join-Path $out 'multipass-version.txt')
& $mp list --format json|Out-File (Join-Path $out 'multipass-list.json')
$names=@($config.Primary.InstanceName,$config.Failover.InstanceName,$config.Vault.InstanceName)|Where-Object{Test-MultipassInstance $_}
foreach($name in $names){& $mp exec $name -- bash -lc 'sudo journalctl -u devfleet -n 300 --no-pager 2>/dev/null || sudo journalctl -u rest-server -n 300 --no-pager 2>/dev/null || true'|Out-File (Join-Path $out "$name.log")}
Compress-Archive -Path "$out\*" -DestinationPath "$out.zip"
Write-Host "Diagnostics: $out.zip" -ForegroundColor Green

```


## FILE: source/windows/Export-Vault-OfflineCopy.ps1

SHA256: 2ec63a9fa38753b0f55ff752faa9f3511b47e2fca70cff9b432fac2823eb9dd7 | Bytes: 1727 | Git mode: 100644

```
[CmdletBinding()]
param([string]$DestinationDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-Administrator
$config=Get-DevFleetConfig;$mp=Get-MultipassExe;$name=$config.Vault.InstanceName
if(-not (Test-MultipassInstance $name)){throw 'The local DevFleet vault VM was not found.'}
if(-not $DestinationDirectory){
  $default=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'DevFleet-Offline-Vault-Copies'
  $entered=Read-Host "Destination folder [$default] (an external drive is preferable)"
  $DestinationDirectory=if($entered){$entered}else{$default}
}
New-Item -ItemType Directory -Path $DestinationDirectory -Force|Out-Null
$stamp=(Get-Date).ToString('yyyyMMdd-HHmmss')
$remote="/tmp/devfleet-vault-$stamp.tar.gz"
$local=Join-Path $DestinationDirectory "devfleet-vault-$stamp.tar.gz"
Write-Host 'Temporarily stopping the REST service to make a consistent encrypted repository copy...' -ForegroundColor Cyan
$command="set -Eeuo pipefail; systemctl stop rest-server; trap 'systemctl start rest-server' EXIT; tar -C /srv -czf '$remote' restic; chown ubuntu:ubuntu '$remote'; chmod 0640 '$remote'; systemctl start rest-server; trap - EXIT"
Invoke-External $mp @('exec',$name,'--','sudo','bash','-lc',$command)
try{Invoke-External $mp @('transfer',"${name}:$remote",$local)}
finally{Invoke-External $mp @('exec',$name,'--','sudo','rm','-f',$remote) -IgnoreExitCode}
$hash=Get-FileHash -Algorithm SHA256 -Path $local
"$($hash.Hash.ToLower())  $([IO.Path]::GetFileName($local))"|Set-Content "$local.sha256" -Encoding ascii
Write-Host "Offline encrypted vault copy: $local" -ForegroundColor Green
Write-Host "SHA-256: $($hash.Hash)" -ForegroundColor Green

```


## FILE: source/windows/Install-DevFleet-HostAgent.ps1

SHA256: 2f8aaeef509e22b14ee2f53b7cc64ef92851042e7487c0e5eefacd9c77c7396b | Bytes: 18803 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\ProgramData\DevFleetHostAgent',
    [int]$Port = 8790,
    [switch]$SkipFirewall,
    [switch]$AdoptLegacyDevFleetIntegrations
)

$ErrorActionPreference = 'Stop'
$commonModule = Join-Path $PSScriptRoot 'DevFleet.Common.psm1'
$protocolModule = Join-Path $PSScriptRoot 'DevFleet-HostAgentProtocol.psm1'
$ownershipModule = Join-Path $PSScriptRoot 'DevFleet-WindowsIntegrationOwnership.psm1'
Import-Module $commonModule -Force
Import-Module $protocolModule -Force
Import-Module $ownershipModule -Force
function Write-AtomicText {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text,[Text.Encoding]$Encoding = [Text.UTF8Encoding]::new($false))
    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($tmp,$Text,$Encoding)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
$expectedHost = $env:DEVFLEET_HOST_AGENT_EXPECTED_HOST
if ($expectedHost -and $env:COMPUTERNAME -ne $expectedHost) { throw "Host-agent fixture restriction failed. Expected: $expectedHost. Current host: $env:COMPUTERNAME" }
$multipass = Get-MultipassExe
if (-not $multipass) { throw 'Multipass was installed but could not be rediscovered from PATH, App Paths, registry, or known vendor locations.' }
$packageRoot = Split-Path -Parent $PSScriptRoot
$agentSource = Join-Path $packageRoot 'windows\DevFleet-HostAgent.ps1'
$protocolSource = Join-Path $packageRoot 'windows\DevFleet-HostAgentProtocol.psm1'
if (-not (Test-Path -LiteralPath $agentSource)) { throw "Host agent source not found: $agentSource" }
if (-not (Test-Path -LiteralPath $protocolSource)) { throw "Host agent protocol helper not found: $protocolSource" }
$vscodeHelperSource = Join-Path $packageRoot 'windows\DevFleet-VSCode.ps1'
if (-not (Test-Path -LiteralPath $vscodeHelperSource)) { throw "VS Code helper source not found: $vscodeHelperSource" }
$ownershipModuleSource = Join-Path $packageRoot 'windows\DevFleet-WindowsIntegrationOwnership.psm1'
$removalHelperSource = Join-Path $packageRoot 'windows\Remove-DevFleet-OwnedIntegrations.ps1'
if (-not (Test-Path -LiteralPath $ownershipModuleSource)) { throw "Windows integration ownership helper not found: $ownershipModuleSource" }
if (-not (Test-Path -LiteralPath $removalHelperSource)) { throw "Windows integration removal helper not found: $removalHelperSource" }

# The agent is intentionally a SYSTEM scheduled task.  Multipass 1.16.x
# authenticates each Windows client by its per-profile certificate, so make
# the already-authenticated installing user's client available to SYSTEM.
# Copy only the two client PEM files into the SYSTEM profile and lock the
# destination to SYSTEM and local Administrators.  No Multipass daemon
# restart or host-network change is required.
$userMultipassCertRoot = Join-Path $env:LOCALAPPDATA 'multipass-client-certificate'
$systemMultipassCertRoot = Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Local\multipass-client-certificate'
if (-not (Test-Path -LiteralPath $userMultipassCertRoot)) {
    if (-not (Test-Path -LiteralPath $systemMultipassCertRoot)) { throw "Authenticated Multipass client certificate directory was not found: $userMultipassCertRoot" }
} else {
    New-Item -ItemType Directory -Path $systemMultipassCertRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $userMultipassCertRoot -File -Filter '*.pem' -ErrorAction Stop | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $systemMultipassCertRoot $_.Name) -Force
    }
}
$certAcl = New-Object System.Security.AccessControl.DirectorySecurity
$certAcl.SetAccessRuleProtection($true, $false)
$certAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
$certAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
Set-Acl -LiteralPath $systemMultipassCertRoot -AclObject $certAcl
Get-ChildItem -LiteralPath $systemMultipassCertRoot -File -Filter '*.pem' | ForEach-Object { Set-Acl -LiteralPath $_.FullName -AclObject $certAcl }

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
$initialAcl = Get-Acl -LiteralPath $InstallRoot
$initialAcl.SetAccessRuleProtection($true, $false)
foreach ($existingRule in @($initialAcl.Access)) { $initialAcl.RemoveAccessRuleAll($existingRule) }
$initialAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
$initialAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
Set-Acl -LiteralPath $InstallRoot -AclObject $initialAcl
$tokenPath = Join-Path $InstallRoot 'token.txt'
if (-not (Test-Path -LiteralPath $tokenPath)) {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    Write-AtomicText $tokenPath ([Convert]::ToBase64String($bytes)) ([Text.ASCIIEncoding]::new())
}
$token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
if ($token.Length -lt 40) { throw 'Host-agent token is unexpectedly short.' }

$agentPath = Join-Path $InstallRoot 'DevFleet-HostAgent.ps1'
$vscodeHelperPath = Join-Path $InstallRoot 'DevFleet-VSCode.ps1'
$configPath = Join-Path $InstallRoot 'config.json'
$ownershipPath = Join-Path $InstallRoot 'integration-ownership.json'
$taskName = 'DevFleet Host Agent'
$powerShellPath = ConvertTo-DevFleetCanonicalPath (Get-DevFleetPowerShell)
$taskArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$agentPath`" -ConfigPath `"$configPath`""
$existingOwnership = Read-DevFleetIntegrationOwnership -Path $ownershipPath -AllowMissing
if ($existingOwnership) {
    # A virtual adapter can be recreated across reboot/checkpoint restore. Reconcile
    # only an exact ledger-owned rule before the normal remove/recreate path; any
    # immutable identity mismatch remains a fail-closed ownership conflict.
    Invoke-DevFleetOwnedFirewallRefresh -Path $ownershipPath -WaitSeconds 30 | Out-Null
    $existingOwnership = Read-DevFleetIntegrationOwnership -Path $ownershipPath -AllowMissing
}
function Remove-PriorOwnedFirewallRules {
    param($Ownership)
    if (-not $Ownership) { return }
    foreach ($ownedRule in @($Ownership.FirewallRules)) {
        $liveRules = @(Get-NetFirewallRule -Name ([string]$ownedRule.Name) -ErrorAction SilentlyContinue)
        if ($liveRules.Count -eq 0) { continue }
        if ($liveRules.Count -ne 1) { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: prior firewall identity '$($ownedRule.Name)' is ambiguous. All rules preserved." }
        $live = $liveRules[0]
        $portFilter = $live | Get-NetFirewallPortFilter
        $addressFilter = $live | Get-NetFirewallAddressFilter
        $interfaceFilter = $live | Get-NetFirewallInterfaceFilter
        $actual = @{Name=[string]$live.Name;DisplayName=[string]$live.DisplayName;Group=[string]$live.Group;Description=[string]$live.Description;Direction=[string]$live.Direction;Action=[string]$live.Action;Protocol=[string]$portFilter.Protocol;LocalPort=[string]$portFilter.LocalPort;InterfaceAlias=[string]$interfaceFilter.InterfaceAlias;RemoteAddress=[string]$addressFilter.RemoteAddress;Profile=[string]$live.Profile;Generation=[string]$ownedRule.Generation}
        Assert-DevFleetFirewallBinding -Expected $ownedRule -Actual $actual | Out-Null
        $live | Remove-NetFirewallRule -Confirm:$false
    }
}
$existingTask = Get-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue
if ($existingTask) {
    if (@($existingTask.Actions).Count -ne 1) { throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: scheduled task has an ambiguous action set. Foreign task preserved.' }
    $ownedTask = @()
    if ($existingOwnership) { $ownedTask = @($existingOwnership.ScheduledTasks | Where-Object { [string]$_.Name -eq $taskName }) }
    if ($ownedTask.Count -eq 1) {
        $actualTask = @{Name=[string]$existingTask.TaskName;Executable=[string]$existingTask.Actions[0].Execute;Arguments=[string]$existingTask.Actions[0].Arguments;Principal=[string]$existingTask.Principal.UserId;LogonType=[string]$existingTask.Principal.LogonType;RunLevel=[string]$existingTask.Principal.RunLevel;Description=[string]$existingTask.Description;Generation=[string]$ownedTask[0].Generation}
        Assert-DevFleetTaskBinding -Expected $ownedTask[0] -Actual $actualTask | Out-Null
    } elseif ($AdoptLegacyDevFleetIntegrations) {
        $legacyExpected = @{Name=$taskName;Executable=$powerShellPath;Arguments=$taskArguments;Principal='SYSTEM';LogonType='ServiceAccount';RunLevel='Highest';Description=[string]$existingTask.Description;Generation='legacy-explicit-adoption'}
        $legacyActual = @{Name=[string]$existingTask.TaskName;Executable=[string]$existingTask.Actions[0].Execute;Arguments=[string]$existingTask.Actions[0].Arguments;Principal=[string]$existingTask.Principal.UserId;LogonType=[string]$existingTask.Principal.LogonType;RunLevel=[string]$existingTask.Principal.RunLevel;Description=[string]$existingTask.Description;Generation='legacy-explicit-adoption'}
        Assert-DevFleetTaskBinding -Expected $legacyExpected -Actual $legacyActual | Out-Null
    } else {
        throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: same-name scheduled task has no owned binding. Foreign task preserved. Use -AdoptLegacyDevFleetIntegrations only after explicit legacy review.'
    }
    Stop-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}
Copy-Item -LiteralPath $agentSource -Destination $agentPath -Force
Copy-Item -LiteralPath $protocolSource -Destination (Join-Path $InstallRoot 'DevFleet-HostAgentProtocol.psm1') -Force
Copy-Item -LiteralPath $vscodeHelperSource -Destination $vscodeHelperPath -Force
Copy-Item -LiteralPath $ownershipModuleSource -Destination (Join-Path $InstallRoot 'DevFleet-WindowsIntegrationOwnership.psm1') -Force
Copy-Item -LiteralPath $removalHelperSource -Destination (Join-Path $InstallRoot 'Remove-DevFleet-OwnedIntegrations.ps1') -Force
$multipassVersion = (& $multipass version 2>$null | Select-Object -First 1).ToString().Trim()
$config = [ordered]@{
    SchemaVersion = 1
    HostId = $env:COMPUTERNAME.ToLowerInvariant()
    HostName = $env:COMPUTERNAME
    ListenPrefix = "http://+:$Port/"
    TokenPath = $tokenPath
    MultipassPath = $multipass
    MultipassVersion = $multipassVersion
    MultipassClientCertificateRoot = $systemMultipassCertRoot
    UbuntuImage = '24.04'
    BootTimeoutSeconds = 900
    ResourcePolicy = [ordered]@{
        PolicyVersion = '1.0.0'
        PhysicalFloorMinGb = 8
        PhysicalFloorPercent = 0.10
        CommitHeadroomFloorMinGb = 16
        CommitHeadroomPercent = 0.20
        CommitUsageLimitPercent = 80
        ReservedLogicalProcessors = 2
        ReservedHostDiskGb = 50
        MaximumVmCount = 4
        MaximumParallelProvisioning = 1
        MaxProjectCpus = 6
        MaxProjectMemoryGb = 12
        MaxProjectDiskGb = 120
    }
    SshPublicKeyPath = Join-Path $env:USERPROFILE '.ssh\devfleet_ed25519.pub'
    # Project aliases are deliberately scoped to this installing user's SSH
    # config. The SYSTEM host agent receives only this fixed path and key path,
    # never browser-provided SSH configuration text.
    SshConfigPath = Join-Path $env:USERPROFILE '.ssh\config'
    SshKnownHostsPath = Join-Path $env:USERPROFILE '.ssh\devfleet_known_hosts'
    SshPrivateKeyPath = Join-Path $env:USERPROFILE '.ssh\devfleet_ed25519'
    VsCodeSettingsPaths = @(
        (Join-Path $env:APPDATA 'Code\User\settings.json'),
        (Join-Path $env:APPDATA 'Code\User\settings.jsonc'),
        (Join-Path $env:APPDATA 'Code - Insiders\User\settings.json'),
        (Join-Path $env:APPDATA 'Code - Insiders\User\settings.jsonc')
    )
}
Write-AtomicText $configPath ($config | ConvertTo-Json -Depth 8)

$acl = Get-Acl -LiteralPath $InstallRoot
$acl.SetAccessRuleProtection($true, $false)
$acl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
$acl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
Set-Acl -LiteralPath $InstallRoot -AclObject $acl
Set-Acl -LiteralPath $tokenPath -AclObject $acl
Set-Acl -LiteralPath $configPath -AclObject $acl

$generation = [guid]::NewGuid().ToString('D')
$version = (Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw).Trim()
$taskDescription = "M-TechLabs DevFleet Host Agent v$version; generation=$generation"
$action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $taskArguments
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $taskDescription -Force | Out-Null
$taskBinding = [ordered]@{Name=$taskName;Executable=$powerShellPath;Arguments=$taskArguments;Principal='SYSTEM';LogonType='ServiceAccount';RunLevel='Highest';Description=$taskDescription;Generation=$generation;Marker='M-TechLabs DevFleet Host Agent';Version=$version}
$firewallBindings = @()
Remove-PriorOwnedFirewallRules -Ownership $existingOwnership
if (-not $SkipFirewall) {
    $multipassAdapter = Get-NetAdapter -Name 'vEthernet (Default Switch)' -ErrorAction SilentlyContinue
    $tailscaleAdapter = Get-NetAdapter -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($multipassAdapter) {
        $multipassAddress = Get-NetIPAddress -InterfaceIndex $multipassAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1
        if (-not $multipassAddress) { throw 'Multipass adapter has no usable IPv4 subnet; refusing a broad host-agent firewall rule.' }
        $multipassSubnet = ConvertTo-DevFleetCanonicalFirewallRemoteAddress "$($multipassAddress.IPAddress)/$($multipassAddress.PrefixLength)"
        $firewallBindings += [ordered]@{Name="DevFleetHostAgent-$Port-Multipass";DisplayName="DevFleet Host Agent $Port - Multipass";Group='M-TechLabs DevFleet Host Agent';Description="M-TechLabs DevFleet Host Agent v$version; generation=$generation; scope=Multipass";Direction='Inbound';Action='Allow';Protocol='TCP';LocalPort=[string]$Port;InterfaceAlias=[string]$multipassAdapter.Name;RemoteAddress=$multipassSubnet;Profile='Any';Generation=$generation;Marker='M-TechLabs DevFleet Host Agent';Version=$version}
    }
    if ($tailscaleAdapter) {
        $firewallBindings += [ordered]@{Name="DevFleetHostAgent-$Port-Tailscale";DisplayName="DevFleet Host Agent $Port - Tailscale";Group='M-TechLabs DevFleet Host Agent';Description="M-TechLabs DevFleet Host Agent v$version; generation=$generation; scope=Tailscale";Direction='Inbound';Action='Allow';Protocol='TCP';LocalPort=[string]$Port;InterfaceAlias=[string]$tailscaleAdapter.Name;RemoteAddress=(ConvertTo-DevFleetCanonicalFirewallRemoteAddress '100.64.0.0/10');Profile='Any';Generation=$generation;Marker='M-TechLabs DevFleet Host Agent';Version=$version}
    }
    if (-not $multipassAdapter -and -not $tailscaleAdapter) { throw 'No supported narrow host-agent interface was found; refusing a broad firewall rule.' }

    foreach ($desired in $firewallBindings) {
        $sameDisplay = @(Get-NetFirewallRule -DisplayName ([string]$desired.DisplayName) -ErrorAction SilentlyContinue)
        foreach ($live in $sameDisplay) {
            $owned = @()
            if ($existingOwnership) { $owned = @($existingOwnership.FirewallRules | Where-Object { [string]$_.Name -eq [string]$live.Name }) }
            $portFilter = $live | Get-NetFirewallPortFilter; $addressFilter = $live | Get-NetFirewallAddressFilter; $interfaceFilter = $live | Get-NetFirewallInterfaceFilter
            $actual = @{Name=[string]$live.Name;DisplayName=[string]$live.DisplayName;Group=[string]$live.Group;Description=[string]$live.Description;Direction=[string]$live.Direction;Action=[string]$live.Action;Protocol=[string]$portFilter.Protocol;LocalPort=[string]$portFilter.LocalPort;InterfaceAlias=[string]$interfaceFilter.InterfaceAlias;RemoteAddress=[string]$addressFilter.RemoteAddress;Profile=[string]$live.Profile;Generation=if($owned.Count -eq 1){[string]$owned[0].Generation}else{'legacy-explicit-adoption'}}
            if ($owned.Count -eq 1) { Assert-DevFleetFirewallBinding -Expected $owned[0] -Actual $actual | Out-Null }
            elseif ($AdoptLegacyDevFleetIntegrations) {
                $legacyExpected = @{}
                foreach ($key in $desired.Keys) { $legacyExpected[$key] = $desired[$key] }
                $legacyExpected.Name=[string]$live.Name;$legacyExpected.Group=[string]$live.Group;$legacyExpected.Description=[string]$live.Description;$legacyExpected.Generation='legacy-explicit-adoption'
                Assert-DevFleetFirewallBinding -Expected $legacyExpected -Actual $actual | Out-Null
            } else { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: same-name firewall rule '$($desired.DisplayName)' has no owned binding. Foreign rule preserved." }
            $live | Remove-NetFirewallRule -Confirm:$false
        }
        New-NetFirewallRule -Name ([string]$desired.Name) -DisplayName ([string]$desired.DisplayName) -Group ([string]$desired.Group) -Description ([string]$desired.Description) -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress ([string]$desired.RemoteAddress) -InterfaceAlias ([string]$desired.InterfaceAlias) -Profile Any | Out-Null
    }
}
$integrationLedger = [ordered]@{SchemaVersion=1;InstallationGeneration=$generation;DevFleetVersion=$version;Marker='M-TechLabs DevFleet Host Agent';ScheduledTasks=@($taskBinding);FirewallRules=@($firewallBindings);Services=@();UpdatedUtc=(Get-Date).ToUniversalTime().ToString('o')}
Write-DevFleetIntegrationOwnership -Path $ownershipPath -Ledger $integrationLedger
Start-ScheduledTask -TaskName $taskName
$healthExpectedHost = if($expectedHost){$expectedHost}else{$env:COMPUTERNAME}
for ($i = 0; $i -lt 30; $i++) {
    try { $health = Invoke-HostAgentAuthenticatedJson -Uri "http://127.0.0.1:$Port/healthz" -Method GET -Key $token -ExpectedHost $healthExpectedHost; if ($health.ok) { $health | ConvertTo-Json -Compress; exit 0 } } catch {}
    Start-Sleep -Seconds 1
}
throw 'DevFleet host agent did not pass its local health check.'

```


## FILE: source/windows/Invoke-Quarantine-Maintenance.ps1

SHA256: 6770649aab6111d099e0ef4652238910cbfc61a69b4815686fadf052068e6eb8 | Bytes: 865 | Git mode: 100644

```
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([int]$OlderThanDays=30,[string]$InstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe
if(-not $InstanceName){$InstanceName=$config.Failover.InstanceName}
Write-Warning 'This is the only included permanent project-file deletion path. Verify GitHub and vault backups first.'
$phrase=Read-Host "Type PURGE QUARANTINE $InstanceName to continue"
if($phrase -ne "PURGE QUARANTINE $InstanceName"){throw 'Confirmation phrase did not match.'}
if($PSCmdlet.ShouldProcess($InstanceName,"Permanently delete quarantine entries older than $OlderThanDays days")){
 Invoke-External $mp @('exec',$InstanceName,'--','sudo','-u','devrunner','/usr/local/bin/devfleet-purge-quarantine',[string]$OlderThanDays)
}

```


## FILE: source/windows/Invoke-Vault-Maintenance.ps1

SHA256: ebf2557670dfd98191f8918699b08ef6607f166429943034fb96f2d4473944dd | Bytes: 611 | Git mode: 100644

```
[CmdletBinding(SupportsShouldProcess)]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe;$name=$config.Vault.InstanceName
if($PSCmdlet.ShouldProcess($name,'Stop append-only server temporarily, apply retention locally, prune and check repository')){
 Invoke-External $mp @('snapshot',$name,'--name',"pre-maintenance-$((Get-Date).ToString('yyyyMMdd-HHmmss'))") -IgnoreExitCode
 Invoke-External $mp @('exec',$name,'--','sudo','/usr/local/sbin/devfleet-vault-maintenance',[string]$config.Backup.KeepWithin)
}

```


## FILE: source/windows/Migrate-Config.ps1

SHA256: 05506c1475b1562de935be365873970bb297f6f5adff8d281d7b82db9e20ec7f | Bytes: 2289 | Git mode: 100644

```
[CmdletBinding(SupportsShouldProcess)]
param([string]$ConfigPath=(Join-Path $env:ProgramData 'DevFleet\devfleet.config.json'),[string]$OutputPath=$ConfigPath,[switch]$PreviewOnly)
$ErrorActionPreference='Stop';$package=Split-Path -Parent $PSScriptRoot;$defaults=Get-Content (Join-Path $package 'config\devfleet.config.json') -Raw|ConvertFrom-Json -AsHashtable;$existing=Get-Content $ConfigPath -Raw|ConvertFrom-Json -AsHashtable
if([int]$existing.SchemaVersion -gt 2){throw "Configuration schema $($existing.SchemaVersion) is newer than supported."}
function Merge-Map([System.Collections.IDictionary]$Base,[System.Collections.IDictionary]$Overlay){$r=[ordered]@{};foreach($k in $Base.Keys){$v=$Base[$k];$r[$k]=if($v -is [System.Collections.IDictionary]){Merge-Map $v @{}}else{$v}};foreach($k in $Overlay.Keys){$v=$Overlay[$k];if($v -is [System.Collections.IDictionary] -and $r.Contains($k) -and $r[$k] -is [System.Collections.IDictionary]){$r[$k]=Merge-Map $r[$k] $v}else{$r[$k]=$v}};return $r}
$m=Merge-Map $defaults $existing
if([int]$existing.SchemaVersion -eq 1){$m.Development.Profile='strict';$m.Docker.PrimaryMode='rootless';$m.Docker.FailoverMode='rootless'}
$m.SchemaVersion=2;$m.PackageVersion='1.1.0';$m.Primary.InstanceName=[string]$existing.Primary.InstanceName;$m.Failover.InstanceName=[string]$existing.Failover.InstanceName;$m.Vault.InstanceName=[string]$existing.Vault.InstanceName
$preview=[ordered]@{Source=$ConfigPath;Output=$OutputPath;PreviousSchema=[int]$existing.SchemaVersion;NewSchema=2;PreservedInstanceNames=@($m.Primary.InstanceName,$m.Failover.InstanceName,$m.Vault.InstanceName);DevelopmentProfile=$m.Development.Profile;PrimaryDockerMode=$m.Docker.PrimaryMode;FailoverDockerMode=$m.Docker.FailoverMode;MigrationSafety='Existing values, instance names, Docker stores, credentials and data are preserved';Generated=(Get-Date).ToString('o')}
$previewPath=Join-Path (Split-Path $OutputPath) "devfleet-v1.1.0-migration-preview-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json";$preview|ConvertTo-Json -Depth 20|Set-Content $previewPath -Encoding utf8;Write-Host ($preview|ConvertTo-Json -Depth 20)
if($PreviewOnly){return};if($PSCmdlet.ShouldProcess($OutputPath,'Write schema-2 configuration')){$m|ConvertTo-Json -Depth 40|Set-Content $OutputPath -Encoding utf8}

```


## FILE: source/windows/Remove-DevFleet-OwnedIntegrations.ps1

SHA256: a3fa2f7e42741649e8c5098b24574a4d2dd49b0c6f1815f5df25e096e64e1d80 | Bytes: 4357 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$OwnershipPath = 'C:\ProgramData\DevFleetHostAgent\integration-ownership.json',
    [Parameter(Mandatory)][string]$ExpectedGeneration
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet-WindowsIntegrationOwnership.psm1') -Force
$canonicalOwnershipPath = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'DevFleetHostAgent\integration-ownership.json'))
if (-not [IO.Path]::GetFullPath($OwnershipPath).Equals($canonicalOwnershipPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'Windows integration ownership ledger path is not canonical; all resources preserved.' }
$ledger = Read-DevFleetIntegrationOwnership -Path $OwnershipPath
if ([string]$ledger.InstallationGeneration -ne $ExpectedGeneration) { throw 'Windows integration ownership generation changed; foreign resources preserved.' }

foreach ($binding in @($ledger.ScheduledTasks)) {
    $task = Get-ScheduledTask -TaskName ([string]$binding.Name) -ErrorAction SilentlyContinue
    if (-not $task) { continue }
    if (@($task.Actions).Count -ne 1) { throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: scheduled task action count changed. Foreign resource preserved.' }
    $actual = @{
        Name=[string]$task.TaskName; Executable=[string]$task.Actions[0].Execute; Arguments=[string]$task.Actions[0].Arguments
        Principal=[string]$task.Principal.UserId; LogonType=[string]$task.Principal.LogonType; RunLevel=[string]$task.Principal.RunLevel
        Description=[string]$task.Description; Generation=[string]$binding.Generation
    }
    Assert-DevFleetTaskBinding -Expected $binding -Actual $actual | Out-Null
    Stop-ScheduledTask -TaskName ([string]$binding.Name) -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName ([string]$binding.Name) -Confirm:$false
}

foreach ($binding in @($ledger.FirewallRules)) {
    $rules = @(Get-NetFirewallRule -Name ([string]$binding.Name) -ErrorAction SilentlyContinue)
    if ($rules.Count -eq 0) { continue }
    if ($rules.Count -ne 1) { throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall identity is ambiguous. Foreign resources preserved.' }
    $rule = $rules[0]; $port = $rule | Get-NetFirewallPortFilter; $address = $rule | Get-NetFirewallAddressFilter; $interface = $rule | Get-NetFirewallInterfaceFilter
    $actual = @{
        Name=[string]$rule.Name; DisplayName=[string]$rule.DisplayName; Group=[string]$rule.Group; Description=[string]$rule.Description
        Direction=[string]$rule.Direction; Action=[string]$rule.Action; Protocol=[string]$port.Protocol; LocalPort=[string]$port.LocalPort; Profile=[string]$rule.Profile
        InterfaceAlias=[string]$interface.InterfaceAlias; RemoteAddress=[string]$address.RemoteAddress; Generation=[string]$binding.Generation
    }
    Assert-DevFleetFirewallBinding -Expected $binding -Actual $actual | Out-Null
    $rule | Remove-NetFirewallRule -Confirm:$false
}

foreach ($binding in @($ledger.Services)) {
    $escapedServiceName = ([string]$binding.Name).Replace('"','""')
    $serviceFilter = "Name=`"$escapedServiceName`""
    $service = Get-CimInstance Win32_Service -Filter $serviceFilter -ErrorAction SilentlyContinue
    if (-not $service) { continue }
    $actual = @{Name=[string]$service.Name;ImagePath=[string]$service.PathName;Account=[string]$service.StartName;StartMode=[string]$service.StartMode;Generation=[string]$binding.Generation}
    Assert-DevFleetServiceBinding -Expected $binding -Actual $actual | Out-Null
    Stop-Service -Name ([string]$binding.Name) -ErrorAction SilentlyContinue
    & (Join-Path $env:SystemRoot 'System32\sc.exe') delete ([string]$binding.Name) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Owned service deletion failed: $($binding.Name)" }
}

foreach ($binding in @($ledger.ScheduledTasks)) { if (Get-ScheduledTask -TaskName ([string]$binding.Name) -ErrorAction SilentlyContinue) { throw "Owned scheduled task remains after cleanup: $($binding.Name)" } }
foreach ($binding in @($ledger.FirewallRules)) { if (Get-NetFirewallRule -Name ([string]$binding.Name) -ErrorAction SilentlyContinue) { throw "Owned firewall rule remains after cleanup: $($binding.Name)" } }
foreach ($binding in @($ledger.Services)) { if (Get-Service -Name ([string]$binding.Name) -ErrorAction SilentlyContinue) { throw "Owned service remains after cleanup: $($binding.Name)" } }

```


## FILE: source/windows/Repair-DevFleet.ps1

SHA256: a0c494824681657502694ef8cdd9622a247a9401d549fefb17fdbf37632e9ad5 | Bytes: 728 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$mp=Get-MultipassExe
Invoke-External $mp @('set','local.privileged-mounts=false')
Assert-MultipassIsolation -InstanceNames @($InstanceName)
# Snapshot before repair. No deletions or pruning.
$snap="pre-repair-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
New-DevFleetSnapshotSafe -InstanceName $InstanceName -SnapshotName $snap|Out-Null
Invoke-External $mp @('start',$InstanceName) -IgnoreExitCode
Invoke-External $mp @('exec',$InstanceName,'--','sudo','/usr/local/sbin/devfleet-repair')
Write-Host "Safe repair complete. Snapshot: $snap" -ForegroundColor Green

```


## FILE: source/windows/Repair-DevFleetHostSecrets.ps1

SHA256: 6c3233e1643fa8a5e317ee04a98da27b40c297ad15f961a68c5d5ccfd0ceba4b | Bytes: 14840 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('REKEY DEVFLEET HOST SECRETS')][string]$ConfirmReKey
)

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'DevFleet.Common.psm1'
$protocol = Join-Path $PSScriptRoot 'DevFleet-HostAgentProtocol.psm1'
$ownership = Join-Path $PSScriptRoot 'DevFleet-WindowsIntegrationOwnership.psm1'
Import-Module $common -Force
Import-Module $protocol -Force
Import-Module $ownership -Force
Assert-PowerShell7
Assert-Administrator
if (-not (Test-ExistingDeploymentState)) { throw 'SECRET RECOVERY REQUIRED applies only to an existing deployment; use normal fresh installation for a new host.' }

function Write-AtomicUtf8 {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,$Text,[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Get-ExactGuestIdentity {
    param([Parameter(Mandatory)][string]$Multipass,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Path)
    $raw = Invoke-External $Multipass @('exec',$Name,'--','sudo','cat',$Path) -Capture
    try { return $raw | ConvertFrom-Json }
    catch { throw "SECRET RECOVERY REQUIRED: $Name returned invalid immutable identity evidence." }
}

$stateRoot = Get-DevFleetStateRoot
$config = Get-DevFleetConfig
$hostIdentityPath = Join-Path $stateRoot 'node-identity.json'
$hostIdentity = Get-Content -LiteralPath $hostIdentityPath -Raw | ConvertFrom-Json
if ([string]$hostIdentity.node_id -notmatch '^[0-9a-fA-F-]{36}$' -or [string]$hostIdentity.deployment_id -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'SECRET RECOVERY REQUIRED: deployment/node inventory is incomplete; no credentials were changed.'
}
$generation = [guid]::NewGuid().ToString('D')
$newSecrets = New-DevFleetSecretRecord -Generation $generation
$newHostToken = New-RandomSecret 40
$multipass = Get-MultipassExe
$instances = @(Get-MultipassInstances)
$computeName = if ([string]$hostIdentity.node_role -eq 'primary') { [string]$config.Primary.InstanceName } elseif ([string]$hostIdentity.node_role -eq 'surrogate') { [string]$config.Failover.InstanceName } else { throw 'SECRET RECOVERY REQUIRED: unsupported host node role.' }
if (@($instances | Where-Object name -eq $computeName).Count -ne 1) { throw "SECRET RECOVERY REQUIRED: exact compute instance inventory is ambiguous or missing: $computeName" }
Assert-MultipassIsolation -InstanceNames @($computeName)
Invoke-External $multipass @('start',$computeName) -IgnoreExitCode
$computeIdentity = Get-ExactGuestIdentity -Multipass $multipass -Name $computeName -Path '/etc/devfleet/node-identity.json'
if ([string]$computeIdentity.node_id -ne [string]$hostIdentity.node_id -or [string]$computeIdentity.deployment_id -ne [string]$hostIdentity.deployment_id -or [string]$computeIdentity.node_name -ne $computeName) {
    throw 'SECRET RECOVERY REQUIRED: compute identity does not match the exact deployment inventory; no credentials were changed.'
}

$vaultName = $null
$vaultIdentity = $null
if ([string]$hostIdentity.node_role -eq 'surrogate') {
    $vaultName = [string]$config.Vault.InstanceName
    if (@($instances | Where-Object name -eq $vaultName).Count -ne 1) { throw "SECRET RECOVERY REQUIRED: exact vault instance inventory is ambiguous or missing: $vaultName" }
    $vaultIdentityPath = Join-Path $stateRoot 'vault-node-identity.json'
    if (-not (Test-Path -LiteralPath $vaultIdentityPath -PathType Leaf)) { throw 'SECRET RECOVERY REQUIRED: vault identity metadata is missing; use the explicit legacy vault-adoption procedure before re-keying.' }
    $vaultIdentity = Get-Content -LiteralPath $vaultIdentityPath -Raw | ConvertFrom-Json
    Assert-MultipassIsolation -InstanceNames @($vaultName)
    Invoke-External $multipass @('start',$vaultName) -IgnoreExitCode
    $liveVaultIdentity = Get-ExactGuestIdentity -Multipass $multipass -Name $vaultName -Path '/etc/devfleet-vault-identity.json'
    if ([string]$vaultIdentity.deployment_id -ne [string]$hostIdentity.deployment_id -or [string]$liveVaultIdentity.deployment_id -ne [string]$hostIdentity.deployment_id -or [string]$liveVaultIdentity.no