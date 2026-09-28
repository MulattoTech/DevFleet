# DevFleet source part 113

Full-source UTF-8 byte interval [5208000, 5254500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 19e9c3214121546bb6803917c8585e8973bce1c8490ed577826c33778cfe6ec0

<!-- BEGIN SOURCE SLICE -->
=0;output=$output}}
                catch {$endpointResult=[pscustomobject]@{exitCode=if($_.Exception.Message -match '(?i)deadline|timed out|timeout'){124}else{1};output=$_.Exception.Message}}
            }
        } else {
            try {Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 10 -ErrorAction Stop|Out-Null;$endpointResult=[pscustomobject]@{exitCode=0;output=''}}catch{$endpointResult=[pscustomobject]@{exitCode=if($_.Exception.Message -match '(?i)deadline|timed out|timeout'){124}else{1};output=$_.Exception.Message}}
        }
        if ([int]$endpointResult.exitCode -ne 0) {$Readiness.endpointLayer='FAIL';$Readiness.failureClass='DEVFLEET_SERVICE_UNREACHABLE_OVER_TAILSCALE';$Readiness.ready=$false;return $Readiness}
        $Readiness.endpointLayer='PASS'
    }
    $Readiness.ready=$true;$Readiness.failureClass='';return $Readiness
}

function ConvertTo-DevFleetTailscaleNativeArguments {
    param(
        [string]$InstanceName,
        [Parameter(Mandatory)][ValidateSet('Tailscale','System')][string]$CommandKind,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    if (-not $InstanceName) { return @($Arguments) }
    $prefix = @('exec', $InstanceName, '--', 'sudo')
    if ($CommandKind -ceq 'Tailscale') { $prefix += 'tailscale' }
    return @($prefix + $Arguments)
}

function Invoke-DevFleetTailscaleOAuthPairing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$InstanceName,
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][datetime]$DeadlineUtc,
        [string]$EvidencePath = '',
        [string]$RunId = '',
        [string]$TransactionId = '',
        [string]$PayloadSha256 = '',
        [string]$StageName = 'tailscale',
        [string]$TargetRole = '',
        [string]$ExpectedPeer = '',
        [ValidateRange(0,65535)][int]$ServicePort = 0,
        [string]$ServicePath = '/healthz',
         [scriptblock]$CommandInvoker,
         [scriptblock]$EndpointInvoker,
         [scriptblock]$EnrollmentProfileProvider,
         [scriptblock]$EnrollmentOptionsProvider,
         [scriptblock]$TailnetLockProvider,
         [scriptblock]$ServiceStateProvider,
         [scriptblock]$ServiceStartProvider,
         [scriptblock]$PendingRebootProvider
    )
    if ($Hostname -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$' -or ($InstanceName -and $InstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$')) { throw 'Tailscale pairing target identity is invalid.' }
    if ($ExpectedPeer -and $ExpectedPeer -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$|^(?:100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3})$') { throw 'Tailscale expected peer identity is invalid.' }
    if ($ServicePort -and $ServicePath -notmatch '^/[A-Za-z0-9._~!$&''()*+,;=:@%/-]{0,255}$') { throw 'DevFleet service readiness path is invalid.' }
    if (-not $TransactionId) { try { $TransactionId = [string](Get-ActiveDevFleetTransaction).transactionId } catch { } }
    if (-not $PayloadSha256) { try { $PayloadSha256 = [string](Get-ActiveDevFleetTransaction).payloadSha256 } catch { } }
    if ($TransactionId -notmatch '^[0-9a-fA-F]{32}$') { $TransactionId = '' }
    if ($PayloadSha256 -notmatch '^[0-9a-fA-F]{64}$') { $PayloadSha256 = '' }
    $safeRunId = if ($RunId) { $RunId } else { [string]$env:DEVFLEET_RUN_ID }
    if ($safeRunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { $safeRunId = '' }
    $safeStage=ConvertTo-DevFleetTailscaleSafeIdentity $StageName;$safeRole=ConvertTo-DevFleetTailscaleSafeIdentity $TargetRole;$safeInstance=ConvertTo-DevFleetTailscaleSafeIdentity $InstanceName
    $ownerSessionId=0;try{$ownerSessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId}catch{}
    $elevated=$false;try{$elevated=[bool](Test-Administrator)}catch{}
    $targetKind=if($InstanceName){'guest'}else{'windows'}
    $eventContext=@{schemaVersion=1;runId=$safeRunId;transactionId=$TransactionId;payloadSha256=$PayloadSha256;stage=$safeStage;targetKind=$targetKind;targetRole=$safeRole;instanceName=$safeInstance;requestedHostname=$Hostname;ownerDeadlineUtc=$DeadlineUtc.ToUniversalTime().ToString('o');ownerProcessId=$PID;ownerSessionId=$ownerSessionId;environmentUserInteractive=[Environment]::UserInteractive;elevated=$elevated;authProvider='OAuthClientSecret';expectedTag='';enrollmentMode='';expectedPeer=if($ExpectedPeer){$ExpectedPeer}else{''};servicePort=$ServicePort;servicePath=if($ServicePath){$ServicePath}else{''}}
    $writeEvent={param([string]$Class,[hashtable]$Extra=@{});$script:DevFleetTailscalePairingEventSequence++;$event=@{};foreach($key in $eventContext.Keys){$event[$key]=$eventContext[$key]};$event.schemaVersion=1;$event.eventSequence=$script:DevFleetTailscalePairingEventSequence;$event.eventClass=$Class;$event.timestampUtc=[datetime]::UtcNow.ToString('o');foreach($key in $Extra.Keys){$event[$key]=$Extra[$key]};Write-DevFleetTailscalePairingEvent -Path $EvidencePath -Event $event}
    $context=Get-DevFleetDeadlineContext;if($context-and([datetime]$context.StageDeadlineUtc).ToUniversalTime()-lt$DeadlineUtc){$DeadlineUtc=([datetime]$context.StageDeadlineUtc).ToUniversalTime()};$eventContext.ownerDeadlineUtc=$DeadlineUtc.ToUniversalTime().ToString('o')
    $authenticationAttempted=$false;$serviceStartCount=0
    $checkPendingReboot={param([string]$Boundary)
        if(-not $PendingRebootProvider){return}
        if([bool](& $PendingRebootProvider)){
            &$writeEvent 'REBOOT_REQUIRED_DURING_TAILSCALE' @{authenticatedState='NOT_READY';authenticationAttempted=[bool]$authenticationAttempted;rebootRequired=$true;boundary=$Boundary}
            throw "DEVFLEET_REBOOT_REQUIRED: Windows servicing requires a reboot at the $Boundary boundary."
        }
    }
    &$writeEvent 'OAUTH_PAIRING_STARTED' @{authenticatedState='NOT_OBSERVED';authenticationAttempted=$false}
    &$checkPendingReboot 'stage-entry'
    $invoke={param([string[]]$Arguments,[int]$MaximumSeconds=20)
        $verb=[string]$Arguments[0];$remaining=[int][math]::Floor(($DeadlineUtc-[datetime]::UtcNow).TotalSeconds)-5
        if($remaining-le0){&$writeEvent 'COMMAND_BLOCKED_DEADLINE' @{command=$verb;commandOutcome='BLOCKED';failureClass='OWNER_DEADLINE_EXPIRED'};throw 'Tailscale OAuth pairing exceeded the owning stage deadline.'}
        $limit=[math]::Min($MaximumSeconds,$remaining);$commandKind=if($verb-ceq'systemctl'){'System'}else{'Tailscale'};$native=ConvertTo-DevFleetTailscaleNativeArguments -InstanceName $InstanceName -CommandKind $commandKind -Arguments $Arguments
        &$writeEvent 'COMMAND_STARTED' @{command=$verb;commandOutcome='STARTED'}
        try {
            if($CommandInvoker){$response=&$CommandInvoker $Arguments;if($response -is [string]){$response=[pscustomobject]@{exitCode=0;output=[string]$response}};if(-not $response){throw 'command invoker returned no response'};$output=[string]$response.output;$exitCode=[int]$response.exitCode}
            else{try{$output=Invoke-External -FilePath $FilePath -ArgumentList $native -Capture -AllowedExitCodes @(0) -TimeoutSeconds $limit -DeadlineUtc $DeadlineUtc;$exitCode=0}catch{$output=$_.Exception.Message;$exitCode=if($output -match '(?i)deadline|timed out|timeout'){124}else{1}}}
             $outputClass=if($verb-ceq'up'){if($exitCode-eq0){'ENROLLMENT_ACCEPTED'}else{'ENROLLMENT_REJECTED'}}else{ConvertTo-DevFleetTailscaleSafeOutput ($output|Select-Object -First 1)}
             &$writeEvent 'COMMAND_COMPLETED' @{command=$verb;commandOutcome=if($exitCode-eq0){'COMPLETED'}else{'FAILED'};commandOutputClass=$outputClass;exitCode=$exitCode}
             &$checkPendingReboot ("command:$verb")
             return [pscustomobject]@{exitCode=$exitCode;output=$output}
        } catch {if([string]$_.Exception.Message -notmatch '^DEVFLEET_REBOOT_REQUIRED:'){&$writeEvent 'COMMAND_FAILED' @{command=$verb;commandOutcome='FAILED';failureClass='COMMAND_FAILED'}};throw}
    }
    $serviceState='RUNNING'
    try {
        if($ServiceStateProvider){$serviceState=[string](& $ServiceStateProvider)}elseif($InstanceName){$serviceState=[string]((&$invoke @('systemctl','is-active','tailscaled') 10).output).Trim()}else{$service=Get-Service -Name Tailscale -ErrorAction SilentlyContinue;if(-not $service){&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass='TAILSCALE_NOT_INSTALLED'};throw 'TAILSCALE_NOT_INSTALLED: Tailscale service is absent.'};$serviceState=[string]$service.Status}
        &$checkPendingReboot 'service-check'
        if($serviceState -match '(?i)Stopped|Inactive|Deactivated|Failed'){
            $serviceStartCount++
            if($ServiceStartProvider){& $ServiceStartProvider|Out-Null}elseif($InstanceName){$startResult=&$invoke @('systemctl','start','tailscaled') 30;if([int]$startResult.exitCode-ne0){throw 'TAILSCALE_SERVICE_STOPPED: tailscaled could not be started.'}}else{Start-Service -Name Tailscale -ErrorAction Stop}
            $serviceState='RUNNING';&$checkPendingReboot 'service-start'
        }
        if($serviceState -notmatch '(?i)Running|Active|RUNNING'){
            &$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass='TAILSCALE_SERVICE_STOPPED';serviceState=ConvertTo-DevFleetTailscaleSafeOutput $serviceState};throw 'TAILSCALE_SERVICE_STOPPED: Tailscale service is not running.'
        }
        # Peer enumeration can remain blocked while the local node has already
        # authenticated. Self/backend readiness is sufficient for this layer;
        # the expected peer is verified separately with bounded tailscale ping.
        $statusResult=&$invoke @('status','--json','--peers=false') 20
        $preferencesResult=&$invoke @('debug','prefs') 10
        if([int]$statusResult.exitCode -ne 0){&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass='TAILSCALE_CONTROL_PLANE_OFFLINE';command='status';exitCode=[int]$statusResult.exitCode;authenticationAttempted=$false};throw 'TAILSCALE_CONTROL_PLANE_OFFLINE: Tailscale status command failed.'}
        if([int]$preferencesResult.exitCode -ne 0){&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass='TAILSCALE_HEALTH_ERROR';command='debug-prefs';exitCode=[int]$preferencesResult.exitCode;authenticationAttempted=$false};throw 'TAILSCALE_HEALTH_ERROR: Tailscale preference inspection failed.'}
        $lock=if($TailnetLockProvider){& $TailnetLockProvider}else{Get-DevFleetTailscaleTailnetLockState -FilePath $FilePath -InstanceName $InstanceName -DeadlineUtc $DeadlineUtc -CommandInvoker $CommandInvoker}
        &$checkPendingReboot 'tailnet-lock-check'
        &$writeEvent 'TAILNET_LOCK_OBSERVED' @{tailnetLockStatus=$lock.status;tailnetLockObserved=[bool]$lock.observed}
        if($lock.status -in @('ENABLED','UNKNOWN')) { &$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass='TAILNET_LOCK_SIGNING_REQUIRED';authenticationAttempted=$false;tailnetLockStatus=$lock.status}; throw 'TAILNET_LOCK_SIGNING_REQUIRED: Tailnet Lock requires a trusted signing path before automatic enrollment.' }
        $profile=if($EnrollmentProfileProvider){& $EnrollmentProfileProvider}else{Get-DevFleetTailscaleEnrollmentProfile}
        $readinessHostname=Resolve-DevFleetTailscaleProfileHostname -Profile $profile -RequestedHostname $Hostname -InstanceName $InstanceName
        $readiness=Get-DevFleetTailscaleReadiness -StatusJson ([string]$statusResult.output) -ExpectedHostname $readinessHostname -ExpectedTag ([string]$profile.tag) -PreferencesJson ([string]$preferencesResult.output)
        $eventContext.expectedTag=[string]$profile.tag;$eventContext.enrollmentMode=[string]$profile.mode
        &$writeEvent 'READINESS_LAYER2_OBSERVED' @{statusClass=$readiness.statusClass;authenticated=[bool]$readiness.authenticated;selfOnline=[bool]$readiness.selfOnline;hasTailscaleIp=[bool]$readiness.hasTailscaleIp;selfHostname=$readiness.selfHostname;expectedHostname=$readinessHostname;nodeIdentityMatch=$readiness.nodeIdentityMatch;expectedTagMatch=$readiness.expectedTagMatch;blockingHealthError=[bool]$readiness.blockingHealthError;serviceLayer='PASS';authenticationAttempted=$false}
        $authenticationAttempted=$false;$authResult=$null
        if($readiness.ready){$readiness.serviceLayer='PASS';$readiness=Invoke-DevFleetTailscalePeerAndEndpointReadiness -Readiness $readiness -ExpectedPeer $ExpectedPeer -ServicePort $ServicePort -ServicePath $ServicePath -TailscaleInvoker $invoke -FilePath $FilePath -InstanceName $InstanceName -EndpointInvoker $EndpointInvoker -DeadlineUtc $DeadlineUtc;if(-not $readiness.ready){&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass=$readiness.failureClass;authenticationAttempted=$false;peerLayer=$readiness.peerLayer;endpointLayer=$readiness.endpointLayer};throw ([string]$readiness.failureClass + ': Tailscale readiness peer or endpoint gate failed.')};&$writeEvent 'OAUTH_PAIRING_PASS' @{authenticatedState='AUTHENTICATED';authenticationAttempted=$false;mutation='NONE';statusClass='READY';peerLayer=$readiness.peerLayer;endpointLayer=$readiness.endpointLayer};return [pscustomobject]@{authenticated=$true;ipv4=$readiness.tailscaleIpv4;authenticationAttempted=$false;authenticationSucceeded=$true;authProvider='OAuthClientSecret';enrollmentMode=$profile.mode;expectedTag=$profile.tag;hostname=$readiness.selfHostname;readiness=$readiness;serviceRecoveryCount=$serviceStartCount}}
        if($readiness.statusClass -notin @('NEEDS_LOGIN','CONTROL_PLANE_OFFLINE') -and $readiness.backendState -notin @('NeedsLogin','NoState')){&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass=$readiness.failureClass;statusClass=$readiness.statusClass;authenticationAttempted=$false};throw ([string]$readiness.failureClass + ': Tailscale readiness gate failed before authentication.')}
        &$checkPendingReboot 'oauth-enrollment-before'
        $options=if($EnrollmentOptionsProvider){& $EnrollmentOptionsProvider $Hostname $InstanceName $TargetRole}else{Get-DevFleetTailscaleEnrollmentOptions -RequestedHostname $Hostname -InstanceName $InstanceName -TargetRole $TargetRole}
        $eventContext.expectedTag=$options.tag;$eventContext.enrollmentMode=$options.mode;$authenticationAttempted=$true
        &$writeEvent 'OAUTH_ENROLLMENT_STARTED' @{authenticatedState='AUTHENTICATION_PENDING';authenticationAttempted=$true;mutation='OAUTH_ENROLLMENT_ONCE'}
        $payload="$($options.secret)?ephemeral=$(([string]$options.ephemeral).ToLowerInvariant())&preauthorized=$(([string]$options.preauthorized).ToLowerInvariant())"
        # The query controls the OAuth client's registration lifecycle. It is
        # written only to the short-lived file/pipe and never to evidence.
        if($InstanceName){
            $remotePath="/run/devfleet-tailscale-oauth-$([guid]::NewGuid().ToString('N'))"
            $qPath=ConvertTo-ShellSingleQuotedScalar $remotePath;$qTag=ConvertTo-ShellSingleQuotedScalar ([string]$options.tag);$qHost=ConvertTo-ShellSingleQuotedScalar ([string]$options.hostname)
            $guestScript=@'
set -Eeuo pipefail
p=__PATH__
cleanup(){ sudo rm -f -- "$p"; }
trap cleanup EXIT
IFS= read -r secret
test -n "$secret"
printf '%s\n' "$secret" | sudo tee "$p" >/dev/null
sudo chmod 600 "$p"
set +e
timeout --signal=TERM --kill-after=10s 120s sudo tailscale up --client-secret=file:$p --advertise-tags=__TAG__ --hostname=__HOST__ --accept-dns=false --timeout=110s
rc=$?
set -e
printf 'DEVFLEET_TAILSCALE_UP_EXIT=%s\n' "$rc"
exit 0
'@
            $guestScript=$guestScript.Replace('__PATH__',$qPath).Replace('__TAG__',$qTag).Replace('__HOST__',$qHost)
            # Multipass command arguments are deliberately restricted to
            # single-line shell scalars. Keep the guest program as a
            # here-string for reviewability, but flatten its commands before
            # passing it as the bash -lc argument; the OAuth payload remains
            # delivered only through the protected standard-input transport.
            $guestScript=((@($guestScript -split "`r?`n"|Where-Object{$_ -ne ''}) -join '; '))
            if($CommandInvoker){$authResult=&$CommandInvoker @('up',"--client-secret=file:$remotePath",("--advertise-tags=$($options.tag)"),("--hostname=$($options.hostname)"),'--accept-dns=false','--timeout=110s');if($authResult -is [string]){$authResult=[pscustomobject]@{exitCode=0;output=[string]$authResult}}}else{$remaining=[int][math]::Floor(($DeadlineUtc-[datetime]::UtcNow).TotalSeconds)-5;$authText=Invoke-MultipassWithStandardInput -FilePath $FilePath -InstanceName $InstanceName -CommandArgumentList @('bash','-lc',$guestScript) -StandardInputText ($payload+"`n") -TimeoutSeconds ([math]::Min(120,[math]::Max(1,$remaining))) -DeadlineUtc $DeadlineUtc -Capture -ExpectedCompletionMarkerPattern '(?m)^DEVFLEET_TAILSCALE_UP_EXIT=(\d+)\s*$';$match=[regex]::Match([string]$authText,'(?m)^DEVFLEET_TAILSCALE_UP_EXIT=(\d+)\s*$');$guestExitCode=if($match.Success){[int]$match.Groups[1].Value}else{1};$authResult=[pscustomobject]@{exitCode=$guestExitCode;output=[string]$authText}}
            &$writeEvent 'OAUTH_ENROLLMENT_COMPLETED' @{authenticatedState=if([int]$authResult.exitCode -eq 0){'AUTHENTICATION_ACCEPTED'}else{'AUTHENTICATION_FAILED'};authenticationAttempted=$true;commandOutcome=if([int]$authResult.exitCode -eq 0){'COMPLETED'}else{'FAILED'};exitCode=[int]$authResult.exitCode;failureClass=if([int]$authResult.exitCode -eq 124){'TAILSCALE_AUTH_TIMEOUT'}else{''}}
            &$checkPendingReboot 'oauth-enrollment'
        }else{
            $authFile=Join-Path (Join-Path (Get-DevFleetStateRoot) 'tmp') ('.tailscale-oauth-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path (Split-Path -Parent $authFile) -Force|Out-Null
            try{[IO.File]::WriteAllText($authFile,'',[Text.UTF8Encoding]::new($false));Set-DevFleetTailscaleProtectedFileAcl -Path $authFile;[IO.File]::WriteAllText($authFile,$payload+"`n",[Text.UTF8Encoding]::new($false));$args=@('up',"--client-secret=file:$authFile",("--advertise-tags=$($options.tag)"),("--hostname=$($options.hostname)"),'--accept-dns=false','--unattended=true','--timeout=120s');if($CommandInvoker){$authResult=&$CommandInvoker $args;if($authResult -is [string]){$authResult=[pscustomobject]@{exitCode=0;output=[string]$authResult}}}else{$authResult=&$invoke $args 120}}finally{if(Test-Path -LiteralPath $authFile -PathType Leaf){$length=(Get-Item -LiteralPath $authFile -Force).Length;if($length-gt0){[IO.File]::WriteAllBytes($authFile,[byte[]]::new($length))};Remove-Item -LiteralPath $authFile -Force -ErrorAction SilentlyContinue}}
            &$checkPendingReboot 'oauth-enrollment'
        }
        if(-not $authResult -or [int]$authResult.exitCode-ne0){$failureClass=if($authResult -and [int]$authResult.exitCode -eq 124){'TAILSCALE_AUTH_TIMEOUT'}else{'TAILSCALE_AUTH_FAILED'};&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass=$failureClass;authenticationAttempted=$true;authenticationSucceeded=$false;statusClass='AUTH_FAILED'};throw "${failureClass}: OAuth client enrollment did not complete successfully."}
        # A successful `tailscale up` can briefly precede control-plane
        # availability while the daemon publishes its new identity. Keep the
        # post-enrollment check fail-closed, but give that narrow convergence
        # window a finite bounded set of status attempts. OAuth itself remains one-shot;
        # preferences and structured readiness are still required afterward.
        $finalStatus=$null;$postEnrollmentStatusAttempts=0
        $postEnrollmentStatusMaximumAttempts=8
        # Each status call is bounded to ten seconds and each retry may sleep
        # for up to two seconds. A 120-second wall-clock window gives the
        # finite eight-attempt policy room to observe daemon convergence while
        # remaining well inside the owning Tailscale stage deadline.
        $postEnrollmentStatusWindowSeconds=120
        $postEnrollmentStatusDeadline=[datetime]::UtcNow.AddSeconds($postEnrollmentStatusWindowSeconds)
        if($DeadlineUtc -gt [datetime]::MinValue -and $DeadlineUtc.ToUniversalTime() -lt $postEnrollmentStatusDeadline){$postEnrollmentStatusDeadline=$DeadlineUtc.ToUniversalTime()}
        do {
            $postEnrollmentStatusAttempts++
            $statusRemaining=[int][math]::Floor(($postEnrollmentStatusDeadline-[datetime]::UtcNow).TotalSeconds)
            $statusMaximumSeconds=[math]::Min(10,[math]::Max(1,$statusRemaining))
            $finalStatus=&$invoke @('status','--json','--peers=false') $statusMaximumSeconds
            if([int]$finalStatus.exitCode -eq 0){break}
            $remaining=[int][math]::Floor(($postEnrollmentStatusDeadline-[datetime]::UtcNow).TotalSeconds)
            $ownerRemaining=[int][math]::Floor(($DeadlineUtc-[datetime]::UtcNow).TotalSeconds)-5
            $remaining=[math]::Min($remaining,$ownerRemaining)
            if($postEnrollmentStatusAttempts -ge $postEnrollmentStatusMaximumAttempts -or $remaining -le 0){break}
            &$writeEvent 'POST_ENROLLMENT_STATUS_RETRY' @{command='status';commandOutcome='RETRY';pollCount=$postEnrollmentStatusAttempts;lastStatusClass='NONZERO';authenticationAttempted=$true;authenticationSucceeded=$false;retryWindowSeconds=$postEnrollmentStatusWindowSeconds;maximumAttempts=$postEnrollmentStatusMaximumAttempts}
            Start-Sleep -Seconds ([math]::Min(2,[math]::Max(1,$remaining)))
        } while($true)
        if([int]$finalStatus.exitCode -ne 0){&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass='TAILSCALE_CONTROL_PLANE_OFFLINE';command='status';exitCode=[int]$finalStatus.exitCode;authenticationAttempted=$true;authenticationSucceeded=$false};throw 'TAILSCALE_CONTROL_PLANE_OFFLINE: post-enrollment Tailscale status command failed.'}
        $finalPrefs=&$invoke @('debug','prefs') 10
        if([int]$finalPrefs.exitCode -ne 0){&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass='TAILSCALE_HEALTH_ERROR';command='debug-prefs';exitCode=[int]$finalPrefs.exitCode;authenticationAttempted=$true;authenticationSucceeded=$false};throw 'TAILSCALE_HEALTH_ERROR: post-enrollment Tailscale preference inspection failed.'}
        $readiness=Get-DevFleetTailscaleReadiness -StatusJson ([string]$finalStatus.output) -ExpectedHostname ([string]$options.hostname) -ExpectedTag ([string]$options.tag) -PreferencesJson ([string]$finalPrefs.output);$readiness.serviceLayer='PASS'
        if($readiness.ready){$readiness=Invoke-DevFleetTailscalePeerAndEndpointReadiness -Readiness $readiness -ExpectedPeer $ExpectedPeer -ServicePort $ServicePort -ServicePath $ServicePath -TailscaleInvoker $invoke -FilePath $FilePath -InstanceName $InstanceName -EndpointInvoker $EndpointInvoker -DeadlineUtc $DeadlineUtc}
        if(-not $readiness.ready){&$writeEvent 'OAUTH_PAIRING_FAILED' @{failureClass=$readiness.failureClass;authenticationAttempted=$true;authenticationSucceeded=$false;statusClass=$readiness.statusClass;expectedTagMatch=$readiness.expectedTagMatch;peerLayer=$readiness.peerLayer;endpointLayer=$readiness.endpointLayer};throw ([string]$readiness.failureClass + ': authenticated Tailscale node did not pass structured readiness.')}
        &$writeEvent 'OAUTH_PAIRING_PASS' @{authenticatedState='AUTHENTICATED';authenticationAttempted=$true;authenticationSucceeded=$true;mutation='OAUTH_ENROLLMENT_ONCE';statusClass='READY';expectedTagMatch=$readiness.expectedTagMatch;selfHostname=$readiness.selfHostname}
        return [pscustomobject]@{authenticated=$true;ipv4=$readiness.tailscaleIpv4;authenticationAttempted=$true;authenticationSucceeded=$true;authProvider='OAuthClientSecret';enrollmentMode=$options.mode;expectedTag=$options.tag;hostname=$readiness.selfHostname;readiness=$readiness;serviceRecoveryCount=$serviceStartCount}
    } catch {
        $message=[string]$_.Exception.Message
        if($message -match '^TAILSCALE_CREDENTIAL_MISSING'){Write-DevFleetTailscaleOAuthActionRequired}
        throw
    }
}

function Get-DevFleetTailscaleTailnetLockState {
    param([Parameter(Mandatory)][string]$FilePath,[string]$InstanceName,[datetime]$DeadlineUtc=[datetime]::UtcNow.AddSeconds(30),[scriptblock]$CommandInvoker)
    $arguments=@('lock','status','--json')
    if ($CommandInvoker) { $response=& $CommandInvoker $arguments; if($response -is [string]){$response=[pscustomobject]@{exitCode=0;output=[string]$response};} elseif(-not $response){$response=[pscustomobject]@{exitCode=1;output=''}} } else {
        $native=if($InstanceName){@('exec',$InstanceName,'--','sudo','tailscale')+$arguments}else{$arguments}
        try { $response=[pscustomobject]@{exitCode=0;output=(Invoke-External -FilePath $FilePath -ArgumentList $native -Capture -IgnoreExitCode -TimeoutSeconds 20 -DeadlineUtc $DeadlineUtc)} } catch { $response=[pscustomobject]@{exitCode=1;output='' } }
    }
    if(-not $response){return [pscustomobject]@{status='UNKNOWN';enabled=$null;observed=$false;outputClass='UNAVAILABLE';exitCode=1}}
    if($response -is [string]){$response=[pscustomobject]@{exitCode=0;output=[string]$response}}
    $responseExitCode=1
    $responseExitProperty=$response.PSObject.Properties['exitCode']
    if($responseExitProperty){try{$responseExitCode=[int]$responseExitProperty.Value}catch{$responseExitCode=1}}
    $responseOutput=''
    $responseOutputProperty=$response.PSObject.Properties['output']
    if($responseOutputProperty){$responseOutput=[string]$responseOutputProperty.Value}
    $text=ConvertTo-DevFleetTailscaleSafeOutput $responseOutput
    if($responseExitCode -ne 0){return [pscustomobject]@{status='UNKNOWN';enabled=$null;observed=$false;outputClass='NONZERO';exitCode=$responseExitCode}}
    try {
        $json=[string]$response.output | ConvertFrom-Json -ErrorAction Stop
        $enabled=$false
        foreach($name in @('enabled','locked','tailnetLockEnabled')){if($json.PSObject.Properties[$name]){$enabled=[bool]$json.$name;break}}
        return [pscustomobject]@{status=if($enabled){'ENABLED'}else{'DISABLED'};enabled=$enabled;observed=$true;outputClass='JSON';exitCode=$responseExitCode}
    } catch {
        if($text -match '(?i)disabled|not enabled|not locked|no tailnet lock'){return [pscustomobject]@{status='DISABLED';enabled=$false;observed=$true;outputClass='TEXT';exitCode=$responseExitCode}}
        return [pscustomobject]@{status='UNKNOWN';enabled=$null;observed=$false;outputClass='UNAVAILABLE';exitCode=$responseExitCode}
    }
}

function Write-DevFleetTailscaleOAuthActionRequired {
    Write-Host "`a" -ForegroundColor Yellow
    try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}
    try { [Console]::Beep(1200,450); Start-Sleep -Milliseconds 100; [Console]::Beep(1700,700) } catch {}
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host '>>> DYLAN ACTION REQUIRED <<< ' -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Yellow
    try {
        $package=Get-PackageRootFromState
        Write-Host "Run once in a local Administrator PowerShell: & '$package\windows\Set-DevFleetTailscaleOAuthCredential.ps1'" -ForegroundColor Yellow
    } catch { Write-Host 'Run the repository-supported Set-DevFleetTailscaleOAuthCredential.ps1 workflow in a local Administrator PowerShell.' -ForegroundColor Yellow }
}

function Open-DevFleetTailscaleAuthenticationPage {
    param([Parameter(Mandatory)][uri]$Uri)
    # The exact official, one-use device URL was validated above. Opening the
    # interactive browser does not store a password or reusable authentication key.
    $process = Start-Process -FilePath $Uri.AbsoluteUri -PassThru -ErrorAction Stop
    $processId = 0
    $processSessionId = $null
    $processName = ''
    if ($process) {
        try { $processId = [int]$process.Id } catch { }
        try { $processSessionId = [int]$process.SessionId } catch { }
        try { $processName = [string]$process.ProcessName } catch { }
    }
    return [pscustomobject]@{
        apiAccepted = $true
        processObserved = $processId -gt 0
        processId = if ($processId -gt 0) { $processId } else { $null }
        processSessionId = $processSessionId
        processName = $processName
    }
}

function Invoke-DevFleetTailscaleBrowserPairing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$InstanceName,
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][datetime]$DeadlineUtc,
        [string]$EvidencePath = '',
        [string]$RunId = '',
        [string]$TransactionId = '',
        [string]$PayloadSha256 = '',
        [string]$StageName = 'tailscale',
        [string]$TargetRole = ''
    )
    if($Hostname-notmatch'^[A-Za-z0-9][A-Za-z0-9-]{0,62}$'-or($InstanceName-and$InstanceName-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$')){throw 'Tailscale pairing target identity is invalid.'}
    if (-not $TransactionId) { try { $TransactionId = [string](Get-ActiveDevFleetTransaction).transactionId } catch { } }
    if (-not $PayloadSha256) { try { $PayloadSha256 = [string](Get-ActiveDevFleetTransaction).payloadSha256 } catch { } }
    if ($TransactionId -notmatch '^[0-9a-fA-F]{32}$') { $TransactionId = '' }
    if ($PayloadSha256 -notmatch '^[0-9a-fA-F]{64}$') { $PayloadSha256 = '' }
    $safeRunId = if ($RunId) { $RunId } else { [string]$env:DEVFLEET_RUN_ID }
    if ($safeRunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { $safeRunId = '' }
    $safeStage = ConvertTo-DevFleetTailscaleSafeIdentity $StageName
    $safeRole = ConvertTo-DevFleetTailscaleSafeIdentity $TargetRole
    $safeInstance = ConvertTo-DevFleetTailscaleSafeIdentity $InstanceName
    $ownerProcessId = $PID
    $ownerSessionId = 0
    try { $ownerSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId } catch { }
    $elevated = $false
    try { $elevated = [bool](Test-Administrator) } catch { }
    $targetKind = if ($InstanceName) { 'guest' } else { 'windows' }
    $eventContext = @{
        schemaVersion = 1
        runId = $safeRunId
        transactionId = $TransactionId
        payloadSha256 = $PayloadSha256
        stage = $safeStage
        targetKind = $targetKind
        targetRole = $safeRole
        instanceName = $safeInstance
        requestedHostname = $Hostname
        ownerDeadlineUtc = $DeadlineUtc.ToUniversalTime().ToString('o')
        ownerProcessId = $ownerProcessId
        ownerSessionId = $ownerSessionId
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
# restart or host-network change is