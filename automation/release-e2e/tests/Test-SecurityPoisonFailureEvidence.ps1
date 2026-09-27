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
