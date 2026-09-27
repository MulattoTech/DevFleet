[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
$entry=Join-Path $WorkspaceRoot 'automation\release-e2e\Invoke-DevFleetReleaseE2E.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'Release entrypoint failed PowerShell parser validation.'}
$function=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-RequiredReleaseFinalizer'},$true))
if($function.Count -ne 1){throw 'Expected one production finalizer process-boundary function.'}
$functionText=$function[0].Extent.Text
. ([scriptblock]::Create($functionText))
$pwsh=(Get-Command pwsh.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$temp=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-finalizer-exit-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
$checks=[Collections.Generic.List[object]]::new()
try{
    $success=Join-Path $temp 'success.ps1';$failure=Join-Path $temp 'failure.ps1'
    [IO.File]::WriteAllText($success,"Write-Output 'safe completion'`nexit 0`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($failure,"Write-Output 'bounded child output'`nexit 17`n",[Text.UTF8Encoding]::new($false))
    $successOutput=@(Invoke-RequiredReleaseFinalizer -PowerShellPath $pwsh -FinalizerPath $success)
    $checks.Add([pscustomobject]@{name='successful finalizer child remains successful';pass=($LASTEXITCODE -eq 0 -and ($successOutput -join "`n") -match 'safe completion');detail="childOutput=$($successOutput -join ' ')"})
    $failed=$false;$failureMessage=''
    try{Invoke-RequiredReleaseFinalizer -PowerShellPath $pwsh -FinalizerPath $failure|Out-Null}catch{$failed=$true;$failureMessage=$_.Exception.Message}
    $checks.Add([pscustomobject]@{name='nonzero finalizer child blocks the release caller';pass=($failed -and $failureMessage -match 'code 17');detail="blocked=$failed message=$failureMessage"})
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
$bad=@($checks|Where-Object{-not $_.pass})
[ordered]@{scope='VM_FREE_PRODUCTION_FINALIZER_PROCESS_EXIT_REGRESSION';certificationCredit=$false;status=if($bad.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$bad.Count;total=$checks.Count;checks=@($checks)}|ConvertTo-Json -Depth 8
if($bad.Count){exit 1}
