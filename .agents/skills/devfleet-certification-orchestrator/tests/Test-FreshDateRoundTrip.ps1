$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/FreshAttemptAdmission.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$journal=Join-Path $PSScriptRoot '../scripts/fresh/fresh_attempts.py'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('fresh-journal-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
try {
 $auth=Join-Path $fixture 'authorization.txt';'ISOLATED TEST FIXTURE NO VM AUTHORITY'|Set-Content $auth
 $ledger=Join-Path $fixture 'ledger.json';$request=Join-Path $fixture 'request.json'
 & python $journal initialize --ledger $ledger --authorization $auth|Out-Null
 if($LASTEXITCODE -ne 0){throw 'Fixture initialization failed'}
 $owner=Get-Process -Id $PID
 $req=@{runId='date-roundtrip-fixture';operation='diagnostic';owner=@{pid=$PID;startUtc=$owner.StartTime.ToUniversalTime().ToString('o')};tuple=@{repositoryHead=(& git -C $root rev-parse HEAD).Trim()};entrypoint=$PSCommandPath;entrypointSha256=(Get-FileHash $PSCommandPath).Hash.ToLowerInvariant();arguments=@();changedCondition='Isolated metadata roundtrip regression';deadlineUtc=[datetimeoffset]::UtcNow.AddMinutes(2).ToString('o')}
 $req|ConvertTo-Json -Depth 5|Set-Content $request
 & python $journal reserve --ledger $ledger --request $request|Out-Null
 if($LASTEXITCODE -ne 0){throw 'Fixture reservation failed'}
 $active=Get-FreshDiagnosticAdmission -LedgerPath $ledger -RunId $req.runId -WorkspaceRoot $root -ScriptPath $PSCommandPath
 if($active.runId -cne $req.runId){throw 'Roundtrip admission failed'}
 'PASS actual journal/PowerShell owner timestamp roundtrip; VM operations 0'
}finally{Remove-Item -LiteralPath $fixture -Recurse -Force}
