# DevFleet source part 046

Full-source UTF-8 byte interval [2092500, 2139000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 54335c3e22916452e8344971f3d7336d6413678a2e647debcb5af9882f1b981a

<!-- BEGIN SOURCE SLICE -->
$initializer[0].Extent.Text))
        $request.packageRoot=$temp;$request.workRoot=Join-Path $temp 'work'
        $result=Invoke-MaintenanceVaultProvisioning -Request ([pscustomobject]$request)
        if($result.status-cne'PASS'-or-not$script:stdinDelivered-or($script:steps-join ',')-cne'list,transfer,exec,exec'){throw 'Native fixture steps did not complete the exact setup path'}
        $pairingOrder=@(Get-Content -LiteralPath $env:DEVFLEET_MAINTENANCE_TEST_TRACE)
        if(($pairingOrder-join ',')-cne'windows-host,guest:devfleet-vault,client:devfleet-primary'){throw ('Maintenance Vault pairing order is unsafe: '+($pairingOrder-join ','))}
        [ordered]@{status='PASS';realStepBodies=$true;realHostRequest=$true;realProductBootstrapBoundary=$true;externalIoMocked=$true;vmMutation=$false;steps=@($script:steps)}|ConvertTo-Json
    } $temp $WorkspaceRoot
} finally {$env:COMPUTERNAME=$oldComputer;$env:DEVFLEET_MAINTENANCE_TEST_TRACE=$oldTrace}

```


## FILE: automation/release-e2e/tests/Test-MaintenanceVaultPrivateFailurePreservation.ps1

SHA256: 746ecef5996014ef9f032b2532db9a27ca901b42d80cf33a5e7aaa59303f4598 | Bytes: 3865 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$modulePath=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/MaintenanceVault.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$module=Get-Module MaintenanceVault
$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-private-preservation-'+[guid]::NewGuid().ToString('N'))
$runDir=Join-Path $temp 'run'
$controlRoot=Join-Path $temp 'control'
[IO.Directory]::CreateDirectory($runDir)|Out-Null
[IO.Directory]::CreateDirectory($controlRoot)|Out-Null
$plain=[Text.Encoding]::UTF8.GetBytes("PRIVATE_TEST_EXCEPTION``nPRIVATE_STREAM_WARNING``n")
$runId='fullrelease-private-preservation-unit'
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$sourcePath='C:\ProgramData\DevFleet\tmp\maintenance-vault-unit\private-product-operations.log'
try{
    $metadata=& $module {
        param($bytes,$runId,$vmId,$sourcePath,$workspace,$runDir,$controlRoot)
        Protect-MaintenanceVaultPrivateFailureBytes -Plaintext $bytes -RunId $runId -VmId $vmId -SourcePath $sourcePath -WorkspaceRoot $workspace -RunDir $runDir -ControlRoot $controlRoot
    } $plain $runId $vmId $sourcePath $WorkspaceRoot $runDir $controlRoot
    if(-not$metadata.roundTripVerified-or$metadata.plaintextWrittenToHost-or$metadata.plaintextIncludedInAudit){throw 'DPAPI preservation metadata is not fail-closed.'}
    if([string]$metadata.encryption-cne'Windows DPAPI CurrentUser'){throw 'Unexpected private evidence encryption contract.'}
    $encryptedPath=[string]$metadata.encryptedLocalPath
    if(-not(Test-Path -LiteralPath $encryptedPath -PathType Leaf)){throw 'Encrypted private evidence file was not created.'}
    $encrypted=[IO.File]::ReadAllBytes($encryptedPath)
    if([Text.Encoding]::UTF8.GetString($encrypted)-match'PRIVATE_TEST_EXCEPTION'){throw 'Encrypted evidence contains plaintext marker.'}
    Add-Type -AssemblyName System.Security
    $entropy=[Text.Encoding]::UTF8.GetBytes("DevFleet exact failure evidence $runId")
    $round=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try{
        if([Text.Encoding]::UTF8.GetString($round)-cne[Text.Encoding]::UTF8.GetString($plain)){throw 'Independent DPAPI round-trip differs.'}
    } finally {if($round){[Array]::Clear($round,0,$round.Length)};if($entropy){[Array]::Clear($entropy,0,$entropy.Length)};if($encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}}
    $metadataPath=Join-Path $runDir 'private-failure-preservation.json'
    $persisted=Get-Content -LiteralPath $metadataPath -Raw|ConvertFrom-Json
    if(-not[bool]$persisted.roundTripVerified-or[string]$persisted.sourceVmId-cne$vmId.ToString()){throw 'Persisted preservation metadata is incomplete.'}
    if(Test-Path -LiteralPath (Join-Path $runDir 'private-product-operations.log')){throw 'Plaintext private log was written into run evidence.'}
    $source=Get-Content -LiteralPath $modulePath -Raw
    $call=$source.IndexOf('Save-MaintenanceVaultPrivateFailureEvidence -Session $session')
    $throw=$source.IndexOf("throw 'Configured Primary Vault bounded worker failed; see maintenance-vault-process.json.'",$call)
    if($call-lt0-or$throw-le$call){throw 'Failure branch does not preserve private evidence before public failure.'}
    if($source.IndexOf('maintenance-vault-windows-tailscale-preflight.json')-lt0){throw 'Sanitized Windows Tailscale pre-Vault telemetry is missing.'}
    [ordered]@{status='PASS';cases=7;dpapiRoundTrip=$true;plaintextHostFile=$false;preserveBeforeThrow=$true;tailscaleTelemetry=$true;vmMutation=$false}|ConvertTo-Json -Depth 4
} finally {
    if($plain){[Array]::Clear($plain,0,$plain.Length)}
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}

```


## FILE: automation/release-e2e/tests/Test-MaintenanceVaultScenarioBinding.ps1

SHA256: 2a62ceead9e4bebf83027d592c57583f37b7075896ef54169b1969199db2409e | Bytes: 2382 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Raw
$start=$source.IndexOf("            if(`$scenario-in@('permanent-delete','delete-restore','vault')){")
$end=$source.IndexOf('            $runId=[string]$runId;', $start)
if($start-lt0-or$end-le$start){throw 'Real configured-scenario guard was not found.'}
$guard=[scriptblock]::Create($source.Substring($start,$end-$start))
$scenario='permanent-delete';$primary='devfleet-primary';$mp='mock-external-multipass';$expectedTarHash='a'*64
$config=[pscustomobject]@{Vault=[pscustomobject]@{InstanceName='devfleet-vault'}}
$hostIdentity=[pscustomobject]@{deployment_id='33333333-3333-3333-3333-333333333333'}
$script:readinessCalls=[Collections.Generic.List[string]]::new();$script:wrongId=$false
$readinessSource='param($Primary,$MultipassPath);$script:readinessCalls.Add($Primary);[pscustomobject]@{status="PASS"}'
function Get-VM {param([guid]$Id,$ErrorAction) [pscustomobject]@{Id=$Id;Name=if($script:wrongId){'foreign'}elseif($Id.ToString()-eq'11111111-1111-1111-1111-111111111111'){'devfleet-primary'}else{'devfleet-vault'}}}
$fixture=[ordered]@{status='PASS';payloadSha256=$expectedTarHash;primaryRole='primary';primaryName=$primary;primaryId='11111111-1111-1111-1111-111111111111';vaultName='devfleet-vault';vaultId='22222222-2222-2222-2222-222222222222';deploymentId=$hostIdentity.deployment_id;configurationPresent=$true;proofCredit=$false}
$vaultFixtureJson=$fixture|ConvertTo-Json -Compress
. $guard
if($primary-cne'devfleet-primary'-or($script:readinessCalls-join ',')-cne'devfleet-vault'){throw 'Vault readiness changed the Primary scenario target.'}
$script:wrongId=$true;$caught='';$script:readinessCalls.Clear()
try{. $guard}catch{$caught=$_.Exception.Message}
if($caught-notmatch'immutable identity'-or$script:readinessCalls.Count-ne0){throw 'Changed VM identity must be rejected before readiness mutation.'}
$script:wrongId=$false;$vaultFixtureJson='';$caught=''
try{. $guard}catch{$caught=$_.Exception.Message}
if($caught-notmatch'configured checkpoint'){throw 'Unconfigured positive scenario did not refuse.'}
[ordered]@{status='PASS';cases=3;actualScenarioGuard=$true;externalIoMocked=$true;vmMutation=$false}|ConvertTo-Json

```


## FILE: automation/release-e2e/tests/Test-MaintenanceVaultWrapperStreams.ps1

SHA256: c1b941de50dbbe3388c1e0e8f8779e8144eb2c25c054b1152385f30c8bff94ee | Bytes: 7778 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'

$modulePath=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/MaintenanceVault.psm1'
$tokens=$null
$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count-ne0){throw "MaintenanceVault parse failed: $($parseErrors[0].Message)"}
$wrapperStrings=@($ast.FindAll({
    param($node)
    $node-is[Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Value-match'private-product-operations\.log' -and
        $node.Value-match'Invoke-MaintenanceVaultProvisioning -Request \$request'
},$true))
if($wrapperStrings.Count-ne1){throw 'Generated Maintenance Vault wrapper body is missing or ambiguous.'}
$wrapperLines=@($wrapperStrings[0].Value -split "`r?`n")
$start=-1
$end=-1
for($i=0;$i-lt$wrapperLines.Count;$i++){
    if($start-lt0-and$wrapperLines[$i]-match'^\$privateLog='){$start=$i}
    if($start-ge0-and$wrapperLines[$i]-match'^try\{\$result=Invoke-MaintenanceVaultProvisioning'){$end=$i;break}
}
if($start-lt0-or$end-lt$start){throw 'Generated Maintenance Vault private-stream wrapper segment is missing.'}
$wrapperSegment=($wrapperLines[$start..$end]-join[Environment]::NewLine)

$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-vault-wrapper-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
try{
    function Invoke-WrapperCase {
        param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][bool]$ThrowProvisioning)
        $caseRoot=Join-Path $temp $Name
        [IO.Directory]::CreateDirectory($caseRoot)|Out-Null
        $entryPath=Join-Path $caseRoot 'provisioning-entered.txt'
        $childPath=Join-Path $caseRoot 'wrapper-child.ps1'
        $child=@'
param([Parameter(Mandatory)][string]$WorkRoot,[Parameter(Mandatory)][string]$EntryPath,[Parameter(Mandatory)][string]$Mode)
$ErrorActionPreference='Stop'
$request=[pscustomobject]@{workRoot=$WorkRoot;entryPath=$EntryPath;throwProvisioning=($Mode-ceq'throw')}
function Invoke-MaintenanceVaultProvisioning {
    param([Parameter(Mandatory)]$Request)
    [IO.File]::WriteAllText([string]$Request.entryPath,'ENTERED',[Text.UTF8Encoding]::new($false))
    Write-Warning 'PRIVATE_STREAM_WARNING' -WarningAction Continue
    Write-Verbose 'PRIVATE_STREAM_VERBOSE' -Verbose
    Write-Debug 'PRIVATE_STREAM_DEBUG' -Debug
    Write-Information 'PRIVATE_STREAM_INFORMATION' -InformationAction Continue
    if([bool]$Request.throwProvisioning){throw [InvalidOperationException]::new('PRIVATE_ORIGINAL_PROVISIONING_EXCEPTION')}
    [pscustomobject][ordered]@{status='PASS';contract='maintenance-vault-wrapper-stream-test'}
}
'@
        [IO.File]::WriteAllText($childPath,($child+[Environment]::NewLine+$wrapperSegment),[Text.UTF8Encoding]::new($false))
        $pwsh=(Get-Command pwsh -CommandType Application -ErrorAction Stop).Source
        $psi=[Diagnostics.ProcessStartInfo]::new()
        $psi.FileName=$pwsh
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$childPath,'-WorkRoot',$caseRoot,'-EntryPath',$entryPath,'-Mode',$(if($ThrowProvisioning){'throw'}else{'pass'}))){[void]$psi.ArgumentList.Add($argument)}
        $process=[Diagnostics.Process]::new()
        $process.StartInfo=$psi
        if(-not$process.Start()){throw 'Could not start local PowerShell 7 wrapper regression child.'}
        $stdout=$process.StandardOutput.ReadToEnd()
        $stderr=$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $privateLogs=@(Get-ChildItem -LiteralPath $caseRoot -Filter 'private-product-operations*.log' -File -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            name=$Name
            exitCode=$process.ExitCode
            stdout=$stdout.Trim()
            stderr=$stderr.Trim()
            provisioningEntered=(Test-Path -LiteralPath $entryPath -PathType Leaf)
            privateLogCount=$privateLogs.Count
            privateLogNames=@($privateLogs.Name)
            privateContent=(@($privateLogs|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw})-join[Environment]::NewLine)
        }
    }

    $success=Invoke-WrapperCase -Name success -ThrowProvisioning $false
    $failure=Invoke-WrapperCase -Name exception -ThrowProvisioning $true
    $successJson=$null
    $failureJson=$null
    try{$successJson=$success.stdout|ConvertFrom-Json -ErrorAction Stop}catch{}
    try{$failureJson=$failure.stdout|ConvertFrom-Json -ErrorAction Stop}catch{}

    if($success.exitCode-ne0-and-not$success.provisioningEntered-and
        [string]$successJson.errorCategory-ceq'OpenError'-and
        [string]$successJson.errorType-ceq'System.IO.IOException'){
        throw 'RED_REPRODUCED: duplicate same-file stream redirection raised OpenError/System.IO.IOException before provisioning entry.'
    }
    if($success.exitCode-ne0-or-not$success.provisioningEntered-or[string]$successJson.status-cne'PASS'){
        throw "Success wrapper case failed: exit=$($success.exitCode), entered=$($success.provisioningEntered), stdout=$($success.stdout), stderr=$($success.stderr)"
    }
    if(@($success.stdout -split "`r?`n"|Where-Object{$_}).Count-ne1){throw 'Success wrapper stdout must contain exactly one machine-readable record.'}
    foreach($marker in @('PRIVATE_STREAM_WARNING','PRIVATE_STREAM_VERBOSE','PRIVATE_STREAM_DEBUG','PRIVATE_STREAM_INFORMATION')){
        if($success.privateContent-notmatch[regex]::Escape($marker)){throw "Success wrapper private stream is missing $marker."}
        if($success.stdout-match[regex]::Escape($marker)){throw "Success wrapper leaked $marker to stdout."}
    }
    if($success.privateLogCount-ne1-or$success.privateLogNames[0]-cne'private-product-operations.log'){
        throw 'Success wrapper must merge isolated ephemeral stream sinks into one final private log.'
    }

    if($failure.exitCode-ne1-or-not$failure.provisioningEntered-or[string]$failureJson.status-cne'FAIL'){
        throw "Exception wrapper case did not fail after provisioning entry: exit=$($failure.exitCode), entered=$($failure.provisioningEntered), stdout=$($failure.stdout), stderr=$($failure.stderr)"
    }
    if([string]$failureJson.errorCategory-cne'OperationStopped'-or[string]$failureJson.errorType-cne'System.InvalidOperationException'){
        throw "Provisioning exception classification changed: category=$($failureJson.errorCategory), type=$($failureJson.errorType)"
    }
    if($failure.stdout-match'PRIVATE_' -or[string]$failureJson.message-cne'Configured Primary Vault prerequisite failed; no proof credit.'){
        throw 'Provisioning exception or private stream content leaked to machine-readable stdout.'
    }
    foreach($marker in @('PRIVATE_STREAM_WARNING','PRIVATE_STREAM_VERBOSE','PRIVATE_STREAM_DEBUG','PRIVATE_STREAM_INFORMATION','PRIVATE_ORIGINAL_PROVISIONING_EXCEPTION')){
        if($failure.privateContent-notmatch[regex]::Escape($marker)){throw "Exception wrapper private log is missing $marker."}
    }
    if($failure.privateLogCount-ne1-or$failure.privateLogNames[0]-cne'private-product-operations.log'){
        throw 'Exception wrapper must merge isolated ephemeral stream sinks into one final private log.'
    }
    [ordered]@{status='PASS';cases=2;actualGeneratedWrapper=$true;childRuntime='PowerShell 7';privateStreamIsolation=$true;originalExceptionClassification=$true;vmMutation=$false}|ConvertTo-Json -Compress
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}

```


## FILE: automation/release-e2e/tests/Test-MultipassDiagnosticCollector.ps1

SHA256: 4f00c88ffe00ad82e36936c89f2cb08e702294bf4cbbdd77f5dd508dcf3809e8 | Bytes: 21888 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$modulePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules\MultipassDiagnostic.psm1'
Import-Module $modulePath -Force
$count=0
function Check([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message};$script:count++}

$pwsh=(Get-Process -Id $PID).Path
$deadline=[datetime]::UtcNow.AddSeconds(10)
$success=Invoke-DevFleetBoundedNativeProbe -Operation version -FilePath $pwsh -ArgumentList @('-NoProfile','-NonInteractive','-Command','[Console]::Out.Write("multipass 1.15.1")') -TimeoutSeconds 5 -OwnerDeadlineUtc $deadline
Check ($success.outcome -eq 'PASS' -and $success.stdout -eq 'multipass 1.15.1') 'bounded native collector did not preserve successful output'
$legacy=Invoke-DevFleetBoundedNativeProbe -Operation version -FilePath $pwsh -ArgumentList @('-NoProfile','-NonInteractive','-Command','[Console]::Out.Write("legacy argument path")') -TimeoutSeconds 5 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(10)) -ForceLegacyArgumentString
Check ($legacy.outcome-eq'PASS'-and$legacy.stdout-eq'legacy argument path') 'Windows PowerShell legacy argument quoting changed the native probe contract'
$singlePath=@(Get-DevFleetExistingFilePathSet -CandidatePaths @('C:\fixture\multipass.exe') -PathExistsProvider {param($path)$true})
Check ($singlePath.Count-eq1-and$singlePath[0]-eq'C:\fixture\multipass.exe') 'production executable-path normalization unwrapped a singleton under StrictMode'
$nonzero=Invoke-DevFleetBoundedNativeProbe -Operation version -FilePath $pwsh -ArgumentList @('-NoProfile','-NonInteractive','-Command','[Console]::Error.Write("classified failure");exit 7') -TimeoutSeconds 5 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(10))
Check ($nonzero.outcome -eq 'NONZERO' -and $nonzero.exitCode -eq 7 -and $nonzero.stderr -match 'classified failure') 'bounded native collector conflated a nonzero exit with absence'
$timer=[Diagnostics.Stopwatch]::StartNew();$timeout=Invoke-DevFleetBoundedNativeProbe -Operation version -FilePath $pwsh -ArgumentList @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 20') -TimeoutSeconds 1 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(3));$timer.Stop()
Check ($timeout.outcome -eq 'TIMEOUT' -and $timer.Elapsed.TotalSeconds -lt 8) 'bounded native collector did not terminalize a stuck child'
$expired=Invoke-DevFleetBoundedNativeProbe -Operation version -FilePath $pwsh -ArgumentList @('-NoProfile') -TimeoutSeconds 5 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(-1))
Check ($expired.outcome -eq 'OWNER_EXPIRED') 'native collector revived an expired owner deadline'

$processScript=Get-DevFleetBoundedProcessScriptBlock
$scratchRoot=Join-Path (Split-Path -Parent $PSScriptRoot) ".tmp-multipass-process-$PID"
try {
    New-Item -ItemType Directory -Path $scratchRoot -Force|Out-Null
    $importWorker=Join-Path $scratchRoot 'import-worker.ps1'
    [IO.File]::WriteAllText($importWorker,"param([string]`$ModulePath)`nImport-Module `$ModulePath -Force -ErrorAction Stop`n[Console]::Out.Write((ConvertTo-DevFleetDiagnosticSafeText 'bounded-ok'))`n",[Text.UTF8Encoding]::new($false))
    $request=[ordered]@{filePath=$pwsh;arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$importWorker,$modulePath);deadlineUnixMilliseconds=[DateTimeOffset]::new([datetime]::UtcNow.AddSeconds(10)).ToUnixTimeMilliseconds()}|ConvertTo-Json -Depth 4 -Compress
    $processSuccess=&$processScript $request
    Check ($processSuccess.outcome-eq'PASS'-and$processSuccess.stdout-eq'bounded-ok') 'bounded per-process worker did not deliver and import the hash-addressable module'
    $stuckWorker=Join-Path $scratchRoot 'stuck-worker.ps1'
    [IO.File]::WriteAllText($stuckWorker,"Start-Sleep -Seconds 20`n",[Text.UTF8Encoding]::new($false))
    $request=[ordered]@{filePath=$pwsh;arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$stuckWorker);deadlineUnixMilliseconds=[DateTimeOffset]::new([datetime]::UtcNow.AddSeconds(1)).ToUnixTimeMilliseconds()}|ConvertTo-Json -Depth 4 -Compress
    $timer=[Diagnostics.Stopwatch]::StartNew();$processTimeout=&$processScript $request;$timer.Stop()
    Check ($processTimeout.outcome-eq'TIMEOUT'-and$timer.Elapsed.TotalSeconds-lt8) "bounded per-process worker did not stop its exact process tree at the inherited deadline (outcome=$($processTimeout.outcome); elapsed=$([math]::Round($timer.Elapsed.TotalSeconds,3)); deadline=$($processTimeout.deadlineUtc); error=$($processTimeout.stderr))"
} finally {if(Test-Path -LiteralPath $scratchRoot){Remove-Item -LiteralPath $scratchRoot -Recurse -Force}}

$fixtureRun="m1-worker-entry-$PID";$fixtureParent="C:\Users\Public\DevFleet-E2E\$fixtureRun";$fixtureRoot=Join-Path $fixtureParent 'M1';$fixturePrograms=Join-Path (Split-Path -Parent $PSScriptRoot) ".tmp-m1-worker-programs-$PID";$originalProgramFiles=$env:ProgramFiles;$originalProgramFilesX86=${env:ProgramFiles(x86)};$originalProgramData=$env:ProgramData
try {
    New-Item -ItemType Directory -Path $fixtureRoot,$fixturePrograms,(Join-Path $fixturePrograms 'Multipass\bin') -Force|Out-Null
    $fixtureModule=Join-Path $fixtureRoot 'MultipassDiagnostic.psm1';Copy-Item -LiteralPath $modulePath -Destination $fixtureModule
    $fakeMultipass=Join-Path $fixturePrograms 'Multipass\bin\multipass.exe';Copy-Item -LiteralPath (Get-Command cmd.exe).Source -Destination $fakeMultipass
    $env:ProgramFiles=$fixturePrograms;${env:ProgramFiles(x86)}=$fixturePrograms;$env:ProgramData=Join-Path $fixturePrograms 'ProgramData'
    $workerName="DevFleet-E2E-E-M1-$fixtureRun";$workerOwner=[datetime]::UtcNow.AddSeconds(30);$workerOperation=$workerOwner.AddSeconds(-10)
    $workerRequest=[ordered]@{runId=$fixtureRun;vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);instanceName=$workerName;remoteRoot=$fixtureRoot;modulePath=$fixtureModule;ubuntuImage='24.04';expectedMultipassSha256=(Get-FileHash -LiteralPath $fakeMultipass -Algorithm SHA256).Hash.ToLowerInvariant();ownerDeadlineUnixMilliseconds=[DateTimeOffset]::new($workerOwner).ToUnixTimeMilliseconds();operationDeadlineUnixMilliseconds=[DateTimeOffset]::new($workerOperation).ToUnixTimeMilliseconds()}|ConvertTo-Json -Depth 6 -Compress
    $workerBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($workerRequest));$entryWorker=Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-CampaignEMultipassM1Worker.ps1'
    $workerOutput=@(& $pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entryWorker -RequestBase64 $workerBase64 2>$null);$workerExit=$LASTEXITCODE;$durablePath=Join-Path $fixtureRoot 'm1-worker-result.json';$durable=Get-Content -LiteralPath $durablePath -Raw|ConvertFrom-Json
    Check ($workerExit-eq1-and[string]$durable.status-ceq'BLOCKED'-and[string]$durable.cleanup.instanceName-ceq$workerName-and[string]$durable.primaryError-cnotmatch'New-DevFleetCampaignEM1CleanupState') 'actual M1 worker entry did not import before cleanup construction or durably bind the validated identity'
} finally {
    $env:ProgramFiles=$originalProgramFiles;${env:ProgramFiles(x86)}=$originalProgramFilesX86;$env:ProgramData=$originalProgramData
    if((Test-Path -LiteralPath $fixtureParent)-and[IO.Path]::GetFullPath($fixtureParent).StartsWith('C:\Users\Public\DevFleet-E2E\',[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixtureParent -Recurse -Force}
    if((Test-Path -LiteralPath $fixturePrograms)-and[IO.Path]::GetFullPath($fixturePrograms).StartsWith([IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixturePrograms -Recurse -Force}
}

$base=[datetime]'2026-09-06T18:00:00Z';$clock=$base
$environment={param($vm,$id,$candidate,$prefix)[ordered]@{computerName='E2E-L1';principal=[ordered]@{kind='ADMINISTRATOR';isAdministrator=$true};capacity=[ordered]@{logicalProcessors=4;totalMemoryBytes=16GB;freeMemoryBytes=12GB;systemDriveFreeBytes=100GB};nestedVirtualization=[ordered]@{hyperVFeatureState='Enabled';vmMonitorModeExtensions=$true;secondLevelAddressTranslation=$true;virtualizationFirmwareEnabled=$true};multipass=[ordered]@{executableStatus='PRESENT';executablePresent=$true;executablePath='C:\Program Files\Multipass\bin\multipass.exe';sha256=('a'*64);fileVersion='1.15.1'};services=@([ordered]@{name='Multipass';state='Running';startMode='Auto';processId=42});backendInventory=[ordered]@{hyperV=[ordered]@{status='PASS';boundNames=@();foreignCount=0}};activeProduct=[ordered]@{activeTransactionPresent=$false;activeInstallProcessCount=0}}}
$probe={param($operation,$path,$args,$seconds,$owner) $script:clock=$script:clock.AddSeconds(1);$output=switch($operation){version{'multipass 1.15.1'}driver{'hyperv'}'privileged-mounts'{'false'}inventory{'{"list":[]}'}image{'Image 24.04 Ubuntu'}};[pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc=$script:clock.AddMilliseconds(-100).ToString('o');finishedAtUtc=$script:clock.ToString('o');deadlineUtc=([datetime]$owner).ToUniversalTime().ToString('o');stdout=$output;stderr='';pid=42;outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}}
$events={param($owner)[ordered]@{status='PASS';records=@([ordered]@{provider='Multipass';eventId=1;level='Error';timestampUtc='2026-09-06T17:59:00Z';category='SERVICE'})}}
$snapshot=Get-DevFleetMultipassM0Snapshot -RunId 'e-m0-unit' -ExpectedVmName 'DevFleet-E2E-Win11-01' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -UbuntuImage '24.04' -CandidateInstanceNames @('devfleet-primary','devfleet-failover','devfleet-vault') -RunOwnedPrefix 'DevFleet-E2E-E-unit' -OwnerDeadlineUtc $base.AddMinutes(2) -EnvironmentProvider $environment -NativeProbeProvider $probe -EventProvider $events -ClockProvider {$script:clock} -PrimaryError 'password=do-not-store'
Check (Assert-DevFleetMultipassM0Snapshot -Snapshot $snapshot -ExpectedRunId 'e-m0-unit' -ExpectedVmName 'DevFleet-E2E-Win11-01' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2')) 'valid production collector snapshot was rejected'
Check ($snapshot.status -eq 'COMPLETE' -and $snapshot.primaryError -eq 'password=<redacted>') 'collector did not preserve and redact the primary error'
Check ((@($snapshot.probes|Where-Object operation -eq inventory)[0].data.foreignCount) -eq 0) 'collector inventory normalization failed'

$wrongRun=$snapshot|ConvertTo-Json -Depth 24|ConvertFrom-Json;$wrongRun.runId='wrong';$rejected=$false;try{Assert-DevFleetMultipassM0Snapshot -Snapshot $wrongRun -ExpectedRunId 'e-m0-unit' -ExpectedVmName 'DevFleet-E2E-Win11-01' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2')|Out-Null}catch{$rejected=$true};Check $rejected 'collector accepted a wrong run identity'
$wrongVm=$snapshot|ConvertTo-Json -Depth 24|ConvertFrom-Json;$wrongVm.expectedVmId=[guid]::NewGuid().ToString();$rejected=$false;try{Assert-DevFleetMultipassM0Snapshot -Snapshot $wrongVm -ExpectedRunId 'e-m0-unit' -ExpectedVmName 'DevFleet-E2E-Win11-01' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2')|Out-Null}catch{$rejected=$true};Check $rejected 'collector accepted a wrong VM identity'
$late=$snapshot|ConvertTo-Json -Depth 24|ConvertFrom-Json;$late.producedAtUtc='2026-09-06T18:03:00Z';$rejected=$false;try{Assert-DevFleetMultipassM0Snapshot -Snapshot $late -ExpectedRunId 'e-m0-unit' -ExpectedVmName 'DevFleet-E2E-Win11-01' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2')|Out-Null}catch{$rejected=$true};Check $rejected 'collector accepted a result first produced after its immutable deadline'
$overlap=$snapshot|ConvertTo-Json -Depth 24|ConvertFrom-Json;$overlap.probes[1].startedAtUtc=$overlap.probes[0].startedAtUtc;$rejected=$false;try{Assert-DevFleetMultipassM0Snapshot -Snapshot $overlap -ExpectedRunId 'e-m0-unit' -ExpectedVmName 'DevFleet-E2E-Win11-01' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2')|Out-Null}catch{$rejected=$true};Check $rejected 'collector accepted overlapping Multipass CLI probes'
$malformed=[pscustomobject]@{operation='inventory';outcome='PASS';exitCode=0;startedAtUtc=$base.ToString('o');finishedAtUtc=$base.AddSeconds(1).ToString('o');deadlineUtc=$base.AddMinutes(1).ToString('o');stdout='not-json';stderr=''}
$normalized=ConvertTo-DevFleetMultipassProbeObservation -Probe $malformed -UbuntuImage '24.04' -CandidateInstanceNames @('devfleet-primary') -RunOwnedPrefix 'DevFleet-E2E-E-unit'
Check ($normalized.outcome -eq 'MALFORMED') 'invalid Multipass JSON masqueraded as absence'
foreach($outcome in @('NONZERO','TIMEOUT','START_FAILED')){$raw=[pscustomobject]@{operation='inventory';outcome=$outcome;exitCode=if($outcome-eq'NONZERO'){9}else{$null};startedAtUtc=$base.ToString('o');finishedAtUtc=$base.AddSeconds(1).ToString('o');deadlineUtc=$base.AddMinutes(1).ToString('o');stdout='';stderr='token=redact-me'};$normalized=ConvertTo-DevFleetMultipassProbeObservation -Probe $raw -UbuntuImage '24.04' -CandidateInstanceNames @('devfleet-primary') -RunOwnedPrefix 'DevFleet-E2E-E-unit';Check ($normalized.outcome -eq $outcome -and $normalized.error -notmatch 'redact-me') "$outcome was not preserved and redacted"}

$absentEnvironment={param($vm,$id,$candidate,$prefix)[ordered]@{computerName='E2E-L1';principal=[ordered]@{kind='ADMINISTRATOR';isAdministrator=$true};capacity=[ordered]@{};nestedVirtualization=[ordered]@{};multipass=[ordered]@{executableStatus='ABSENT';executablePresent=$false;executablePath='';sha256='';fileVersion=''};services=@();backendInventory=[ordered]@{};activeProduct=[ordered]@{activeTransactionPresent=$false;activeInstallProcessCount=0}}}
$clock=$base;$absent=Get-DevFleetMultipassM0Snapshot -RunId 'e-m0-absent' -ExpectedVmName 'DevFleet-E2E-Win11-01' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -UbuntuImage '24.04' -CandidateInstanceNames @('devfleet-primary') -RunOwnedPrefix 'DevFleet-E2E-E-absent' -OwnerDeadlineUtc $base.AddMinutes(1) -EnvironmentProvider $absentEnvironment -EventProvider $events -ClockProvider {$script:clock}
Check ($absent.status -eq 'COMPLETE' -and @($absent.probes|Where-Object outcome -eq 'SKIPPED_NO_EXECUTABLE').Count -eq 5) 'executable absence did not remain a complete positive environment observation'
$clock=$base;$partial=Get-DevFleetMultipassM0Snapshot -RunId 'e-m0-partial' -ExpectedVmName 'DevFleet-E2E-Win11-01' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -UbuntuImage '24.04' -CandidateInstanceNames @('devfleet-primary') -RunOwnedPrefix 'DevFleet-E2E-E-partial' -OwnerDeadlineUtc $base.AddMinutes(1) -EnvironmentProvider $absentEnvironment -EventProvider {throw 'event token=redact-me'} -ClockProvider {$script:clock} -PrimaryError 'primary failure remains'
Check ($partial.status -eq 'PARTIAL' -and $partial.primaryError -eq 'primary failure remains' -and $partial.errors[0] -notmatch 'redact-me') 'partial collector failure suppressed the primary error or leaked diagnostics'

$m1Name='DevFleet-E2E-E-M1-unit';$script:m1Clock=$base;$script:m1Calls=[Collections.Generic.List[object]]::new();$infoJson='{"info":{"DevFleet-E2E-E-M1-unit":{"state":"Running","ipv4":["10.10.10.2"]}},"errors":[]}'
$m1Provider={param($operation,$path,$arguments,$seconds,$owner)$start=$script:m1Clock;$script:m1Clock=$script:m1Clock.AddSeconds(2);[void]$script:m1Calls.Add([pscustomobject]@{operation=$operation;arguments=@($arguments);seconds=$seconds;owner=([datetime]$owner).ToUniversalTime().ToString('o')});$stdout=if($operation-like'info-*'){$infoJson}elseif($operation-eq'cloud-init'){'status: done'}else{''};[pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;pid=55;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:m1Clock.ToString('o');deadlineUtc=([datetime]$owner).ToUniversalTime().ToString('o');stdout=$stdout;stderr='';outputComplete=$true}}
$m1=Invoke-DevFleetCampaignEMultipassM1Sequence -RunId 'unit' -InstanceName $m1Name -UbuntuImage '24.04' -MultipassPath 'C:\fixture\multipass.exe' -OwnerDeadlineUtc $base.AddMinutes(15) -NativeProbeProvider $m1Provider -ClockProvider {$script:m1Clock}
Check ([string]$m1.status-ceq'PASS'-and[bool]$m1.progress.launchAccepted-and[bool]$m1.progress.instanceRunning-and[bool]$m1.progress.ipObserved-and[bool]$m1.progress.sshReady-and[bool]$m1.progress.cloudInitDone) 'M1 production sequence did not distinguish launch, IP, SSH and cloud-init completion'
Check ((@($script:m1Calls[0].arguments)-join'|')-ceq"launch|24.04|--name|$m1Name|--cpus|2|--memory|2G|--disk|10G") 'M1 production sequence did not construct the exact modest-resource plain launch'
Check ((@($script:m1Calls[2].arguments)-join'|')-ceq"exec|$m1Name|--|true"-and(@($script:m1Calls[3].arguments)-join'|')-ceq"exec|$m1Name|--|cloud-init|status|--wait") 'M1 production sequence did not exercise real SSH/cloud-init readiness without product inputs'
Check (@($script:m1Calls|Where-Object{$_.owner-cne'2026-09-06T18:15:00.0000000Z'}).Count-eq0-and@($m1.observations).Count-eq5) 'M1 production sequence granted a fresh child deadline or lost operation cardinality'
Check (-not[bool]$m1.productLifecycleStarted-and-not[bool]$m1.productProgressClaimed-and($m1|ConvertTo-Json -Depth 16)-notmatch'10.10.10.2') 'M1 production sequence fabricated product progress or retained guest address output'

$cleanupState=New-DevFleetCampaignEM1CleanupState -InstanceName $m1Name
Check ([string]$cleanupState.instanceName-ceq$m1Name-and[string]$cleanupState.status-ceq'UNVERIFIED'-and[int]$cleanupState.finalInventoryCount-eq-1) 'M1 cleanup producer did not bind the validated launch identity'
$invalidCleanupRejected=$false;try{New-DevFleetCampaignEM1CleanupState -InstanceName 'devfleet-primary'|Out-Null}catch{$invalidCleanupRejected=$true};Check $invalidCleanupRejected 'M1 cleanup producer accepted a product or non-run-owned identity'
$cleanupState.status='ABSENT_VERIFIED';$cleanupState.finalInventoryCount=0
$validM1=[pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_M1_RESULT';status='PASS_DIAGNOSTIC';runId='unit';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);instanceName=$m1Name;ubuntuImage='24.04';ownerDeadlineUtc=$base.AddMinutes(20).ToString('o');producedAtUtc=$base.AddMinutes(16).ToString('o');multipassSha256=('b'*64);boundaryBefore=[ordered]@{activeTransactionPresent=$false;stageMarkerCount=0};preflight=[ordered]@{operation='baseline-inventory';outcome='PASS'};sequence=$m1;cleanup=$cleanupState;boundaryAfter=[ordered]@{activeTransactionPresent=$false;stageMarkerCount=0};primaryError='';productLifecycleStarted=$false;productProgressClaimed=$false}
Check (Assert-DevFleetCampaignEM1Result -Result $validM1 -ExpectedRunId 'unit' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedInstanceName $m1Name -ExpectedPayloadSha256 ('a'*64)) 'valid M1 result was rejected'
$badM1=$validM1|ConvertTo-Json -Depth 24|ConvertFrom-Json;$badM1.cleanup.status='UNVERIFIED';$rejected=$false;try{Assert-DevFleetCampaignEM1Result -Result $badM1 -ExpectedRunId 'unit' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedInstanceName $m1Name -ExpectedPayloadSha256 ('a'*64)|Out-Null}catch{$rejected=$true};Check $rejected 'M1 result accepted unverified cleanup'
$badM1=$validM1|ConvertTo-Json -Depth 24|ConvertFrom-Json;$badM1.productProgressClaimed=$true;$rejected=$false;try{Assert-DevFleetCampaignEM1Result -Result $badM1 -ExpectedRunId 'unit' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedInstanceName $m1Name -ExpectedPayloadSha256 ('a'*64)|Out-Null}catch{$rejected=$true};Check $rejected 'M1 result accepted fabricated product progress'
$script:m1Clock=$base;$script:m1Calls=[Collections.Generic.List[object]]::new();$timeoutM1={param($operation,$path,$arguments,$seconds,$owner)[void]$script:m1Calls.Add($operation);[pscustomobject]@{operation=$operation;outcome='TIMEOUT';exitCode=$null;pid=56;startedAtUtc=$base.ToString('o');finishedAtUtc=$base.AddSeconds(1).ToString('o');deadlineUtc=$base.AddMinutes(1).ToString('o');stdout='';stderr='bounded timeout';outputComplete=$true}}
$blockedM1=Invoke-DevFleetCampaignEMultipassM1Sequence -RunId 'unit' -InstanceName $m1Name -UbuntuImage '24.04' -MultipassPath 'C:\fixture\multipass.exe' -OwnerDeadlineUtc $base.AddMinutes(15) -NativeProbeProvider $timeoutM1 -ClockProvider {$script:m1Clock}
Check ([string]$blockedM1.status-ceq'BLOCKED'-and@($blockedM1.observations).Count-eq1-and@($script:m1Calls).Count-eq1-and-not[bool]$blockedM1.progress.launchAccepted) 'M1 launch timeout was mistaken for semantic progress or allowed later operations'
$script:m1Clock=$base;$malformedInfo={param($operation,$path,$arguments,$seconds,$owner)$start=$script:m1Clock;$script:m1Clock=$script:m1Clock.AddSeconds(1);[pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;pid=57;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:m1Clock.ToString('o');deadlineUtc=([datetime]$owner).ToUniversalTime().ToString('o');stdout=if($operation-eq'info-running'){'{"info":{"wrong":{"state":"Running","ipv4":["10.0.0.2"]}}}'}else{''};stderr='';outputComplete=$true}}
$badInfoM1=Invoke-DevFleetCampaignEMultipassM1Sequence -RunId 'unit' -InstanceName $m1Name -UbuntuImage '24.04' -MultipassPath 'C:\fixture\multipass.exe' -OwnerDeadlineUtc $base.AddMinutes(15) -NativeProbeProvider $malformedInfo -ClockProvider {$script:m1Clock}
Check ([string]$badInfoM1.status-ceq'BLOCKED'-and-not[bool]$badInfoM1.progress.instanceRunning-and[string]$badInfoM1.primaryError-match'exact instance') 'M1 wrong-instance info masqueraded as readiness'
foreach($scriptName in @('Invoke-CampaignEMultipassM1.ps1','Invoke-CampaignEMultipassM1Worker.ps1')){$errors=$null;$tokens=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) $scriptName),[ref]$tokens,[ref]$errors)|Out-Null;Check ($errors.Count-eq0) "$scriptName has parser errors"}

Write-Host "PASS $count Campaign E Multipass diagnostic collector behavioral checks"

```


## FILE: automation/release-e2e/tests/Test-NestedPrimaryReadiness.ps1

SHA256: 167cd8a464fee826bfdfb77507f54ac008d84cd964094966001a43703986f142 | Bytes: 9664 | Git mode: 100644

```
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
$readyBlock=Get-DevFleetNestedPrimaryReadinessScriptBlock
$originalComputerName=$env:COMPUTERNAME
$checks=0
try {
    $env:COMPUTERNAME='DEVFLEET-E2E-UNIT'
    foreach($case in @('ready','inventory-timeout','inventory-timeout-forced','inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid','control-plane-recovery-failure','info-unready','info-timeout-exhausted','wrong-instance','malformed-inventory','wrong-immutable-id','wrong-host')){
        $multipassPath=Join-Path $env:ProgramFiles 'Multipass/bin/multipass.exe'
        $multipassDaemon=Join-Path (Split-Path -Parent $multipassPath) 'multipassd.exe'
        $state=@{case=$case;calls=[Collections.Generic.List[string]]::new();probes=[Collections.Generic.List[object]]::new();mutations=[Collections.Generic.List[string]]::new();serviceControls=[Collections.Generic.List[string]]::new();daemonStops=[Collections.Generic.List[int]]::new();serviceState='Running';servicePid=42;clock=[datetime]'2026-09-22T14:18:29Z';infoCount=0;listCount=0}
        $probe={param($Arguments,$TimeoutSeconds)
            $operation=[string]$Arguments[0];$state.calls.Add($operation);$state.probes.Add([pscustomobject]@{operation=$operation;timeoutSeconds=[int]$TimeoutSeconds})
            if($operation -eq 'list'){
                $state.listCount++
                if($state.case -in @('inventory-timeout','inventory-timeout-forced','inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid','control-plane-recovery-failure','wrong-immutable-id') -and $state.listCount -eq 1){throw 'native inventory TIMEOUT'}
                $stdout=if($state.case -eq 'malformed-inventory'){'not-json'}elseif($state.case -eq 'wrong-instance'){'{"list":[{"name":"foreign","state":"Running"}]}'}else{'{"list":[{"name":"devfleet-primary","state":"Running"}]}'}
            }elseif($operation -eq 'info'){
                $state.infoCount++
                if($state.case -eq 'info-timeout-exhausted' -and $state.infoCount -gt 1){$state.clock=$state.clock.AddSeconds([int]$TimeoutSeconds);throw "Nested Multipass operation timed out after $TimeoutSeconds seconds: info devfleet-primary"}
                $stdout=if($state.case -in @('info-unready','wrong-immutable-id') -and $state.infoCount -eq 1){'IPv4: --'}else{'IPv4: 10.0.0.2'}
                if($state.case -eq 'info-timeout-exhausted'){$stdout='IPv4: --'}
            }else{throw 'Readiness attempted an unexpected operation'}
            [pscustomobject]@{exitCode=0;stdout=@($stdout);stderr=@();output=@($stdout)}
        }.GetNewClosure()
        $lookup={param($Name,$Id)
            [pscustomobject]@{Name='devfleet-primary';Id=if($Id -and $state.case -eq 'wrong-immutable-id'){[guid]'22222222-2222-2222-2222-222222222222'}else{[guid]'11111111-1111-1111-1111-111111111111'};State='Running'}
        }.GetNewClosure()
        $stop={param($Vm)if($Vm.Id -ne [guid]'11111111-1111-1111-1111-111111111111'){throw 'Wrong exact stop target'};$state.mutations.Add('stop')}.GetNewClosure()
        $start={param($Vm)if($Vm.Id -ne [guid]'11111111-1111-1111-1111-111111111111'){throw 'Wrong exact start target'};$state.mutations.Add('start')}.GetNewClosure()
        $serviceLookup={
            if($state.case -eq 'control-plane-recovery-failure'){throw 'controlled Multipass service recovery failure'}
            [pscustomobject]@{Name='Multipass';State=$state.serviceState;ProcessId=$state.servicePid;PathName="`"$multipassDaemon`"";StartName='LocalSystem'}
        }.GetNewClosure()
        $serviceControl={param($Action)
            $state.serviceControls.Add([string]$Action)
            if($Action -eq 'stop'){$state.serviceState=if($state.case -in @('inventory-timeout-forced','inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid')){'Stop Pending'}else{'Stopped'}}
            elseif($Action -eq 'start'){$state.serviceState='Running'}else{throw 'Unexpected service control action'}
        }.GetNewClosure()
        $daemonLookup={param($Id)if($Id -ne 42 -and -not($Id -eq 43 -and $state.case -in @('inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path'))){throw 'Wrong daemon PID'};[pscustomobject]@{ProcessName='multipassd';Path=if($Id -eq 43 -and $state.case -eq 'inventory-timeout-auto-restart-wrong-path'){'C:\Untrusted\multipassd.exe'}else{$multipassDaemon}}}.GetNewClosure()
        $daemonStop={param($Id)if($Id -ne 42){throw 'Wrong daemon stop PID'};$state.daemonStops.Add([int]$Id);$state.serviceState=if($state.case -in @('inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid')){'Running'}else{'Stopped'};if($state.case -in @('inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path')){$state.servicePid=43}}.GetNewClosure()
        $clock={$state.clock}.GetNewClosure()
        $sleep={param($Milliseconds)$state.clock=$state.clock.AddMilliseconds([int]$Milliseconds)}.GetNewClosure()
        $recoverArgs=@{
            ServiceLookupProvider=$serviceLookup;ServiceControlProvider=$serviceControl;DaemonLookupProvider=$daemonLookup;DaemonStopProvider=$daemonStop;ClockProvider=$clock;SleepProvider=$sleep
        }
        if($case -eq 'wrong-host'){$env:COMPUTERNAME=$originalComputerName}
        $failure=$null;$result=$null
        try{$result=& $readyBlock -Primary 'devfleet-primary' -MultipassPath $multipassPath -NativeProbeProvider $probe -VmLookupProvider $lookup -VmStopProvider $stop -VmStartProvider $start @recoverArgs}catch{$failure=$_.Exception.Message}
        $expectedFailure=$case -in @('inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid','control-plane-recovery-failure','info-timeout-exhausted','wrong-instance','malformed-inventory','wrong-immutable-id','wrong-host')
        if($expectedFailure){
            if(-not $failure -or ($case -ne 'info-timeout-exhausted' -and $state.mutations.Count)){throw "Readiness did not fail closed without mutation: $case"}
        }else{
            if($failure -or -not $result.ready -or $state.listCount -lt 1 -or $state.infoCount -lt 1){throw "Readiness bypassed inventory/info: $case / $failure"}
            $expectedMutations=if($case -eq 'info-unready'){'stop|start'}else{''}
            if(($state.mutations -join '|') -cne $expectedMutations){throw "Exact recovery sequence changed: $case"}
        }
        $expectedServiceControls=if($case -in @('inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid')){'stop'}elseif($case -in @('inventory-timeout','inventory-timeout-forced','wrong-immutable-id')){'stop|start'}else{''}
        if(($state.serviceControls -join '|') -cne $expectedServiceControls){throw "Control-plane recovery cardinality changed: $case"}
        $expectedDaemonStops=if($case -in @('inventory-timeout-forced','inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid')){1}else{0}
        if($state.daemonStops.Count -ne $expectedDaemonStops){throw "Forced daemon recovery changed: $case"}
        if($case -in @('inventory-timeout','inventory-timeout-forced','inventory-timeout-auto-restart') -and ([string]$result.controlPlaneRecovery.status -cne 'PASS' -or $state.listCount -ne 2 -or [bool]$result.controlPlaneRecovery.forcedDaemonTermination -ne ($case -ne 'inventory-timeout'))){throw 'Inventory timeout did not recover the real control-plane path and re-probe inventory before guest mutation'}
        if($case -eq 'inventory-timeout-reused-pid' -and $failure -cnotmatch 'exact daemon PID'){throw 'Recovery accepted a Running service without a new exact daemon PID'}
        if($case -eq 'inventory-timeout-auto-restart-wrong-path' -and $failure -cnotmatch 'trusted daemon identity'){throw 'Recovery accepted a daemon outside the trusted installation'}
        if(@($state.probes|Where-Object{$_.operation -eq 'list' -and $_.timeoutSeconds -gt 30}).Count){throw "Inventory probe escaped its 30-second child bound: $case"}
        if($result -and $result.controlPlaneRecovery -and [datetime]$result.controlPlaneRecovery.ownerDeadlineUtc -ne [datetime]'2026-09-22T14:21:29Z'){throw "Control-plane recovery widened or replaced the 180-second owner deadline: $case"}
        if($state.clock -gt [datetime]'2026-09-22T14:21:29Z'){throw "Readiness exceeded the 180-second owner deadline: $case"}
        if($case