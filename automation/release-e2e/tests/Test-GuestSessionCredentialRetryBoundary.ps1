[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/GuestSession.psm1') -Force
$module=Get-Module GuestSession
$passed=0;$failures=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{$script:failures.Add($Name)}}
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$vmName='DevFleet-E2E-Win11-01'
# All credentials and VM/session operations below are isolated fixtures.
& $module {
    $script:FixtureCredential=[pscredential]::new('fixture-user',(ConvertTo-SecureString 'fixture-only-not-a-password' -AsPlainText -Force))
    $script:FixtureTargetName='DevFleet-E2E-Win11-01'
    function script:Get-DevFleetE2ECredential { $script:FixtureCredential }
    function script:Get-VM { param($Id,$Name,$ErrorAction) [pscustomobject]@{Name=$script:FixtureTargetName} }
    function script:Start-Sleep { param($Seconds) $script:FixtureSleepSeconds += $Seconds }
    $script:OriginalOpener=(Get-Command New-BoundedVmPSSession).ScriptBlock.ToString()
    function script:New-BoundedVmPSSession {
        param($VmId,$VmName,$Credential)
        if(-not [object]::ReferenceEquals($Credential,$script:FixtureCredential)){throw 'Fixture credential identity mismatch'}
        $index=$script:FixtureAttempts;$script:FixtureAttempts++
        $value=$script:FixtureErrors[[Math]::Min($index,$script:FixtureErrors.Count-1)]
        if($null -ne $value){throw $value}
        return [pscustomobject]@{fixtureSession=$true}
    }
}
function Set-Case([object[]]$Errors){
    & $module {param($row)$script:FixtureErrors=$row.errors;$script:FixtureAttempts=0;$script:FixtureSleepSeconds=0} ([pscustomobject]@{errors=$Errors})
}
function Invoke-Case([string]$Mode){if($Mode -eq 'ById'){Connect-DevFleetGuest -VmId $vmId}else{Connect-DevFleetGuest -VmName $vmName}}
try {
    $cases=@(
        @{name='generic denial';error='Access is denied.';code='LAB_SESSION_ACCESS_DENIED';auth='UNVERIFIED'},
        @{name='typed denial';error=[UnauthorizedAccessException]::new('DEMO_SECRET_DO_NOT_RETURN');code='LAB_SESSION_ACCESS_DENIED';auth='UNVERIFIED'},
        @{name='invalid response';error='The credential is invalid.';code='LAB_GUEST_AUTHENTICATION_REJECTED';auth='REJECTED'},
        @{name='typed logon rejection';error=[ComponentModel.Win32Exception]::new(1326);code='LAB_GUEST_AUTHENTICATION_REJECTED';auth='REJECTED'},
        @{name='nested native denial';error=[InvalidOperationException]::new('outer DEMO_SECRET_DO_NOT_RETURN',[UnauthorizedAccessException]::new('inner DEMO_SECRET_DO_NOT_RETURN'));code='LAB_SESSION_ACCESS_DENIED';auth='UNVERIFIED'},
        @{name='unrelated credential text';error='Credential parameter conversion failed DEMO_SECRET_DO_NOT_RETURN';code='LAB_SESSION_OPEN_FAILED';auth='UNVERIFIED'},
        @{name='unknown failure';error='unclassified DEMO_SECRET_DO_NOT_RETURN';code='LAB_SESSION_OPEN_FAILED';auth='UNVERIFIED'},
        @{name='bounded timeout';error='Guest session establishment exceeded its finite 60-second open deadline.';code='LAB_SESSION_OPEN_TIMEOUT';auth='UNVERIFIED'},
        @{name='known socket transport';error='Hyper-V socket target process has ended.';code='LAB_SESSION_TRANSPORT_FAILED';auth='UNVERIFIED'}
    )
    foreach($mode in @('ById','ByName')){
        Set-Case @('The running command stopped because a remote session might have ended.',$null)
        $session=Invoke-Case $mode
        Check ($session.fixtureSession -and (& $module {$script:FixtureAttempts}) -eq 2) "$mode transient then success uses two attempts"
        Check ((& $module {$script:FixtureSleepSeconds}) -eq 5) "$mode success preserves bounded backoff"
        foreach($case in $cases){
            Set-Case @($case.error);$failure=$null
            try {Invoke-Case $mode|Out-Null}catch{$failure=$_.Exception}
            Check ($null -ne $failure -and $failure.Message.StartsWith($case.code+':')) "$mode $($case.name) truthful failure classification"
            Check ((& $module {$script:FixtureAttempts}) -eq 3 -and (& $module {$script:FixtureSleepSeconds}) -eq 10) "$mode $($case.name) original attempt cap and waits"
            Check ($null -ne $failure -and $failure.Data['authenticationOutcome'] -eq $case.auth -and $failure.Data['attemptCount'] -eq 3) "$mode $($case.name) safe structured diagnostics"
            Check ($null -ne $failure -and $failure.ToString() -notmatch 'DEMO_SECRET_DO_NOT_RETURN|LAB_CREDENTIAL_STALE') "$mode $($case.name) no arbitrary error text or stale-password claim"
            if($case.code -eq 'LAB_SESSION_TRANSPORT_FAILED'){
                Check ($failure.Message -match 'Hyper-V socket target process has ended') "$mode known transport retains existing recovery discriminator"
            }
        }
        & $module {$script:FixtureTargetName='protected-production'};Set-Case @($null)
        $rejected=$false;try{Invoke-Case $mode|Out-Null}catch{$rejected=$true}
        Check ($rejected -and (& $module {$script:FixtureAttempts}) -eq 0) "$mode rejects foreign target before opening a session"
        & $module {$script:FixtureTargetName='DevFleet-E2E-Win11-01'}
    }
    # Real local PowerShell pipeline, with only New-PSSession replaced by dummy I/O.
    # This verifies EndInvoke error handling without Hyper-V, WinRM or real secrets.
    & $module {
        function script:New-FixtureOpenerPipeline {
            $pipeline=[powershell]::Create()
            $null=$pipeline.AddScript('function New-PSSession { param($Credential,$VMId,$VMName,$ErrorAction) throw [ComponentModel.Win32Exception]::new(1326) }').Invoke()
            $pipeline.Commands.Clear()
            return $pipeline
        }
        $body=$script:OriginalOpener.Replace('$pipeline=[powershell]::Create()','$pipeline=New-FixtureOpenerPipeline')
        if($body -ceq $script:OriginalOpener){throw 'Expected opener I/O factory not found'}
        Set-Item Function:script:New-BoundedVmPSSession -Value ([scriptblock]::Create($body))
    }
    $nativeFailure=$null
    try{Connect-DevFleetGuest -VmId $vmId|Out-Null}catch{$nativeFailure=$_.Exception}
    Check ($null -ne $nativeFailure -and $nativeFailure.Message.StartsWith('LAB_GUEST_AUTHENTICATION_REJECTED:')) 'real opener propagates native authentication rejection into safe classification'
    Check ($null -ne $nativeFailure -and $nativeFailure.Data['nativeErrorCode'] -eq 1326) 'real opener preserves native error code rather than flattening to text'
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 0) 'failed native openers retain no live session pipelines'
} finally {
    & $module {
        foreach($name in @('New-BoundedVmPSSession','New-FixtureOpenerPipeline','Get-DevFleetE2ECredential','Get-VM','Start-Sleep')){Remove-Item "Function:$name" -ErrorAction SilentlyContinue}
        $script:FixtureCredential=$null
    }
    Remove-Module GuestSession -Force
}
[pscustomobject]@{status=if($failures.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failures);vmOperations=0;realCredentialReads=0}|ConvertTo-Json -Depth 4
if($failures.Count){exit 1}
