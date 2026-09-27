$ErrorActionPreference='Stop'
$guard=Join-Path $PSScriptRoot '../scripts/FreshAttemptAdmission.ps1'
if(-not(Test-Path $guard)){throw 'Fresh admission implementation missing'}
. $guard
$now=[datetimeoffset]::UtcNow
$start=$now.AddMinutes(-1).ToString('o')
function New-Fixture { @{runId='fresh-fixture';operation='diagnostic';owner=@{pid=123;startUtc=$start};tuple=@{repositoryHead=('a'*40)};entrypointSha256=('b'*64);deadlineUtc=$now.AddMinutes(5).ToString('o')} }
function Check($a){Assert-FreshAttemptAdmission -Active $a -RunId 'fresh-fixture' -CurrentHead ('a'*40) -CurrentScriptHash ('b'*64) -CurrentPid 123 -ParentPid 122 -ActualOwnerStartUtc $start}
$passes=0
Check (New-Fixture);$passes++
foreach($case in @('missing','run','operation','head','hash','owner','ownerStart','expired','badDate')){
 $a=New-Fixture
 switch($case){
 'missing'{$a=$null}
 'run'{$a.runId='foreign'}
 'operation'{$a.operation='fullrelease'}
 'head'{$a.tuple.repositoryHead='c'*40}
 'hash'{$a.entrypointSha256='d'*64}
 'owner'{$a.owner.pid=999}
 'ownerStart'{$a.owner.startUtc=$now.AddHours(-1).ToString('o')}
 'expired'{$a.deadlineUtc=$now.AddMinutes(-1).ToString('o')}
 'badDate'{$a.deadlineUtc='not-a-date'}
 }
 $rejected=$false;try{Check $a}catch{$rejected=$true}
 if(-not $rejected){throw "Incorrectly admitted: $case"};$passes++
}
Write-Output "PASS $passes fresh-admission assertions; VM operations 0"
