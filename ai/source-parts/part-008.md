# DevFleet source part 008

Full-source UTF-8 byte interval [325500, 372000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ab9865632b0c334af15d71ea53ed22c2a8f13a7c8da16631b2f100daab024223

<!-- BEGIN SOURCE SLICE -->
ndidateSha256=$fingerprint.candidate.sha256}|ConvertTo-Json -Depth 8 -Compress
} catch {
    $errorText = $_.Exception.Message
    try { Write-EvidenceJson -Path (Join-Path $runDir 'proof-error.json') -Value ([ordered]@{status='BLOCKED';runId=$RunId;error=$errorText;passwordLogged=$false}) } catch { }
    try { Set-CurrentProofPointer $(if($DiagnosticOnly){'DIAGNOSTIC_NOT_OBSERVED'}else{'NOT_OBSERVED'}) } catch { try { Write-EvidenceJson -Path (Join-Path $runDir 'authority-pointer-error.json') -Value ([ordered]@{status='TOOLING_ERROR';runId=$RunId;error=$_.Exception.Message;passwordLogged=$false}) } catch {} }
    [ordered]@{status='BLOCKED';runId=$RunId;error=$errorText;evidencePath=(Join-Path $runDir 'proof-error.json')}|ConvertTo-Json -Depth 8 -Compress
    $proofExitCode = 1
} finally {
    if(-not $cleanupAttempted -and $vm){$cleanupAttempted=$true;try{$cleanup=Invoke-ExactProofCleanup -Vm $vm;if([string]$cleanup.status -ne 'PASS'){$proofExitCode=1}}catch{$proofExitCode=1}}
    try { & (Join-Path $WorkspaceRoot 'tools\Update-CurrentReleaseAuthority.ps1') -Workspace $WorkspaceRoot -CurrentProofRunId $RunId | Out-Null } catch { try { Write-EvidenceJson -Path (Join-Path $runDir 'authority-refresh-error.json') -Value ([ordered]@{status='TOOLING_ERROR';runId=$RunId;error=$_.Exception.Message;passwordLogged=$false}) } catch {} }
}
if($proofExitCode -ne 0){exit $proofExitCode}

```


## FILE: automation/release-e2e/Initialize-DevFleetE2ESecrets.ps1

SHA256: 34249b04ed46de9f5fa091c8ad5e6ed554a2f55873f4fce2bcedd8c4c5ce3cf3 | Bytes: 949 | Git mode: 100644

```
[CmdletBinding()]
param([string]$CredentialFile)
$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot 'modules\Secrets.psm1'
Import-Module $module -Force
if ($CredentialFile) {
    $kv=@{}
    foreach($line in Get-Content -LiteralPath $CredentialFile){ $parts=$line.Split('=',2); if($parts.Count -eq 2){$kv[$parts[0]]=$parts[1]} }
    if (-not $kv.username -or -not $kv.password) { throw 'Credential file must contain username and password keys.' }
    $secure=ConvertTo-SecureString $kv.password -AsPlainText -Force
    $credential=[pscredential]::new($kv.username,$secure)
} else {
    $username=Read-Host 'Disposable E2E username'
    $secure=Read-Host 'Disposable E2E password' -AsSecureString
    $credential=[pscredential]::new($username,$secure)
}
$path=Save-DevFleetE2ECredential -Credential $credential
[pscustomobject]@{ status='PASS'; storePath=$path; plaintextStoredInWorkspace=$false; passwordPrinted=$false } | ConvertTo-Json

```


## FILE: automation/release-e2e/Invoke-AutomatedInteractiveLoginSmoke.ps1

SHA256: 7c926fb4b5069d77cfc12d34d699c4bb9972eaba0d613f41cefe1a3156a12e3d | Bytes: 27979 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$Workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$RunId = "interactive-login-smoke-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))",
    [switch]$AllowRamPressure
)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$runRoot = Join-Path $Workspace "audit\automation-harness\runs\$RunId"
$resultPath = Join-Path $runRoot 'interactive-login-smoke.json'
$diagnosticPath = Join-Path $runRoot 'interactive-logon-attempt-diagnostic.json'
$armed = $false
$l1Touched = $false
$primary = $null
$result = $null
$arm = $null
$preBoot = $null
$postBoot = $null
$desktopProof = $null
$disarm = $null
$survival = $null
$marker = $null
$waitFailure = $null
$cleanupError = $null
$terminalState = $null
$preflight = $null
$credentialRoundTrip = $null
$attemptAfterUtc = $null
$attemptDiagnostic = [ordered]@{schemaVersion=1;status='INCOMPLETE';runId=$RunId;contract='devfleet-disposable-l1-interactive-logon-v1';vmName='DevFleet-E2E-Win11-01';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';credentialsStoredInEvidence=$false}
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

foreach ($module in @('Candidate','HostSafety','FullRelease','InteractiveLogon','GuestSession','Secrets')) {
    Import-Module (Join-Path $Workspace "automation\release-e2e\modules\$module.psm1") -Force
}
$fingerprint=Get-CandidateFingerprint -WorkspaceRoot $Workspace -CandidatePath (Join-Path $Workspace 'outputs\DevFleet-Setup-v1.2.13-win-x64.exe')
$baseline=Set-DevFleetBaselineBinding -WorkspaceRoot $Workspace -Fingerprint $fingerprint

function Write-AtomicJson([string]$Path, $Value) {
    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($tmp, (($Value | ConvertTo-Json -Depth 30) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Get-SafeSmokeError([object]$ErrorValue) {
    $message=if($ErrorValue -is [System.Management.Automation.ErrorRecord]){[string]$ErrorValue.Exception.Message}else{[string]$ErrorValue}
    if([string]::IsNullOrWhiteSpace($message)){$message='Unknown controlled smoke failure.'}
    $message=([regex]::Replace($message,'(?i)(password|secret|token|credential|hmac|dpapi|private.?key)\s*[:=]\s*\S+','$1=<redacted>')) -replace '\r?\n',' '
    if($message.Length -gt 320){$message=$message.Substring(0,320)}
    return $message
}

function Connect-ExactL1 {
    $credential = Get-DevFleetE2ECredential
    $session = New-PSSession -VMId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -Credential $credential -ErrorAction Stop
    return $session
}

function Get-GuestInteractiveLogonPreconditions {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    Invoke-Command -Session $Session -ScriptBlock {
        $safe = { param($e) $message=([string]$e.Exception.Message -replace '\r?\n',' ');$message=([regex]::Replace($message,'(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>'));if($message.Length -gt 320){$message=$message.Substring(0,320)};[ordered]@{type=$e.Exception.GetType().FullName;message=$message} }
        $securityError=$null;$latest=$null
        try {$latest=Get-WinEvent -LogName Security -MaxEvents 1 -ErrorAction Stop | Select-Object -First 1}catch{$securityError=&$safe $_}
        $user=$null;$userError=$null
        try {$user=Get-LocalUser -Name 'E2EAdmin' -ErrorAction Stop}catch{$userError=&$safe $_}
        $rights=[ordered]@{};$rightsError=$null;$cfg=Join-Path $env:TEMP "devfleet-e2e-rights-$([guid]::NewGuid().ToString('N')).inf"
        try {secedit.exe /export /cfg $cfg /areas USER_RIGHTS | Out-Null;$lines=Get-Content -LiteralPath $cfg -ErrorAction Stop;foreach($right in @('SeInteractiveLogonRight','SeDenyInteractiveLogonRight','SeRemoteInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight')){$line=$lines|Where-Object{$_ -match "^$right\s*="}|Select-Object -First 1;$rights[$right]=if($line){([string]$line -split '=',2)[1].Trim()}else{$null}}}catch{$rightsError=&$safe $_}finally{Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue}
        [ordered]@{capturedAtUtc=(Get-Date).ToUniversalTime().ToString('o');securityWatermark=[ordered]@{latestEventRecordId=if($latest){[int64]$latest.RecordId}else{0};capturedAtUtc=(Get-Date).ToUniversalTime().ToString('o');readError=$securityError};localE2EAdmin=[ordered]@{enabled=if($user){[bool]$user.Enabled}else{$null};accountExpires=if($user -and $user.AccountExpires){$user.AccountExpires.ToUniversalTime().ToString('o')}else{$null};passwordExpires=if($user -and $user.PasswordExpires){$user.PasswordExpires.ToUniversalTime().ToString('o')}else{$null};lockedOut=if($user){[bool]$user.LockedOut}else{$null};sid=if($user){$user.SID.Value}else{$null};readError=$userError};userRights=$rights;userRightsReadError=$rightsError;localGroups=[ordered]@{administrators=@(Get-LocalGroupMember -Group Administrators -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name);remoteDesktopUsers=@(Get-LocalGroupMember -Group 'Remote Desktop Users' -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name)}}
    }
}

function Get-GuestPreLogonPolicyStructure {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    $state = Get-DevFleetE2EPreLogonPolicyState -Session $Session
    return (Get-DevFleetE2EPreLogonPolicyStructure -State $state)
}

function Get-GuestInteractiveLogonPostAttempt {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][int64]$Watermark,[Parameter(Mandatory)][datetime]$AfterUtc)
    Invoke-Command -Session $Session -ScriptBlock {
        param($watermark,$afterUtc)
        $safe = { param($e) $message=([string]$e.Exception.Message -replace '\r?\n',' ');$message=([regex]::Replace($message,'(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>'));if($message.Length -gt 320){$message=$message.Substring(0,320)};[ordered]@{type=$e.Exception.GetType().FullName;message=$message} }
        $fieldNames=@('TargetUserName','TargetDomainName','LogonType','LogonProcessName','AuthenticationPackageName','ProcessName','Status','SubStatus','FailureReason','SubjectUserName','SubjectDomainName','LogonId','TargetLogonId','SubjectLogonId')
        function Convert-SecurityEvent($event) {
            [xml]$xml=$event.ToXml();$data=@{}
            foreach($item in @($xml.Event.EventData.Data)){if($item.Name){$data[[string]$item.Name]=[string]$item.'#text'}}
            $identityValues=@($data['TargetUserName'],$data['SubjectUserName'],$data['TargetDomainName'],$data['SubjectDomainName']) | Where-Object {$_}
            if(-not (@($identityValues | Where-Object {[string]$_ -match '(?i)(^|\\)E2EAdmin$'}).Count)){return $null}
            $selected=[ordered]@{};foreach($name in $fieldNames){$selected[$name]=if($data.ContainsKey($name)){[string]$data[$name]}else{$null}}
            [ordered]@{eventRecordId=[int64]$event.RecordId;timeCreated=$event.TimeCreated.ToUniversalTime().ToString('o');eventId=[int]$event.Id;fields=$selected;relevantToE2EAdmin=$true}
        }
        $security=@();$securityError=$null
        try {foreach($event in @(Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624,4625,4634,4648,4672} -ErrorAction Stop | Where-Object{[int64]$_.RecordId -gt $watermark}|Sort-Object RecordId)){$row=Convert-SecurityEvent $event;if($null -ne $row){$security+=$row}}}catch{$securityError=&$safe $_}
        $winlogon=[ordered]@{};$winlogonError=$null
        try {$key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';$item=Get-ItemProperty -LiteralPath $key -ErrorAction Stop;$winlogon=[ordered]@{AutoAdminLogon=if($null -ne $item.PSObject.Properties['AutoAdminLogon']){[string]$item.AutoAdminLogon}else{$null};AutoLogonCount=if($null -ne $item.PSObject.Properties['AutoLogonCount']){[int]$item.AutoLogonCount}else{$null};DefaultUserName=if($null -ne $item.PSObject.Properties['DefaultUserName']){[string]$item.DefaultUserName}else{$null};DefaultDomainName=if($null -ne $item.PSObject.Properties['DefaultDomainName']){[string]$item.DefaultDomainName}else{$null};ordinaryDefaultPasswordPresent=($null -ne $item.PSObject.Properties['DefaultPassword'])}}catch{$winlogonError=&$safe $_}
        function Get-OperationalEvents([string]$channel) {$rows=@();try {foreach($event in @(Get-WinEvent -FilterHashtable @{LogName=$channel;StartTime=$afterUtc} -MaxEvents 50 -ErrorAction Stop)){$rows+=[ordered]@{eventRecordId=[int64]$event.RecordId;timeCreated=$event.TimeCreated.ToUniversalTime().ToString('o');eventId=[int]$event.Id;provider=[string]$event.ProviderName;message=(([string]$event.Message -replace '\r?\n',' ')-replace '(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>')}}}catch{$rows=@([ordered]@{readError=&$safe $_})};return $rows}
        $desktop=$null;$desktopError=$null
        try {$active=@();$quserLines=@(& quser 2>&1);foreach($line in $quserLines){if(([string]$line)-match '^\s*>?\s*(\S+)\s+(\S*)\s+(\d+)\s+(Active)\s+'){$active+=[ordered]@{user=$Matches[1];sessionName=$Matches[2];sessionId=[int]$Matches[3];state='Active'}}};$explorer=@();foreach($p in @(Get-Process explorer -ErrorAction SilentlyContinue)){$row=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue;$owner=if($row){Invoke-CimMethod -InputObject $row -MethodName GetOwner -ErrorAction SilentlyContinue};$explorer+=[ordered]@{pid=[int]$p.Id;sessionId=[int]$p.SessionId;user=if($owner){[string]$owner.User}else{$null};domain=if($owner){[string]$owner.Domain}else{$null}}};$desktop=[ordered]@{quser=($quserLines -join "`n");activeSessions=$active;explorer=$explorer}}catch{$desktopError=&$safe $_}
        $rdp=[ordered]@{};$rdpError=$null
        try {$key='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server';$item=Get-ItemProperty -LiteralPath $key -ErrorAction Stop;$rdp=[ordered]@{fDenyTSConnections=if($null -ne $item.PSObject.Properties['fDenyTSConnections']){[int]$item.fDenyTSConnections}else{$null};firewallRules=@(Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop|ForEach-Object{[ordered]@{name=[string]$_.Name;enabled=[string]$_.Enabled}});listeners=@(Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{address=[string]$_.LocalAddress;port=[int]$_.LocalPort;state=[string]$_.State}});termService=[string](Get-Service TermService -ErrorAction Stop).Status}}catch{$rdpError=&$safe $_}
        [ordered]@{capturedAtUtc=(Get-Date).ToUniversalTime().ToString('o');securityWatermark=$watermark;securityEvents=$security;securityReadError=$securityError;winlogon=$winlogon;winlogonReadError=$winlogonError;rdp=$rdp;rdpReadError=$rdpError;quserExplorer=$desktop;quserExplorerReadError=$desktopError;userProfileServiceEvents=@(Get-OperationalEvents 'Microsoft-Windows-User Profiles Service/Operational');winlogonOperationalEvents=@(Get-OperationalEvents 'Microsoft-Windows-Winlogon/Operational');terminalServicesLocalSessionManagerEvents=@(Get-OperationalEvents 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational');terminalServicesRemoteConnectionManagerEvents=@(Get-OperationalEvents 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational');rdpCoreEvents=@(Get-OperationalEvents 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational')}
    } -ArgumentList $Watermark,$AfterUtc
}

try {
    $vm = Get-VM -Id ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ErrorAction Stop
    Assert-DevFleetE2EL1Identity -Vm $vm | Out-Null
    $l1Touched = $true
    $hostSnapshot = Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB 14.38
    $hostSnapshot = Apply-RamPressureOverride -Snapshot $hostSnapshot -AllowRamPressure:$AllowRamPressure
    if (-not [bool]$hostSnapshot.effectiveE2EStartAuthorized) { throw 'HOST-SAFETY blocked the automated interactive-login smoke before VM start.' }

    $clean = @(Get-VMSnapshot -Id ([guid][string]$baseline.id) -ErrorAction Stop)
    if ($clean.Count -ne 1 -or $clean[0].Name -cne [string]$baseline.name -or [string]$clean[0].VMName -cne $vm.Name -or (-not $baseline.legacyOriginal -and $clean[0].ParentSnapshotId -ne [guid][string]$baseline.predecessorId)) { throw 'Accepted CLEAN checkpoint identity was not exact and unique.' }
    $restored = Restore-ExactCheckpoint -Vm $vm -Name ([string]$baseline.name) -StartAfterRestore

    $preSession=Connect-ExactL1
    try {
        $credentialRoundTrip=Test-DevFleetE2EGuestCredential -Session $preSession -CredentialPassword (Get-DevFleetE2ECredential).Password
        $attemptDiagnostic.credentialRoundTrip=$credentialRoundTrip
        $preflight=Get-GuestInteractiveLogonPreconditions -Session $preSession
        $preflight.preLogonPolicy=Get-GuestPreLogonPolicyStructure -Session $preSession
        $attemptDiagnostic.preconditions=$preflight
        $attemptDiagnostic.securityWatermark=$preflight.securityWatermark
        if([int64]$preflight.securityWatermark.latestEventRecordId -le 0){throw 'Security event watermark was not captured.'}
        $attemptAfterUtc=[datetime]$preflight.securityWatermark.capturedAtUtc
    } finally {if($preSession){Remove-PSSession $preSession -ErrorAction SilentlyContinue}}

    $arm = Arm-DevFleetE2EInteractiveLogon -VmId $vm.Id -CredentialValidation $credentialRoundTrip
    $attemptDiagnostic.arm=[ordered]@{status=[string]$arm.status;mode=[string]$arm.mode;preBoot=[string]$arm.preBoot;autoLogonCount=if($arm.PSObject.Properties['autoLogonCount']){[int]$arm.autoLogonCount}else{$null};credentialRoundTripValidated=[bool]$arm.credentialRoundTripValidated;credentialRoundTrip=$arm.credentialRoundTrip;registryArmVerified=if($arm.PSObject.Properties['registryArmVerified']){[bool]$arm.registryArmVerified}else{$null};registryPersistenceBarrier=$arm.registryPersistenceBarrier;registryPersistenceBarrierUtc=if($arm.PSObject.Properties['registryPersistenceBarrierUtc']){[string]$arm.registryPersistenceBarrierUtc}else{$null};lsaStored=[bool]$arm.lsaStored;lsaProof=$arm.lsaProof;rdpAddress=if($arm.PSObject.Properties['rdpAddress']){[string]$arm.rdpAddress}else{$null};rdpBaseline=$arm.rdpBaseline;ordinaryDefaultPasswordPresent=[bool]$arm.ordinaryDefaultPasswordPresent;baseline=$arm.baseline;preLogonPolicy=$arm.preLogonPolicy;preLogonPolicySuppressed=if($arm.PSObject.Properties['preLogonPolicySuppressed']){[bool]$arm.preLogonPolicySuppressed}else{$null};preLogonPolicySuppressionPersisted=if($arm.PSObject.Properties['preLogonPolicySuppressionPersisted']){[bool]$arm.preLogonPolicySuppressionPersisted}else{$null};preLogonPolicyReasserted=if($arm.PSObject.Properties['preLogonPolicyReasserted']){[bool]$arm.preLogonPolicyReasserted}else{$null}}
    $armed = $true
    $preBoot = [string]$arm.preBoot
    $restart = Restart-DevFleetE2EL1 -ArmState $arm
    $attemptDiagnostic.restart=$restart
    $waitFailure=$null;$desktop=$null
    try {$desktop = Wait-DevFleetE2EInteractiveDesktop -VmId $vm.Id -RestartedAtUtc ([datetime]$restart.requestedAtUtc) -QuietSettleSeconds 60 -TimeoutSeconds 120 -PollIntervalSeconds 10} catch {$waitFailure=$_}
    $attemptDiagnostic.desktopWait=if($desktop){[ordered]@{status='PASS';boot=[string]$desktop.boot;desktop=$desktop.desktop;pollProgress=@($desktop.pollProgress)}}elseif($waitFailure -and $waitFailure.Exception.Data.Contains('interactiveDesktopDiagnostic')){$waitFailure.Exception.Data['interactiveDesktopDiagnostic']}else{[ordered]@{status='BLOCKED';failure=([string]$waitFailure.Exception.Message)}}
    if($waitFailure){if($attemptDiagnostic.desktopWait.lastSuccessfullyCollectedState){$postBoot=[string]$attemptDiagnostic.desktopWait.lastSuccessfullyCollectedState.boot};throw (Get-SafeSmokeError $waitFailure)}
    $postBoot = [string]$desktop.boot
    if (-not $preBoot -or -not $postBoot -or $preBoot -ceq $postBoot) { throw 'Automated interactive-login smoke did not prove a changed boot identity.' }
    $desktopProof = $desktop.desktop
    if ([int]$desktopProof.sessionId -le 0 -or [int]$desktopProof.explorerPid -le 0) { throw 'Automated interactive-login smoke did not prove a non-zero E2EAdmin Explorer session.' }

    # Disarm is deliberately the first action after the exact desktop proof:
    # remove ordinary DefaultPassword and clear residual LSA state before any
    # additional diagnostics or run-owned task work.
    $disarm = Disarm-DevFleetE2EInteractiveLogon -ArmState $arm
    $armed = $false
    $survival = Assert-DevFleetE2EInteractiveDesktopAfterDisarm -VmId $vm.Id
    $attemptDiagnostic.disarm=$disarm;$attemptDiagnostic.survival=$survival
    if (-not [bool]$disarm.lsaCleared -or [bool]$disarm.lsaDefaultPasswordPresent -or [bool]$disarm.ordinaryDefaultPasswordPresent -or -not [bool]$disarm.autoLogonCountRestored) { throw 'Interactive autologon disarm postconditions were incomplete.' }
    if ([int]$survival.desktop.sessionId -ne [int]$desktopProof.sessionId -or [int]$survival.desktop.sessionId -le 0) { throw 'The E2EAdmin Explorer session did not survive disarm.' }
    $postSession=$null
    try {$postSession=Connect-ExactL1;$attemptDiagnostic.postAttempt=Get-GuestInteractiveLogonPostAttempt -Session $postSession -Watermark ([int64]$preflight.securityWatermark.latestEventRecordId) -AfterUtc $attemptAfterUtc;$attemptDiagnostic.postAttempt.preLogonPolicy=Get-GuestPreLogonPolicyStructure -Session $postSession;$attemptDiagnostic.status='CAPTURED'} catch {$attemptDiagnostic.postAttemptReadError=[ordered]@{type=$_.Exception.GetType().FullName;message=([string]$_.Exception.Message -replace '(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>')}} finally {if($postSession){Remove-PSSession $postSession -ErrorAction SilentlyContinue}}
    Write-AtomicJson $diagnosticPath $attemptDiagnostic

    $taskName = "DevFleet-E2E-InteractiveSmoke-$($RunId -replace '[^A-Za-z0-9-]','-')"
    $remoteRoot = 'C:\ProgramData\DevFleet-E2E-InteractiveSmoke'
    $remoteScript = "$remoteRoot\write-marker.ps1"
    $remoteMarker = "$remoteRoot\marker.json"
    $markerScript = @'
$sessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId
[ordered]@{driverPid=[int]$PID;driverSessionId=[int]$sessionId;timestampUtc=(Get-Date).ToUniversalTime().ToString('o')} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath 'C:\ProgramData\DevFleet-E2E-InteractiveSmoke\marker.json' -Encoding UTF8
'@
    $session = Connect-ExactL1
    try {
        Invoke-Command -Session $session -ScriptBlock { param($root,$scriptPath,$scriptText) New-Item -ItemType Directory -Force -Path $root | Out-Null;Set-Content -LiteralPath $scriptPath -Value $scriptText -Encoding UTF8 } -ArgumentList $remoteRoot,$remoteScript,$markerScript
        Invoke-Command -Session $session -ScriptBlock { param($name,$scriptPath) $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`"";$principal=New-ScheduledTaskPrincipal -UserId 'DEVFLEET-E2E-01\E2EAdmin' -LogonType Interactive -RunLevel Highest;Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force | Out-Null;Start-ScheduledTask -TaskName $name } -ArgumentList $taskName,$remoteScript
        $deadline=(Get-Date).AddSeconds(60);$marker=$null
        do { Start-Sleep -Seconds 2;try{$raw=Invoke-Command -Session $session -ScriptBlock { param($p) if(Test-Path -LiteralPath $p){Get-Content -LiteralPath $p -Raw}else{$null} } -ArgumentList $remoteMarker;if($raw){$marker=$raw|ConvertFrom-Json}}catch{}} while($null -eq $marker -and (Get-Date)-lt $deadline)
        if($null -eq $marker){throw 'Run-owned interactive scheduled-task marker was not produced before the bounded deadline.'}
        if([int]$marker.driverSessionId -ne [int]$survival.desktop.sessionId -or [int]$marker.driverSessionId -le 0){throw 'Run-owned interactive scheduled task did not share the exact Explorer session.'}
    } finally {
        try { Invoke-Command -Session $session -ScriptBlock { param($name,$root) Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } -ArgumentList $taskName,$remoteRoot | Out-Null } catch {}
        if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}
    }
    $result=[ordered]@{status='PASS';runId=$RunId;contract='devfleet-disposable-l1-interactive-logon-v1';vmName=$vm.Name;vmId=$vm.Id.ToString();checkpointName=$clean[0].Name;checkpointId=$clean[0].Id.ToString();preBoot=$preBoot;postBoot=$postBoot;bootIdentityChanged=$true;activeE2EAdminSessionId=[int]$desktopProof.sessionId;explorerPid=[int]$desktopProof.explorerPid;disarm=$disarm;survivesDisarm=$true;driverPid=[int]$marker.driverPid;driverSessionId=[int]$marker.driverSessionId;markerTimestampUtc=[string]$marker.timestampUtc;taskRemoved=$true;markerRemoved=$true;hostSafety=$hostSnapshot;l1Finalization='delegated to mandatory finalizer';l2Finalization='delegated to mandatory finalizer';credentialsStoredInEvidence=$false}
    Write-AtomicJson $resultPath $result
} catch {
    $primary=Get-SafeSmokeError $_
    # Wait-DevFleetE2EInteractiveDesktop ends at the absolute arm deadline.
    # Take the one required final sanitized guest capture before disarm so a
    # failed transition remains diagnosable without exposing credentials.
    if($null -eq $attemptDiagnostic.postAttempt -and $preflight -and $attemptAfterUtc){
        $finalSession=$null
        try {$finalSession=Connect-ExactL1;$attemptDiagnostic.postAttempt=Get-GuestInteractiveLogonPostAttempt -Session $finalSession -Watermark ([int64]$preflight.securityWatermark.latestEventRecordId) -AfterUtc $attemptAfterUtc;$attemptDiagnostic.postAttempt.preLogonPolicy=Get-GuestPreLogonPolicyStructure -Session $finalSession} catch {$attemptDiagnostic.postAttemptReadError=[ordered]@{type=$_.Exception.GetType().FullName;message=([string]$_.Exception.Message -replace '(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>')}} finally {if($finalSession){Remove-PSSession $finalSession -ErrorAction SilentlyContinue}}
    }
    $result=[ordered]@{status='BLOCKED';runId=$RunId;primaryBlocker=$primary;credentialsStoredInEvidence=$false}
    try { Write-AtomicJson $resultPath $result } catch {}
    try {$attemptDiagnostic.status='BLOCKED';$attemptDiagnostic.primaryBlocker=$primary} catch {}
} finally {
    try {
        if($armed -and $arm){try { $disarm=Disarm-DevFleetE2EInteractiveLogon -ArmState $arm; $armed=$false } catch {$cleanupError=([string]$_.Exception.Message -replace '(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>')}}
        if($armed -and $arm){try { Clear-DevFleetE2EInteractiveLogonState -VmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') | Out-Null; $armed=$false } catch {$cleanupError=([string]$_.Exception.Message -replace '(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>')}}
        $security=@();if($attemptDiagnostic.postAttempt){$security=@($attemptDiagnostic.postAttempt.securityEvents)};$typeCounts=[ordered]@{type2=0;type3=0;type10=0};foreach($event in $security){if([int]$event.eventId -eq 4624){$type=[string]$event.fields.LogonType;if($type -eq '2'){$typeCounts.type2++}elseif($type -eq '3'){$typeCounts.type3++}elseif($type -eq '10'){$typeCounts.type10++}}};$failures=@($security|Where-Object{[int]$_.eventId -eq 4625}|ForEach-Object{[ordered]@{status=[string]$_.fields.Status;subStatus=[string]$_.fields.SubStatus}}|Select-Object -Unique);$lastCategory=if($attemptDiagnostic.desktopWait -and $attemptDiagnostic.desktopWait.finalFailure){[string]$attemptDiagnostic.desktopWait.finalFailure.category}elseif($primary){'smoke-blocked'}else{$null}
        if($disarm){$attemptDiagnostic.disarm=$disarm};if($cleanupError){$attemptDiagnostic.cleanupError=$cleanupError};$attemptDiagnostic.status=if($primary){'BLOCKED'}else{'PASS'};Write-AtomicJson $diagnosticPath $attemptDiagnostic
        Write-AtomicJson (Join-Path $Workspace 'evidence\CURRENT-INTERACTIVE-LOGIN.json') ([ordered]@{schemaVersion=1;generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o');RunId=$RunId;mechanism='native-winlogon';status=if($primary){'BLOCKED'}else{'PASS'};vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';vmName='DevFleet-E2E-Win11-01';guestName='DEVFLEET-E2E-01';preBoot=$preBoot;postBoot=$postBoot;bootChanged=if($preBoot -and $postBoot){$preBoot -cne $postBoot}else{$null};interactiveUser=if($desktopProof){'DEVFLEET-E2E-01\E2EAdmin'}else{$null};SessionId=if($desktopProof){[int]$desktopProof.sessionId}else{$null};ExplorerPID=if($desktopProof){[int]$desktopProof.explorerPid}else{$null};ExplorerSessionId=if($desktopProof){[int]$desktopProof.sessionId}else{$null};driverSessionId=if($marker){[int]$marker.driverSessionId}else{$null};candidateSessionId=$null;securityEventCount=if($attemptDiagnostic.postAttempt){$security.Count}else{$null};securityEventTypeCounts=if($attemptDiagnostic.postAttempt){$typeCounts}else{$null};'4624Type2Type3Type10'=if($attemptDiagnostic.postAttempt){$typeCounts}else{$null};'4625StatusSubStatus'=if($attemptDiagnostic.postAttempt){$failures}else{$null};lastSanitizedTransportErrorCategory=$lastCategory;primaryBlocker=if($primary){$primary}else{$null};credentialExposed=$false;preLogonPolicy=$attemptDiagnostic.arm.preLogonPolicy;preLogonPolicySuppressed=if($attemptDiagnostic.arm){$attemptDiagnostic.arm.preLogonPolicySuppressed}else{$null};preLogonPolicyReasserted=if($attemptDiagnostic.arm){$attemptDiagnostic.arm.preLogonPolicyReasserted}else{$null};preLogonPolicyRestored=if($disarm -and $disarm.PSObject.Properties['preLogonPolicyRestored']){[bool]$disarm.preLogonPolicyRestored}else{$null};transientDefaultPasswordCleared=if($disarm){-not [bool]$disarm.ordinaryDefaultPasswordPresent}else{$null};lsaDefaultPasswordCleared=if($disarm){[bool]$disarm.lsaCleared}else{$null};autologonStateRestored=if($disarm){[bool]$disarm.autoLogonCountRestored}else{$null};finalL1='NOT_OBSERVED';finalL2='NOT_OBSERVED'})
        $finalizer=Join-Path $Workspace 'tools\Invoke-DevFleetFinalConvergence.ps1';$args=@('-Workspace',$Workspace,'-L1Touched');if($armed){$args+=@('-InteractiveLogonArmed')};if($primary){$args+=@('-PrimaryBlocker',$primary,'-PrimaryBlockerClassification','BLOCKED — AUTOMATED INTERACTIVE LOGIN SMOKE')};& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $finalizer @args | Out-Null
        $terminalStatePath=Join-Path $Workspace 'evidence\FINALIZER-TERMINAL-STATE.json';if(Test-Path -LiteralPath $terminalStatePath){$terminalState=Get-Content $terminalStatePath -Raw|ConvertFrom-Json -AsHashtable};$currentPath=Join-Path $Workspace 'evidence\CURRENT-INTERACTIVE-LOGIN.json';if((Test-Path -LiteralPath $currentPath) -and $null -ne $terminalState){$current=Get-Content $currentPath -Raw|ConvertFrom-Json -AsHashtable;if($terminalState.l1Observation){$current.finalL1=$terminalState.l1Observation.state};if($terminalState.l2Observation){$current.finalL2=if([string]$terminalState.l2Observation.status -ceq 'ABSENT' -and $terminalState.l2Observation.present -eq $false){'ABSENT'}elseif($terminalState.l2Observation.present -eq $true){'PRESENT'}else{'UNVERIFIED'}};if($cleanupError){$current.cleanupError=$cleanupError};Write-AtomicJson $currentPath $current}
    } catch { $cleanupError=if($cleanupError){$cleanupError}else{Get-SafeSmokeError $_};try{$currentPath=Join-Path $Workspace 'evidence\CURRENT-INTERACTIVE-LOGIN.json';if(Test-Path -LiteralPath $currentPath){$current=Get-Content $currentPath -Raw|ConvertFrom-Json -AsHashtable;$current.cleanupError=$cleanupError;Write-AtomicJson $currentPath $current}}catch{} }
}

if($primary){throw $primary}
$result|ConvertTo-Json -Depth 20

```


## FILE: automation/release-e2e/Invoke-CampaignEMultipassM0.ps1

SHA256: 7e275399a8e7032477a489fb965c51b5aa26316bd465e8c16b738ed7ea5cb32f | Bytes: 9824 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
    [ValidateRange(300,900)][int]$OwnerSeconds=600
)

$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$vmName='DevFleet-E2E-Win11-01'
$cleanId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'
$cleanName='DevFleet-E2E-CLEAN'
$l2Name='DevFleet-E2E-Linux-01'
$runOwnedPrefix="DevFleet-E2E-E-$RunId"
$runDir=Join-Path $root "audit\automation-harness\runs\$RunId"
$ownerDeadline=[datetime]::UtcNow.AddSeconds($OwnerSeconds)

foreach($module in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic')){Import-Module (Join-Path $root "automation\release-e2e\modules\$module.psm1") -Force}

$result=[ordered]@{
    schemaVersion=1
    campaign='DF-STABLE-20260906-E'
    experiment='M0'
    status='INCOMPLETE'
    certificationEligible=$false
    proofCredit=$false
    runId=$RunId
    startedAtUtc=[datetime]::UtcNow.ToString('o')
    ownerDeadlineUtc=$ownerDeadline.ToString('o')
    exactL1=[ordered]@{name=$vmName;id=$vmId.ToString()}
    sourceCheckpoint=[ordered]@{name=$cleanName;id=$cleanId.ToString()}
    runOwnedPrefix=$runOwnedPrefix
    cleanupOwner='Invoke-CampaignEMultipassM0.ps1'
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    moduleSha256=(Get-FileHash -LiteralPath (Join-Path $root 'automation\release-e2e\modules\MultipassDiagnostic.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
    workerSha256=(Get-FileHash -LiteralPath (Join-Path $root 'automation\release-e2e\Invoke-CampaignEMultipassM0Worker.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
}
$session=$null
$restored=$false
try {
    New-Item -ItemType Directory -Path $runDir -Force|Out-Null
    $vm=Get-VM -Id $vmId -ErrorAction Stop
    if([string]$vm.Name-cne$vmName-or$vm.Id-ne$vmId){throw 'Campaign E M0 exact L1 identity mismatch.'}
    Assert-DisposableOwnership -Vm $vm -ExpectedId $vmId.ToString()|Out-Null
    $clean=@(Get-VMSnapshot -VM $vm -ErrorAction Stop|Where-Object{$_.Name-ceq$cleanName-and$_.Id-eq$cleanId})
    if($clean.Count-ne1){throw 'Campaign E M0 canonical CLEAN name/GUID binding failed.'}
    $safety=Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB 14.38
    $result.hostSafety=[ordered]@{status=if([bool]$safety.startSafe){'PASS'}else{'BLOCKED'};startSafe=[bool]$safety.startSafe;resourceExhaustion=[bool]$safety.resourceExhaustion;availableMemoryGiB=[double]$safety.availableMemoryGiB;projectedPostStartAvailableMemoryGiB=[double]$safety.projectedPostStartAvailableMemoryGiB;observedAtUtc=[datetime]::UtcNow.ToString('o')}
    if(-not[bool]$safety.startSafe){throw 'BLOCKED - HOST-SAFETY startSafe=false.'}
    $fingerprint=Get-CandidateFingerprint -WorkspaceRoot $root
    $result.tuple=[ordered]@{repositoryHead=(&git -C $root rev-parse HEAD).Trim();candidateCommit=[string]$fingerprint.gitCommit;shippingInputIdentity=[string]$fingerprint.shippingInputIdentity;releaseFingerprintId=[string]$fingerprint.releaseFingerprintId;toolingFingerprintId=[string]$fingerprint.toolingFingerprintId;candidateSha256=[string]$fingerprint.candidate.sha256;payloadSha256=[string]$fingerprint.tar.sha256}
    $result.restore=Restore-ExactCheckpoint -Vm $vm -Name $cleanName -StartAfterRestore
    $restored=$true
    $session=Connect-DevFleetGuest -VmId $vmId
    $initialL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name
    $result.initialL2=$initialL2
    if([string]$initialL2.status-cne'ABSENT'){throw "Campaign E M0 requires exact initial L2 absence; observed $([string]$initialL2.status)."}
    $remoteRoot="C:\Users\Public\DevFleet-E2E\$RunId\M0"
    $null=Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {param($Path)if($Path-notlike'C:\Users\Public\DevFleet-E2E\*\M0'){throw 'Remote M0 staging path is outside the run-owned boundary.'};New-Item -ItemType Directory -Path $Path -Force|Out-Null} -ArgumentList @($remoteRoot)
    $localModule=Join-Path $root 'automation\release-e2e\modules\MultipassDiagnostic.psm1'
    $remoteModule=Join-Path $remoteRoot 'MultipassDiagnostic.psm1'
    $localWorker=Join-Path $root 'automation\release-e2e\Invoke-CampaignEMultipassM0Worker.ps1'
    $remoteWorker=Join-Path $remoteRoot 'Invoke-CampaignEMultipassM0Worker.ps1'
    $result.stage=[ordered]@{
        module=Copy-DevFleetBoundedGuestFile -LocalPath $localModule -Session $session -RemotePath $remoteModule -TimeoutSeconds 60
        worker=Copy-DevFleetBoundedGuestFile -LocalPath $localWorker -Session $session -RemotePath $remoteWorker -TimeoutSeconds 60
    }
    $candidateConfig=Get-Content -LiteralPath (Join-Path $root 'source\config\devfleet.config.json') -Raw|ConvertFrom-Json -ErrorAction Stop
    $candidateNames=@([string]$candidateConfig.Primary.InstanceName,[string]$candidateConfig.Failover.InstanceName,[string]$candidateConfig.Vault.InstanceName)
    if($candidateNames.Count-ne3-or@($candidateNames|Where-Object{$_-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'}).Count){throw 'Candidate-bound product instance names are invalid.'}
    $ubuntuImage=[string]$candidateConfig.Primary.UbuntuImage
    $collectorRequest=[ordered]@{
        modulePath=$remoteModule
        runId=$RunId
        vmName=$vmName
        vmId=$vmId.ToString()
        ubuntuImage=$ubuntuImage
        candidateNames=$candidateNames
        runPrefix=$runOwnedPrefix
        ownerDeadlineUnixMilliseconds=[DateTimeOffset]::new($ownerDeadline.ToUniversalTime()).ToUnixTimeMilliseconds()
    }|ConvertTo-Json -Depth 4 -Compress
    $requestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($collectorRequest))
    $remotePowerShell=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {$path=Join-Path $PSHOME 'powershell.exe';if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Windows PowerShell runtime is missing.'};$path})|Select-Object -Last 1
    if(-not$remotePowerShell-or[IO.Path]::GetFileName([string]$remotePowerShell)-ine'powershell.exe'){throw 'Exact in-L1 Windows PowerShell worker runtime is unavailable.'}
    $workerResult=Invoke-DevFleetBoundedGuestProcess -Session $session -FilePath ([string]$remotePowerShell) -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$remoteWorker,'-RequestBase64',$requestBase64) -OwnerDeadlineUtc $ownerDeadline
    $result.worker=[ordered]@{outcome=[string]$workerResult.outcome;exitCode=$workerResult.exitCode;pid=$workerResult.pid;runtime='WindowsPowerShell';startedAtUtc=[string]$workerResult.startedAtUtc;finishedAtUtc=[string]$workerResult.finishedAtUtc;outputComplete=[bool]$workerResult.outputComplete;executionPolicyScope='PROCESS_ONLY';systemPolicyChanged=$false}
    if([string]$workerResult.outcome-cne'PASS'){throw "Campaign E M0 worker failed: $(ConvertTo-DevFleetDiagnosticSafeText $workerResult.stderr 1024)"}
    try{$snapshot=[string]$workerResult.stdout|ConvertFrom-Json -ErrorAction Stop}catch{throw "Campaign E M0 worker returned malformed JSON: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)"}
    Assert-DevFleetMultipassM0Snapshot -Snapshot $snapshot -ExpectedRunId $RunId -ExpectedVmName $vmName -ExpectedVmId $vmId|Out-Null
    $result.collector=$snapshot
    $result.status=if([string]$snapshot.status-ceq'COMPLETE'){'PASS_DIAGNOSTIC'}else{'INCONCLUSIVE'}
} catch {
    $result.status='BLOCKED'
    $result.primaryError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024
} finally {
    if($session){
        try{$result.finalL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name}catch{$result.finalL2=[ordered]@{status='UNVERIFIED';expectedName=$l2Name;verification=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)}}
        try{$null=Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {param($Path)if($Path-notlike'C:\Users\Public\DevFleet-E2E\*\M0'){throw 'Remote M0 cleanup path is outside the run-owned boundary.'};if(Test-Path -LiteralPath $Path){Remove-Item -LiteralPath $Path -Recurse -Force}} -ArgumentList @("C:\Users\Public\DevFleet-E2E\$RunId\M0");$result.stagingCleanup='PASS'}catch{$result.stagingCleanup='UNVERIFIED'}
        Remove-PSSession $session -ErrorAction SilentlyContinue;$session=$null
    } elseif($restored) {$result.finalL2=[ordered]@{status='UNVERIFIED';expectedName=$l2Name;verification='No bounded in-L1 inventory was available before final stop.'}}
    try {
        $finalVm=Get-VM -Id $vmId -ErrorAction Stop
        if([string]$finalVm.Name-cne$vmName-or$finalVm.Id-ne$vmId){throw 'Campaign E M0 final L1 identity mismatch.'}
        if($finalVm.State-ne'Off'){Stop-VM -VM $finalVm -Force -Confirm:$false -ErrorAction Stop}
        $stopDeadline=[datetime]::UtcNow.AddMinutes(2)
        do{$finalVm=Get-VM -Id $vmId -ErrorAction Stop;if($finalVm.State-eq'Off'){break};Start-Sleep -Seconds 2}while([datetime]::UtcNow-lt$stopDeadline)
        $result.finalL1=[ordered]@{status=if($finalVm.State-eq'Off'){'OFF'}else{'UNVERIFIED'};name=$finalVm.Name;id=$finalVm.Id.ToString();observedAtUtc=[datetime]::UtcNow.ToString('o')}
    } catch {$result.finalL1=[ordered]@{status='UNVERIFIED';error=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message);observedAtUtc=[datetime]::UtcNow.ToString('o')}}
    if($restored-and([string]$result.finalL1.status-cne'OFF'-or[string]$result.finalL2.status-cne'ABSENT')){$result.status='BLOCKED'}
    $result.completedAtUtc=[datetime]::UtcNow.ToString('o')
    Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m0.json') -Value $result
}

[pscustomobject]$result
if([string]$result.status-cne'PASS_DIAGNOSTIC'){exit 1}

```


## FILE: automation/release-e2e/Invoke-CampaignEMultipassM0Worker.ps1

SHA256: f202b5b1e279812a02cac9d00f80ccf612f7fb8e886b7b0c0bb5f1005af70412 | Bytes: 1767 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
try {
    $requestJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))
    $request=$requestJson|ConvertFrom-Json -ErrorAction Stop
    if([string]$request.runId-notmatch'^[A-Za-z0-9._-]+$'){throw 'Worker run identity is invalid.'}
    if([string]$request.modulePath-notlike'C:\Users\Public\DevFleet-E2E\*\M0\MultipassDiagnostic.psm1'){throw 'Worker module path is outside the exact run staging boundary.'}
    if([string]$request.runPrefix-notmatch'^DevFleet-E2E-E-[A-Za-z0-9._-]+$'){throw 'Worker run-owned prefix is invalid.'}
    Import-Module ([string]$request.modulePath) -Force -ErrorAction Stop
    $ownerDeadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.ownerDeadlineUnixMilliseconds).UtcDateTime
    $snapshot=Get-DevFleetMultipassM0Snapshot -RunId ([string]$request.runId) -ExpectedVmName ([string]$request.vmName) -ExpectedVmId ([guid]([string]$request.vmId)) -UbuntuImage ([string]$request.ubuntuImage) -CandidateInstanceNames @($request.candidateNames|ForEach-Object{[string]$_}) -RunOwnedPrefix ([string]$request.runPrefix) -OwnerDeadlineUtc $ownerDeadline
    Assert-DevFleetMultipassM0Snapshot -Snapshot $snapshot -ExpectedRunId ([string]$request.runId) -ExpectedVmName ([string]$request.vmName) -ExpectedVmId ([guid]([string]$request.vmId))|Out-Null
    [Console]::Out.Write(($snapshot|ConvertTo-Json -Depth 24 -Compress))
} catch {
    $message=[regex]::Replace([string]$_.Exception.Message,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    [Console]::Error.Write($message)
    exit 1
}

```


## FILE: automation/release-e2e/Invoke-CampaignEMultipassM1.ps1

SHA256: 20572993f3b78106327d6189d520ee7d58b19f6dbe01c702e58952ad54502f8c | Bytes: 22747 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
    [Parameter(Mandatory)][string]$CheckpointEvidencePath,
    [ValidateRange(900,3000)][int]$OwnerSeconds=1500,
    [switch]$ProductCapacity,
    [switch]$ProductLaunch
)
$ErrorActionPreference='Stop'
if($ProductLaunch){$ProductCapacity=$true}
if($ProductCapacity-and-not$PSBoundParameters.ContainsKey('OwnerSeconds')){$OwnerSeconds=2400}
$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path;$checkpointEvidencePath=(Resolve-Path -LiteralPath $CheckpointEvidencePath).Path
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';$vmName='DevFleet-E2E-Win11-01';$cleanId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9';$l2Name='DevFleet-E2E-Linux-01'
$instanceName="DevFleet-E2E-E-M1-$RunId";$runDir=Join-Path $root "audit\automation-harness\runs\$RunId";$remoteRoot="C:\Users\Public\DevFleet-E2E\$RunId\M1";$nonce=[guid]::NewGuid();$owner=[datetime]::UtcNow.AddSeconds($OwnerSeconds);$operationDeadline=$owner.AddSeconds(-240)
foreach($module in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic')){Import-Module (Join-Path $root "automation\release-e2e\modules\$module.psm1") -Force}
$result=[ordered]@{schemaVersion=1;campaign='DF-STABLE-20260906-E';experiment='M1';status='RESERVED';certificationEligible=$false;proofCredit=$false;runId=$RunId;startedAtUtc=[datetime]::UtcNow.ToString('o');ownerDeadlineUtc=$owner.ToString('o');operationDeadlineUtc=$operationDeadline.ToString('o');exactL1=[ordered]@{name=$vmName;id=$vmId.ToString()};diagnosticInstanceName=$instanceName;cleanupOwner='Invoke-CampaignEMultipassM1.ps1';diagnosticDeviation=[ordered]@{cpus=2;memory='2G';disk='10G';cloudInit='NONE_PRODUCT';productLifecycle=$false}}
$session=$null;$restored=$false;$restoreAttempted=$false;$stagingOwned=$false;$m1=$null;$checkpoint=$null
$expectedResources=@{cpus=2;memory='2G';disk='10G'};$profile=$null;$rawCollected=-not$ProductCapacity;$workerDeadline=$owner
if(Test-Path -LiteralPath $runDir){throw 'Campaign E M1 refuses to reuse an existing evidence run directory.'}
if($ProductCapacity){
    $operationDeadline=$owner.AddSeconds(-480);$workerDeadline=$owner.AddSeconds(-180)
    if(($operationDeadline-[datetime]::UtcNow).TotalSeconds-lt1600){throw 'M2 owner cannot cover unchanged operation limits plus evidence and cleanup reserves.'}
    $result.experiment='M2';$result.operationDeadlineUtc=$operationDeadline.ToString('o');$result.workerDeadlineUtc=$workerDeadline.ToString('o')
    $result.diagnosticDeviation=[ordered]@{resources='PENDING_ACTUAL_CANDIDATE_PREFLIGHT';cloudInit='NONE_PRODUCT';productLifecycle=$false;workerRuntime='CHECKPOINT_WINDOWS_POWERSHELL_5_1'}
    if($ProductLaunch){
        $result.experiment='M3'
        $result.diagnosticDeviation.cloudInit='CANDIDATE_RENDERED_COMPUTE_TEMPLATE'
        $result.diagnosticDeviation.workerRuntime='CHECKPOINT_HASH_BOUND_POWERSHELL_7'
        $result.diagnosticDeviation.launchImplementation='CANDIDATE_COMMON_INVOKE_EXTERNAL'
        $result.diagnosticDeviation.captureMode=$true
        $result.diagnosticDeviation.context='QUIET_TRANSACTIONLESS_DIAGNOSTIC_WITH_RUN_OWNED_NAME'
        $result.diagnosticDeviation.cloudInitWaitMaximumSeconds=300
    }
}
try {
    New-Item -ItemType Directory -Path $runDir -Force|Out-Null;Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m1.json') -Value $result
    $checkpointRecord=Get-Content -LiteralPath $checkpointEvidencePath -Raw|ConvertFrom-Json -ErrorAction Stop
    if([string]$checkpointRecord.status-cne'PASS_CHECKPOINT_READY'-or[