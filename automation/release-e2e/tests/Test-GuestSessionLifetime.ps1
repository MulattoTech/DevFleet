[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/GuestSession.psm1') -Force
$module=Get-Module GuestSession
$passed=0;$failures=[Collections.Generic.List[string]]::new();$owned=[Collections.Generic.List[object]]::new()
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{$script:failures.Add($Name)}}
function New-LocalFixtureSession {
    # Exercise native PowerShell session/pipeline lifetime on the local host.
    # This named-pipe session needs no VM, credentials, network or service change.
    $pipeline=[powershell]::Create()
    $row=[pscustomobject]@{pipeline=$pipeline;session=$null};$script:owned.Add($row)
    $null=$pipeline.AddCommand('New-PSSession').AddParameter('UseWindowsPowerShell').AddParameter('ErrorAction','Stop')
    $async=$pipeline.BeginInvoke()
    if(-not $async.AsyncWaitHandle.WaitOne(15000)){$pipeline.Stop();throw 'Local session fixture exceeded15s.'}
    $session=@($pipeline.EndInvoke($async))|Select-Object -First 1
    if(-not $session){throw 'Local fixture returned no native session.'}
    $row.session=$session
    & $module {param($s,$p)$script:GuestSessionPipelines[[string]$s.InstanceId]=$p} $session $pipeline
    return $row
}
try {
    foreach($i in 1..3){
        $row=New-LocalFixtureSession
        Check ((Invoke-Command -Session $row.session -ScriptBlock {'alive'}) -ceq 'alive') "native session $i stays usable while opener is retained"
        Remove-DevFleetGuestSession -Session $row.session
        Check ([string]$row.session.State -ceq 'Closed' -and (& $module {$script:GuestSessionPipelines.Count}) -eq 0) "native close $i removes its registry entry"
        $disposed=$false;try{$null=$row.pipeline.Invoke()}catch{$disposed=$_.Exception.ToString() -match 'ObjectDisposedException|disposed'}
        Check $disposed "native close $i disposes the completed opener"
    }
    $first=New-LocalFixtureSession;$second=New-LocalFixtureSession
    Remove-DevFleetGuestSession -Session $first.session
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 1 -and (Invoke-Command -Session $second.session -ScriptBlock {'other-alive'}) -ceq 'other-alive') 'closing one session preserves the other live session and opener'
    Remove-DevFleetGuestSession -Session $first.session
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 1) 'closing an already closed session cannot remove another owner'
    Remove-DevFleetGuestSession -Session $second.session
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 0) 'last native close leaves no retained opener'
    $retained=New-LocalFixtureSession
    & $module {function script:Remove-PSSession {param($Session,$ErrorAction)throw 'controlled native removal failure'}}
    try {
        $failedClose=$false;try{Remove-DevFleetGuestSession -Session $retained.session}catch{$failedClose=$true}
        Check ($failedClose -and [string]$retained.session.State -ceq 'Opened' -and (& $module {$script:GuestSessionPipelines.Count}) -eq 1) 'failed native removal preserves the live session opener'
        Check ((Invoke-Command -Session $retained.session -ScriptBlock {'still-alive'}) -ceq 'still-alive') 'failed removal does not invalidate the still open native session'
        $quietCloseReturned=$false;try{Remove-DevFleetGuestSession -Session $retained.session -ErrorAction SilentlyContinue;$quietCloseReturned=$true}catch{}
        Check ($quietCloseReturned -and (& $module {$script:GuestSessionPipelines.Count}) -eq 1) 'caller-selected quiet cleanup preserves the primary error and live opener'
    } finally {& $module {Remove-Item Function:Remove-PSSession -ErrorAction SilentlyContinue}}
    Remove-DevFleetGuestSession -Session $retained.session
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 0) 'subsequent successful close disposes the retained opener'
} finally {
    foreach($row in $owned){if($row.session){Remove-PSSession -Session $row.session -ErrorAction SilentlyContinue};$row.pipeline.Dispose()}
    & $module {$script:GuestSessionPipelines.Clear()}
}
[pscustomobject]@{status=if($failures.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failures);nativeTransport='local UseWindowsPowerShell';vmOperations=0}|ConvertTo-Json -Depth 4
if($failures.Count){exit 1}
