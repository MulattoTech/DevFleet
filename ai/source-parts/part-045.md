# DevFleet source part 045

Full-source UTF-8 byte interval [2046000, 2092500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 05621d23f7478b74f699d79c921ff1e239dc0711d0ce613d3f2a7ba84a3faff5

<!-- BEGIN SOURCE SLICE -->
PF'" -and $source -match "Invoke-SupportedFreshInstallLifecycle[\s\S]{0,180}-CompleteLifecycle" -and $source -match 'FRESH-INSTALL-WPF requires verified lifecycle completion') 'LIFE-05 FRESH-INSTALL-WPF cannot promote a non-terminal lifecycle boundary'
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
        . ([scriptblock]::Create($initializer[0].Extent.Text))
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
            std