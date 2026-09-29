# DevFleet source part 092

Full-source UTF-8 byte interval [4231500, 4278000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: c872bf7796c7c0af1543469a28a82021ee6489977b38b8e795862b0340f1082c

<!-- BEGIN SOURCE SLICE -->
artNew()
        try{$output=Invoke-MultipassWithStandardInput -FilePath 'fixture-multipass.exe' -InstanceName $name -CommandArgumentList @('bash','-c',$consumer,'--',(UnixPath $caseRoot)) -StandardInputText $dummy -TimeoutSeconds 45 -DeadlineUtc $deadline -Capture}catch{$errorText=$_.Exception.Message}
        $timer.Stop()
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($dummy))).ToLowerInvariant()
        $exists=Test-Path $state.localDirectory
        $secretOnlyOnTransfer=@($state.calls|Where-Object{$_.hasInput-and$_.verb-cne'transfer'}).Count-eq0
        $noSecretArgs=@($state.calls|Where-Object argumentContainsDummy).Count-eq0
        $bounded=@($state.calls|Where-Object{$_.deadline-gt$deadline.AddSeconds(-5)}).Count-eq0
        if($state.calls.Count-ge2){$bounded=$bounded-and($state.calls[0].deadline-le$deadline.AddSeconds(-15))-and($state.calls[1].deadline-le$deadline.AddSeconds(-15))}
        $pass=switch($mode){
            {$_-in@('success','unicode')} {$output.Trim()-ceq$hash-and-not$errorText-and-not$exists-and$state.calls.Count-eq4;break}
            'transfer-failure' {$errorText-match'exit code 77'-and-not$exists-and$state.calls.Count-eq3;break}
            'consumer-failure' {$errorText-match'exit code 23'-and-not$exists-and$state.calls.Count-eq4;break}
            'bad-file-mode' {$errorText-match'exit code 1'-and-not$exists-and$state.calls.Count-eq4;break}
            'prepare-collision' {$errorText-match'exit code 1'-and(Test-Path (Join-Path $state.localDirectory 'foreign-marker'))-and$state.calls.Count-eq1;break}
            'prepare-partial-failure' {$errorText-match'exit code 42'-and-not$exists-and$state.calls.Count-eq1;break}
            'cleanup-failure' {$errorText-match'cleanup unavailable'-and-not$exists-and$state.calls.Count-eq4;break}
            'combined-failure' {$errorText-match'exit code 77'-and$errorText-match'Guest input cleanup failed'-and$errorText-match'cleanup unavailable'-and$exists-and$state.calls.Count-eq3;break}
            default {$errorText-and$state.calls.Count-eq0-and-not$exists}
        }
        $checks.Add([pscustomobject]@{case=$mode;pass=[bool]($pass-and$secretOnlyOnTransfer-and$noSecretArgs-and$bounded-and(-not$dummy-or-not$errorText.Contains($dummy)));calls=$state.calls.Count;elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);stagingRemains=$exists;transferredBytes=$state.transferredBytes;expectedBytes=[Text.Encoding]::UTF8.GetByteCount($dummy);transferredHashMatches=($state.transferredSha256-ceq$hash);error=if($pass){''}else{$errorText}})
    }
} finally {
    $global:DevFleetDeadlineContext=$priorContext
    $resolved=[IO.Path]::GetFullPath($fixtureRoot);$tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not$resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped the temporary directory.'}
    if(Test-Path $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
[pscustomobject]@{status=if(@($checks|Where-Object{-not$_.pass}).Count){'FAIL'}else{'PASS'};passed=@($checks|Where-Object pass).Count;total=$checks.Count;checks=@($checks);vmOperations=0;realMultipassOperations=0;fixtureBoundary='Multipass external I/O, remote filesystem root/sudo and Linux mode observations are fixtures. Production orchestration, shell parsing, collision rejection, input helper, JSON parser, native stdin writer, file content/EOF and unlink execute locally. Linux ACL enforcement requires the actual guest gate.'}|ConvertTo-Json -Depth 5
if(@($checks|Where-Object{-not$_.pass}).Count){exit 1}

```


## FILE: source/tests/Test-PendingReboot.ps1

SHA256: 0dae89d672d2e5250c009b50f69f4b248e9315bd169cbb82a8828f72d7fff966 | Bytes: 1582 | Git mode: 100644

```
$ErrorActionPreference = 'Stop'
$common = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\DevFleet.Common.psm1'
Import-Module $common -Force
$cases = @(
    @{ name='clean absent'; cbs=$false; wu=$false; pfro=$null; expected=$false },
    @{ name='empty value'; cbs=$false; wu=$false; pfro=@(); expected=$false },
    @{ name='empty strings'; cbs=$false; wu=$false; pfro=@('','   '); expected=$false },
    @{ name='real rename'; cbs=$false; wu=$false; pfro=@('C:\source.tmp','C:\destination.tmp'); expected=$true },
    @{ name='real delete'; cbs=$false; wu=$false; pfro=@('C:\source.tmp',''); expected=$true },
    @{ name='CBS with empty value'; cbs=$true; wu=$false; pfro=@(''); expected=$true },
    @{ name='Windows Update with empty value'; cbs=$false; wu=$true; pfro=@(''); expected=$true },
    @{ name='multiple operations'; cbs=$false; wu=$false; pfro=@('C:\one','C:\two','C:\three',''); expected=$true }
)
foreach ($case in $cases) {
    $actual = Test-PendingRebootState -CbsPending:$case.cbs -WindowsUpdatePending:$case.wu -PendingFileRenameOperations $case.pfro
    if ([bool]$actual -ne [bool]$case.expected) { throw "PFRO semantic case failed: $($case.name) expected=$($case.expected) actual=$actual" }
}
$source = Get-Content $common -Raw
if ($source -match '(?m)\b(Remove|Set)-Item(Property)?\b[^\r\n]*PendingFileRenameOperations') { throw 'PFRO regression test detected registry mutation in shipping reboot detection.' }
[ordered]@{ status='PASS'; cases=$cases.Count; cbsAndWindowsUpdatePreserved=$true; registryMutated=$false } | ConvertTo-Json -Compress

```


## FILE: source/tests/Test-ProcessOutputDrain.ps1

SHA256: a553a80e8fbe8c2863faeacf3ccccf4261e7b7e636e819443a1f7410b44bbf1c | Bytes: 5755 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'windows\DevFleet.Common.psm1') -Force

$shell=(Get-Command powershell.exe -ErrorAction Stop).Source
$normal=Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command',"[Console]::Out.Write('complete-output')") -Capture
if($normal -cne 'complete-output'){throw 'Invoke-External did not preserve ordinary complete output.'}

$pidPath=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-common-inherited-pipe-"+[guid]::NewGuid().ToString('N')+'.pid')
$descendantPid=0
try{
    $escapedPidPath=$pidPath.Replace("'","''")
    $parentCommand="`$childInfo=[Diagnostics.ProcessStartInfo]::new();`$childInfo.FileName=(Get-Command powershell.exe).Source;`$childInfo.UseShellExecute=`$false;`$childInfo.CreateNoWindow=`$true;`$childInfo.ArgumentList.Add('-NoProfile');`$childInfo.ArgumentList.Add('-NonInteractive');`$childInfo.ArgumentList.Add('-Command');`$childInfo.ArgumentList.Add('Start-Sleep -Seconds 30');`$child=[Diagnostics.Process]::Start(`$childInfo);[IO.File]::WriteAllText('$escapedPidPath',[string]`$child.Id);exit 0"
    $timer=[Diagnostics.Stopwatch]::StartNew();$blocked=$false
    try{Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command',$parentCommand) -Capture|Out-Null}catch{if($_.Exception.Message -match 'redirected output was incomplete after the bounded post-exit drain'){$blocked=$true}else{throw}}
    $timer.Stop()
    if(-not $blocked -or $timer.Elapsed -ge [TimeSpan]::FromSeconds(15)){throw 'Invoke-External did not fail closed within the bounded post-exit drain allowance.'}
    if(-not(Test-Path -LiteralPath $pidPath) -or -not [int]::TryParse([IO.File]::ReadAllText($pidPath),[ref]$descendantPid)){throw 'Invoke-External inherited-handle fixture did not publish its descendant PID.'}
    $descendant=Get-Process -Id $descendantPid -ErrorAction Stop
    if($descendant.HasExited){throw 'Invoke-External killed a descendant merely to manufacture redirected-output EOF.'}
}finally{
    if($descendantPid -gt 0){Stop-Process -Id $descendantPid -Force -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

$tx='a'*32;$payload='b'*64
$computeBoundary=New-DevFleetBootstrapBoundary -Kind compute -InstanceName 'devfleet-primary' -TransactionId $tx -PayloadSha256 $payload -BootstrapMaxSeconds 6600 -PackageVersion '1.2.13' -NodeRole 'primary'
if($computeBoundary.multipassResolvedStageName -cne 'compute-devfleet-primary-multipass-resolved' -or $computeBoundary.isolationVerifiedStageName -cne 'compute-devfleet-primary-isolation-verified' -or $computeBoundary.instanceAbsentStageName -cne 'compute-devfleet-primary-instance-absent' -or $computeBoundary.instanceLaunchedStageName -cne 'compute-devfleet-primary-instance-launched' -or $computeBoundary.instanceReadyStageName -cne 'compute-devfleet-primary-instance-ready' -or $computeBoundary.payloadTransferredStageName -cne 'compute-devfleet-primary-payload-transferred' -or $computeBoundary.payloadExtractedStageName -cne 'compute-devfleet-primary-payload-extracted' -or $computeBoundary.completionStageName -cne 'compute-devfleet-primary'){throw 'Compute bootstrap boundary did not produce the allowlisted substep names.'}
if($computeBoundary.extractionCommand -notmatch 'unzip.+devfleet-payload\.zip' -or $computeBoundary.extractionCommand -match 'sudo\s+bash|(?i)password|apitoken|secret='){throw 'Compute extraction did not remain a distinct non-secret production boundary.'}
if($computeBoundary.bootstrapCommand -notmatch "bootstrap-compute\.sh.*--transaction-id '$tx'.*--payload-sha256 '$payload'.*--bootstrap-max-seconds '6600'.*--package-version '1\.2\.13'.*--node-role 'primary'" -or $computeBoundary.bootstrapCommand -match '(?i)password|apitoken|secret='){throw 'Compute bootstrap command did not preserve its non-secret identity contract.'}
$vaultBoundary=New-DevFleetBootstrapBoundary -Kind vault -InstanceName 'devfleet-vault' -TransactionId $tx -PayloadSha256 $payload -BootstrapMaxSeconds 3900 -PackageVersion 'vault' -NodeRole 'vault'
if($vaultBoundary.multipassResolvedStageName -cne 'vault-multipass-resolved' -or $vaultBoundary.isolationVerifiedStageName -cne 'vault-isolation-verified' -or $vaultBoundary.instancePresentStageName -cne 'vault-instance-present' -or $vaultBoundary.instanceStartedStageName -cne 'vault-instance-started' -or $vaultBoundary.instanceReadyStageName -cne 'vault-instance-ready' -or $vaultBoundary.payloadTransferredStageName -cne 'vault-payload-transferred' -or $vaultBoundary.payloadExtractedStageName -cne 'vault-payload-extracted' -or $vaultBoundary.completionStageName -cne 'vault'){throw 'Vault bootstrap boundary did not produce the allowlisted substep names.'}
if($vaultBoundary.extractionCommand -notmatch 'unzip.+devfleet-vault-payload\.zip' -or $vaultBoundary.extractionCommand -match 'sudo\s+bash|(?i)password|resticpassword|secret='){throw 'Vault extraction did not remain a distinct non-secret production boundary.'}
if($vaultBoundary.bootstrapCommand -notmatch "bootstrap-vault\.sh.*--transaction-id '$tx'.*--payload-sha256 '$payload'.*--bootstrap-max-seconds '3900'.*--package-version 'vault'.*--node-role 'vault'" -or $vaultBoundary.bootstrapCommand -match '(?i)password|resticpassword|secret='){throw 'Vault bootstrap command did not preserve its non-secret identity contract.'}

[ordered]@{ok=$true;tests=8;ordinaryCompleteOutput=$true;inheritedPipeFailsClosedBoundedly=$true;computeExtractionSeparated=$true;vaultExtractionSeparated=$true;computeBoundaryIdentityBound=$true;vaultBoundaryIdentityBound=$true;substepNamesAllowlisted=$true;secretsExcludedFromArguments=$true}|ConvertTo-Json -Compress

```


## FILE: source/tests/Test-TailscaleBrowserPairing.ps1

SHA256: 4cae989aa96639e30e27d4a444b2bf1ae1c6f922d1cb5203f522b5db7e52408e | Bytes: 5498 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$WarningPreference='SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot '../windows/DevFleet.Tailscale.psm1') -Force
$module=Get-Module DevFleet.Tailscale
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$results.Add([pscustomobject]@{case=$Name;pass=$Pass})}
foreach($item in @(
    @('https://login.tailscale.com/a/fixture123',$true),
    @('http://login.tailscale.com/a/fixture123',$false),
    @('https://login.tailscale.com.evil.example/a/fixture123',$false),
    @('https://evil.example/?https://login.tailscale.com/a/fixture123',$false),
    @('https://evil@login.tailscale.com/a/fixture123',$false),
    @('https://login.tailscale.com:8443/a/fixture123',$false),
    @('https://login.tailscale.com/a/fixture123?redirect=evil',$false),
    @('https://login.tailscale.com/a/fixture123#evil',$false),
    @('https://login.tailscale.com/a/one https://login.tailscale.com/a/two',$false),
    @('https://login.tailscale.com/a/fixture123 https://login.tailscale.com/a/fixture123',$true)
)){
    $uri=&$module {param($s)Get-DevFleetTailscaleAuthenticationUri $s} $item[0]
    Check ('official browser URL case '+$results.Count) ([bool]$uri-eq$item[1])
}
foreach($item in @(@('Running','100.64.1.2',$true),@('NeedsLogin','100.64.1.2',$false),@('Running','192.168.1.2',$false),@('Running','100.1.1.2',$false),@('Running','100.128.1.2',$false),@('Running','fd7a:115c:a1e0::1',$false))){
    $ip=&$module {param($s,$ip)Get-DevFleetAuthenticatedTailscaleIPv4 (@{BackendState=$s;TailscaleIPs=@($ip)}|ConvertTo-Json -Compress)} $item[0] $item[1]
    Check ('authenticated private IPv4 '+$item[0]+'/'+$item[1]) ([bool]$ip-eq$item[2])
}
&$module {
    function script:Get-DevFleetDeadlineContext {return $script:PairingFixtureContext}
    function script:Open-DevFleetTailscaleAuthenticationPage {param($Uri)$script:PairingFixtureOpened++;if($Uri.AbsoluteUri-cne'https://login.tailscale.com/a/fixture123'){throw 'Unexpected browser target.'}}
    function script:Start-Sleep {param($Milliseconds)}
    function script:Invoke-External {
        param($FilePath,$ArgumentList,[switch]$Capture,[switch]$IgnoreExitCode,$TimeoutSeconds,$DeadlineUtc)
        if(-not$Capture-or-not$IgnoreExitCode-or$TimeoutSeconds-gt35-or$DeadlineUtc-gt$script:PairingFixtureDeadline){throw 'Native command lost its bounded capture contract.'}
        $script:PairingFixtureCalls.Add([pscustomobject]@{path=$FilePath;args=@($ArgumentList);timeout=$TimeoutSeconds})
        if($ArgumentList-contains'up'){
            $script:PairingFixtureUp++
            if($ArgumentList-notcontains'--timeout=30s'-or$ArgumentList-notcontains'--accept-dns=false'-or$ArgumentList-contains'--auth-key'){throw 'Unexpected authentication authority.'}
            if($script:PairingFixtureCase-eq'bad-url'){return 'https://evil.example/a/fake'}
            return 'To authenticate, visit: https://login.tailscale.com/a/fixture123'
        }
        if($ArgumentList-notcontains'--json'){throw 'Status request arguments were lost.'}
        if($script:PairingFixtureCase-eq'malformed'){return 'malformed status'}
        $connected=$script:PairingFixtureCase-eq'already-connected'-or$script:PairingFixtureOpened-gt0
        return (@{BackendState=if($connected){'Running'}else{'NeedsLogin'};TailscaleIPs=if($connected){@('100.64.1.2')}else{@()}}|ConvertTo-Json -Compress)
    }
}
foreach($target in @('windows','guest')){
    foreach($case in @('already-connected','browser-required','bad-url','deadline-exhausted','parent-deadline')){
        $v=&$module {
            param($Case,$Target)
            $script:PairingFixtureCase=$Case;$script:PairingFixtureOpened=0;$script:PairingFixtureUp=0;$script:PairingFixtureCalls=[Collections.Generic.List[object]]::new();$script:PairingFixtureContext=$null
            $script:PairingFixtureDeadline=[datetime]::UtcNow.AddSeconds($(if($Case-eq'deadline-exhausted'){3}else{60}))
            if($Case-eq'parent-deadline'){$script:PairingFixtureContext=[pscustomobject]@{StageDeadlineUtc=[datetime]::UtcNow.AddSeconds(3)}}
            $parameters=@{FilePath=if($Target-eq'guest'){'multipass-fixture.exe'}else{'tailscale-fixture.exe'};Hostname='devfleet-fixture';DeadlineUtc=$script:PairingFixtureDeadline}
            if($Target-eq'guest'){$parameters.InstanceName='devfleet-vault'}
            $result=$null;$failed=$false
            try{$result=Invoke-DevFleetTailscaleBrowserPairing @parameters}catch{$failed=$true}
            [pscustomobject]@{result=$result;failed=$failed;calls=@($script:PairingFixtureCalls);up=$script:PairingFixtureUp;opened=$script:PairingFixtureOpened}
        } $case $target
        $pass=switch($case){
            'already-connected' {-not$v.failed-and$v.result.authenticated-and$v.up-eq0-and$v.opened-eq0}
            'browser-required' {-not$v.failed-and$v.result.authenticated-and$v.up-eq1-and$v.opened-eq1}
            'bad-url' {$v.failed-and$v.up-eq1-and$v.opened-eq0}
            default {$v.failed-and$v.calls.Count-eq0-and$v.opened-eq0}
        }
        if($target-eq'guest'-and$v.calls.Count){$pass=$pass-and($v.calls[0].args[0..4]-join' ')-ceq'exec devfleet-vault -- sudo tailscale'}
        Check ($target+' '+$case) $pass
    }
}
$results|ConvertTo-Json -Depth 4
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Browser pairing qualification failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) browser pairing checks; no browser, network or VM operations performed."

```


## FILE: source/tests/Test-TailscaleGuestOAuthTransport.ps1

SHA256: 3767e97aab7be361db254c680245813726b437c4baf2017511d4dbcffbec5dab | Bytes: 7089 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

$sourceRoot = Join-Path $WorkspaceRoot 'source'
$commonPath = Join-Path $sourceRoot 'windows\DevFleet.Common.psm1'
$tailscalePath = Join-Path $sourceRoot 'windows\DevFleet.Tailscale.psm1'
$commonModule = Import-Module $commonPath -Force -PassThru
$state = [ordered]@{
    calls = [System.Collections.Generic.List[object]]::new()
    transferInputs = [System.Collections.Generic.List[string]]::new()
    consume = ''
    consumeIgnoreExitCode = $false
    statusCalls = 0
    initialStatus = [ordered]@{ BackendState = 'NeedsLogin'; Self = [ordered]@{ HostName = 'fixture-node'; Online = $false }; TailscaleIPs = @(); Health = @() } | ConvertTo-Json -Depth 5 -Compress
    finalStatus = [ordered]@{ BackendState = 'Running'; Self = [ordered]@{ HostName = 'fixture-node'; Online = $true }; TailscaleIPs = @('100.64.1.2'); Health = @() } | ConvertTo-Json -Depth 5 -Compress
    preferences = ([ordered]@{ AdvertiseTags = @('tag:devfleet-e2e') } | ConvertTo-Json -Depth 3 -Compress)
}
$originalExternal = & $commonModule { (Get-Command Invoke-External -CommandType Function).ScriptBlock }
$fixtureState = $state
$externalFixture = {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int[]]$RedactArgumentIndexes = @(),
        [int]$TimeoutSeconds = 900,
        [int]$MaxDiagnosticChars = 12000,
        [string]$EvidenceLogPath = '',
        [string]$StandardInputText = '',
        [datetime]$DeadlineUtc = [datetime]::MinValue,
        [int[]]$AllowedExitCodes = @(0),
        [switch]$IgnoreExitCode,
        [switch]$Capture
    )
    $s = $fixtureState
    $args = @($ArgumentList)
    [void]$s.calls.Add([pscustomobject]@{ arguments = $args; input = [string]$StandardInputText })
    if ($args.Count -ge 6 -and $args[0] -ceq 'exec' -and $args[3] -ceq 'bash' -and $args[4] -ceq '-lc') {
        $command = [string]$args[5]
        if ($command -match 'mkdir -m 0700') { return }
        if ($command -match "exec 'bash' '-lc' ") {
            $s.consume = $command
            $s.consumeIgnoreExitCode = [bool]$IgnoreExitCode
            if (-not $IgnoreExitCode) { throw 'fixture multipass failed with exit code 1 DEVFLEET_TAILSCALE_UP_EXIT=0' }
            return 'DEVFLEET_TAILSCALE_UP_EXIT=0'
        }
        if ($command -match 'test -e') { return }
    }
    if ($args.Count -gt 0 -and $args[0] -ceq 'transfer') {
        [void]$s.transferInputs.Add([string]$StandardInputText)
        return
    }
    if ($args -contains 'status') {
        $s.statusCalls = [int]$s.statusCalls + 1
        if ([int]$s.statusCalls -eq 1) { return [string]$s.initialStatus }
        return [string]$s.finalStatus
    }
    if ($args -contains 'debug') { return $s.preferences }
    throw 'Unexpected command in guest OAuth transport fixture.'
}.GetNewClosure()
$result = $null
$errorText = ''
& $commonModule { param($stub) Set-Item Function:\Invoke-External -Value $stub } $externalFixture
try {
    # Common is already loaded with the fixture, so the Tailscale module
    # imports that exact fixture-backed dependency and the production pairing
    # takes its no-CommandInvoker path.
    $tailscaleModule = Import-Module $tailscalePath -Force -PassThru
    $optionsProvider = { [pscustomobject]@{ mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true; hostname = 'fixture-node'; targetRole = 'Fixture'; instanceName = 'fixture-guest'; secret = 'fixture-oauth-client-secret'; credentialSource = 'fixture-only' } }
    $parameters = @{
        FilePath = 'fixture-multipass.exe'; InstanceName = 'fixture-guest'; Hostname = 'fixture-node'; DeadlineUtc = [datetime]::UtcNow.AddSeconds(60)
        RunId = 'oauth-transport-fixture'; StageName = 'TAILSCALE-AUTH'; TargetRole = 'Fixture'
        EnrollmentProfileProvider = { [pscustomobject]@{ mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true } }
        EnrollmentOptionsProvider = $optionsProvider
        TailnetLockProvider = { [pscustomobject]@{ status = 'DISABLED'; observed = $true; enabled = $false } }
        ServiceStateProvider = { 'Running' }; PendingRebootProvider = { $false }
    }
    $result = & $tailscaleModule { param($p) Invoke-DevFleetTailscaleOAuthPairing @p } $parameters
} catch {
    $errorText = [string]$_.Exception.Message
} finally {
    & $commonModule { param($original) Set-Item Function:\Invoke-External -Value $original } $originalExternal
}

$secret = 'fixture-oauth-client-secret'
$argumentText = (@($state.calls) | ForEach-Object { @($_.arguments) -join ' ' }) -join ' '
$marker = "exec 'bash' '-lc' "
$markerIndex = [string]$state.consume.IndexOf($marker)
$guestArgument = if ([int]$markerIndex -ge 0) { [string]$state.consume.Substring([int]$markerIndex + $marker.Length).TrimEnd([char]13, [char]10) } else { '' }
$guestSyntaxPass = $false
$guestSyntaxError = ''
if ($guestArgument.Length -ge 2 -and $guestArgument.StartsWith("'") -and $guestArgument.EndsWith("'")) {
    $decodedGuestScript = $guestArgument.Substring(1, $guestArgument.Length - 2).Replace("'\''", "'")
    $bash = 'C:\Program Files\Git\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw 'Existing Git for Windows bash is required for the guest script syntax fixture.' }
    $guestSyntaxError = (& $bash --noprofile --norc -n -c $decodedGuestScript 2>&1 | Out-String).Trim()
    $guestSyntaxPass = $LASTEXITCODE -eq 0
}
$expectedTransfer = $secret + '?ephemeral=true&preauthorized=true' + "`n"
$pass = $result -and [bool]$result.authenticated -and [bool]$result.authenticationAttempted -and [int]$state.statusCalls -eq 2 -and @($state.transferInputs).Count -eq 1 -and (@($state.transferInputs)[0] -ceq $expectedTransfer) -and [bool]$state.consumeIgnoreExitCode -and $argumentText -notmatch [regex]::Escape($secret) -and $guestArgument -and $guestArgument -notmatch '[\r\n]' -and $guestArgument -match 'DEVFLEET_TAILSCALE_UP_EXIT=' -and $guestSyntaxPass
$errorClass = if (-not $pass -and $errorText -match 'Shell scalar contains a forbidden control or newline character') { 'SHELL_SCALAR_REJECTION' } elseif ($errorText) { 'OTHER_FIXTURE_ERROR' } else { '' }
[pscustomobject][ordered]@{
    status = if ($pass) { 'PASS' } else { 'FAIL' }
    authenticated = [bool]($result -and $result.authenticated)
    authenticationAttempted = [bool]($result -and $result.authenticationAttempted)
    statusCalls = [int]$state.statusCalls
    externalCalls = @($state.calls).Count
    transferCount = @($state.transferInputs).Count
    guestCommandCaptured = [bool]$state.consume
    outerExitMismatchHandled = [bool]$state.consumeIgnoreExitCode
    guestCommandHasControl = [bool]($guestArgument -match '[\r\n]')
    guestCommandSyntaxPass = $guestSyntaxPass
    secretInArguments = [bool]($argumentText -match [regex]::Escape($secret))
    errorClass = $errorClass
} | ConvertTo-Json -Depth 4
if (-not $pass) { exit 1 }

```


## FILE: source/tests/Test-TailscalePostEnrollmentStatusRetry.ps1

SHA256: 31de50a4f3beea14044a09fcf7ae763d4b495226d6ebd40d916b1d3be12bf2a2 | Bytes: 10166 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

$sourceModule = Join-Path $WorkspaceRoot 'windows\DevFleet.Tailscale.psm1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-tailscale-post-status-test-' + [guid]::NewGuid().ToString('N'))
$passed = 0
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

function New-FixtureStatusJson {
    param([bool]$Authenticated)
    if ($Authenticated) {
        [ordered]@{
            BackendState = 'Running'
            Self = [ordered]@{ HostName = 'fixture-node'; Online = $true; Tags = @('tag:devfleet-e2e') }
            TailscaleIPs = @('100.64.1.2')
            Health = @()
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        [ordered]@{
            BackendState = 'NeedsLogin'
            Self = [ordered]@{ HostName = ''; Online = $false }
            TailscaleIPs = @()
            Health = @()
        } | ConvertTo-Json -Depth 5 -Compress
    }
}

function New-FixturePreferencesJson {
    [ordered]@{ AdvertiseTags = @('tag:devfleet-e2e') } | ConvertTo-Json -Depth 3 -Compress
}

function New-FixtureInvoker {
    param([Parameter(Mandatory)][hashtable]$State)
    $statusJson = ${function:New-FixtureStatusJson}.GetNewClosure()
    $preferencesJson = ${function:New-FixturePreferencesJson}.GetNewClosure()
    $invoker = {
        param([string[]]$Arguments)
        $verb = [string]$Arguments[0]
        [void]$State.commands.Add(($Arguments -join ' '))
        switch ($verb) {
            'status' {
                $State.statusCalls = [int]$State.statusCalls + 1
                if ([int]$State.authCalls -eq 0) {
                    return [pscustomobject]@{ exitCode = 0; output = & $statusJson -Authenticated:$false }
                }
                $State.postStatusCalls = [int]$State.postStatusCalls + 1
                if ([int]$State.postStatusCalls -le [int]$State.postStatusFailures) {
                    if ([int]$State.statusFailureDelaySeconds -gt 0) { Start-Sleep -Seconds ([int]$State.statusFailureDelaySeconds) }
                    return [pscustomobject]@{ exitCode = 7; output = '' }
                }
                return [pscustomobject]@{ exitCode = 0; output = & $statusJson -Authenticated:$true }
            }
            'debug' {
                return [pscustomobject]@{ exitCode = 0; output = & $preferencesJson }
            }
            'up' {
                $State.authCalls = [int]$State.authCalls + 1
                return [pscustomobject]@{ exitCode = 0; output = 'fixture enrollment accepted' }
            }
            default { return [pscustomobject]@{ exitCode = 0; output = '' } }
        }
    }.GetNewClosure()
    return $invoker
}

function Invoke-Fixture {
    param([Parameter(Mandatory)][int]$PostStatusFailures, [Parameter(Mandatory)][string]$EvidencePath, [int]$StatusFailureDelaySeconds = 0)
    $state = @{
        authCalls = 0
        statusCalls = 0
        postStatusCalls = 0
        postStatusFailures = $PostStatusFailures
        statusFailureDelaySeconds = $StatusFailureDelaySeconds
        commands = [System.Collections.Generic.List[string]]::new()
    }
    $profile = [pscustomobject]@{ mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true }
    $optionsProvider = {
        param([string]$RequestedHostname, [string]$InstanceName, [string]$TargetRole)
        [pscustomobject]@{
            mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true
            hostname = $RequestedHostname; targetRole = $TargetRole; instanceName = $InstanceName
            secret = 'fixture-oauth-client-secret'; credentialSource = 'fixture-only'
        }
    }
    $result = $null
    $errorText = ''
    $started = [datetime]::UtcNow
    try {
        $result = Invoke-DevFleetTailscaleOAuthPairing `
            -FilePath 'fixture-tailscale.exe' -InstanceName 'fixture-guest' -Hostname 'fixture-node' `
            -DeadlineUtc ([datetime]::UtcNow.AddSeconds(180)) -EvidencePath $EvidencePath `
            -RunId 'post-status-retry-fixture' -TransactionId '0123456789abcdef0123456789abcdef' `
            -PayloadSha256 ('a' * 64) -StageName 'TAILSCALE-AUTH' -TargetRole 'Fixture' `
            -CommandInvoker (New-FixtureInvoker -State $state) `
            -EnrollmentProfileProvider { $profile } -EnrollmentOptionsProvider $optionsProvider `
            -TailnetLockProvider { [pscustomobject]@{ status = 'DISABLED'; observed = $true; enabled = $false } } `
            -ServiceStateProvider { 'Running' }
    } catch { $errorText = [string]$_.Exception.Message }
    $events = if (Test-Path -LiteralPath $EvidencePath -PathType Leaf) {
        @(Get-Content -LiteralPath $EvidencePath | ForEach-Object { $_ | ConvertFrom-Json })
    } else { @() }
    [pscustomobject]@{
        result = $result
        error = $errorText
        state = $state
        events = $events
        elapsedSeconds = ([datetime]::UtcNow - $started).TotalSeconds
    }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $sourceModule -Force

    $transientEvidence = Join-Path $scratch 'transient.jsonl'
    $transient = Invoke-Fixture -PostStatusFailures 1 -EvidencePath $transientEvidence
    $transientRetries = @($transient.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' })
    Check ($transient.result -and [bool]$transient.result.authenticated -and [int]$transient.state.authCalls -eq 1 -and [int]$transient.state.postStatusCalls -eq 2 -and [int]$transient.state.statusCalls -eq 3 -and $transientRetries.Count -eq 1 -and ($transient.commands -join ' ') -notmatch 'fixture-oauth-client-secret' -and @($transient.commands | Where-Object { $_ -match '(^|\s)status\s' -and $_ -notmatch '--peers=false' }).Count -eq 0) 'one transient post-enrollment status failure recovers with one bounded retry and one OAuth attempt using self-only status'

    $extendedEvidence = Join-Path $scratch 'extended.jsonl'
    $extended = Invoke-Fixture -PostStatusFailures 5 -EvidencePath $extendedEvidence
    $extendedRetries = @($extended.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' })
    Check ($extended.result -and [bool]$extended.result.authenticated -and [int]$extended.state.authCalls -eq 1 -and [int]$extended.state.postStatusCalls -eq 6 -and [int]$extended.state.statusCalls -eq 7 -and $extendedRetries.Count -eq 5 -and ($extended.commands -join ' ') -notmatch 'fixture-oauth-client-secret') 'extended post-enrollment control-plane convergence recovers within a finite retry window without repeating OAuth'

    $timeoutEvidence = Join-Path $scratch 'timeout-convergence.jsonl'
    $timeoutConvergence = Invoke-Fixture -PostStatusFailures 3 -StatusFailureDelaySeconds 10 -EvidencePath $timeoutEvidence
    $timeoutRetries = @($timeoutConvergence.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' })
    Check ($timeoutConvergence.result -and [bool]$timeoutConvergence.result.authenticated -and [int]$timeoutConvergence.state.authCalls -eq 1 -and [int]$timeoutConvergence.state.postStatusCalls -eq 4 -and [int]$timeoutConvergence.state.statusCalls -eq 5 -and $timeoutRetries.Count -eq 3 -and ($timeoutConvergence.commands -join ' ') -notmatch 'fixture-oauth-client-secret') 'three ten-second post-enrollment status timeouts still converge within the bounded wall-clock window without repeating OAuth'

    $persistentEvidence = Join-Path $scratch 'persistent.jsonl'
    $persistent = Invoke-Fixture -PostStatusFailures 99 -EvidencePath $persistentEvidence
    $persistentRetries = @($persistent.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' })
    Check (-not $persistent.result -and $persistent.error -match '^TAILSCALE_CONTROL_PLANE_OFFLINE' -and [int]$persistent.state.authCalls -eq 1 -and [int]$persistent.state.postStatusCalls -eq 8 -and [int]$persistent.state.statusCalls -eq 9 -and $persistentRetries.Count -eq 7 -and [double]$persistent.elapsedSeconds -lt 18) 'persistent post-enrollment status failure remains fail-closed within the expanded finite retry budget'
} catch {
    [void]$failures.Add('unexpected post-enrollment status retry fixture exception')
} finally {
    if (Test-Path -LiteralPath $scratch -PathType Container) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

$summary = [ordered]@{
    status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    passed = $passed
    failed = $failures.Count
    failures = @($failures)
    diagnostic = [ordered]@{
        transient = if ($transient) { [ordered]@{ result = [bool]$transient.result; error = [string]$transient.error; authCalls = [int]$transient.state.authCalls; statusCalls = [int]$transient.state.statusCalls; postStatusCalls = [int]$transient.state.postStatusCalls; retryEvents = @($transient.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' }).Count } } else { $null }
        extended = if ($extended) { [ordered]@{ result = [bool]$extended.result; error = [string]$extended.error; authCalls = [int]$extended.state.authCalls; statusCalls = [int]$extended.state.statusCalls; postStatusCalls = [int]$extended.state.postStatusCalls; retryEvents = @($extended.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' }).Count } } else { $null }
        persistent = if ($persistent) { [ordered]@{ result = [bool]$persistent.result; error = [string]$persistent.error; authCalls = [int]$persistent.state.authCalls; statusCalls = [int]$persistent.state.statusCalls; postStatusCalls = [int]$persistent.state.postStatusCalls; retryEvents = @($persistent.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' }).Count } } else { $null }
    }
}
$summary | ConvertTo-Json -Depth 8
if ($failures.Count -ne 0) { exit 1 }

```


## FILE: source/tests/Test-TailscaleStageDeadlineComposition.ps1

SHA256: 32076c12d01e5c0b9cbc72fb7824959e633e60aa098cadc71f76d8e41182fd23 | Bytes: 1201 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference = 'Stop'
$commonPath = Join-Path $WorkspaceRoot 'source/windows/DevFleet.Common.psm1'
Import-Module $commonPath -Force -DisableNameChecking

$windowsBudget = [int](Get-DevFleetStageBudgetSeconds 'windowsTailscale')
$guestBudget = [int](Get-DevFleetStageBudgetSeconds 'tailscale')

# The Windows stage owns service startup, browser handoff, and a real human
# approval. The exact Laptop run showed that 180 seconds could be consumed
# before the browser handoff became usable. Reuse the existing bounded guest
# pairing budget instead of introducing a second timeout policy.
if ($windowsBudget -ne 900) {
    throw "windowsTailscale stage budget must be 900 seconds for the bounded human pairing flow; observed $windowsBudget."
}
if ($windowsBudget -ne $guestBudget) {
    throw "Windows and guest Tailscale pairing budgets diverged: windows=$windowsBudget guest=$guestBudget."
}

[ordered]@{
    status = 'PASS'
    windowsTailscaleSeconds = $windowsBudget
    tailscaleSeconds = $guestBudget
    boundedHumanPairingBudgetAligned = $true
} | ConvertTo-Json -Compress

```


## FILE: source/tests/Test-WindowsIntegrationOwnership.ps1

SHA256: b1ed85f8d67c5ab506ad550fac4d6a93af97ca8a2b9b6ab2ff530ad83aa14846 | Bytes: 5263 | Git mode: 100644

```
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'windows\DevFleet-WindowsIntegrationOwnership.psm1') -Force

function Assert-ThrowsOwnershipConflict([scriptblock]$Action) {
    try { & $Action; throw 'Expected an ownership conflict.' }
    catch { if ($_.Exception.Message -notmatch 'OWNERSHIP CONFLICT') { throw } }
}

$generation = [guid]::NewGuid().ToString('D')
$task = @{Name='DevFleet Host Agent';Executable="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe";Arguments='-NoProfile -File "C:\ProgramData\DevFleetHostAgent\DevFleet-HostAgent.ps1"';Principal='SYSTEM';LogonType='ServiceAccount';RunLevel='Highest';Description="M-TechLabs DevFleet; generation=$generation";Generation=$generation;Marker='M-TechLabs DevFleet Host Agent'}
Assert-DevFleetTaskBinding -Expected $task -Actual (@{} + $task) | Out-Null
$foreignTask = @{} + $task; $foreignTask.Executable = "$env:SystemRoot\System32\cmd.exe"
Assert-ThrowsOwnershipConflict { Assert-DevFleetTaskBinding -Expected $task -Actual $foreignTask }

$firewall = @{Name='DevFleetHostAgent-8790-Tailscale';DisplayName='DevFleet Host Agent 8790 - Tailscale';Group='M-TechLabs DevFleet Host Agent';Description="M-TechLabs DevFleet; generation=$generation";Direction='Inbound';Action='Allow';Protocol='TCP';LocalPort='8790';InterfaceAlias='Tailscale';RemoteAddress='100.64.0.0/10';Profile='Any';Generation=$generation;Marker='M-TechLabs DevFleet Host Agent'}
Assert-DevFleetFirewallBinding -Expected $firewall -Actual (@{} + $firewall) | Out-Null
$providerFirewall = @{} + $firewall; $providerFirewall.RemoteAddress = '100.64.0.0/255.192.0.0'
Assert-DevFleetFirewallBinding -Expected $firewall -Actual $providerFirewall | Out-Null
$multipassFirewall = @{} + $firewall; $multipassFirewall.Name = 'DevFleetHostAgent-8790-Multipass'; $multipassFirewall.DisplayName = 'DevFleet Host Agent 8790 - Multipass'; $multipassFirewall.InterfaceAlias = 'vEthernet (Default Switch)'; $multipassFirewall.RemoteAddress = '172.23.144.1/20'
$multipassProviderFirewall = @{} + $multipassFirewall; $multipassProviderFirewall.RemoteAddress = '172.23.144.0/255.255.240.0'
Assert-DevFleetFirewallBinding -Expected $multipassFirewall -Actual $multipassProviderFirewall | Out-Null
$staleVirtualNetworkFirewall = @{} + $multipassFirewall; $staleVirtualNetworkFirewall.InterfaceAlias = '0e5a7c8a-7826-4655-8648-a711bb6d7f87'; $staleVirtualNetworkFirewall.RemoteAddress = '172.21.176.0/255.255.240.0'
Assert-DevFleetFirewallRefreshIdentity -Expected $multipassFirewall -Actual $staleVirtualNetworkFirewall | Out-Null
Assert-ThrowsOwnershipConflict { Assert-DevFleetFirewallBinding -Expected $multipassFirewall -Actual $staleVirtualNetworkFirewall }
$foreignRefreshFirewall = @{} + $staleVirtualNetworkFirewall; $foreignRefreshFirewall.Group = 'Foreign Firewall Group'
Assert-ThrowsOwnershipConflict { Assert-DevFleetFirewallRefreshIdentity -Expected $multipassFirewall -Actual $foreignRefreshFirewall }
$foreignFirewall = @{} + $firewall; $foreignFirewall.RemoteAddress = 'Any'
Assert-ThrowsOwnershipConflict { Assert-DevFleetFirewallBinding -Expected $firewall -Actual $foreignFirewall }

$service = @{Name='DevFleetHostAgent';ImagePath='C:\Program Files\M-TechLabs\DevFleet\agent.exe';Account='LocalSystem';StartMode='Auto';Generation=$generation;Marker='M-TechLabs DevFleet Host Agent'}
$liveService = @{} + $service; $liveService.ImagePath = '"C:\Program Files\M-TechLabs\DevFleet\agent.exe" --service'
Assert-DevFleetServiceBinding -Expected $service -Actual $liveService | Out-Null
$foreignService = @{} + $service; $foreignService.ImagePath = 'C:\Foreign\agent.exe'
Assert-ThrowsOwnershipConflict { Assert-DevFleetServiceBinding -Expected $service -Actual $foreignService }

$temporary = Join-Path ([IO.Path]::GetTempPath()) ("devfleet-integration-ownership-$([guid]::NewGuid().ToString('N')).json")
try {
    $ledger = @{SchemaVersion=1;InstallationGeneration=$generation;ScheduledTasks=@($task);FirewallRules=@($firewall);Services=@($service)}
    Write-DevFleetIntegrationOwnership -Path $temporary -Ledger $ledger
    $loaded = Read-DevFleetIntegrationOwnership -Path $temporary
    if ($loaded.InstallationGeneration -ne $generation) { throw 'Ledger generation did not round-trip.' }
    $ledger.FirewallRules[0].Generation = [guid]::NewGuid().ToString('D')
    Write-DevFleetIntegrationOwnership -Path $temporary -Ledger $ledger
    try { Read-DevFleetIntegrationOwnership -Path $temporary | Out-Null; throw 'Cross-generation ledger was accepted.' }
    catch { if ($_.Exception.Message -notmatch 'cross-generation') { throw } }
} finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }

$hostAgent = Get-Content -LiteralPath (Join-Path $root 'windows\DevFleet-HostAgent.ps1') -Raw
if ($hostAgent -notmatch 'Invoke-DevFleetOwnedFirewallRefresh') { throw 'Host Agent startup does not reconcile owned firewall bindings.' }
$installer = Get-Content -LiteralPath (Join-Path $root 'windows\Install-DevFleet-HostAgent.ps1') -Raw
if ($installer -notmatch 'Invoke-DevFleetOwnedFirewallRefresh') { throw 'Host Agent installation path does not reconcile prior owned firewall bindings.' }

'PASS Windows integration ownership binding tests'

```


## FILE: source/tests/_bundle_layout.py

SHA256: bcd842e85f5b6c5f4a5365ffbdf032b9b1781b4e9a1a9f811e12652d171727c3 | Bytes: 1572 | Git mode: 100644

```
from __future__ import annotations

from dataclasses import dataclass
import importlib.util
import sys
from pathlib import Path


@dataclass(frozen=True)
class BundleLayout:
    """Explicit repository/canonical-bundle roots used by path-sensitive tests."""

    bundle_root: Path
    source_root: Path
    installer_source_root: Path
    release_tooling_root: Path
    release_e2e_root: Path


def resolve_bundle_layout(anchor: Path) -> BundleLayout:
    anchor = anchor.resolve()
    for candidate in (anchor, *anchor.parents):
        for helper in (candidate / "release-tooling/audit_bundle_paths.py", candidate / "tools/audit_bundle_paths.py"):
            if not helper.is_file():
                continue
            spec = importlib.util.spec_from_file_location("devfleet_audit_bundle_paths", helper)
            if spec is None or spec.loader is None:
                continue
            module = importlib.util.module_from_spec(spec)
            # Dataclasses and other introspection-based modules expect the
            # executing module to be registered, as it is during ordinary
            # imports.  Preserve that invariant for relocated bundles.
            sys.modules[spec.name] = module
            spec.loader.exec_module(module)
            layout = module.resolve_bundle_layout(anchor)
            return BundleLayout(layout.bundle_root, layout.source_root, layout.installer_source_root, layout.release_tooling_root, layout.release_e2e_root)
    raise AssertionError(f"Could not identify a repository or canonical audit bundle root from {anchor}")

```


## FILE: source/tests/conftest.py

SHA256: 03e3e1fab21c2523e89b74fb326aca7d38c1927a1aec528997f30558f714ee64 | Bytes: 1430 | Git mode: 100644

```
import json,os,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'app'))
TESTROOT=ROOT/'.test-runtime';
for d in ('workspaces','quarantine','runtime','cache','static','templates'): (TESTROOT/d).mkdir(parents=True,exist_ok=True)
config={'node_name':'test-node','deployment_id':'deployment-123','node_role':'primary','friendly_name':'CodexDevVM','portal_port':8787,'workspaces':str(TESTROOT/'workspaces'),'quarantine':str(TESTROOT/'quarantine'),'peer_file':str(TESTROOT/'peer.json'),'runtime_root':str(TESTROOT/'runtime'),'cache_root':str(TESTROOT/'cache'),'ollama_base_url':'http://127.0.0.1:11434/v1','ollama_model':'test-model','ollama_profile':'stable-interactive','development_profile':'balanced','docker_mode':'rootless','enable_shared_caches':True,'enable_analyzer_cache':True,'auto_start_codexpro':True,'allow_tailnet_ports':True,'backup_before_rebuild':False,'backup_before_quarantine':True,'require_tailscale':False,'tailnet_cidr':'100.64.0.0/10','public_binding_allowed':True}
(TESTROOT/'config.json').write_text(json.dumps(config));(TESTROOT/'peer.json').write_text('{}');os.environ.update({'DEVFLEET_CONFIG_PATH':str(TESTROOT/'config.json'),'DEVFLEET_ADMIN_USER':'test','DEVFLEET_ADMIN_PASSWORD':'test-password','DEVFLEET_API_TOKEN':'test-token','DEVFLEET_STATIC_DIR':str(ROOT/'app/static'),'DEVFLEET_TEMPLATE_DIR':str(ROOT/'app/templates')})

```


## FILE: source/tests/test_analyzer.py

SHA256: 359450217b36e714dd5411b47230100fc0723991377d4ecab213d3ef11ed2a00 | Bytes: 3363 | Git mode: 100644

```
from pathlib import Path
import tempfile
import pytest

from devfleet.analyzer import analyze_project, has_blockers


def analyze(compose: str):
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)
        (p/'compose.yaml').write_text(compose)
        return analyze_project(p)


def test_safe_relative_mount():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    volumes: [\".:/workspaces/x\"]\n    security_opt: [\"no-new-privileges:true\"]\n    healthcheck: {test: [\"CMD\", \"true\"]}\n''')
    assert not has_blockers(findings), findings


def test_absolute_mount_blocked():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    volumes: [\"/home/devrunner:/host\"]\n''')
    assert any(x['code']=='docker.mount' and x['severity']=='critical' for x in findings)


def test_parent_mount_blocked():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    volumes: [\"../other-project:/other\"]\n''')
    assert any(x['code']=='docker.mount' and x['severity']=='critical' for x in findings)


def test_socket_and_privileged_blocked():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    privileged: true\n    volumes: [\"/run/user/1001/docker.sock:/var/run/docker.sock\"]\n''')
    assert has_blockers(findings)
    assert {'docker.mount','docker.privileged'} <= {x['code'] for x in findings}

def test_public_port_and_device_blocked():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    ports: [\"3000:3000\"]\n    devices: [\"/dev/kvm:/dev/kvm\"]\n''')
    assert {'docker.port-p