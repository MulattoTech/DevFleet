[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop';if([string]::IsNullOrWhiteSpace($WorkspaceRoot)){$WorkspaceRoot=Join-Path $PSScriptRoot '..\..\..'};$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$candidate=Get-Content -Raw (Join-Path $root 'automation\release-e2e\modules\Candidate.psm1');$standard=Get-Content -Raw (Join-Path $root 'automation\release-e2e\tests\Test-InstallerSelfTestStandardToken.ps1')
$checks=[ordered]@{
    candidateAcceptsCallerReportPath=$candidate -match '\[string\]\$ReportPath' -and $candidate -match 'already exists; a unique path is required'
    candidateDoesNotDeleteCallerReport=$candidate -match 'if \(\$callerSuppliedReportPath\) \{ throw' -and $candidate -match 'Remove-Item -LiteralPath \$reportPath -Force -ErrorAction Stop'
    candidateCapturesToken=$candidate -match 'Get-WindowsTokenEvidence' -and $candidate -match 'integrityLevelSid' -and $candidate -match 'S-1-16-'
    candidatePowerShell51Compatible=$candidate -notmatch '\?\?' -and $candidate -match 'shipping_input_identity' -and $candidate -match 'shippingInputIdentity'
    standardRejectsAdminAndElevated=$standard -match 'standardNonAdministratorToken' -and $candidate -match 'S-1-5-32-544'
    standardPowerShell51DefaultResolution=$standard -match 'param\(\[string\]\$WorkspaceRoot' -and $standard -match 'IsNullOrWhiteSpace\(\$WorkspaceRoot\)' -and $standard -match '\$PSScriptRoot'
    standardUsesExactSignedCandidate=$standard -match 'Get-CandidateFingerprint' -and $standard -match 'PRIVATE_SELF_SIGNED' -and $standard -match 'authenticode'
    standardUsesImmutableEvidenceRoot=$standard -match 'evidence/standard-token' -and $standard -match 'installer-self-test-raw\.txt' -and $standard -match 'standard-token-evidence\.json'
    standardBindsTupleAndHashes=$standard -match 'candidateBuildCommit' -and $standard -match 'shippingInputIdentity' -and $standard -match 'releaseFingerprintId' -and $standard -match 'toolingFingerprintId' -and $standard -match 'reportSha256' -and $standard -match 'runnerRelative'
    standardAtomicCurrentPointer=$standard -match 'CURRENT-STANDARD-TOKEN\.json' -and $standard -match 'Write-AtomicJson'
    noBuildOrSign=$standard -notmatch 'dotnet publish|Build-Release|Set-AuthenticodeSignature'
}
$failed=@($checks.GetEnumerator()|Where-Object{-not[bool]$_.Value});$result=[ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=($checks.Count-$failed.Count);total=$checks.Count;checks=$checks}
$result|ConvertTo-Json -Depth 8;if($failed.Count){throw "Standard-token candidate evidence contract failed: $(@($failed.Name)-join ',')"}
