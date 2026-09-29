# DevFleet source part 049

Full-source UTF-8 byte interval [2232000, 2278500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: b502e2b2d3015fd21d7bd152933e02af0643dc9d3ad386e831813d044358846b

<!-- BEGIN SOURCE SLICE -->
minal L2 evidence requires configured name and protects foreign H10 resource'
$finalizationSource=Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\FullRelease.psm1')
Check ($finalizationSource -match 'Get-VM -Id' -and $finalizationSource -match 'terminalL1Hash' -and $finalizationSource -match 'l2ExactAbsent') 'post-cleanup finalization performs live terminal checks and consumes hashes'
$buildSource=Get-Content -Raw (Join-Path $Workspace 'installer-source\Build-Release.ps1')
Check ($buildSource -match 'authorizedCorrection' -and $buildSource -match 'authorized_correction=\$authorizedCorrection' -and $buildSource -match 'RELEASE BLOCKED — authorized correction path is invalid') 'release build preserves only validated authorized-correction shipping paths in generated authority'
if($failed.Count){[pscustomobject]@{status='FAIL';passed=$passed;failures=@($failed)}|ConvertTo-Json -Depth 5;exit 1}
[pscustomobject]@{status='PASS';passed=$passed;failures=@()}|ConvertTo-Json -Depth 5

```


## FILE: automation/release-e2e/tests/Test-SecurityPoisonFailureEvidence.ps1

SHA256: b4073442a9c880cc11bfc9da083c4215d770313127d95829cd3bd54b1b6da28b | Bytes: 7129 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$checks.Add([pscustomobject]@{name=$Name;pass=$Pass})}
$root=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-security-evidence-'+[guid]::NewGuid().ToString('N'))
$global:DevFleetSecurityFixture=@{childCalls=0;provisioningExit=0;childComputerName='';childProgramFilesX86=''}
$originalComputerName=[Environment]::GetEnvironmentVariable('COMPUTERNAME','Process')
$originalProgramFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)','Process')
$expectedComputerName=[Environment]::MachineName
$expectedProgramFilesX86=[Environment]::GetFolderPath('ProgramFilesX86')
try {
    $execDir=Join-Path $root 'automation/release-e2e/modules/executors'
    New-Item -ItemType Directory -Path $execDir,(Join-Path $root 'source') -Force|Out-Null
    $executor=Join-Path $execDir 'Invoke-SecurityPoisonPhase.ps1'
    Copy-Item (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-SecurityPoisonPhase.ps1') $executor
    Copy-Item (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Evidence.psm1') (Join-Path $execDir '../Evidence.psm1')
    $candidate=Join-Path $root 'candidate-fixture.exe'
    [IO.File]::WriteAllText($candidate,'not executable; hash-bound test fixture')
    $sha=(Get-FileHash $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    $bytes=(Get-Item $candidate).Length
    function Get-Command {
        param([string]$Name,[string]$ErrorAction)
        if($Name -eq 'python.exe'){return [pscustomobject]@{Source='Invoke-TestPython'}}
        Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction Stop
    }
    function Invoke-TestPython {
        param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments)
        $global:DevFleetSecurityFixture.childCalls++
        Set-Variable -Name LASTEXITCODE -Value 0 -Scope 1
        'fixture python passed'
    }
    function pwsh.exe {
        param([switch]$NoProfile,[switch]$NonInteractive,[string]$ExecutionPolicy,[string]$File,[string]$WorkspaceRoot)
        $global:DevFleetSecurityFixture.childCalls++
        $global:DevFleetSecurityFixture.childComputerName=[string]$env:COMPUTERNAME
        $global:DevFleetSecurityFixture.childProgramFilesX86=[string]${env:ProgramFiles(x86)}
        Set-Variable -Name LASTEXITCODE -Value $global:DevFleetSecurityFixture.provisioningExit -Scope 1
        if($global:DevFleetSecurityFixture.provisioningExit){'fixture failure: '+('x'*4500)}else{'fixture provisioning passed'}
    }
    Remove-Item -LiteralPath 'Env:COMPUTERNAME' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Env:ProgramFiles(x86)' -ErrorAction SilentlyContinue
    foreach($case in @('failure','success','identity-mismatch','preserve-nonempty')){
        $global:DevFleetSecurityFixture.childCalls=0
        $global:DevFleetSecurityFixture.provisioningExit=if($case -eq 'failure'){23}else{0}
        if($case -eq 'preserve-nonempty'){$env:COMPUTERNAME='PRESERVE-COMPUTERNAME';${env:ProgramFiles(x86)}='C:\Preserve-ProgramFilesX86'}
        $runDir=Join-Path $root $case
        $ctx=[ordered]@{runDir=$runDir;candidate=[ordered]@{releaseFingerprintId='release-fixture';toolingFingerprintId='tooling-fixture';gitCommit='commit-fixture';candidate=[ordered]@{path=$candidate;sha256=if($case -eq 'identity-mismatch'){'0'*64}else{$sha};bytes=$bytes}}}
        $caught=$null
        try { & $executor -ContextJson ($ctx|ConvertTo-Json -Depth 8 -Compress)|Out-Null } catch {$caught=$_.Exception.Message}
        $path=Join-Path $runDir 'SECURITY-POISON-evidence.json'
        $exists=Test-Path -LiteralPath $path
        if($case -eq 'failure'){
            Check 'native scenario failure is rethrown' ($caught -match 'PROVISIONING-OWNERSHIP')
            Check 'failed scenario evidence exists before throw' $exists
            Check 'no scenario runs after first failure' ($global:DevFleetSecurityFixture.childCalls -eq 2)
            if($exists){
                $e=Get-Content $path -Raw|ConvertFrom-Json
                Check 'failure cannot claim REAL E2E PASS' ($e.status -eq 'FAIL' -and -not $e.allRequiredScenariosPassed)
                Check 'prior PASS and failed row both retained' ($e.scenarios.Count -eq 2 -and $e.scenarios[0].status -eq 'PASS' -and $e.scenarios[1].status -eq 'FAIL')
                Check 'native nonzero exit retained' ($e.scenarios[1].exitCode -eq 23)
                Check 'failed output is bounded' ($e.scenarios[1].outputExcerpt.Length -eq 4000)
                Check 'candidate binding retained' ($e.candidate.exeSha256 -eq $sha -and $e.candidate.toolingFingerprintId -eq 'tooling-fixture')
                Check 'missing process COMPUTERNAME comes from native machine identity' ($global:DevFleetSecurityFixture.childComputerName -ceq $expectedComputerName)
                Check 'missing process ProgramFiles(x86) comes from trusted Windows API' ($global:DevFleetSecurityFixture.childProgramFilesX86 -ceq $expectedProgramFilesX86)
            }
        } elseif($case -eq 'success'){
            Check 'all-success control does not throw' (-not $caught)
            Check 'success requires all seven children' ($global:DevFleetSecurityFixture.childCalls -eq 7)
            Check 'all-success evidence exists' $exists
            if($exists){$e=Get-Content $path -Raw|ConvertFrom-Json;Check 'unchanged success contract requires seven PASS rows' ($e.status -eq 'REAL E2E PASS' -and $e.allRequiredScenariosPassed -and $e.scenarios.Count -eq 7 -and @($e.scenarios|Where-Object status -ne 'PASS').Count -eq 0)}
        } elseif($case -eq 'identity-mismatch') {
            Check 'changed candidate rejected before children' ($caught -match 'exact candidate changed' -and $global:DevFleetSecurityFixture.childCalls -eq 0)
            Check 'identity rejection produces no success evidence' (-not $exists)
        } else {
            Check 'nonempty process COMPUTERNAME is preserved' ($global:DevFleetSecurityFixture.childComputerName -ceq 'PRESERVE-COMPUTERNAME')
            Check 'nonempty process ProgramFiles(x86) is preserved' ($global:DevFleetSecurityFixture.childProgramFilesX86 -ceq 'C:\Preserve-ProgramFilesX86')
        }
    }
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
    if($null -eq $originalComputerName){Remove-Item -LiteralPath 'Env:COMPUTERNAME' -ErrorAction SilentlyContinue}else{$env:COMPUTERNAME=$originalComputerName}
    if($null -eq $originalProgramFilesX86){Remove-Item -LiteralPath 'Env:ProgramFiles(x86)' -ErrorAction SilentlyContinue}else{${env:ProgramFiles(x86)}=$originalProgramFilesX86}
    Remove-Variable -Name DevFleetSecurityFixture -Scope Global -ErrorAction SilentlyContinue
}
$failed=@($checks|Where-Object {-not $_.pass})
[ordered]@{scope='VM_FREE_PRODUCTION_EXECUTOR_REGRESSION';releaseCredit=$false;status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks)}|ConvertTo-Json -Depth 6
if($failed.Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-SecurityPoisonHostAgent.ps1

SHA256: 611abf463f61e0b1c29e11819eabe9772c54e2751075bd18cd89af69711d0224 | Bytes: 5702 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
$agent=Join-Path $WorkspaceRoot 'source\windows\DevFleet-HostAgent.ps1'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) "devfleet-security-poison-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot -Force|Out-Null
try {
    $tokenPath=Join-Path $testRoot 'token.txt';[IO.File]::WriteAllText($tokenPath,('x'*48))
    $configPath=Join-Path $testRoot 'config.json'
    $config=[ordered]@{
        HostId='SECURITY-POISON-HOST';HostName='SECURITY-POISON-HOST';TokenPath=$tokenPath
        MultipassPath=(Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
        SshConfigPath=(Join-Path $testRoot 'ssh-config');SshKnownHostsPath=(Join-Path $testRoot 'known-hosts')
        SshPrivateKeyPath=(Join-Path $testRoot 'key');BootTimeoutSeconds=1;UbuntuImage='test-image'
        ResourcePolicy=@{MaxProjectCpus=8;MaxProjectMemoryGb=32;MaxProjectDiskGb=500}
    }
    $config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
    . $agent -ConfigPath $configPath -LibraryOnly
    $registry=Read-Registry;Write-Registry $registry

    # Multiple independent pwsh processes exercise the real inter-process mutex,
    # latest-read transaction, and atomic replacement. Every worker owns a distinct
    # project record; a missing record proves a lost update.
    $workerPath=Join-Path $testRoot 'registry-worker.ps1'
    $worker=@'
param()
$ErrorActionPreference='Stop'
$Agent=$env:DEVFLEET_SECURITY_AGENT;$Config=$env:DEVFLEET_SECURITY_CONFIG;$Slug=$env:DEVFLEET_SECURITY_SLUG;$Index=[int]$env:DEVFLEET_SECURITY_INDEX
. $Agent -ConfigPath $Config -LibraryOnly
$record=@{managed_by='devfleet';host_id='SECURITY-POISON-HOST';project_id=([guid]::NewGuid().ToString());slug=$Slug;runtime_id="runtime-$Slug";vm_name="vm-$Slug";state='ready';worker=$Index;updated_at=(Get-Date).ToUniversalTime().ToString('o')}
Update-ProjectRecord $Slug $record|Out-Null
'PASS'
'@
    [IO.File]::WriteAllText($workerPath,$worker)
    $processes=[Collections.Generic.List[Diagnostics.Process]]::new()
    for($i=0;$i -lt 24;$i++){
        $slug="parallel-$i"
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=(Get-Command pwsh.exe).Source;$psi.UseShellExecute=$false
        $psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$workerPath`""
        $psi.Environment['DEVFLEET_SECURITY_AGENT']=$agent;$psi.Environment['DEVFLEET_SECURITY_CONFIG']=$configPath;$psi.Environment['DEVFLEET_SECURITY_SLUG']=$slug;$psi.Environment['DEVFLEET_SECURITY_INDEX']=[string]$i
        $p=[Diagnostics.Process]::new();$p.StartInfo=$psi;if(-not $p.Start()){throw "Could not start registry worker $i"};$processes.Add($p)
    }
    foreach($p in $processes){if(-not $p.WaitForExit(60000)){try{$p.Kill($true)}catch{};throw 'Registry worker timed out.'};if($p.ExitCode -ne 0){throw "Registry worker failed with $($p.ExitCode)."}}
    $after=Read-Registry
    $missing=@(0..23|Where-Object{-not $after.projects.ContainsKey("parallel-$_")})
    if($missing.Count -gt 0){throw "Registry lost $($missing.Count) concurrent project updates: $($missing -join ',')."}
    $json=Get-Content -LiteralPath $script:RegistryPath -Raw|ConvertFrom-Json
    if(@($json.projects.PSObject.Properties).Count -lt 24){throw 'Concurrent registry result was not valid complete JSON.'}

    # Repeat the TOCTOU collision at launch. The foreign VM is created only by the
    # fake launch boundary; launch_succeeded remains false, so cleanup must never
    # issue delete/purge and the foreign inventory remains observable.
    $raceResults=[Collections.Generic.List[object]]::new()
    function Assert-ResourceRequest { }
    function New-CloudInit { param([string]$Slug,[string]$ProjectId,[string]$GitUrl,[string]$ProvisioningAttemptId);return 'fixture-cloud-init' }
    function Get-MultipassVms { if($script:ForeignCreated){return @([pscustomobject]@{name=$script:ForeignName;state='RUNNING'})};return @() }
    function Invoke-Multipass {
        param([string[]]$ArgumentList,[int]$TimeoutSeconds=120)
        if([string]$ArgumentList[0] -eq 'launch'){$script:ForeignCreated=$true;throw 'fixture same-name foreign launch collision'}
        if([string]$ArgumentList[0] -eq 'delete'){$script:DeleteCalls++;throw 'DELETE MUST NOT BE CALLED AGAINST FOREIGN VM'}
        return [pscustomobject]@{ExitCode=0;Text=''}
    }
    for($i=0;$i -lt 20;$i++){
        $script:ForeignName="devfleet-project-race-$i";$script:ForeignCreated=$false;$script:DeleteCalls=0
        $projectId=[guid]::NewGuid().ToString();$threw=$false
        try{Ensure-ProjectVm "race-$i" $projectId 1 2 20}catch{$threw=$true}
        if(-not $threw -or -not $script:ForeignCreated -or $script:DeleteCalls -ne 0){throw "Same-name race iteration $i did not fail closed."}
        $raceResults.Add([ordered]@{iteration=$i;operation='Ensure-ProjectVm';launch='collision';foreignVmSurvived=$true;deletePurges=0;registryClaimRemoved=(-not (Read-Registry).projects.ContainsKey("race-$i"))})
    }
    if(@($raceResults|Where-Object{-not $_.registryClaimRemoved}).Count -gt 0){throw 'Failed launch left a provisional registry claim.'}
    [ordered]@{status='PASS';schemaVersion=1;registryConcurrency=[ordered]@{iterations=24;lostUpdates=0;validJson=$true};sameNameVmToctou=[ordered]@{iterations=20;foreignVmSurvived=$true;purgesAgainstForeign=0;provisionalClaims=0};evidenceScope='owned temporary fixture resources only'}|ConvertTo-Json -Depth 12 -Compress
}finally{Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}

```


## FILE: automation/release-e2e/tests/Test-StandardTokenCandidateEvidenceContract.ps1

SHA256: ed4e8167e2af5b31f3643141b4de172ce0e5a90bf3667825144d19d2bdc51cfa | Bytes: 2621 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop';if([string]::IsNullOrWhiteSpace($WorkspaceRoot)){$WorkspaceRoot=Join-Path $PSScriptRoot '..\..\..'};$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$candidate=Get-Content -Raw (Join-Path $root 'automation\release-e2e\modules\Candidate.psm1');$standard=Get-Content -Raw (Join-Path $root 'automation\release-e2e\tests\Test-InstallerSelfTestStandardToken.ps1')
$checks=[ordered]@{
    candidateAcceptsCallerReportPath=$candidate -match '\[string\]\$ReportPath' -and $candidate -match 'already exists; a unique path is required'
    candidateDoesNotDeleteCallerReport=$candidate -match 'if \(\$callerSuppliedReportPath\) \{ throw' -and $candidate -match 'Remove-Item -LiteralPath \$reportPath -Force -ErrorAction Stop'
    candidateCapturesToken=$candidate -match 'Get-WindowsTokenEvidence' -and $candidate -match 'integrityLevelSid' -and $candidate -match 'S-1-16-'
    candidatePowerShell51Compatible=$candidate -notmatch '\?\?' -and $candidate -match 'shipping_input_identity' -and $candidate -match 'shippingInputIdentity'
    standardRejectsAdminAndElevated=$standard -match 'standardNonAdministratorToken' -and $candidate -match 'S-1-5-32-544'
    standardPowerShell51DefaultResolution=$standard -match 'param\(\[string\]\$WorkspaceRoot' -and $standard -match 'IsNullOrWhiteSpace\(\$WorkspaceRoot\)' -and $standard -match '\$PSScriptRoot'
    standardUsesExactSignedCandidate=$standard -match 'Get-CandidateFingerprint' -and $standard -match 'PRIVATE_SELF_SIGNED' -and $standard -match 'authenticode'
    standardUsesImmutableEvidenceRoot=$standard -match 'evidence/standard-token' -and $standard -match 'installer-self-test-raw\.txt' -and $standard -match 'standard-token-evidence\.json'
    standardBindsTupleAndHashes=$standard -match 'candidateBuildCommit' -and $standard -match 'shippingInputIdentity' -and $standard -match 'releaseFingerprintId' -and $standard -match 'toolingFingerprintId' -and $standard -match 'reportSha256' -and $standard -match 'runnerRelative'
    standardAtomicCurrentPointer=$standard -match 'CURRENT-STANDARD-TOKEN\.json' -and $standard -match 'Write-AtomicJson'
    noBuildOrSign=$standard -notmatch 'dotnet publish|Build-Release|Set-AuthenticodeSignature'
}
$failed=@($checks.GetEnumerator()|Where-Object{-not[bool]$_.Value});$result=[ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=($checks.Count-$failed.Count);total=$checks.Count;checks=$checks}
$result|ConvertTo-Json -Depth 8;if($failed.Count){throw "Standard-token candidate evidence contract failed: $(@($failed.Name)-join ',')"}

```


## FILE: automation/release-e2e/tests/Test-TailscaleBrowserPairingObservability.ps1

SHA256: 924883c14680e33733106aac103ad9e612cf159ab004e6635261d3626a612bb9 | Bytes: 7442 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
$windowsRoot = Join-Path $WorkspaceRoot 'source/windows'
Import-Module (Join-Path $windowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
$module = Get-Module DevFleet.Tailscale
$checks = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [bool]$Pass) {
    $checks.Add([pscustomobject]@{ name = $Name; pass = $Pass })
}

function Read-Events([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Invoke-FixtureCase([string]$Case) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-Tailscale-Observability-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $eventPath = Join-Path $root 'pairing-events.log'
    try {
        $record = & $module {
            param($FixtureCase, $FixtureEventPath)
            $script:PairingFixtureCase = $FixtureCase
            $script:PairingFixtureOpened = 0
            $script:PairingFixtureStatusCalls = 0

            function script:Get-DevFleetDeadlineContext { return $null }
            function script:Start-Sleep { param($Milliseconds) }
            function script:Open-DevFleetTailscaleAuthenticationPage {
                param($Uri)
                $script:PairingFixtureOpened++
                if ($script:PairingFixtureCase -eq 'launch-failure') { throw 'fixture browser launch failure' }
                [pscustomobject]@{ apiAccepted = $true; processId = 4242; processSessionId = 1 }
            }
            function script:Invoke-External {
                param($FilePath, $ArgumentList, [switch]$Capture, [switch]$IgnoreExitCode, $TimeoutSeconds, $DeadlineUtc)
                if (-not $Capture -or -not $IgnoreExitCode -or $TimeoutSeconds -le 0) { throw 'fixture lost bounded capture contract' }
                if ($ArgumentList -contains 'up') {
                    if ($script:PairingFixtureCase -eq 'no-uri') { return 'https://evil.example/a/fake' }
                    return 'To authenticate, visit: https://login.tailscale.com/a/fixture123'
                }
                if ($ArgumentList -notcontains '--json') { throw 'fixture lost status JSON contract' }
                $script:PairingFixtureStatusCalls++
                if ($script:PairingFixtureCase -eq 'poll-command-failure' -and $script:PairingFixtureOpened -gt 0) { throw 'fixture status command timeout' }
                $connected = $script:PairingFixtureCase -eq 'already-connected' -or
                    ($script:PairingFixtureCase -eq 'auth-after-launch' -and $script:PairingFixtureOpened -gt 0)
                return (@{
                        BackendState = if ($connected) { 'Running' } else { 'NeedsLogin' }
                        TailscaleIPs = if ($connected) { @('100.64.1.2') } else { @() }
                        Self = if ($connected) { @{ HostName = 'devfleet-fixture' } } else { $null }
                    } | ConvertTo-Json -Compress)
            }

            $deadline = if ($FixtureCase -eq 'deadline-before-command') { [datetime]::UtcNow.AddSeconds(-1) } else { [datetime]::UtcNow.AddSeconds(60) }
            $result = $null
            $failed = $false
            $errorText = ''
            try {
                $result = Invoke-DevFleetTailscaleBrowserPairing `
                    -FilePath 'tailscale-fixture.exe' `
                    -Hostname 'devfleet-fixture' `
                    -DeadlineUtc $deadline `
                    -EvidencePath $FixtureEventPath `
                    -RunId 'fixture-run-observability' `
                    -TransactionId ('a' * 32) `
                    -PayloadSha256 ('b' * 64) `
                    -StageName 'windows-tailscale' `
                    -TargetRole 'Host'
            } catch {
                $failed = $true
                $errorText = $_.Exception.Message
            }
            [pscustomobject]@{
                result = $result
                failed = $failed
                error = $errorText
                opened = $script:PairingFixtureOpened
                statusCalls = $script:PairingFixtureStatusCalls
            }
        } $Case $eventPath
        [pscustomobject]@{ case = $Case; record = $record; events = @(Read-Events $eventPath); raw = if (Test-Path -LiteralPath $eventPath) { Get-Content -Raw -LiteralPath $eventPath } else { '' } }
    } finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

foreach ($case in @('already-connected', 'auth-after-launch', 'launch-failure', 'no-uri', 'poll-command-failure', 'deadline-before-command')) {
    $value = Invoke-FixtureCase $case
    $events = @($value.events)
    Check "$case writes sanitized event evidence" ($events.Count -gt 0)
    Check "$case event evidence has no URL or fixture token" ($value.raw -notmatch 'https?://|login\.tailscale\.com|fixture123')
    Check "$case event evidence binds transaction and target" (@($events | Where-Object { $_.transactionId -eq ('a' * 32) -and $_.requestedHostname -eq 'devfleet-fixture' -and $_.stage -eq 'windows-tailscale' }).Count -gt 0)
    switch ($case) {
        'already-connected' {
            Check "$case records authenticated state" (@($events | Where-Object eventClass -eq 'PAIRING_AUTHENTICATED').Count -gt 0 -and -not $value.record.failed)
        }
        'auth-after-launch' {
            Check "$case records accepted browser launch and authentication" (@($events | Where-Object eventClass -eq 'BROWSER_LAUNCH_ACCEPTED').Count -gt 0 -and @($events | Where-Object eventClass -eq 'PAIRING_AUTHENTICATED').Count -gt 0 -and -not $value.record.failed)
        }
        'launch-failure' {
            Check "$case records browser launch failure" (@($events | Where-Object { $_.eventClass -eq 'BROWSER_LAUNCH_FAILED' -and $_.failureClass -eq 'BROWSER_LAUNCH_API_FAILED' }).Count -gt 0 -and $value.record.failed)
        }
        'no-uri' {
            Check "$case records missing official URI" (@($events | Where-Object { $_.eventClass -eq 'PAIRING_FAILED' -and $_.failureClass -eq 'NO_VALID_OFFICIAL_URI' }).Count -gt 0 -and $value.record.failed)
        }
        'poll-command-failure' {
            Check "$case records wait and poll command failure" (@($events | Where-Object eventClass -eq 'PAIRING_WAIT_ENTERED').Count -gt 0 -and @($events | Where-Object eventClass -eq 'COMMAND_FAILED').Count -gt 0 -and $value.record.failed)
        }
        'deadline-before-command' {
            Check "$case records owner deadline before command" (@($events | Where-Object eventClass -eq 'COMMAND_BLOCKED_DEADLINE').Count -gt 0 -and $value.record.failed)
        }
    }
}

$result = [ordered]@{
    status = if (@($checks | Where-Object { -not $_.pass }).Count) { 'FAIL' } else { 'PASS' }
    scope = 'LOCAL_PRODUCTION_TAILSCALE_PAIRING_BOUNDARY_WITH_SANITIZED_EVENT_FIXTURES'
    passed = @($checks | Where-Object pass).Count
    total = $checks.Count
    checks = @($checks)
}
$result | ConvertTo-Json -Depth 8
if ($result.status -ne 'PASS') { exit 1 }
Write-Host "PASS $($result.passed)/$($result.total) Tailscale pairing observability checks; no browser, network, VM or auth-store operations performed."

```


## FILE: automation/release-e2e/tests/Test-TailscaleModuleVisibility.ps1

SHA256: 74d6de4ffae1b588cff231731ed5797d3aa50e715f2ff869d4d5d4d839e80ccb | Bytes: 4845 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WindowsRoot = (Join-Path $PSScriptRoot '../../../source/windows'),
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$WindowsRoot = (Resolve-Path -LiteralPath $WindowsRoot).Path
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'The installed caller requires PowerShell 7.' }
$results = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Pass) {
    $results.Add([pscustomobject]@{name=$Name;pass=$Pass})
}

# This is the actual dependency import order used by both shipping pairing scripts.
Import-Module (Join-Path $WindowsRoot 'DevFleet.Common.psm1') -Force -DisableNameChecking
$adminBefore = Get-Command Assert-Administrator -ErrorAction Stop
$commonExports = @((Get-Module DevFleet.Common).ExportedFunctions.Keys)
Import-Module (Join-Path $WindowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
$adminAfter = Get-Command Assert-Administrator -ErrorAction SilentlyContinue
$pairingModule = Get-Module DevFleet.Tailscale
$nestedAdmin = & $pairingModule { Get-Command Assert-Administrator -ErrorAction SilentlyContinue }
Check 'Common administrator guard is visible before dependency import' ($null -ne $adminBefore)
Check 'Dependency import preserves caller administrator guard' ($null -ne $adminAfter)
Check 'Dependency retains its own Common command visibility' ($null -ne $nestedAdmin)
$expectedExports=@('Invoke-DevFleetTailscaleBrowserPairing','Invoke-DevFleetTailscaleOAuthPairing','Get-DevFleetTailscaleReadiness','Get-DevFleetTailscaleEnrollmentProfile','Get-DevFleetTailscaleOAuthSecretPath','Set-DevFleetTailscaleOAuthClientSecret')
$actualExports=@($pairingModule.ExportedFunctions.Keys)
Check 'Tailscale exports only the reviewed public pairing/readiness/credential entrypoints' ($actualExports.Count -eq $expectedExports.Count -and @($expectedExports|Where-Object{$actualExports -notcontains $_}).Count -eq 0 -and @($actualExports|Where-Object{$expectedExports -notcontains $_}).Count -eq 0)
$missingExports = @($commonExports | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
Check 'All normal caller Common exports remain visible' ($missingExports.Count -eq 0)

# Invoke the actual shipping script. The real administrator check runs unchanged;
# a caller-scope mock stops execution at the first external service boundary.
# No service, Tailscale CLI, browser, credential store or VM operation may run.
function Get-Service { throw 'LOCAL_FIXTURE_SERVICE_BOUNDARY_AFTER_REAL_ADMIN_GUARD' }
$scriptError = ''
try { & (Join-Path $WindowsRoot '04a-Connect-WindowsTailscale.ps1') }
catch { $scriptError = $_.Exception.Message }
Check 'Production Windows pairing script reaches external boundary after real guard' ($scriptError -eq 'LOCAL_FIXTURE_SERVICE_BOUNDARY_AFTER_REAL_ADMIN_GUARD')
Check 'Nested pairing caller can still resolve its Common helpers' ([bool](Get-Command Get-MultipassExe -ErrorAction SilentlyContinue) -and [bool](Get-Command Get-DevFleetStageBudgetSeconds -ErrorAction SilentlyContinue))

# Repeated stage imports are part of the same durable installer process.
Import-Module (Join-Path $WindowsRoot 'DevFleet.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $WindowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
Check 'Repeated production import order preserves caller guard' ([bool](Get-Command Assert-Administrator -ErrorAction SilentlyContinue))
$privateHelpers = & (Get-Module DevFleet.Tailscale) {
    [bool](Get-Command Get-DevFleetDeadlineContext -ErrorAction SilentlyContinue) -and
    [bool](Get-Command Invoke-External -ErrorAction SilentlyContinue)
}
Check 'Repeated dependency load preserves internal deadline and process helpers' ([bool]$privateHelpers)

$report = [ordered]@{
    status = if (@($results | Where-Object { -not $_.pass }).Count) {'FAIL'} else {'PASS'}
    runtime = $PSVersionTable.PSVersion.ToString()
    scope = 'LOCAL_PRODUCTION_IMPORT_AND_SCRIPT_EXTERNAL_BOUNDARY_NO_RUNTIME_PROOF'
    actualScriptError = $scriptError
    callerCommonExportCount = $commonExports.Count
    missingCallerExports = $missingExports
    inputHashes = @(foreach ($name in @('DevFleet.Common.psm1','DevFleet.Tailscale.psm1','04a-Connect-WindowsTailscale.ps1')) {
        [ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $WindowsRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    results = @($results)
    passed = @($results | Where-Object pass).Count
    total = $results.Count
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding utf8
[pscustomobject]@{status=$report.status;passed=$report.passed;total=$report.total;actualScriptError=$scriptError;missingCallerExportCount=$missingExports.Count} | ConvertTo-Json -Compress
if ($report.status -ne 'PASS') { exit 1 }

```


## FILE: automation/release-e2e/tests/Test-TailscaleOAuthAutomation.ps1

SHA256: 75c28c6c435b49db4f2d0703fac36f50d71af8766a7822d7a502db5d02dc3a29 | Bytes: 32684 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }

$sourceModule = Join-Path $WorkspaceRoot 'source\windows\DevFleet.Tailscale.psm1'
$e2eModule = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\TailscaleE2E.psm1'
$passed = 0
$failures = [System.Collections.Generic.List[string]]::new()
$caseCount = 0
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-tailscale-oauth-test-' + [guid]::NewGuid().ToString('N'))

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

function New-FixtureStatusJson {
    param(
        [string]$BackendState = 'Running',
        [string]$HostName = 'fixture-node',
        [bool]$Online = $true,
        [string[]]$Ips = @('100.64.1.2'),
        [string[]]$Health = @()
    )
    [ordered]@{
        BackendState = $BackendState
        Self = [ordered]@{ HostName = $HostName; Online = $Online }
        TailscaleIPs = @($Ips)
        Health = @($Health)
    } | ConvertTo-Json -Depth 5 -Compress
}

function New-FixturePreferencesJson {
    param([string[]]$Tags = @('tag:devfleet-e2e'))
    [ordered]@{ AdvertiseTags = @($Tags) } | ConvertTo-Json -Depth 3 -Compress
}

function New-FixtureCommandInvoker {
    param([Parameter(Mandatory)][hashtable]$State)
    $statusJsonBuilder = ${function:New-FixtureStatusJson}.GetNewClosure()
    $preferencesJsonBuilder = ${function:New-FixturePreferencesJson}.GetNewClosure()
    $invoker = {
        param([string[]]$Arguments)
        $command = [string]$Arguments[0]
        [void]$State.commandArguments.Add(($Arguments -join ' '))
        switch ($command) {
            'status' {
                $State.statusCalls = [int]$State.statusCalls + 1
                $afterAuth = [int]$State.authCalls -gt 0
                $backend = if ($afterAuth) { [string]$State.finalBackend } else { [string]$State.initialBackend }
                $hostName = if ($afterAuth) { [string]$State.finalHostName } else { [string]$State.initialHostName }
                $online = if ($afterAuth) { [bool]$State.finalOnline } else { [bool]$State.initialOnline }
                $ips = if ($afterAuth) { @($State.finalIps) } else { @($State.initialIps) }
                $health = if ($afterAuth) { @($State.finalHealth) } else { @($State.initialHealth) }
                return [pscustomobject]@{ exitCode = [int]$State.statusExitCode; output = & $statusJsonBuilder -BackendState $backend -HostName $hostName -Online:$online -Ips $ips -Health $health }
            }
            'debug' {
                $afterAuth = [int]$State.authCalls -gt 0
                $tags = if ($afterAuth) { @($State.finalTags) } else { @($State.initialTags) }
                return [pscustomobject]@{ exitCode = [int]$State.preferencesExitCode; output = & $preferencesJsonBuilder -Tags $tags }
            }
            'up' {
                $State.authCalls = [int]$State.authCalls + 1
                if ($State.pendingRebootOnAuth) { $State.pendingReboot = $true }
                return [pscustomobject]@{ exitCode = [int]$State.upExitCode; output = [string]$State.upOutput }
            }
            'ping' {
                $State.peerCalls = [int]$State.peerCalls + 1
                if ([int]$State.peerFailuresBeforeSuccess -ge 0 -and [int]$State.peerCalls -gt [int]$State.peerFailuresBeforeSuccess) {
                    return [pscustomobject]@{ exitCode = 0; output = 'pong' }
                }
                return [pscustomobject]@{ exitCode = [int]$State.peerExitCode; output = [string]$State.peerOutput }
            }
            default {
                return [pscustomobject]@{ exitCode = 0; output = '' }
            }
        }
    }.GetNewClosure()
    $invoker
}

function Invoke-ProductionFixture {
    param(
        [string]$InitialBackend = 'Running',
        [string]$FinalBackend = 'Running',
        [string]$InitialHostName = 'fixture-node',
        [string]$FinalHostName = 'fixture-node',
        [bool]$InitialOnline = $true,
        [bool]$FinalOnline = $true,
        [string[]]$InitialIps = @('100.64.1.2'),
        [string[]]$FinalIps = @('100.64.1.2'),
        [string[]]$InitialHealth = @(),
        [string[]]$FinalHealth = @(),
        [string[]]$InitialTags = @('tag:devfleet-e2e'),
        [string[]]$FinalTags = @('tag:devfleet-e2e'),
        [string]$EnrollmentGuestHostname = '',
        [string]$ExpectedPeer = '',
        [int]$ServicePort = 0,
        [string]$OptionsError = '',
        [string]$EvidencePath = '',
        [string]$LockStatus = 'DISABLED',
        [int]$UpExitCode = 0,
        [string]$UpOutput = '',
        [int]$PeerExitCode = 0,
        [string]$PeerOutput = '',
        [int]$PeerFailuresBeforeSuccess = -1,
        [int]$EndpointExitCode = 0,
        [int]$StatusExitCode = 0,
        [int]$PreferencesExitCode = 0,
        [bool]$Stopped = $false,
        [switch]$PendingRebootOnAuth
    )
    $state = @{
        initialBackend = $InitialBackend; finalBackend = $FinalBackend
        initialHostName = $InitialHostName; finalHostName = $FinalHostName
        initialOnline = $InitialOnline; finalOnline = $FinalOnline
        initialIps = @($InitialIps); finalIps = @($FinalIps)
        initialHealth = @($InitialHealth); finalHealth = @($FinalHealth)
        initialTags = @($InitialTags); finalTags = @($FinalTags)
        optionsError = $OptionsError; lockStatus = $LockStatus; stopped = $Stopped
        upExitCode = $UpExitCode; upOutput = $UpOutput
        peerExitCode = $PeerExitCode; peerOutput = $PeerOutput; peerFailuresBeforeSuccess = $PeerFailuresBeforeSuccess
        endpointExitCode = $EndpointExitCode; statusExitCode = $StatusExitCode; preferencesExitCode = $PreferencesExitCode
        pendingRebootOnAuth = [bool]$PendingRebootOnAuth; pendingReboot = $false; pendingRebootChecks = 0
        statusCalls = 0; authCalls = 0; startCalls = 0; endpointCalls = 0; peerCalls = 0
        commandArguments = [System.Collections.Generic.List[string]]::new()
    }
    $guestHostnames = @{}
    if ($EnrollmentGuestHostname) { $guestHostnames['fixture-guest'] = $EnrollmentGuestHostname }
    $profile = [pscustomobject]@{ mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true; guestHostnames = $guestHostnames }
    $optionsProvider = {
        param([string]$RequestedHostname, [string]$InstanceName, [string]$TargetRole)
        if ([string]$State.optionsError) { throw [string]$State.optionsError }
        [pscustomobject]@{
            mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true
            hostname = $RequestedHostname; targetRole = $TargetRole; instanceName = $InstanceName
            secret = 'fixture-oauth-client-secret'; credentialSource = 'fixture-only'
        }
    }.GetNewClosure()
    $lockProvider = {
        [pscustomobject]@{ status = [string]$State.lockStatus; observed = $true; enabled = ([string]$State.lockStatus -ceq 'ENABLED') }
    }.GetNewClosure()
    $serviceProvider = {
        if ([bool]$State.stopped) { 'Stopped' } else { 'Running' }
    }.GetNewClosure()
    $startProvider = {
        $State.startCalls = [int]$State.startCalls + 1
    }.GetNewClosure()
    $pendingRebootProvider = {
        $State.pendingRebootChecks = [int]$State.pendingRebootChecks + 1
        [bool]$State.pendingReboot
    }.GetNewClosure()
    $endpointInvoker = {
        param([string]$Target, [int]$Port, [string]$Path)
        $State.endpointCalls = [int]$State.endpointCalls + 1
        [pscustomobject]@{ exitCode = [int]$State.endpointExitCode; output = '' }
    }.GetNewClosure()
    $result = $null
    $errorText = ''
    try {
        $pairingParameters = @{
            FilePath = 'fixture-tailscale.exe'; InstanceName = 'fixture-guest'; Hostname = 'fixture-node'
            DeadlineUtc = [datetime]::UtcNow.AddSeconds(30); EvidencePath = $EvidencePath; RunId = 'oauth-automation-fixture'
            StageName = 'TAILSCALE-AUTH'; TargetRole = 'Fixture'; ExpectedPeer = $ExpectedPeer
            ServicePort = $ServicePort; ServicePath = '/healthz'
            CommandInvoker = (New-FixtureCommandInvoker -State $state)
            EndpointInvoker = $endpointInvoker; EnrollmentProfileProvider = { $profile }
            EnrollmentOptionsProvider = $optionsProvider; TailnetLockProvider = $lockProvider
            ServiceStateProvider = $serviceProvider; ServiceStartProvider = $startProvider
        }
        if ($PendingRebootOnAuth) { $pairingParameters.PendingRebootProvider = $pendingRebootProvider }
        $result = Invoke-DevFleetTailscaleOAuthPairing @pairingParameters
    } catch { $errorText = [string]$_.Exception.Message }
    [pscustomobject]@{ result = $result; error = $errorText; state = $state }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $sourceModule -Force
    Import-Module $e2eModule -Force

    # 1. Healthy authenticated state is a read-only PASS.
    $caseCount++
    $healthy = Invoke-ProductionFixture
    $healthyStatusCommands = @($healthy.state.commandArguments | Where-Object { $_ -match '(^|\s)status\s' })
    Check ($healthy.result -and [bool]$healthy.result.authenticated -and -not [bool]$healthy.result.authenticationAttempted -and [int]$healthy.state.authCalls -eq 0 -and [string]$healthy.result.readiness.statusClass -eq 'READY') 'healthy state skips OAuth mutation and passes readiness'
    $caseCount++
    Check ($healthyStatusCommands.Count -gt 0 -and @($healthyStatusCommands | Where-Object { $_ -notmatch '--peers=false' }).Count -eq 0) 'status readiness excludes peer enumeration while retaining self state'

    # An E2E guest's Tailscale self hostname is generated from the run identity,
    # not copied from the Multipass instance name. Pre-auth readiness must use
    # that profile-resolved identity or it will reject an already-authenticated
    # guest as TAILSCALE_WRONG_TAG before OAuth.
    $guestProfileIdentity = Invoke-ProductionFixture -InitialHostName 'fixture-guest-e2e' -EnrollmentGuestHostname 'fixture-guest-e2e'
    $caseCount++
    Check ($guestProfileIdentity.result -and [bool]$guestProfileIdentity.result.authenticated -and -not [bool]$guestProfileIdentity.result.authenticationAttempted -and [int]$guestProfileIdentity.state.authCalls -eq 0) 'E2E guest readiness uses the profile-resolved hostname before OAuth'

    # 2. A stopped service gets one bounded recovery and is rechecked.
    $caseCount++
    $stopped = Invoke-ProductionFixture -Stopped:$true
    Check ($stopped.result -and [int]$stopped.state.startCalls -eq 1 -and [int]$stopped.result.serviceRecoveryCount -eq 1 -and [int]$stopped.state.authCalls -eq 0) 'stopped service has one recovery and one readiness recheck'

    # 3. NeedsLogin invokes the OAuth enrollment exactly once.
    $caseCount++
    $needsLogin = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -FinalBackend 'Running'
    Check ($needsLogin.result -and [bool]$needsLogin.result.authenticated -and [bool]$needsLogin.result.authenticationAttempted -and [int]$needsLogin.state.authCalls -eq 1 -and [int]$needsLogin.state.statusCalls -eq 2) 'NeedsLogin performs one OAuth enrollment and verifies the resulting state'

    # 3a. A servicing transition during OAuth must leave the auth boundary and
    # propagate a typed reboot requirement to the installer lifecycle.
    $servicingEvidencePath = Join-Path $scratch 'servicing-transition-events.jsonl'
    $servicingTransition = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -FinalBackend 'Running' -EvidencePath $servicingEvidencePath -PendingRebootOnAuth
    $caseCount++
    Check (-not $servicingTransition.result -and $servicingTransition.error -match '^DEVFLEET_REBOOT_REQUIRED:' -and [int]$servicingTransition.state.authCalls -eq 1 -and [int]$servicingTransition.state.statusCalls -eq 1 -and [int]$servicingTransition.state.pendingRebootChecks -gt 0) 'servicing transition during OAuth propagates a typed reboot requirement before readiness'
    $servicingEvents = if (Test-Path -LiteralPath $servicingEvidencePath -PathType Leaf) { @(Get-Content -LiteralPath $servicingEvidencePath | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
    $servicingEvent = $servicingEvents | Where-Object { [string]$_.eventClass -ceq 'REBOOT_REQUIRED_DURING_TAILSCALE' } | Select-Object -First 1
    $caseCount++
    Check ($servicingEvent -and [bool]$servicingEvent.rebootRequired -and [string]$servicingEvent.boundary -ceq 'oauth-enrollment' -and ($servicingEvents | ConvertTo-Json -Compress) -notmatch 'fixture-oauth-client-secret') 'servicing transition emits a bounded redacted structured event'

    $windowsTailscaleSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'source\windows\04a-Connect-WindowsTailscale.ps1') -Raw
    $installSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'source\Install-DevFleet.ps1') -Raw
    $caseCount++
    Check ($windowsTailscaleSource -match 'DEVFLEET_REBOOT_REQUIRED' -and $windowsTailscaleSource -match 'exit 3010' -and $installSource -match 'windows\\04a-Connect-WindowsTailscale\.ps1' -and $installSource -match 'LASTEXITCODE' -and $installSource -match 'Write-StageMarker ''windows-tailscale''') 'Windows Tailscale reboot result is propagated before its stage marker is published'

    $guestTailscaleSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'source\windows\04-Connect-Tailscale.ps1') -Raw
    $tailscaleSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'source\windows\DevFleet.Tailscale.psm1') -Raw
    $caseCount++
    Check ($guestTailscaleSource -match 'DEVFLEET_REBOOT_REQUIRED' -and $guestTailscaleSource -match 'exit 3010' -and $guestTailscaleSource -match '(?s)-PendingRebootProvider\s+\{\s*Test-PendingReboot\s*\}') 'Guest Tailscale reboot result is propagated before Vault completion'
    $caseCount++
    Check ($tailscaleSource -match 'OAUTH_ENROLLMENT_STARTED' -and $tailscaleSource -match "oauth-enrollment-before" -and $tailscaleSource -match 'DEVFLEET_TAILSCALE_UP_EXIT' -and $tailscaleSource -match 'timeout\s+--signal=TERM\s+--kill-after=10s') 'Guest OAuth enrollment has a bounded servicing-aware result handoff'
    $caseCount++
    Check ($tailscaleSource -match "status','--json','--peers=false") 'Guest Tailscale readiness uses self-only structured status before peer ping'

    # 3b. Guest service probes must target systemctl directly; only Tailscale
    # subcommands receive the sudo tailscale wrapper used by multipass exec.
    $tailscaleModule = Get-Module DevFleet.Tailscale | Select-Object -First 1
    $guestServiceArgs = & $tailscaleModule {
        ConvertTo-DevFleetTailscaleNativeArguments -InstanceName 'fixture-guest' -CommandKind 'System' -Arguments @('systemctl','is-active','tailscaled')
    }
    $guestTailscaleArgs = & $tailscaleModule {
        ConvertTo-DevFleetTailscaleNativeArguments -InstanceName 'fixture-guest' -CommandKind 'Tailscale' -Arguments @('status','--json','--peers=false')
    }
    $caseCount++
    Check (($guestServiceArgs -join ' ') -ceq 'exec fixture-guest -- sudo systemctl is-active tailscaled' -and ($guestTailscaleArgs -join ' ') -ceq 'exec fixture-guest -- sudo tailscale status --json --peers=false') 'guest service commands bypass the Tailscale subcommand wrapper and bound status excludes peer enumeration'

    # 4. Missing credential is deterministic and never opens a browser.
    $caseCount++
    $missing = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -OptionsError 'fixture credential is absent'
    Check (-not $missing.result -and $missing.error -ceq 'fixture credential is absent' -and [int]$missing.state.authCalls -eq 0 -and (@($missing.state.commandArguments | Where-Object { $_ -match '(?i)browser|login.tailscale' }).Count -eq 0)) 'missing OAuth credential fails closed without browser fallback'

    # 5. Invalid credential has its own failure class and no enrollment attempt.
    $caseCount++
    $invalid = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -OptionsError 'TAILSCALE_CREDENTIAL_INVALID: fixture credential cannot be decrypted'
    Check (-not $invalid.result -and $invalid.error -match '^TAILSCALE_CREDENTIAL_INVALID' -and [int]$invalid.state.authCalls -eq 0) 'invalid OAuth credential fails deterministically without authentication'