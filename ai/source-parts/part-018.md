# DevFleet source part 018

Full-source UTF-8 byte interval [790500, 837000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 79bf34c8e3783375028664baf4698653b0b65918ffc4e6f0a46c7c6318026e87

<!-- BEGIN SOURCE SLICE -->
s.'}
            [IO.File]::WriteAllText($cloud,$rendered,[Text.UTF8Encoding]::new($false))
            Invoke-MultipassLaunchWithReadinessRecovery -InstanceName ([string]$Request.vaultName) -LaunchArguments @('launch',[string]$v.UbuntuImage,'--name',[string]$Request.vaultName,'--cpus',[string]$v.Cpus,'--memory',[string]$v.Memory,'--disk',[string]$v.Disk,'--cloud-init',$cloud) -ReadinessTimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'multipassReadiness') -LaunchTimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'multipassLaunch') -DeadlineUtc $deadline|Out-Null
            $vm=@(Get-VM -Name ([string]$Request.vaultName) -ErrorAction Stop)
            if($vm.Count-ne1){throw 'New fixture Vault identity is ambiguous.'}
            return [pscustomobject]@{vaultId=$vm[0].Id.ToString()}
        }
        'bootstrap' {
            $vault=Get-VM -Id ([guid][string]$State.vault.vaultId) -ErrorAction Stop
            if($vault.Name-cne[string]$Request.vaultName){throw 'Fixture Vault identity changed before bootstrap.'}
            & (Join-Path $package 'windows/04a-Connect-WindowsTailscale.ps1')|Out-Null
            & (Join-Path $package 'windows/04-Connect-Tailscale.ps1') -InstanceName ([string]$Request.vaultName)|Out-Null
            # The product script imports Common with -Force in its own scope.
            # Reacquire its exports after that boundary, as in native cleanup.
            Import-Module (Join-Path $package 'windows/DevFleet.Common.psm1') -Scope Local -DisableNameChecking
            $secrets=Get-OrCreateSecrets;$identity=Get-OrCreateVaultIdentity
            if([string]$identity.deployment_id-cne[string]$State.identity.deploymentId){throw 'Vault deployment differs from the installed Primary.'}
            $boundary=New-DevFleetBootstrapBoundary -Kind vault -InstanceName ([string]$Request.vaultName) -TransactionId ([string]$Request.transactionId) -PayloadSha256 ([string]$Request.payloadSha256) -BootstrapMaxSeconds (Get-DevFleetOperationMaximumSeconds 'vaultBootstrap') -PackageVersion 'vault' -NodeRole 'vault'
            $zip=Join-Path ([string]$Request.workRoot) 'vault-payload.zip'
            Compress-Archive -LiteralPath (Join-Path $package 'linux') -DestinationPath $zip -ErrorAction Stop
            $secretJson=[ordered]@{VaultPort=$config.Network.VaultPort;RestUser=$secrets.VaultRestUser;RestPassword=$secrets.VaultRestPassword;ResticPassword=$secrets.ResticPassword;ClusterName=$config.ClusterName;DeploymentId=$identity.deployment_id;NodeId=$identity.node_id;NodeName=$identity.node_name}|ConvertTo-Json -Compress
            try{
                Invoke-External $mp @('transfer',$zip,([string]$Request.vaultName+':/tmp/devfleet-vault-payload.zip')) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') -DeadlineUtc $deadline|Out-Null
                Invoke-External $mp @('exec',[string]$Request.vaultName,'--','bash','-lc',$boundary.extractionCommand) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') -DeadlineUtc $deadline|Out-Null
                Invoke-MultipassWithStandardInput -FilePath $mp -InstanceName ([string]$Request.vaultName) -CommandArgumentList @('bash','-lc',$boundary.bootstrapCommand) -TimeoutSeconds $boundary.bootstrapMaxSeconds -DeadlineUtc $deadline -StandardInputText $secretJson|Out-Null
            } finally {$secretJson=$null;$secrets=$null}
        }
        'configure' {
            & (Join-Path $package 'windows/05-Configure-LocalVaultClient.ps1') -InstanceName ([string]$Request.primaryName)|Out-Null
        }
        'verify' {
            $identity=Get-Content -LiteralPath (Join-Path (Get-DevFleetStateRoot) 'node-identity.json') -Raw|ConvertFrom-Json
            $primary=Get-VM -Id ([guid][string]$State.identity.primaryId) -ErrorAction Stop
            $vault=Get-VM -Id ([guid][string]$State.vault.vaultId) -ErrorAction Stop
            if($primary.Name-cne[string]$Request.primaryName-or$vault.Name-cne[string]$Request.vaultName-or[string]$identity.deployment_id-cne[string]$State.identity.deploymentId){throw 'Fixture changed the installed Primary or owned Vault identity.'}
            # The product configurator has already authenticated and initialized
            # the repository. Do not print secret env contents or count this
            # setup backup as the later project's data-coverage proof.
            $check='sudo -u devfleet-backup test -r /etc/devfleet/restic.env && sudo -u devfleet-backup test -w /var/lib/devfleet/backup-status/restic-cache && sudo -u devfleet-control test -r /var/lib/devfleet/backup-status/config.json'
            Invoke-External $mp @('exec',[string]$Request.primaryName,'--','bash','-lc',$check) -TimeoutSeconds 60 -DeadlineUtc $deadline|Out-Null
            return [pscustomobject][ordered]@{status='PASS';runId=[string]$Request.runId;payloadSha256=[string]$Request.payloadSha256;primaryName=$primary.Name;primaryId=$primary.Id.ToString();primaryRole=[string]$identity.node_role;vaultName=$vault.Name;vaultId=$vault.Id.ToString();deploymentId=[string]$identity.deployment_id;configurationPresent=$true;authenticatedTransport=$true;proofCredit=$false;contract='configured-primary-vault-prerequisite-v1'}
        }
    }
}

function Initialize-MaintenanceVaultFixture {
    param([Parameter(Mandatory)]$Context)
    if([string]$Context.runId-cnotmatch'\Afullrelease-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'-or([string]$Context.runId).Length-gt128){throw 'Vault fixture requires a validated FullRelease RunId.'}
    if([guid][string]$Context.vmId-ne[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'){throw 'Vault fixture is not bound to the approved immutable L1.'}
    $workspace=[string]$Context.workspaceRoot
    $session=$null;$job=$null;$stageAttempted=$false;$primaryError=$null
    foreach($module in @('GuestSession','HarnessBudget','HostSafety','MultipassDiagnostic','TailscaleE2E')){Import-Module (Join-Path $PSScriptRoot ($module+'.psm1')) -Scope Local -DisableNameChecking}
    $vm=Get-VM -Id ([guid][string]$Context.vmId) -ErrorAction Stop
    if($vm.Name-cne[string]$Context.vmName-or$vm.Name-cne'DevFleet-E2E-Win11-01'){throw 'Vault prerequisite exact L1 identity differs.'}
    $safety=Get-HostSafetySnapshot -Vm $vm
    if(-not[bool]$safety.startSafe){throw 'Vault prerequisite requires fresh native HOST-SAFETY.'}
    $policy=Get-HarnessBudgetPolicy -Config $Context.config
    # Same finite product operations, composed once. No observer timeout or
    # acceptance threshold is increased. The worker owns exact tree termination.
    $o=$policy.operationMaximumsSeconds
    $budget=[int]$o.multipassLaunch+[int]$o.multipassReadiness+2*[int]$o.payloadTransfer+[int]$o.vaultBootstrap+[int]$o.tailscale+[int]$o.vaultClient+[int]$o.verification
    $deadline=[datetime]::UtcNow.AddSeconds($budget)
    $config=Get-Content -LiteralPath (Join-Path $workspace 'source/config/devfleet.config.json') -Raw|ConvertFrom-Json
    $request=[ordered]@{runId=[string]$Context.runId;payloadSha256=[string]$Context.candidate.tar.sha256;primaryName=[string]$config.Primary.InstanceName;vaultName=[string]$config.Vault.InstanceName;transactionId=[guid]::NewGuid().ToString('N');ownerDeadlineUtc=$deadline.ToString('o');budgetSeconds=$budget;inputHashes=[ordered]@{}}
    foreach($relative in @('cloud-init/vault.yaml')+@(Get-ChildItem -LiteralPath (Join-Path $workspace 'source/windows') -File|ForEach-Object{'windows/'+$_.Name})+@(Get-ChildItem -LiteralPath (Join-Path $workspace 'source/linux') -File|ForEach-Object{'linux/'+$_.Name})){
        $request.inputHashes[$relative]=(Get-FileHash -LiteralPath (Join-Path $workspace ('source/'+$relative)) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    try{
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        if([guid]$session.Runspace.ConnectionInfo.VMGuid-ne[guid][string]$Context.vmId){throw 'Vault prerequisite session VM identity differs.'}
        $remoteRoot="C:\ProgramData\DevFleet\tmp\maintenance-vault-$($Context.runId)"
        $request.workRoot=$remoteRoot
        Invoke-DevFleetBoundedGuestCommand -Session $session -ScriptBlock {param($Path)if(Test-Path -LiteralPath $Path){throw 'Vault prerequisite work directory already exists; no unchanged replay is allowed.'};New-Item -ItemType Directory -Path $Path -ErrorAction Stop|Out-Null} -ArgumentList @($remoteRoot) -TimeoutSeconds 30|Out-Null
        $remoteModule=Join-Path $remoteRoot 'MaintenanceVault.psm1'
        Copy-DevFleetBoundedGuestFile -Session $session -LocalPath $PSCommandPath -RemotePath $remoteModule -TimeoutSeconds 30|Out-Null
        $stageAttempted=$true
        $stage=Stage-TailscaleOAuthCredential -Session $session -RunId ([string]$Context.runId) -Config $Context.config.Tailscale -ProductConfig $config
        if([string]$stage.status-cne'PASS'-or-not[bool]$stage.staged){throw 'Vault prerequisite could not stage its existing approved OAuth provider.'}
        $expectedWindowsHostname=if($stage.profile){[string]$stage.profile.hostName}else{''}
        Write-MaintenanceVaultWindowsTailscaleSnapshot -Session $session -ExpectedHostname $expectedWindowsHostname -RunDir ([string]$Context.runDir)|Out-Null
        $json=$request|ConvertTo-Json -Depth 8 -Compress
        # Keep the full exact-input inventory out of Windows' command-line
        # length limit. This request contains only public identities/hashes.
        $localRequest=Join-Path ([string]$Context.runDir) 'maintenance-vault-request.json'
        [IO.File]::WriteAllText($localRequest,$json,[Text.UTF8Encoding]::new($false))
        $remoteRequest=Join-Path $remoteRoot 'request.json'
        $requestStage=Copy-DevFleetBoundedGuestFile -Session $session -LocalPath $localRequest -RemotePath $remoteRequest -TimeoutSeconds 30
        $body=@'
$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
if((Get-FileHash -LiteralPath '__REQUEST_PATH__' -Algorithm SHA256).Hash.ToLowerInvariant()-cne'__REQUEST_HASH__'){throw 'Fixture request identity differs.'}
$request=Get-Content -LiteralPath '__REQUEST_PATH__' -Raw|ConvertFrom-Json
if($env:COMPUTERNAME-cne'DEVFLEET-E2E-01'-or$PSVersionTable.PSVersion.Major-lt7){throw 'Approved disposable L1 PS7 is required.'}
$install=Get-Content 'C:\ProgramData\M-TechLabs\DevFleet\Installer\install-state.json' -Raw|ConvertFrom-Json
if([string]$install.PackageSha256-cne[string]$request.payloadSha256){throw 'Installed payload identity differs.'}
$package=(Get-Content 'C:\ProgramData\DevFleet\package-root.txt' -Raw).Trim()
foreach($input in $request.inputHashes.PSObject.Properties){$path=Join-Path $package $input.Name;if((Get-Item -LiteralPath $path).Attributes-band[IO.FileAttributes]::ReparsePoint-or(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$input.Value){throw 'Exact candidate prerequisite input mismatch.'}}
$request|Add-Member -NotePropertyName packageRoot -NotePropertyValue $package
Import-Module (Join-Path $package 'windows/DevFleet.Common.psm1') -Force -DisableNameChecking
Protect-DevFleetStateAcl
Import-Module (Join-Path $request.workRoot 'MaintenanceVault.psm1') -Force -DisableNameChecking
$privateLog=Join-Path $request.workRoot 'private-product-operations.log'
$privateWarningLog=Join-Path $request.workRoot 'private-product-operations.warning.tmp'
$privateVerboseLog=Join-Path $request.workRoot 'private-product-operations.verbose.tmp'
$privateDebugLog=Join-Path $request.workRoot 'private-product-operations.debug.tmp'
$privateInformationLog=Join-Path $request.workRoot 'private-product-operations.information.tmp'
$privateStreamLogs=@($privateWarningLog,$privateVerboseLog,$privateDebugLog,$privateInformationLog)
function Merge-MaintenanceVaultPrivateStreams {param([string]$Destination,[string[]]$Sources)foreach($source in $Sources){if(Test-Path -LiteralPath $source -PathType Leaf){$content=[IO.File]::ReadAllText($source);if($content.Length-gt0){[IO.File]::AppendAllText($Destination,$content,[Text.UTF8Encoding]::new($false))}}}}
try{$result=Invoke-MaintenanceVaultProvisioning -Request $request 3>$privateWarningLog 4>$privateVerboseLog 5>$privateDebugLog 6>$privateInformationLog;Merge-MaintenanceVaultPrivateStreams -Destination $privateLog -Sources $privateStreamLogs;$result|ConvertTo-Json -Depth 6 -Compress}catch{$failure=$_;try{Merge-MaintenanceVaultPrivateStreams -Destination $privateLog -Sources $privateStreamLogs}catch{};try{$failure|Out-String|Add-Content -LiteralPath $privateLog}catch{};[ordered]@{status='FAIL';errorCategory=[string]$failure.CategoryInfo.Category;errorType=$failure.Exception.GetType().FullName;scriptLine=$failure.InvocationInfo.ScriptLineNumber;message='Configured Primary Vault prerequisite failed; no proof credit.'}|ConvertTo-Json -Compress;exit 1}finally{foreach($path in $privateStreamLogs){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
'@
        $body=$body.Replace('__REQUEST_PATH__',$remoteRequest.Replace("'","''")).Replace('__REQUEST_HASH__',[string]$requestStage.localSha256)
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
        $processRequest=[ordered]@{filePath='C:\Program Files\PowerShell\7\pwsh.exe';arguments=@('-NoProfile','-NonInteractive','-EncodedCommand',$encoded);deadlineUnixMilliseconds=[DateTimeOffset]::new($deadline).ToUnixTimeMilliseconds()}|ConvertTo-Json -Depth 4 -Compress
        $job=Invoke-Command -Session $session -ScriptBlock (Get-DevFleetBoundedProcessScriptBlock) -ArgumentList @($processRequest) -AsJob
        $remaining=[int][math]::Max(1,[math]::Ceiling(($deadline-[datetime]::UtcNow).TotalSeconds)+15)
        $finished=Wait-Job -Job $job -Timeout $remaining
        if(-not$finished){throw 'Vault prerequisite owner deadline expired before its terminal result.'}
        $process=@(Receive-Job -Job $job -ErrorAction Stop)|Select-Object -Last 1
        $evidencePath=Join-Path ([string]$Context.runDir) 'maintenance-vault-process.json'
        [IO.File]::WriteAllText($evidencePath,($process|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        if([string]$process.outcome-cne'PASS'-or-not[bool]$process.outputComplete){
            try{
                Save-MaintenanceVaultPrivateFailureEvidence -Session $session -RunId ([string]$Context.runId) -RemoteRoot $remoteRoot -WorkspaceRoot $workspace -RunDir ([string]$Context.runDir) -VmId ([guid][string]$Context.vmId)|Out-Null
            } catch {
                $preservationFailure=[ordered]@{schemaVersion=1;runId=[string]$Context.runId;classification='PRIVATE_FAILURE_EVIDENCE_PRESERVATION_FAILED';message='Private failure evidence could not be preserved from the owned disposable L1.';observedAtUtc=[datetime]::UtcNow.ToString('o')}
                [IO.File]::WriteAllText((Join-Path ([string]$Context.runDir) 'private-failure-preservation-error.json'),(($preservationFailure|ConvertTo-Json -Depth 4)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            }
            throw 'Configured Primary Vault bounded worker failed; see maintenance-vault-process.json.'
        }
        $result=[string]$process.stdout|ConvertFrom-Json -ErrorAction Stop
        Assert-MaintenanceVaultResult -Result $result -Request ([pscustomobject]$request)
        if([datetime]::UtcNow-gt$deadline){throw 'Vault prerequisite result arrived after its owner deadline.'}
        return $result
    } catch {$primaryError=$_;throw
    } finally {
        if($job){Stop-Job -Job $job -ErrorAction SilentlyContinue;Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
        try{if($stageAttempted-and$session){$removed=Remove-StagedTailscaleOAuthCredential -Session $session;if([string]$removed.status-cne'PASS'){throw 'Vault prerequisite OAuth cleanup failed.'}}}catch{if($primaryError){throw [InvalidOperationException]::new(($primaryError.Exception.Message+'; Vault prerequisite OAuth cleanup also failed.'),$primaryError.Exception)};throw}finally{if($session){Remove-DevFleetGuestSession -Session $session -ErrorAction SilentlyContinue}}
    }
}

Export-ModuleMember -Function Initialize-MaintenanceVaultFixture,Invoke-MaintenanceVaultProvisioning,Assert-MaintenanceVaultResult

```


## FILE: automation/release-e2e/modules/MultipassDiagnostic.psm1

SHA256: ba84f05ee27d9c6eedeaf7de9e7563c938b9a2c21d8111b332a62f07ed588aa4 | Bytes: 111666 | Git mode: 100644

```
Set-StrictMode -Version Latest

function ConvertTo-DevFleetDiagnosticSafeText {
    param([AllowNull()][object]$Value,[int]$MaximumCharacters=512)
    $text=[string]$Value
    if([string]::IsNullOrEmpty($text)){return ''}
    $text=[regex]::Replace($text,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    $text=[regex]::Replace($text,'(?i)\bBearer\s+\S+','Bearer <redacted>')
    $text=$text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',''
    if($MaximumCharacters -gt 0 -and $text.Length -gt $MaximumCharacters){$text=$text.Substring($text.Length-$MaximumCharacters)}
    return $text.Trim()
}

function ConvertTo-DevFleetWindowsProcessArgument {
    param([AllowEmptyString()][string]$Value)
    if($Value.Length-gt0-and$Value-notmatch'[\s"]'){return $Value}
    $builder=[Text.StringBuilder]::new()
    [void]$builder.Append([char]34)
    $slashes=0
    foreach($character in $Value.ToCharArray()){
        if([int]$character-eq92){$slashes++;continue}
        if([int]$character-eq34){for($i=0;$i-lt($slashes*2+1);$i++){[void]$builder.Append([char]92)};[void]$builder.Append([char]34);$slashes=0;continue}
        for($i=0;$i-lt$slashes;$i++){[void]$builder.Append([char]92)}
        $slashes=0;[void]$builder.Append($character)
    }
    for($i=0;$i-lt($slashes*2);$i++){[void]$builder.Append([char]92)}
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Get-DevFleetExistingFilePathSet {
    param([string[]]$CandidatePaths,[scriptblock]$PathExistsProvider)
    $found=[Collections.Generic.List[string]]::new()
    foreach($candidate in @($CandidatePaths)){
        if([string]::IsNullOrWhiteSpace([string]$candidate)){continue}
        $exists=if($PathExistsProvider){[bool](& $PathExistsProvider ([string]$candidate))}else{Test-Path -LiteralPath $candidate -PathType Leaf}
        if($exists){[void]$found.Add([IO.Path]::GetFullPath([string]$candidate))}
    }
    return @($found|Select-Object -Unique)
}

function Invoke-DevFleetBoundedNativeProbe {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList=@(),
        [ValidateRange(1,1800)][int]$TimeoutSeconds=30,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [int[]]$RedactArgumentIndexes=@(),
        [ValidateRange(512,1048576)][int]$MaxStdoutCharacters=4096,
        [ValidateRange(512,65536)][int]$MaxStderrCharacters=2048,
        [switch]$ForceLegacyArgumentString,
        [scriptblock]$ClockProvider
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}}
    $started=&$now
    $ownerDeadline=$OwnerDeadlineUtc.ToUniversalTime()
    $remaining=[int][math]::Floor(($ownerDeadline-$started).TotalSeconds)
    if($remaining -le 0){
        return [pscustomobject]@{operation=$Operation;outcome='OWNER_EXPIRED';exitCode=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=$started.ToString('o');deadlineUtc=$ownerDeadline.ToString('o');stdout='';stderr='Owning diagnostic deadline expired before probe start.';pid=$null;outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}
    }
    $operationDeadline=$started.AddSeconds([math]::Min($TimeoutSeconds,$remaining))
    $arguments=@($ArgumentList)
    $safeArguments=for($i=0;$i -lt $arguments.Count;$i++){if($RedactArgumentIndexes -contains $i){'<redacted>'}else{[string]$arguments[$i]}}
    $process=$null
    try {
        $psi=[Diagnostics.ProcessStartInfo]::new()
        $psi.FileName=$FilePath
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        if(-not$ForceLegacyArgumentString-and$psi.PSObject.Properties.Name-contains'ArgumentList'){
            foreach($argument in $arguments){[void]$psi.ArgumentList.Add([string]$argument)}
        } else {$psi.Arguments=(@($arguments|ForEach-Object{ConvertTo-DevFleetWindowsProcessArgument ([string]$_)})-join' ')}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
        if(-not $process.Start()){throw 'Native process start returned false.'}
        $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
        $waitMilliseconds=[int][math]::Max(1,[math]::Min([int]::MaxValue,[math]::Ceiling(($operationDeadline-(&$now)).TotalMilliseconds)))
        if(-not $process.WaitForExit($waitMilliseconds)){
            try{$process.Kill($true)}catch{try{& (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID ([string]$process.Id) /T /F 2>$null|Out-Null}catch{try{$process.Kill()}catch{}}}
            try{[void]$process.WaitForExit(5000)}catch{}
            try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
            $finished=&$now
            return [pscustomobject]@{operation=$Operation;outcome='TIMEOUT';exitCode=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$operationDeadline.ToString('o');stdout='';stderr="Native probe exceeded its inherited finite deadline: $FilePath $($safeArguments -join ' ')";pid=$process.Id;outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}
        }
        $exitCode=$process.ExitCode
        $drained=$false
        try{$drained=[Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5))}catch{$drained=$false}
        $stdout=if($drained -and $stdoutTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdoutTask.GetAwaiter().GetResult()}else{''}
        $stderr=if($drained -and $stderrTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderrTask.GetAwaiter().GetResult()}else{'Redirected output did not drain within the bounded post-exit margin.'}
        $finished=&$now
        return [pscustomobject]@{operation=$Operation;outcome=if(-not$drained){'DRAIN_INCOMPLETE'}elseif($exitCode -eq 0){'PASS'}else{'NONZERO'};exitCode=$exitCode;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$operationDeadline.ToString('o');stdout=(ConvertTo-DevFleetDiagnosticSafeText $stdout $MaxStdoutCharacters);stderr=(ConvertTo-DevFleetDiagnosticSafeText $stderr $MaxStderrCharacters);pid=$process.Id;outputComplete=$drained;stdoutTruncated=([string]$stdout).Length-gt$MaxStdoutCharacters;stderrTruncated=([string]$stderr).Length-gt$MaxStderrCharacters}
    } catch {
        $finished=&$now
        return [pscustomobject]@{operation=$Operation;outcome='START_FAILED';exitCode=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$operationDeadline.ToString('o');stdout='';stderr=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message);pid=if($process-and-not$process.HasExited){$process.Id}else{$null};outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}
    } finally {
        if($process){$process.Dispose()}
    }
}

function Assert-DevFleetCampaignEArchiveEntries {
    param(
        [Parameter(Mandatory)][string[]]$Entries,
        [string[]]$RequiredEntries=@('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json','windows/DevFleet.Common.psm1')
    )
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($raw in @($Entries)){
        $entry=([string]$raw).Trim().Replace('\','/')
        if([string]::IsNullOrWhiteSpace($entry)){continue}
        if($entry.StartsWith('/')-or$entry-match'^[A-Za-z]:'-or$entry.Contains([char]0)){throw "Candidate archive entry escapes the package root: $entry"}
        $segments=@($entry.Split('/')|Where-Object{$_-ne''})
        if($segments.Count-eq0-or@($segments|Where-Object{$_-eq'..'-or$_-eq'.'}).Count){throw "Candidate archive entry is not a canonical relative path: $entry"}
        $canonical=$segments-join'/'
        if(-not$seen.Add($canonical)){throw "Candidate archive contains a duplicate path: $canonical"}
    }
    foreach($required in @($RequiredEntries)){
        if(-not$seen.Contains($required)){throw "Candidate archive is missing required prerequisite input: $required"}
    }
    return $true
}

function Get-DevFleetCampaignEPrerequisitePlan {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [ValidateSet('Desktop','Laptop')][string]$Role='Desktop'
    )
    $root=(Resolve-Path -LiteralPath $PackageRoot).Path
    $versionPath=Join-Path $root 'VERSION'
    $manifestPath=Join-Path $root 'dependencies.json'
    $configPath=Join-Path $root 'config\devfleet.config.json'
    foreach($path in @($versionPath,$manifestPath,$configPath,(Join-Path $root 'Bootstrap-Install.ps1'),(Join-Path $root 'Install-DevFleet.ps1'),(Join-Path $root 'windows\DevFleet.Common.psm1'))){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Candidate prerequisite input is missing: $path"}}
    $version=(Get-Content -LiteralPath $versionPath -Raw).Trim()
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -ErrorAction Stop
    $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -ErrorAction Stop
    if([int]$manifest.schemaVersion-ne1-or[string]$manifest.manifestVersion-cne$version){throw 'Candidate dependency manifest schema/version mismatch.'}
    if([int]$config.SchemaVersion-ne2-or[string]$config.PackageVersion-cne$version){throw 'Candidate configuration schema/version mismatch.'}
    $selected=[ordered]@{}
    foreach($id in @('powershell7','multipass')){
        $matches=@($manifest.dependencies|Where-Object{[string]$_.id-ceq$id})
        if($matches.Count-ne1){throw "Candidate dependency identity must be unique: $id"}
        $dependency=$matches[0]
        if(-not[bool]$dependency.required-or@($dependency.roles|ForEach-Object{[string]$_})-cnotcontains$Role){throw "Candidate dependency is not required for role ${Role}: $id"}
        if([string]$dependency.minimumSupportedVersion-notmatch'^\d+\.\d+\.\d+$'-or[Version]$dependency.minimumSupportedVersion-le[Version]'0.0.0'){throw "Candidate dependency minimum version is invalid: $id"}
        $selected[$id]=[ordered]@{id=$id;minimumSupportedVersion=[string]$dependency.minimumSupportedVersion;maximumMajor=$dependency.maximumMajor;wingetPackageId=[string]$dependency.wingetPackageId;resolverType=[string]$dependency.directOfficialVendorResolver.type;allowedSignerSubjectsExact=@($dependency.installerAuthenticityPolicy.allowedSignerSubjectsExact|ForEach-Object{[string]$_})}
    }
    if([string]$selected.powershell7.wingetPackageId-cne'Microsoft.PowerShell'-or[string]$selected.multipass.wingetPackageId-cne'Canonical.Multipass'){throw 'Candidate prerequisite package mapping is unsupported.'}
    $names=@([string]$config.Primary.InstanceName,[string]$config.Failover.InstanceName,[string]$config.Vault.InstanceName)
    if($names.Count-ne3-or@($names|Where-Object{$_-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'}).Count-or@($names|Select-Object -Unique).Count-ne3){throw 'Candidate product instance identities are invalid.'}
    [pscustomobject][ordered]@{
        schemaVersion=1;role=$Role;packageVersion=$version;dependencyIds=@('powershell7','multipass');expectedBackend='hyperv';privilegedMounts=$false
        ubuntuImage=[string]$config.Primary.UbuntuImage;candidateInstanceNames=$names
        inputHashes=[ordered]@{
            version=(Get-FileHash -LiteralPath $versionPath -Algorithm SHA256).Hash.ToLowerInvariant()
            dependencies=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
            config=(Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
            bootstrap=(Get-FileHash -LiteralPath (Join-Path $root 'Bootstrap-Install.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
            install=(Get-FileHash -LiteralPath (Join-Path $root 'Install-DevFleet.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
            common=(Get-FileHash -LiteralPath (Join-Path $root 'windows\DevFleet.Common.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        dependencies=$selected
    }
}

function Invoke-DevFleetCampaignEPowerShellAcquisition {
    param(
        [Parameter(Mandatory)][psobject]$Dependency,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [Parameter(Mandatory)][scriptblock]$TrustedWingetCandidateProvider,
        [Parameter(Mandatory)][scriptblock]$NativeProbeProvider,
        [Parameter(Mandatory)][scriptblock]$PowerShellCompatibilityProvider,
        [scriptblock]$ClockProvider
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}}
    $owner=$OwnerDeadlineUtc.ToUniversalTime()
    $started=&$now
    if($owner-le$started){throw 'Campaign E PowerShell acquisition owner deadline expired before compatibility inspection.'}
    if([string]$Dependency.id-cne'powershell7'-or[string]$Dependency.wingetPackageId-cne'Microsoft.PowerShell'){throw 'Campaign E PowerShell acquisition package identity is unsupported.'}
    if([string]$Dependency.minimumSupportedVersion-notmatch'^\d+\.\d+\.\d+$'-or[Version][string]$Dependency.minimumSupportedVersion-le[Version]'0.0.0'){throw 'Campaign E PowerShell acquisition minimum version is invalid.'}
    if($null-eq$Dependency.maximumMajor-or[int]$Dependency.maximumMajor-ne7){throw 'Campaign E PowerShell acquisition maximum-major policy is invalid.'}

    $validateCompatibility={
        param($Status)
        if($null-eq$Status){throw 'Campaign E PowerShell compatibility provider returned no observation.'}
        if([string]$Status.status-cne'Compatible'){return $false}
        $version=[Version][string]$Status.version
        if($version-lt[Version][string]$Dependency.minimumSupportedVersion-or$version.Major-gt[int]$Dependency.maximumMajor){throw 'Campaign E PowerShell compatibility result violates the candidate version policy.'}
        if([string]$Status.pathSha256-notmatch'^[0-9a-f]{64}$'){throw 'Campaign E PowerShell compatibility result lacks an exact executable hash.'}
        return $true
    }
    $initial=&$PowerShellCompatibilityProvider $Dependency $owner
    if(&$validateCompatibility $initial){
        $preservedFinished=&$now
        if($preservedFinished-gt$owner){throw 'Campaign E PowerShell compatibility observation completed after its immutable owner deadline.'}
        return [pscustomobject][ordered]@{
            schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='PRESERVED_CANDIDATE_COMPATIBLE'
            packageId=[string]$Dependency.wingetPackageId;startedAtUtc=$started.ToString('o');finishedAtUtc=$preservedFinished.ToString('o');ownerDeadlineUtc=$owner.ToString('o')
            wingetPathSha256='';operations=@();powershell=[pscustomobject]@{status='Compatible';version=[string]$initial.version;pathSha256=[string]$initial.pathSha256}
            productLifecycleStarted=$false;stageMarkerWritten=$false
        }
    }

    $candidates=@(&$TrustedWingetCandidateProvider $Dependency)
    if($candidates.Count-ne1){throw 'Campaign E PowerShell acquisition requires exactly one candidate-trusted physical WinGet executable.'}
    $candidate=$candidates[0]
    if(-not[bool]$candidate.trustValidated){throw 'Campaign E PowerShell acquisition rejected an unvalidated WinGet candidate.'}
    $wingetPath=[IO.Path]::GetFullPath([string]$candidate.path)
    $wingetRoot=[IO.Path]::GetFullPath([string]$candidate.root).TrimEnd('\')
    if(-not[IO.Path]::GetFileName($wingetPath).Equals('winget.exe',[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetDirectoryName($wingetPath).TrimEnd('\').Equals($wingetRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Campaign E PowerShell acquisition WinGet path/root identity is invalid.'}
    if(-not(Test-Path -LiteralPath $wingetPath -PathType Leaf)){throw 'Campaign E PowerShell acquisition WinGet executable is absent.'}
    $wingetHash=(Get-FileHash -LiteralPath $wingetPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $specifications=@(
        [pscustomobject]@{operation='winget-version';arguments=@('--version');seconds=60;allowAlreadySatisfied=$false;requirePackageId=$false},
        [pscustomobject]@{operation='winget-source-list';arguments=@('source','list','--disable-interactivity');seconds=60;allowAlreadySatisfied=$false;requirePackageId=$false},
        [pscustomobject]@{operation='winget-source-update';arguments=@('source','update','--name','winget','--disable-interactivity');seconds=300;allowAlreadySatisfied=$false;requirePackageId=$false},
        [pscustomobject]@{operation='winget-powershell-search';arguments=@('search','--id',[string]$Dependency.wingetPackageId,'--exact','--source','winget','--disable-interactivity');seconds=90;allowAlreadySatisfied=$false;requirePackageId=$true},
        [pscustomobject]@{operation='winget-powershell-install';arguments=@('install','--id',[string]$Dependency.wingetPackageId,'--exact','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity');seconds=900;allowAlreadySatisfied=$true;requirePackageId=$false}
    )
    $observations=[Collections.Generic.List[object]]::new()
    $lastFinished=$started
    foreach($specification in $specifications){
        $observed=&$now
        $remaining=[int][math]::Floor(($owner-$observed).TotalSeconds)
        if($remaining-le0){throw "Campaign E PowerShell acquisition owner deadline expired before $([string]$specification.operation)."}
        $raw=&$NativeProbeProvider ([string]$specification.operation) $wingetPath ([string[]]$specification.arguments) ([math]::Min([int]$specification.seconds,$remaining)) $owner
        if($null-eq$raw-or[string]$raw.operation-cne[string]$specification.operation){throw "Campaign E PowerShell acquisition received a mismatched native observation for $([string]$specification.operation)."}
        $rawStarted=([datetime]$raw.startedAtUtc).ToUniversalTime();$rawFinished=([datetime]$raw.finishedAtUtc).ToUniversalTime();$rawDeadline=([datetime]$raw.deadlineUtc).ToUniversalTime()
        if($rawStarted-lt$observed-or$rawStarted-lt$lastFinished-or$rawFinished-lt$rawStarted-or$rawFinished-gt$owner-or$rawDeadline-gt$owner){throw "Campaign E PowerShell acquisition received an out-of-deadline or nonmonotonic native observation for $([string]$specification.operation)."}
        $accepted=[string]$raw.outcome-ceq'PASS'
        if([bool]$specification.allowAlreadySatisfied-and[string]$raw.outcome-ceq'NONZERO'-and[int]$raw.exitCode-eq-1978335189){$accepted=$true}
        if(-not$accepted-or-not[bool]$raw.outputComplete){throw "Campaign E PowerShell acquisition operation failed: $([string]$specification.operation) / $([string]$raw.outcome) / $([string]$raw.exitCode)."}
        if([string]$specification.operation-ceq'winget-version'-and[string]$raw.stdout-notmatch'(?<!\d)\d+\.\d+(?:\.\d+){0,2}'){throw 'Campaign E PowerShell acquisition could not parse the bounded WinGet version response.'}
        if([bool]$specification.requirePackageId-and[string]$raw.stdout-notmatch[regex]::Escape([string]$Dependency.wingetPackageId)){throw 'Campaign E PowerShell acquisition search did not identify the exact manifest-approved package.'}
        [void]$observations.Add([pscustomobject][ordered]@{operation=[string]$raw.operation;outcome=[string]$raw.outcome;exitCode=$raw.exitCode;startedAtUtc=[string]$raw.startedAtUtc;finishedAtUtc=[string]$raw.finishedAtUtc;deadlineUtc=[string]$raw.deadlineUtc;outputComplete=[bool]$raw.outputComplete;packageIdentityObserved=if([bool]$specification.requirePackageId){$true}else{$null}})
        $lastFinished=$rawFinished
    }
    $final=&$PowerShellCompatibilityProvider $Dependency $owner
    if(-not(&$validateCompatibility $final)){throw 'Campaign E PowerShell acquisition completed without a candidate-compatible PowerShell executable.'}
    $finished=&$now
    if($finished-gt$owner){throw 'Campaign E PowerShell acquisition completed after its immutable owner deadline.'}
    return [pscustomobject][ordered]@{
        schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='WINGET_MANIFEST_APPROVED_DIAGNOSTIC'
        packageId=[string]$Dependency.wingetPackageId;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');ownerDeadlineUtc=$owner.ToString('o')
        wingetPathSha256=$wingetHash;operations=@($observations);powershell=[pscustomobject]@{status='Compatible';version=[string]$final.version;pathSha256=[string]$final.pathSha256}
        productLifecycleStarted=$false;stageMarkerWritten=$false
    }
}

function Test-DevFleetCampaignEExactSignerSubject {
    param([Parameter(Mandatory)][string]$Actual,[Parameter(Mandatory)][string[]]$Expected)
    $normalize={param([string]$Value)try{(([Security.Cryptography.X509Certificates.X500DistinguishedName]::new($Value)).Format($false)-replace'\s','').ToUpperInvariant()}catch{($Value-replace'\s','').ToUpperInvariant()}}
    $actualNormalized=&$normalize $Actual
    return @($Expected|Where-Object{(&$normalize ([string]$_))-ceq$actualNormalized}).Count-eq1
}

function Save-DevFleetCampaignEAllowlistedHttpsDownload {
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][string[]]$AllowedHosts,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [ValidateRange(60,1200)][int]$MaximumSeconds=900
    )
    $started=[datetime]::UtcNow;$owner=$OwnerDeadlineUtc.ToUniversalTime();$deadline=$started.AddSeconds($MaximumSeconds);if($deadline-gt$owner){$deadline=$owner}
    if($deadline-le$started){throw 'Campaign E official download owner deadline expired before transfer.'}
    if(Test-Path -LiteralPath $Path){throw 'Campaign E official download destination already exists.'}
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp";$current=$Uri;$redirectHosts=[Collections.Generic.List[string]]::new()
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false;$client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[Threading.Timeout]::InfiniteTimeSpan
    try {
        for($hop=0;$hop-le5;$hop++){
            if($current.Scheme-cne'https'-or$current.UserInfo-or@($AllowedHosts)-cnotcontains$current.Host){throw 'Campaign E official download left the allowlisted HTTPS boundary.'}
            [void]$redirectHosts.Add($current.Host)
            $remaining=($deadline-[datetime]::UtcNow)
            if($remaining.TotalMilliseconds-le0){throw 'Campaign E official download exceeded its inherited finite deadline.'}
            $cts=[Threading.CancellationTokenSource]::new($remaining);$response=$null;$input=$null;$output=$null
            try {
                $response=$client.GetAsync($current,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cts.Token).GetAwaiter().GetResult()
                if([int]$response.StatusCode-ge300-and[int]$response.StatusCode-le399){$location=$response.Headers.Location;if(-not$location){throw 'Campaign E official download redirect omitted Location.'};$current=[uri]::new($current,$location);continue}
                if(-not$response.IsSuccessStatusCode){throw "Campaign E official download failed with HTTP $([int]$response.StatusCode)."}
                $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult();$output=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                [void]$input.CopyToAsync($output,81920,$cts.Token).GetAwaiter().GetResult();$output.Flush($true);$output.Dispose();$output=$null
                [IO.File]::Move($temporary,$Path)
                $finished=[datetime]::UtcNow
                return [pscustomobject][ordered]@{outcome='PASS';startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$deadline.ToString('o');finalHost=$current.Host;redirectHosts=@($redirectHosts);bytes=(Get-Item -LiteralPath $Path).Length;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
            } finally {if($output){$output.Dispose()};if($input){$input.Dispose()};if($response){$response.Dispose()};$cts.Dispose()}
        }
        throw 'Campaign E official download exceeded the redirect limit.'
    } finally {$client.Dispose();$handler.Dispose();Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}

function Get-DevFleetCampaignEOfficialPowerShellPayload {
    param(
        [Parameter(Mandatory)][psobject]$Dependency,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [scriptblock]$MetadataProvider,
        [scriptblock]$DownloadProvider,
        [scriptblock]$AuthenticityProvider,
        [scriptblock]$ClockProvider
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}};$started=&$now;$owner=$OwnerDeadlineUtc.ToUniversalTime()
    if($owner-le$started){throw 'Campaign E official PowerShell acquisition owner deadline expired before metadata.'}
    if([string]$Dependency.id-cne'powershell7'-or[string]$Dependency.wingetPackageId-cne'Microsoft.PowerShell'-or[string]$Dependency.directOfficialVendorResolver.type-cne'github-release'){throw 'Campaign E official PowerShell dependency identity/resolver is unsupported.'}
    $resolver=$Dependency.directOfficialVendorResolver;$metadataUri=[uri][string]$resolver.metadataUri
    if($metadataUri.Scheme-cne'https'-or$metadataUri.UserInfo-or$metadataUri.AbsolutePath-cne'/repos/PowerShell/PowerShell/releases/latest'-or@($resolver.allowedHosts)-cnotcontains$metadataUri.Host){throw 'Campaign E official PowerShell metadata identity is invalid.'}
    $remaining=[int][math]::Floor(($owner-(&$now)).TotalSeconds);if($remaining-le0){throw 'Campaign E official PowerShell acquisition owner deadline expired before metadata request.'}
    $metadata=if($MetadataProvider){&$MetadataProvider $metadataUri ([math]::Min(60,$remaining)) $owner}else{Invoke-RestMethod -UseBasicParsing -TimeoutSec ([math]::Min(60,$remaining)) -Uri $metadataUri -Headers @{'User-Agent'='DevFleet-Campaign-E/1.2.13'}}
    $metadataFinished=&$now
    if($metadataFinished-gt$owner){throw 'Campaign E official PowerShell metadata arrived after the immutable owner deadline.'}
    if(-not$metadata-or[bool]$metadata.prerelease-or[bool]$metadata.draft-or[string]$metadata.tag_name-notmatch'^v7\.\d+\.\d+$'){throw 'Campaign E official PowerShell release metadata is unusable.'}
    $releasePage=[uri][string]$metadata.html_url
    if($releasePage.Scheme-cne'https'-or$releasePage.Host-cne'github.com'-or-not$releasePage.AbsolutePath.StartsWith('/PowerShell/PowerShell/releases/tag/',[StringComparison]::Ordinal)){throw 'Campaign E official PowerShell release repository identity mismatch.'}
    $assets=@($metadata.assets|Where-Object{[string]$_.name-match[string]$resolver.assetRegex})
    if($assets.Count-ne1){throw 'Campaign E official PowerShell release did not contain one canonical x64 MSI.'}
    $asset=$assets[0];$assetName=[string]$asset.name;$assetUri=[uri][string]$asset.browser_download_url
    $expectedPathPrefix="/PowerShell/PowerShell/releases/download/$([string]$metadata.tag_name)/"
    if($assetUri.Scheme-cne'https'-or$assetUri.UserInfo-or@($resolver.allowedHosts)-cnotcontains$assetUri.Host-or-not$assetUri.AbsolutePath.StartsWith($expectedPathPrefix,[StringComparison]::Ordinal)-or[IO.Path]::GetFileName($assetUri.AbsolutePath)-cne$assetName-or[IO.Path]::GetExtension($assetName)-cne'.msi'){throw 'Campaign E official PowerShell asset identity is invalid.'}
    $destinationRoot=[IO.Path]::GetFullPath($DestinationDirectory).TrimEnd('\');if(-not(Test-Path -LiteralPath $destinationRoot -PathType Container)){throw 'Campaign E official PowerShell destination root is absent.'}
    $DestinationPath=Join-Path $destinationRoot $assetName
    if(Test-Path -LiteralPath $DestinationPath){throw 'Campaign E official PowerShell destination already exists and will not be overwritten.'}
    $download=if($DownloadProvider){&$DownloadProvider $assetUri @($resolver.allowedHosts) $DestinationPath $owner}else{Save-DevFleetCampaignEAllowlistedHttpsDownload -Uri $assetUri -AllowedHosts @($resolver.allowedHosts) -Path $DestinationPath -OwnerDeadlineUtc $owner}
    if($null-eq$download-or[string]$download.outcome-cne'PASS'-or-not(Test-Path -LiteralPath $DestinationPath -PathType Leaf)-or[int64]$download.bytes-lt1-or[string]$download.sha256-notmatch'^[0-9a-f]{64}$'-or(Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$download.sha256){throw 'Campaign E official PowerShell download evidence is invalid.'}
    $downloadStarted=([datetime]$download.startedAtUtc).ToUniversalTime();$downloadFinished=([datetime]$download.finishedAtUtc).ToUniversalTime();$downloadDeadline=([datetime]$download.deadlineUtc).ToUniversalTime();$redirectHosts=@($download.redirectHosts)
    if($downloadStarted-lt$metadataFinished-or$downloadFinished-lt$downloadStarted-or$downloadFinished-gt$owner-or$downloadDeadline-gt$owner-or$redirectHosts.Count-lt1-or@($redirectHosts|Where-Object{@($resolver.allowedHosts)-cnotcontains[string]$_}).Count){throw 'Campaign E official PowerShell download deadline/redirect evidence is invalid.'}
    $authenticity=if($AuthenticityProvider){&$AuthenticityProvider $DestinationPath $Dependency.installerAuthenticityPolicy}else{$signature=Get-AuthenticodeSignature -LiteralPath $DestinationPath;[pscustomobject]@{status=$signature.Status.ToString();signerSubject=if($signature.SignerCertificate){$signature.SignerCertificate.Subject}else{''}}}
    if([string]$authenticity.status-cne'Valid'-or-not(Test-DevFleetCampaignEExactSignerSubject -Actual ([string]$authenticity.signerSubject) -Expected @($Dependency.installerAuthenticityPolicy.allowedSignerSubjectsExact))){throw 'Campaign E official PowerShell payload signer identity is invalid.'}
 