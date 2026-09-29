# DevFleet source part 045

Full-source UTF-8 byte interval [2046000, 2092500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 4a375de8e14b2711ca32a8b3689ad632ea322bb9bf0694a43b1d4fa29fcc965d

<!-- BEGIN SOURCE SLICE -->
ductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $transition -RebootProvider $errorReboot -SettleProvider $settle
$nullSettlement={param($s)$null};$nullSettlementResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $transition -RebootProvider $reboot -SettleProvider $nullSettlement
Check ([string]$nullWpfResult.status -eq 'TERMINAL_FAILURE') 'WpfProvider null fails closed'
Check ([string]$nullTransitionResult.status -eq 'TERMINAL_FAILURE') 'TransitionProvider null fails closed'
Check ([string]$errorRebootResult.status -eq 'TERMINAL_FAILURE') 'RebootProvider error fails closed'
Check ([string]$nullSettlementResult.status -eq 'TERMINAL_FAILURE') 'SettlementProvider null fails closed'
function Check-FullLifecycleTerminalEvidence([psobject]$Result,[string]$Name){
    $terminal=[string]$Result.evidencePath;$dir=if($terminal){Split-Path -Parent $terminal}else{''};$journal=if($dir){Join-Path $dir 'product-lifecycle-progress.jsonl'}else{''};$current=if($dir){Join-Path $dir 'product-lifecycle-progress-current.json'}else{''};$providerDetail=if($dir){Join-Path $dir 'product-lifecycle-provider-failure.json'}else{''};$pathsPresent=($terminal -and (Test-Path -LiteralPath $terminal) -and (Test-Path -LiteralPath $journal) -and (Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $providerDetail));$journalMatches=$false;if($pathsPresent){try{$last=@(Get-Content -LiteralPath $journal|Where-Object{$_})[-1]|ConvertFrom-Json;$journalMatches=([string]$last.event -eq 'TERMINAL' -and [string]$last.terminalReason -eq 'TERMINAL_FAILURE')}catch{}};Check ($pathsPresent -and $journalMatches) "$Name writes terminal/provider/current/journal evidence with matching terminal reason"
}
Check-FullLifecycleTerminalEvidence $nullWpfResult 'WpfProvider null'
Check-FullLifecycleTerminalEvidence $nullTransitionResult 'TransitionProvider null'
Check-FullLifecycleTerminalEvidence $errorRebootResult 'RebootProvider exception'
Check-FullLifecycleTerminalEvidence $nullSettlementResult 'SettlementProvider null'
$sessionFailureDir=Join-Path $lifeRoot 'session-failure-causal-evidence'
$sessionFailureError=[InvalidOperationException]::new('LAB_GUEST_AUTHENTICATION_REJECTED: guest authentication was rejected; credential freshness remains unverified. Bounded attempts: 3.')
$sessionFailureError.Data['failureCode']='LAB_GUEST_AUTHENTICATION_REJECTED';$sessionFailureError.Data['attemptCount']=3;$sessionFailureError.Data['authenticationOutcome']='REJECTED';$sessionFailureError.Data['credentialFreshness']='UNVERIFIED';$sessionFailureError.Data['nativeErrorCode']=1326
& (Get-Module Invoke-RealProductPhase) {param($failure) function script:Connect-DevFleetGuest { throw $script:SessionFixtureFailure };$script:SessionFixtureFailure=$failure} $sessionFailureError
$sessionFailureContext=[pscustomobject]@{phaseId='SESSION-FAILURE-CAUSAL';runDir=$sessionFailureDir;workspaceRoot=$WorkspaceRoot;vmId=$lifeContext.vmId;vmName=$lifeContext.vmName;candidate=$lifeContext.candidate;config=(Get-Content -Raw (Join-Path $WorkspaceRoot 'source\config\devfleet.config.json')|ConvertFrom-Json);phaseBudgetSeconds=60}
$sessionFailureWpf={param($s)[pscustomobject]@{status='REAL E2E OBSERVER HANDOFF';guest=[pscustomobject]@{processId=0;role='Primary / Desktop'}}}
$sessionFailureCallError='';try{$sessionFailureResult=Invoke-ProductFreshInstallLifecycle -Context $sessionFailureContext -Role 'Primary / Desktop' -WpfProvider $sessionFailureWpf}catch{$sessionFailureCallError=$_.Exception.Message}
Check ([string]::IsNullOrEmpty($sessionFailureCallError) -and $null -ne $sessionFailureResult) 'real lifecycle caller returns a terminal result for session-open failure'
if($sessionFailureCallError){Write-Output "session failure fixture invocation: $sessionFailureCallError"}
$sessionFailureTerminal=Get-ChildItem -LiteralPath $sessionFailureDir -Filter 'product-lifecycle-terminal.json' -File -Recurse|Select-Object -First 1
$sessionFailureEvidence=if($sessionFailureTerminal){Get-Content -Raw $sessionFailureTerminal.FullName|ConvertFrom-Json}else{[pscustomobject]@{safeFailure=$null;error=''}}
Check ([string]$sessionFailureResult.provider -eq 'TransitionObserver' -and [string]$sessionFailureEvidence.safeFailure.failureCode -eq 'LAB_GUEST_AUTHENTICATION_REJECTED' -and [int]$sessionFailureEvidence.safeFailure.nativeErrorCode -eq 1326 -and [int]$sessionFailureEvidence.safeFailure.attemptCount -eq 3) 'real guest caller to observer to terminal evidence preserves allowlisted native failure metadata'
Check (([string]$sessionFailureEvidence.error -notmatch 'DEMO_SECRET|password|credentialFreshness=') -and [string]$sessionFailureEvidence.safeFailure.credentialFreshness -eq 'UNVERIFIED') 'terminal failure evidence contains only safe fields and no raw exception text'
$unknownSessionFailureDir=Join-Path $lifeRoot 'session-failure-unknown-evidence'
& (Get-Module Invoke-RealProductPhase) {$script:SessionFixtureFailure=[InvalidOperationException]::new('deserialized remote authentication/session failure')}
$unknownSessionFailureContext=$sessionFailureContext.PSObject.Copy();$unknownSessionFailureContext.runDir=$unknownSessionFailureDir;$unknownSessionFailureContext.phaseId='SESSION-FAILURE-UNKNOWN'
$unknownSessionFailureResult=Invoke-ProductFreshInstallLifecycle -Context $unknownSessionFailureContext -Role 'Primary / Desktop' -WpfProvider $sessionFailureWpf
$unknownSessionFailureTerminal=Get-ChildItem -LiteralPath $unknownSessionFailureDir -Filter 'product-lifecycle-terminal.json' -File -Recurse|Select-Object -First 1
$unknownSessionFailureEvidence=if($unknownSessionFailureTerminal){Get-Content -Raw $unknownSessionFailureTerminal.FullName|ConvertFrom-Json}else{[pscustomobject]@{safeFailure=$null}}
Check ([string]$unknownSessionFailureResult.status -eq 'TERMINAL_FAILURE' -and $null -eq $unknownSessionFailureEvidence.safeFailure) 'wrapped or deserialized session errors remain terminal with cause UNKNOWN'
& (Get-Module Invoke-RealProductPhase) {Remove-Item Function:Connect-DevFleetGuest -ErrorAction SilentlyContinue;$script:SessionFixtureFailure=$null}
$completedObservation=[pscustomobject]@{matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true;progress=[ordered]@{}}
$completedVariants=[ordered]@{
    'valid checkpoint object'=[pscustomobject]@{checkpoint=$next.checkpoint}
    'checkpointPresent false with object'=[pscustomobject]@{observation=[pscustomobject]@{checkpointPresent=$false;checkpoint=$next.checkpoint}}
    'top-level generation only'=[pscustomobject]@{generation=1}
    'top-level checkpointGeneration only'=[pscustomobject]@{checkpointGeneration=1}
    'embedded observation checkpoint/generation'=[pscustomobject]@{observation=[pscustomobject]@{checkpointPresent=$true;checkpoint=[pscustomobject]@{generation=1;checkpointGeneration=1;state='waiting-for-reboot'}}}
    'waiting-for-reboot state'=[pscustomobject]@{observation=[pscustomobject]@{state='waiting-for-reboot'}}
}
$variantTraceStart=$lifeTrace.Count;foreach($variant in $completedVariants.GetEnumerator()){$variantTransition={param($s)$result=[ordered]@{outcome='COMPLETED';observation=$completedObservation};foreach($p in $thisVariant.PSObject.Properties){$result[$p.Name]=$p.Value};[pscustomobject]$result};$thisVariant=$variant.Value;$variantResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $variantTransition -RebootProvider $reboot -SettleProvider $settle;Check ([string]$variantResult.status -eq 'TERMINAL_FAILURE') "COMPLETED $($variant.Key) is rejected";Check-FullLifecycleTerminalEvidence $variantResult "COMPLETED $($variant.Key)"}
Check (@($lifeTrace|Select-Object -Skip $variantTraceStart|Where-Object{$_ -match '^REBOOT:'}).Count -eq 0) 'presence/checkpoint inconsistencies fail before any reboot provider call'
Check ((Get-ProductLifecycleConsumerMode -PhaseId 'REBOOT-RESUME') -eq 'SYNTHETIC_THEN_PRODUCT' -and (Get-ProductLifecycleConsumerMode -PhaseId 'LINUX') -eq 'PRODUCT_ONLY' -and (Get-ProductLifecycleConsumerMode -PhaseId 'SURROGATE-DISPOSABLE') -eq 'PRODUCT_ONLY' -and (Get-ProductLifecycleConsumerMode -PhaseId 'MAINTENANCE-READY-PROVISION') -eq 'PRODUCT_ONLY' -and (Get-ProductLifecycleConsumerMode -PhaseId 'DEPENDENCY-MATRIX') -eq 'PRODUCT_ONLY') 'LIFE-04/LIFE-05 consumer dispatch proves synthetic independence'
Check ([string]$lifeResult.phase -eq 'LIFE-TEST' -and [string]$lifeResult.invocationId -and (Test-Path -LiteralPath ([string]$lifeResult.evidencePath))) 'LIFE-04 invocation identity and isolated authority evidence are exposed'
$lifeEvidenceDir=Split-Path -Parent ([string]$lifeResult.evidencePath);$observerEvidence=Join-Path $lifeEvidenceDir 'product-lifecycle-observer-generation-1.json';$generationEvidence=Join-Path $lifeEvidenceDir 'product-lifecycle-generation-1.json'
Check ((Test-Path -LiteralPath $observerEvidence) -and (Test-Path -LiteralPath $generationEvidence) -and ([IO.Path]::GetFullPath($observerEvidence) -cne [IO.Path]::GetFullPath($generationEvidence)) -and @($lifeResult.evidenceReferences|Where-Object{$_.kind -eq 'observer-summary' -and $_.sha256}).Count -gt 0 -and @($lifeResult.evidenceReferences|Where-Object{$_.kind -eq 'lifecycle-generation' -and $_.sha256}).Count -gt 0) 'observer summary and lifecycle-generation evidence remain isolated with hash references'
$dispatchTrace=[System.Collections.Generic.List[string]]::new()
$syntheticProvider={param($s);[void]$dispatchTrace.Add('SYNTHETIC');[pscustomobject]@{status='PASS';productLifecycleTouched=$false}}
$dispatchContext=[pscustomobject]@{phaseId='REBOOT-RESUME';runDir=$lifeRoot;vmId=$lifeContext.vmId;vmName=$lifeContext.vmName;candidate=$lifeContext.candidate;config=$lifeContext.config;phaseBudgetSeconds=60;lifecycleWpfProvider=$wpf;lifecycleTransitionProvider=$transition;lifecycleRebootProvider=$reboot;lifecycleSettleProvider=$settle;syntheticRebootProvider=$syntheticProvider}
$dispatchBefore=$global:DevFleetProductDispatchCount;$dispatchResult=Invoke-ProductLifecycleConsumer -Context $dispatchContext
Check ([string]$dispatchResult.contract -eq 'synthetic-probe-then-pure-product-lifecycle' -and $dispatchTrace[0] -eq 'SYNTHETIC' -and ($global:DevFleetProductDispatchCount-$dispatchBefore) -eq 1) 'LIFE-04 actual REBOOT-RESUME dispatch invokes synthetic then exactly one product lifecycle'
$pureBefore=$dispatchTrace.Count;$pureProductBefore=$global:DevFleetProductDispatchCount
foreach($purePhase in @('LINUX','SURROGATE-DISPOSABLE','DEPENDENCY-MATRIX','MAINTENANCE-READY-PROVISION')){$dispatchContext.phaseId=$purePhase;[void](Invoke-ProductLifecycleConsumer -Context $dispatchContext)}
Check ($dispatchTrace.Count -eq $pureBefore -and ($global:DevFleetProductDispatchCount-$pureProductBefore) -eq 4) 'LIFE-05 actual Linux/surrogate/dependency/maintenance dispatch each invokes product once and synthetic zero'
$maintenanceDispatch=[pscustomobject]@{phaseId='MAINTENANCE-READY';runDir=$lifeRoot;vmId=$lifeContext.vmId;vmName=$lifeContext.vmName;candidate=$lifeContext.candidate;config=$lifeContext.config;phaseBudgetSeconds=60;lifecycleWpfProvider=$wpf;lifecycleTransitionProvider=$transition;lifecycleRebootProvider=$reboot;lifecycleSettleProvider=$settle};Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\FullRelease.psm1') -Force;$maintenanceDispatchResult=Invoke-MaintenanceReadyProductLifecycle -WorkspaceRoot $WorkspaceRoot -Context $maintenanceDispatch
Check ([string]$maintenanceDispatchResult.phase -eq 'MAINTENANCE-READY-PROVISION' -and [bool]$maintenanceDispatchResult.completionVerified) 'FullRelease maintenance provisioning uses dedicated pure product dispatch'
Check ($source -match "'FRESH-INSTALL-WPF'" -and $source -match "Invoke-SupportedFreshInstallLifecycle[\s\S]{0,180}-CompleteLifecycle" -and $source -match 'FRESH-INSTALL-WPF requires verified lifecycle completion') 'LIFE-05 FRESH-INSTALL-WPF cannot promote a non-terminal lifecycle boundary'
} finally {
    foreach($dir in @($script:testEvidenceDirs)){if($dir -and (Test-Path -LiteralPath $dir)){$resolved=[IO.Path]::GetFullPath($dir);if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^devfleet-(?:observer-[a-z0-9-]+|role-chain)-[a-f0-9]{32}$'){throw 'Observer fixture cleanup path rejected.'};Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}}
    if($lifeRoot -and (Test-Path -LiteralPath $lifeRoot)){$resolved=[IO.Path]::GetFullPath($lifeRoot);if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^devfleet-life-[a-f0-9]{32}$'){throw 'Lifecycle fixture cleanup path rejected.'};Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
[pscustomobject]@{status=if($failed.Count -eq 0){'PASS'}else{'FAIL'};passed=$passed;failures=@($failed)}|ConvertTo-Json -Depth 5
if($failed.Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-MaintenanceFallbackHealth.ps1

SHA256: 26c4b4a811d3107f8e533fd8ed460cf825f77fc7aafd5155f1ad646abe516e8c | Bytes: 4264 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot,[string]$ReportPath)
$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
if(-not$WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
$module=Get-Module Invoke-RealProductPhase
$results=& $module {
    # Inert typed identity only: no session constructor, connection or methods.
    # Every external remoting/clock/file boundary below is replaced.
    $script:FallbackSession=[Runtime.Serialization.FormatterServices]::GetUninitializedObject([System.Management.Automation.Runspaces.PSSession])
    function script:Get-Date {return $script:FallbackClock}
    function script:Start-Sleep {param($Seconds)$script:FallbackClock=$script:FallbackClock.AddSeconds(200)}
    function script:Write-EvidenceJson {param($Path,$Value)}
    function script:Invoke-Command {param($Session,$ScriptBlock,$ArgumentList)return @{fixtureDiagnostic=$true}}
    function script:Invoke-MaintenanceReadyGuestValidation {
        param($VmId,$Fingerprint,$Session,$OwnerDeadlineUtc)
        $script:ValidationCalls++
        if(-not[object]::ReferenceEquals($Session,$script:FallbackSession)-or$OwnerDeadlineUtc-ne$script:FallbackStart.AddSeconds(180)){throw 'Fallback changed borrowed session or owner deadline.'}
        if($script:FallbackCase-eq'late'){$script:FallbackClock=$script:FallbackClock.AddSeconds(181)}
        return @{status='PASS';hostAgentHealth=@{authenticated=$(if($script:FallbackCase-eq'string-auth'){'true'}elseif($script:FallbackCase-eq'no-auth'){$false}else{$true});ok=$true;hostName='fixture-host';hostId='fixture-id'}}
    }
    function script:Invoke-DevFleetBoundedGuestCommand {
        param($Session,$TimeoutSeconds,$ScriptBlock,$ArgumentList)
        if($TimeoutSeconds-le0-or$TimeoutSeconds-gt10-or$ScriptBlock.ToString().Contains('Invoke-HostAgentAuthenticatedJson')){throw 'Receipt command escaped its bounded metadata-only contract.'}
        $script:ReceiptCalls++
        if($script:FallbackCase-eq'receipt-timeout'){throw 'Fixture bounded receipt timeout.'}
        return &$ScriptBlock @ArgumentList
    }
    function script:Test-Path {param($LiteralPath,$PathType)return $script:FallbackCase-eq'checkpoint'}
    function script:Get-ChildItem {param($LiteralPath,$Filter,[switch]$File,$ErrorAction)return [pscustomobject]@{FullName='fixture-receipt.json'}}
    function script:Get-Content {param($LiteralPath,[switch]$Raw)return (@{payloadSha256=$(if($script:FallbackCase-eq'wrong-receipt'){'a'*64}else{'b'*64})}|ConvertTo-Json -Compress)}
    $rows=@()
    foreach($case in @('healthy','checkpoint','wrong-receipt','no-auth','string-auth','late','receipt-timeout')){
        $script:FallbackCase=$case;$script:FallbackStart=[datetime]::UtcNow;$script:FallbackClock=$script:FallbackStart;$script:ValidationCalls=0;$script:ReceiptCalls=0
        $context=[pscustomobject]@{runId='fixture';phaseId='REBOOT-RESUME';runDir='C:\Fixture';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';candidate=@{tar=@{sha256=('b'*64)};candidate=@{path='C:\Fixture\DevFleet.exe'}}}
        $value=$null;$errorText=''
        try{$value=Invoke-RebootResumeWpfFallback -Context $context -Session $script:FallbackSession -DriverReport ([pscustomobject]@{})}catch{$errorText=$_.Exception.Message}
        $pass=if($case-eq'healthy'){$value.status-eq'PASS'-and$value.authenticatedHealth-and$value.checkpointConsumed-and$value.health.hostName-eq'fixture-host'-and$script:ReceiptCalls-eq1}else{-not$value-and[bool]$errorText}
        $rows+=@([pscustomobject]@{case=$case;pass=($pass-and$script:ValidationCalls-eq1);error=if($pass){''}else{$errorText}})
    }
    return $rows
}
$report=@{parentPowerShellVersion=$PSVersionTable.PSVersion.ToString();actualSecretUsed=$false;vmOperations=0;passed=@($results|Where-Object pass).Count;total=$results.Count;cases=@($results)}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath}
Write-Host "PASS $($report.passed)/$($report.total) actual fallback health/receipt checks"
if($report.passed-ne$report.total){$results|Where-Object{-not$_.pass}|Format-List;exit 1}

```


## FILE: automation/release-e2e/tests/Test-MaintenanceValidationRuntime.ps1

SHA256: ceb4b22547ca790f599c4c143f5a6a1720be6362959740815cb1d8a683f3a260 | Bytes: 10597 | Git mode: 100644

```
[CmdletBinding()]
param([string]$PythonPath='python.exe',[string]$FixtureRoot,[string]$ReportPath)
$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if(-not$FixtureRoot){
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $root=Join-Path $parent ('devfleet-maintenance-runtime-'+[guid]::NewGuid().ToString('N'))
    $server=$null
    try{
        New-Item -ItemType Directory -Path (Join-Path $root 'DevFleetHostAgent'),(Join-Path $root 'M-TechLabs/DevFleet/Installer')|Out-Null
        [IO.File]::SetAttributes($root,([IO.File]::GetAttributes($root)-bor[IO.FileAttributes]::Hidden))
        foreach($name in @('DevFleet-HostAgentProtocol.psm1','DevFleet-WindowsIntegrationOwnership.psm1')){Copy-Item -LiteralPath (Join-Path $repo ('source/windows/'+$name)) -Destination (Join-Path $root ('DevFleetHostAgent/'+$name))}
        [IO.File]::WriteAllText((Join-Path $root 'DevFleetHostAgent/token.txt'),('x'*48))
        [IO.File]::WriteAllText((Join-Path $root 'case.txt'),'healthy')
        $generation=[guid]::NewGuid().ToString()
        $service=@{Name='FixtureService';ImagePath='C:\Fixture\service.exe';Account='LocalSystem';StartMode='Auto';Marker='fixture-owned';Generation=$generation}
        $ownership=@{SchemaVersion=1;InstallationGeneration=$generation;ScheduledTasks=@();FirewallRules=@();Services=@($service)}
        $install=@{DevFleetVersion='1.2.13';InstallerVersion='1.4.1';PackageSha256=('b'*64);WindowsIntegrationOwnershipPath=(Join-Path $root 'DevFleetHostAgent/integration-ownership.json');InstallationGeneration=$generation}
        $ownership|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'DevFleetHostAgent/integration-ownership.json')
        $install|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'M-TechLabs/DevFleet/Installer/install-state.json')
        @{Name=$service.Name;PathName=$service.ImagePath;StartName=$service.Account;StartMode=$service.StartMode}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'service.json')
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=(Get-Command $PythonPath).Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
        foreach($arg in @((Join-Path $PSScriptRoot 'fixtures/host-health-server.py'),$root)){[void]$psi.ArgumentList.Add($arg)}
        $server=[Diagnostics.Process]::Start($psi);$until=[datetime]::UtcNow.AddSeconds(10)
        while(-not(Test-Path -LiteralPath (Join-Path $root 'port.txt'))-and[datetime]::UtcNow-lt$until-and-not$server.HasExited){Start-Sleep -Milliseconds 100}
        if(-not(Test-Path -LiteralPath (Join-Path $root 'port.txt'))){throw 'Owned maintenance fixture server did not become ready.'}
        $reports=@()
        foreach($engine in @('powershell.exe','pwsh.exe')){
            $output=Join-Path $root ($engine+'.json')
            & $engine -NoProfile -File $PSCommandPath -FixtureRoot $root -ReportPath $output
            $code=$LASTEXITCODE
            if(Test-Path -LiteralPath $output){$reports+=Get-Content -Raw -LiteralPath $output|ConvertFrom-Json}
            if($ReportPath){$reports|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $ReportPath}
            if($code-ne0){throw "Maintenance runtime checks failed under $engine."}
        }
        Write-Host "PASS $(($reports|Measure-Object passed -Sum).Sum)/$(($reports|Measure-Object total -Sum).Sum) maintenance runtime checks"
    }finally{
        if($server){if(-not$server.HasExited){$server.Kill();[void]$server.WaitForExit(5000)};$server.Dispose()}
        $resolved=[IO.Path]::GetFullPath($root)
        if([IO.Path]::GetDirectoryName($resolved)-cne$parent-or[IO.Path]::GetFileName($resolved)-notmatch'^devfleet-maintenance-runtime-[0-9a-f]{32}$'){throw 'Fixture cleanup escaped its owner.'}
        if(Test-Path -LiteralPath $resolved){if((Get-Item -LiteralPath $resolved -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Fixture root reparse refused.'};Remove-Item -LiteralPath $resolved -Recurse -Force}
    }
    return
}
Import-Module (Join-Path $repo 'automation/release-e2e/modules/FullRelease.psm1') -Force -DisableNameChecking
$module=Get-Module FullRelease
& $module {
    param($Root)
    $script:FixtureRoot=$Root;$script:FixtureCase='';$script:FixtureOpened=0;$script:FixtureClosed=0;$script:FixtureCalls=0
    function script:Connect-DevFleetGuest {param($VmId)$script:FixtureOpened++;return [pscustomobject]@{Runspace=@{ConnectionInfo=@{VMGuid=$VmId}}}}
    function script:Remove-DevFleetGuestSession {param($Session)$script:FixtureClosed++}
    function script:Invoke-DevFleetBoundedGuestProcess {
        param($Session,$FilePath,$ArgumentList,$OwnerDeadlineUtc)
        $script:FixtureCalls++;$script:FixtureBudget=($OwnerDeadlineUtc-[datetime]::UtcNow).TotalSeconds
        if($FilePath-cne'C:\Program Files\PowerShell\7\pwsh.exe'-or$ArgumentList.Count-ne4-or$ArgumentList[2]-cne'-EncodedCommand'){throw 'PS7 encoded launch contract differs.'}
        $body=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[3]))
        if($body.Contains('x'*48)){throw 'Synthetic secret escaped into process arguments.'}
        $body=$body.Replace('C:\ProgramData',$script:FixtureRoot).Replace('http://127.0.0.1:8790/healthz',('http://127.0.0.1:'+(Get-Content (Join-Path $script:FixtureRoot 'port.txt'))+'/healthz'))
        $prefix='$env:ProgramData='''+$script:FixtureRoot.Replace("'","''")+''';function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) Get-Content -Raw -LiteralPath (Join-Path $env:ProgramData ''service.json'')|ConvertFrom-Json};'
        $arguments=@('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prefix+$body)))
        $json=@{filePath=$FilePath;arguments=$arguments;deadlineUnixMilliseconds=([DateTimeOffset]$OwnerDeadlineUtc).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress
        $raw=& (Get-DevFleetBoundedProcessScriptBlock) $json
        if($script:FixtureCase-eq'incomplete'){$raw.outputComplete=$false}
        if($script:FixtureCase-eq'late'){Start-Sleep -Milliseconds ([int][math]::Max(1,($OwnerDeadlineUtc-[datetime]::UtcNow).TotalMilliseconds+20))}
        if($script:FixtureCase-eq'old-runtime'){$value=$raw.stdout|ConvertFrom-Json;$value.runtimeVersion='5.1';$raw.stdout=$value|ConvertTo-Json -Depth 8 -Compress}
        if($script:FixtureCase-eq'forged-boolean'){$value=$raw.stdout|ConvertFrom-Json;$value.hostAgentHealth.authenticated='true';$raw.stdout=$value|ConvertTo-Json -Depth 8 -Compress}
        return $raw
    }
} $FixtureRoot
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$results.Add([pscustomobject]@{case=$Name;pass=$Pass})}
$installPath=Join-Path $FixtureRoot 'M-TechLabs/DevFleet/Installer/install-state.json'
$ownershipPath=Join-Path $FixtureRoot 'DevFleetHostAgent/integration-ownership.json'
$protocolPath=Join-Path $FixtureRoot 'DevFleetHostAgent/DevFleet-HostAgentProtocol.psm1'
$originalInstall=[IO.File]::ReadAllBytes($installPath);$originalOwnership=[IO.File]::ReadAllBytes($ownershipPath);$originalProtocol=[IO.File]::ReadAllBytes($protocolPath)
foreach($case in @('healthy','owned-session','wrong-session','bad-signature','wrong-host','unauthorized','not-ok','string-health','wrong-payload','wrong-ownership','wrong-protocol','incomplete','old-runtime','forged-boolean','expired','late')){
    [IO.File]::WriteAllBytes($installPath,$originalInstall);[IO.File]::WriteAllBytes($ownershipPath,$originalOwnership);[IO.File]::WriteAllBytes($protocolPath,$originalProtocol)
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'case.txt'),$(if($case-in@('bad-signature','wrong-host','unauthorized','not-ok','string-health')){$case}else{'healthy'}))
    if($case-eq'wrong-payload'){$v=Get-Content -Raw $installPath|ConvertFrom-Json;$v.PackageSha256='a'*64;$v|ConvertTo-Json|Set-Content -LiteralPath $installPath}
    if($case-eq'wrong-ownership'){$v=Get-Content -Raw $ownershipPath|ConvertFrom-Json;$v.InstallationGeneration=[guid]::NewGuid().ToString();$v|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ownershipPath}
    if($case-eq'wrong-protocol'){Add-Content -LiteralPath $protocolPath -Value '# fixture mismatch'}
    $observed=& $module {
        param($Case)
        $script:FixtureCase=$Case;$opened=$script:FixtureOpened;$closed=$script:FixtureClosed;$calls=$script:FixtureCalls
        $deadline=[datetime]::UtcNow.AddSeconds($(if($Case-eq'expired'){-1}elseif($Case-eq'late'){11.5}else{100}))
        $args=@{VmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';Fingerprint=[pscustomobject]@{releaseVersion='1.2.13';installerVersion='1.4.1';tar=@{sha256=('b'*64)}};OwnerDeadlineUtc=$deadline}
        if($Case-ne'owned-session'){$args.Session=[pscustomobject]@{Runspace=@{ConnectionInfo=@{VMGuid=$(if($Case-eq'wrong-session'){[guid]::NewGuid()}else{$args.VmId})}}}}
        $value=$null;$errorText=''
        try{$value=Invoke-MaintenanceReadyGuestValidation @args}catch{$errorText=$_.Exception.Message}
        [pscustomobject]@{value=$value;error=$errorText;opened=$script:FixtureOpened-$opened;closed=$script:FixtureClosed-$closed;calls=$script:FixtureCalls-$calls;budget=$script:FixtureBudget}
    } $case
    $expectedPass=$case-in@('healthy','owned-session')
    $pass=if($expectedPass){$observed.value.status-eq'PASS'-and$observed.value.runtimeVersion-like'7.*'-and$observed.value.hostAgentHealth.authenticated}else{-not$observed.value-and[bool]$observed.error}
    if($case-eq'owned-session'){$pass=$pass-and$observed.opened-eq1-and$observed.closed-eq1}else{$pass=$pass-and$observed.opened-eq0-and$observed.closed-eq0}
    if($case-in@('expired','wrong-session')){$pass=$pass-and$observed.calls-eq0}
    $pass=$pass-and($observed|ConvertTo-Json -Depth 8)-notmatch('x'*48)
    Check $case $pass
    if(-not$pass){Write-Host ($case+': '+$observed.error)}
}
[IO.File]::WriteAllBytes($installPath,$originalInstall);[IO.File]::WriteAllBytes($ownershipPath,$originalOwnership);[IO.File]::WriteAllBytes($protocolPath,$originalProtocol)
$report=@{parentPowerShellVersion=$PSVersionTable.PSVersion.ToString();actualSecretUsed=$false;vmOperations=0;passed=@($results|Where-Object pass).Count;total=$results.Count;cases=@($results)}
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath
Write-Host "PS $($report.parentPowerShellVersion): $($report.passed)/$($report.total) maintenance runtime checks"
if($report.passed-ne$report.total){$results|Where-Object{-not$_.pass}|Format-Table;exit 1}

```


## FILE: automation/release-e2e/tests/Test-MaintenanceVaultCheckpoint.ps1

SHA256: e4d66a1b7b56cc203d6fd905494bd2d816af0bc0660cd0de398846d537bbc3db | Bytes: 3323 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1') -Force -DisableNameChecking
$module=Get-Module FullRelease
$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-fixture-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $temp 'audit/automation-harness'))|Out-Null
& $module {
    param($temp)
    $script:trace=[Collections.Generic.List[string]]::new();$script:created=$false
    $script:testVm=[pscustomobject]@{Name='DevFleet-E2E-Unit';Id=[guid]::NewGuid();State='Off'}
    $script:snapshot=[pscustomobject]@{Name='DevFleet-E2E-MAINTENANCE-READY';Id=[guid]::NewGuid()}
    function script:Get-AssertedDisposableVm {param($ExpectedVm) return $script:testVm}
    function script:Get-VMSnapshot {param($VM,$ErrorAction) if($script:created){$script:snapshot}}
    function script:Get-ExactCheckpoint {param($Vm,$Name) return $script:snapshot}
    function script:Restore-ExactCheckpoint {param($Vm,$Name,[switch]$StartAfterRestore) return [pscustomobject]@{id=$script:snapshot.Id;name=$Name}}
    function script:Invoke-MaintenanceReadyProductLifecycle {param($WorkspaceRoot,$Context) $script:trace.Add('provision-primary');return [pscustomobject]@{status='PASS'}}
    function script:Initialize-MaintenanceVaultFixture {param($Context) $script:trace.Add('configure-vault');return [pscustomobject]@{status='PASS';configurationPresent=$true;authenticatedTransport=$true;proofCredit=$false;primaryRole='primary';payloadSha256=('a'*64);primaryId='11111111-1111-1111-1111-111111111111';vaultId='22222222-2222-2222-2222-222222222222';deploymentId='33333333-3333-3333-3333-333333333333'}}
    function script:Invoke-MaintenanceReadyGuestValidation {param($VmId,$Fingerprint) return [pscustomobject]@{status='PASS';installationGeneration='unit-generation';devFleetVersion='1.2.13';installerVersion='1.2.13';packageSha256=('a'*64);installLedgerSha256=('b'*64);ownershipSchemaVersion=1;ownershipLedgerSha256=('c'*64);bindingCount=1}}
    function script:Checkpoint-VM {param($VM,$SnapshotName,$ErrorAction) $script:trace.Add('checkpoint');$script:created=$true}
    function script:Start-Sleep {param($Seconds)}
    $fingerprint=[pscustomobject]@{gitCommit=('d'*40);releaseVersion='1.2.13';installerVersion='1.2.13';releaseFingerprintId=('e'*64);toolingFingerprintId=('f'*64);tar=[pscustomobject]@{sha256=('a'*64)}}
    $result=Ensure-MaintenanceReadyFixture -Vm $script:testVm -Fingerprint $fingerprint -Config ([pscustomobject]@{}) -WorkspaceRoot $temp -RunId 'fullrelease-fixture-unit' -RunDir $temp
    if(($script:trace-join ',')-cne'provision-primary,configure-vault,checkpoint'){throw ('REAL FIXTURE MISSING CONFIGURED VAULT: '+($script:trace-join ','))}
    if(-not$result.vault.configurationPresent){throw 'Fixture configuration result was not preserved.'}
    $saved=Get-Content (Join-Path $temp 'audit/automation-harness/maintenance-ready-provenance.json') -Raw|ConvertFrom-Json
    if(-not$saved.vault.configurationPresent){throw 'Checkpoint provenance omitted its configured Vault.'}
    [ordered]@{status='PASS';realFixtureEntryPoint=$true;externalIoMocked=$true;vmMutation=$false;trace=@($script:trace)}|ConvertTo-Json
} $temp

```


## FILE: automation/release-e2e/tests/Test-MaintenanceVaultFixture.ps1

SHA256: 29411799477e999eaaf191451f3e2ec4543167d9830702ce0be06b2dda838377 | Bytes: 4414 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$modulePath=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/MaintenanceVault.psm1'
Import-Module $modulePath -Force
$module=Get-Module MaintenanceVault
$results=& $module {
    $script:steps=[Collections.Generic.List[string]]::new()
    $script:fixture=[pscustomobject]@{status='PASS';primaryName='devfleet-primary';primaryId='11111111-1111-1111-1111-111111111111';vaultName='devfleet-vault';vaultId='22222222-2222-2222-2222-222222222222';deploymentId='33333333-3333-3333-3333-333333333333';primaryRole='primary';configurationPresent=$true;authenticatedTransport=$true;proofCredit=$false;payloadSha256=('a'*64)}
    $script:existingVault=$false;$script:failStep='';$script:role='primary'
    # Only external product/VM operations are replaced; exercise the actual
    # prerequisite ordering and fail-closed result validation.
    function script:Invoke-MaintenanceVaultStep {
        param($Name,$Request,$State)
        $script:steps.Add($Name)
        if($Name-ceq$script:failStep){throw "ORIGINAL_$Name"}
        switch($Name){
            'identity' {return [pscustomobject]@{primaryRole=$script:role;existingVault=$script:existingVault;primaryId=$script:fixture.primaryId;deploymentId=$script:fixture.deploymentId}}
            'launch' {return [pscustomobject]@{vaultId=$script:fixture.vaultId}}
            'verify' {return $script:fixture}
        }
    }
    function Check($Value,$Message){if(-not$Value){throw $Message}}
    $request=[pscustomobject]@{runId='fullrelease-fixture-unit';payloadSha256=('a'*64);primaryName='devfleet-primary';vaultName='devfleet-vault';ownerDeadlineUtc=[datetime]::UtcNow.AddSeconds(60).ToString('o')}
    $actual=Invoke-MaintenanceVaultProvisioning -Request $request
    Check ($actual.status-ceq'PASS') 'configured Primary fixture was not accepted'
    Check (($script:steps -join ',')-ceq'identity,launch,bootstrap,configure,verify') 'configuration must precede verification and checkpoint publication'
    $script:steps.Clear();$script:existingVault=$true;$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'existing Vault' -and ($script:steps -join ',')-ceq'identity') 'preexisting Vault must never be adopted or refreshed'
    $script:existingVault=$false;$script:role='surrogate';$script:steps.Clear();$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'Primary' -and $script:steps.Count-eq1) 'Surrogate must not substitute for Primary'
    $script:role='primary';$script:failStep='bootstrap';$script:steps.Clear();$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-ceq'ORIGINAL_bootstrap' -and ($script:steps -join ',')-ceq'identity,launch,bootstrap') 'bootstrap failure must preserve the original error and forbid configure/credit'
    $script:failStep='';$script:fixture.configurationPresent=$false;$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'configuration') 'unconfigured fixture must not pass'
    $script:fixture.configurationPresent=$true;$script:fixture.payloadSha256=('b'*64);$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'payload') 'stale fixture must not pass'
    $script:fixture.payloadSha256=('a'*64);$script:fixture.proofCredit=$true;$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'credit') 'prerequisite must never award proof credit'
    $script:fixture.proofCredit=$false;$request.ownerDeadlineUtc=[datetime]::UtcNow.AddSeconds(-1).ToString('o');$script:steps.Clear();$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'deadline' -and $script:steps.Count-eq0) 'expired owner must prevent any VM operation'
    [pscustomobject]@{status='PASS';cases=8;externalIoMocked=$true;vmMutation=$false;runtime=$PSVersionTable.PSVersion.ToString()}
}
$results|ConvertTo-Json -Depth 6

```


## FILE: automation/release-e2e/tests/Test-MaintenanceVaultImports.ps1

SHA256: a5a77a386d90166bbc51e489f734a3593b9b61c18de979bcf746ead31a4feac3 | Bytes: 2305 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$root=Join-Path $WorkspaceRoot 'automation/release-e2e/modules'
Import-Module (Join-Path $root 'FullRelease.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'MaintenanceVault.psm1') -DisableNameChecking
& (Get-Module MaintenanceVault) {
    param($root,$common)
    foreach($name in @('GuestSession','HarnessBudget','HostSafety','MultipassDiagnostic','TailscaleE2E')){Import-Module (Join-Path $root ($name+'.psm1')) -Scope Local -DisableNameChecking}
    $required=@{'Connect-DevFleetGuest'=@('VmId');'Remove-DevFleetGuestSession'=@('Session');'Copy-DevFleetBoundedGuestFile'=@('LocalPath','RemotePath','Session','TimeoutSeconds');'Get-DevFleetBoundedProcessScriptBlock'=@();'Stage-TailscaleOAuthCredential'=@('Session','RunId','Config','ProductConfig');'Remove-StagedTailscaleOAuthCredential'=@('Session');'Get-HarnessBudgetPolicy'=@('Config');'Get-HostSafetySnapshot'=@('Vm')}
    foreach($name in $required.Keys){$command=Get-Command $name -ErrorAction Stop;foreach($parameter in $required[$name]){if(-not$command.Parameters.ContainsKey($parameter)){throw "$name is missing $parameter after the complete nested imports."}}}
    Import-Module $common -Scope Local -DisableNameChecking
    # Exact nested -Force import boundary used by both shipping 04/05 scripts;
    # no product body, host state, VM, network, or credential I/O is executed.
    & {Import-Module $common -Force -DisableNameChecking}
    Import-Module $common -Scope Local -DisableNameChecking
    foreach($name in @('Get-DevFleetConfig','Get-OrCreateSecrets','Get-OrCreateVaultIdentity','New-DevFleetBootstrapBoundary','Invoke-MultipassWithStandardInput','Invoke-External','Get-DevFleetOperationMaximumSeconds','Set-DevFleetDeadlineContext')){Get-Command $name -ErrorAction Stop|Out-Null}
    foreach($name in $required.Keys){Get-Command $name -ErrorAction Stop|Out-Null}
    [ordered]@{status='PASS';hostCommands=$required.Count;productCommands=8;runtime=$PSVersionTable.PSVersion.ToString();vmMutation=$false}|ConvertTo-Json
} $root (Join-Path $WorkspaceRoot 'source/windows/DevFleet.Common.psm1')

```


## FILE: automation/release-e2e/tests/Test-MaintenanceVaultNativeSteps.ps1

SHA256: 74cc70ce0ed685a0e430fb09b8c7b25e7f59e785cf1017caf719f7ea9dd51e67 | Bytes: 8225 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $WorkspaceRoot 'source/windows/DevFleet.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/MaintenanceVault.psm1') -Force -DisableNameChecking
$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-vault-native-test-'+[guid]::NewGuid().ToString('N'))
foreach($leaf in @('windows','linux','cloud-init','work')){[IO.Directory]::CreateDirectory((Join-Path $temp $leaf))|Out-Null}
Copy-Item (Join-Path $WorkspaceRoot 'source/linux/dependency-policy.json') (Join-Path $temp 'linux/dependency-policy.json')
Copy-Item (Join-Path $WorkspaceRoot 'source/cloud-init/vault.yaml') (Join-Path $temp 'cloud-init/vault.yaml')
$tracePath=Join-Path $temp 'tailscale-order.txt'
$windowsHostScript='if(-not$env:DEVFLEET_MAINTENANCE_TEST_TRACE){throw "Missing ordering trace"};Add-Content -LiteralPath $env:DEVFLEET_MAINTENANCE_TEST_TRACE -Value "windows-host"'
$guestScript='param([string]$InstanceName);if($InstanceName-cne"devfleet-vault"){throw "Unexpected guest pairing target"};Add-Content -LiteralPath $env:DEVFLEET_MAINTENANCE_TEST_TRACE -Value ("guest:"+$InstanceName)'
$clientScript='param([string]$InstanceName);if($InstanceName-cne"devfleet-primary"){throw "Unexpected local client target"};Add-Content -LiteralPath $env:DEVFLEET_MAINTENANCE_TEST_TRACE -Value ("client:"+$InstanceName)'
[IO.File]::WriteAllText((Join-Path $temp 'windows/04a-Connect-WindowsTailscale.ps1'),$windowsHostScript,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $temp 'windows/04-Connect-Tailscale.ps1'),$guestScript,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $temp 'windows/05-Configure-LocalVaultClient.ps1'),$clientScript,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $temp 'node-identity.json'),'{"node_role":"primary","deployment_id":"33333333-3333-3333-3333-333333333333"}',[Text.UTF8Encoding]::new($false))
$oldComputer=$env:COMPUTERNAME
$oldTrace=$env:DEVFLEET_MAINTENANCE_TEST_TRACE
try{
    $env:COMPUTERNAME='DEVFLEET-E2E-01' # Test-process environment only; restored below.
    $env:DEVFLEET_MAINTENANCE_TEST_TRACE=$tracePath
    & (Get-Module MaintenanceVault) {
        param($temp,$workspace)
        $script:testRoot=$temp;$script:created=$false;$script:stdinDelivered=$false
        $script:steps=[Collections.Generic.List[string]]::new()
        $script:testConfig=[pscustomobject]@{Primary=[pscustomobject]@{InstanceName='devfleet-primary'};Vault=[pscustomobject]@{InstanceName='devfleet-vault';UbuntuImage='24.04';Cpus=2;Memory='3G';Disk='80G'};Network=[pscustomobject]@{VaultPort=8000};ClusterName='unit-fixture'}
        # External filesystem-root discovery, VM, transport and credential I/O
        # only. The real fixture steps, payload zip, cloud-init rendering, and
        # production New-DevFleetBootstrapBoundary execute without mocks.
        function script:Import-Module {param($Name,$Scope,[switch]$DisableNameChecking)}
        function script:Get-DevFleetConfig {return $script:testConfig}
        function script:Get-DevFleetStateRoot {return $script:testRoot}
        function script:Get-MultipassExe {return 'unit-only-multipass'}
        function script:Set-DevFleetDeadlineContext {param($TransactionDeadlineUtc,$StageName,$StageBudgetSeconds)}
        function script:Get-DevFleetOperationMaximumSeconds {param($Name) return 60}
        function script:Assert-MultipassIsolation {param($InstanceNames) if(($InstanceNames-join ',')-cne'devfleet-primary'){throw 'Wrong isolation target'}}
        function script:Get-VM {
            param($Name,[guid]$Id,$ErrorAction)
            $primary=[pscustomobject]@{Name='devfleet-primary';Id=[guid]'11111111-1111-1111-1111-111111111111'}
            $vault=[pscustomobject]@{Name='devfleet-vault';Id=[guid]'22222222-2222-2222-2222-222222222222'}
            if($Name-eq'devfleet-primary'-or$Id-eq$primary.Id){return $primary}
            if($Name-eq'devfleet-vault'-or$Id-eq$vault.Id){if(-not$script:created){throw 'Vault is absent'};return $vault}
            return $primary
        }
        function script:Invoke-External {
            param($FilePath,$ArgumentList,[switch]$Capture,$TimeoutSeconds,$DeadlineUtc)
            if($FilePath-cne'unit-only-multipass'){throw 'Unexpected executable'}
            $script:steps.Add([string]$ArgumentList[0])
            if($ArgumentList[0]-eq'list'){return '{"list":[{"name":"devfleet-primary","state":"Running"}]}'}
            if($ArgumentList[0]-eq'transfer'-and-not(Test-Path -LiteralPath $ArgumentList[1] -PathType Leaf)){throw 'Payload zip was not created'}
            if($ArgumentList[0]-eq'exec'-and$ArgumentList[1]-notin@('devfleet-vault','devfleet-primary')){throw 'Unexpected command target'}
        }
        function script:Invoke-MultipassLaunchWithReadinessRecovery {
            param($InstanceName,$LaunchArguments,$ReadinessTimeoutSeconds,$LaunchTimeoutSeconds,$DeadlineUtc)
            if($InstanceName-cne'devfleet-vault'-or$ReadinessTimeoutSeconds-le0-or$DeadlineUtc-le[datetime]::UtcNow){throw 'Invalid bounded fresh launch'}
            $cloud=Get-Content -LiteralPath $LaunchArguments[-1] -Raw
            if($cloud-match'__[A-Z0-9_]+__'-or$cloud-notmatch"hostname: 'devfleet-vault'"){throw 'Actual cloud-init rendering is incomplete'}
            $script:created=$true
        }
        function script:Get-OrCreateSecrets {return [pscustomobject]@{VaultRestUser='unit';VaultRestPassword='unit-only-fake';ResticPassword='unit-only-fake'}}
        function script:Get-OrCreateVaultIdentity {return [pscustomobject]@{deployment_id='33333333-3333-3333-3333-333333333333';node_id='44444444-4444-4444-4444-444444444444';node_name='devfleet-vault'}}
        function script:Invoke-MultipassWithStandardInput {
            param($FilePath,$InstanceName,$CommandArgumentList,$TimeoutSeconds,$DeadlineUtc,$StandardInputText)
            $value=$StandardInputText|ConvertFrom-Json
            if($value.DeploymentId-cne'33333333-3333-3333-3333-333333333333'-or$InstanceName-cne'devfleet-vault'-or$TimeoutSeconds-le0-or$DeadlineUtc-le[datetime]::UtcNow){throw 'Bootstrap binding/deadline is invalid'}
            if(($CommandArgumentList-join ' ')-match'unit-only-fake'-or($CommandArgumentList-join ' ')-notmatch'--secrets-stdin'){throw 'Secrets must use bounded stdin only'}
            $script:stdinDelivered=$true
        }
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $workspace 'automation/release-e2e/modules/MaintenanceVault.psm1'),[ref]$tokens,[ref]$errors)
        $initializer=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$request'-and$n.Right.Extent.Text-match'inputHashes=\[ordered\]'},$true))
        if($initializer.Count-ne1){throw 'Native host request construction is ambiguous'}
        $Context=[pscustomobject]@{runId='fullrelease-fixture-unit';candidate=[pscustomobject]@{tar=[pscustomobject]@{sha256=('a'*64)}}};$config=$script:testConfig;$deadline=[datetime]::UtcNow.AddSeconds(60);$budget=60
        . ([scriptblock]::Create(