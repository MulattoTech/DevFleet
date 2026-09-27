[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}else{$WorkspaceRoot=(Resolve-Path -LiteralPath $WorkspaceRoot).Path}

$executorPath=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1'
$tarPath=(Resolve-Path (Join-Path $WorkspaceRoot 'outputs\devfleet-v1.2.13.tar.gz')).Path
$tarHash=(Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
$runDir=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-NestedArgumentBinding-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runDir)

$observed=$null
$errorText=$null
try {
    Import-Module $executorPath -Force -DisableNameChecking
    $executorModule=Get-Module Invoke-RealProductPhase | Select-Object -First 1
    $context=[pscustomobject]@{
        runId='e2e-fullrelease-current-candidate-20260917T055128Z'
        phaseId='PERMANENT-DELETE'
        candidate=[pscustomobject]@{tar=[pscustomobject]@{path=$tarPath;sha256=$tarHash}}
        vmName='DevFleet-E2E-Win11-01'
        vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
        runDir=$runDir
        workspaceRoot=$WorkspaceRoot
    }
    $probe=& $executorModule {
        param($Context)
        function Connect-DevFleetGuest { param([guid]$VmId) [pscustomobject]@{fake=$true} }
        function Remove-DevFleetGuestSession { param($Session) }
        function Get-StageIntegrity { param([string]$LocalPath,$Session,[string]$RemotePath) [pscustomobject]@{equal=$true} }
        function Assert-ExactCandidate { param($Context) $Context.candidate }
        function Copy-Item { param([string]$LiteralPath,[string]$Destination,[switch]$ToSession,[switch]$Force) }
        function Invoke-Command {
            param($Session,[scriptblock]$ScriptBlock,[object[]]$ArgumentList)
            if($ArgumentList.Count -eq 1){ return $null }
            $rows=@();$index=0
            foreach($value in $ArgumentList){
                $text=[string]$value
                $rows += [pscustomobject]@{
                    index=$index
                    type=if($null -eq $value){'NULL'}else{$value.GetType().FullName}
                    length=$text.Length
                    value=$text
                }
                $index++
            }
            throw ('NESTED_ARGUMENT_CAPTURE:' + ($rows|ConvertTo-Json -Compress))
        }
        try {
            [void](Invoke-NestedProductScenario -Context $Context -Scenario 'permanent-delete')
            [pscustomobject]@{error='expected the remote argument capture to stop the probe';observed=@()}
        } catch {
            $message=$_.Exception.Message
            $prefix='NESTED_ARGUMENT_CAPTURE:'
            $captureIndex=$message.IndexOf($prefix,[StringComparison]::Ordinal)
            if($captureIndex -lt 0){[pscustomobject]@{error=$message;observed=@()}}
            else {[pscustomobject]@{error=$null;observed=(($message.Substring($captureIndex+$prefix.Length))|ConvertFrom-Json)}}
        }
    } $context
    $observed=@($probe.observed)
    $errorText=[string]$probe.error
} finally {
    if([IO.Directory]::Exists($runDir)){Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue}
}

$runIdRow=$observed|Where-Object index -eq 4|Select-Object -First 1
$phaseRow=$observed|Where-Object index -eq 5|Select-Object -First 1
$scenarioRow=$observed|Where-Object index -eq 6|Select-Object -First 1
$expectedRunId=[string]$context.runId
$pass=([string]::IsNullOrEmpty($errorText) -and $runIdRow -and $phaseRow -and $scenarioRow -and
    [string]$runIdRow.value -ceq $expectedRunId -and [string]$phaseRow.value -ceq [string]$context.phaseId -and
    [string]$scenarioRow.value -ceq 'permanent-delete' -and [int]$runIdRow.length -le 128)
[pscustomobject]@{
    status=if($pass){'PASS'}else{'FAIL'}
    passed=if($pass){1}else{0}
    total=1
    checks=@([pscustomobject]@{name='remote nested scenario receives scalar validated identity arguments';pass=$pass;observed=$observed;error=$errorText})
    vmOperations=0
    candidateBytesChanged=$false
}|ConvertTo-Json -Depth 8
if(-not $pass){exit 1}
