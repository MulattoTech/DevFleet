[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'tools\AuthorityTime.psm1') -Force
$raw='{"candidate_binding_utc":"2026-09-05T14:25:53.8477037Z"}'|ConvertFrom-Json
$converted=ConvertTo-AuthorityUtcInstant $raw.candidate_binding_utc
$stringConverted=ConvertTo-AuthorityUtcInstant '2026-09-05T14:25:53.8477037Z'
$pass=$converted.ToString('o') -ceq '2026-09-05T14:25:53.8477037Z' -and $stringConverted.ToString('o') -ceq '2026-09-05T14:25:53.8477037Z'
[pscustomobject]@{status=if($pass){'PASS'}else{'FAIL'};dateTimeType=$raw.candidate_binding_utc.GetType().FullName;dateTimeKind=[string]$raw.candidate_binding_utc.Kind;roundTrip=$converted.ToString('o');stringRoundTrip=$stringConverted.ToString('o')}|ConvertTo-Json -Depth 4
if(-not $pass){exit 1}
