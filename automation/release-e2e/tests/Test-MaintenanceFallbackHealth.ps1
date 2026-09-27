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
