# DevFleet source part 006

Full-source UTF-8 byte interval [232500, 279000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 3e3108b847e83c822669c340029a73612507df22e2057dcf23d1af53f0677cbe

<!-- BEGIN SOURCE SLICE -->
_order(self):
        status = self.initialize()
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0,
                                               'build-sign': 0})
        with self.assertRaises(ValueError):
            self.journal.reserve(self.successor, self.request('diagnostic', 'out-of-order'), dry_run=True)
        for index, (operation, result) in enumerate(self.journal.REPAIR5_SEQUENCE):
            request = self.request(operation, f'repair5-{index}')
            self.journal.reserve(self.successor, request)
            self.journal.finish(self.successor, request['runId'], request['owner'], 0, result, [])
        self.assertEqual(self.journal.status(self.successor)['attemptCount'], 5)

    def test_parent_and_authorization_are_distinct_immutable_sources(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, self.snapshot,
                                    [self.snapshot, self.live], self.journal.REPAIR5_ID)
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, self.authorization,
                                    [self.live, self.live], self.journal.REPAIR5_ID)
        self.initialize()
        self.snapshot.write_bytes(self.snapshot.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.successor)

    def test_no_extra_repair4_attempt_can_be_laundered(self):
        data = self.journal.strict_json(self.live)
        data['attempts'].append(dict(data['attempts'][0], runId='extra-standard-token'))
        self.live.write_text(json.dumps(data), encoding='utf-8')
        self.snapshot.write_bytes(self.live.read_bytes())
        with self.assertRaises(ValueError):
            self.initialize()

    def test_unrelated_qualified_tuple_cannot_replace_exact_repair4(self):
        data = self.journal.strict_json(self.live)
        data['attempts'][0]['tuple']['repositoryHead'] = 'f' * 40
        self.live.write_text(json.dumps(data), encoding='utf-8')
        self.snapshot.write_bytes(self.live.read_bytes())
        with self.assertRaises(ValueError):
            self.initialize()


if __name__ == '__main__':
    unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_r2_repair_successor.py

SHA256: e4624eddff607aadd50ce32915a0bb55387ab3b7b73b2cff2dfdaf1aff54ca49 | Bytes: 6408 | Git mode: 100644

```
"""Fail-closed accounting for one proposed R2 repair successor; no lab access."""
import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = pathlib.Path(__file__).resolve().parent


class RepairSuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.base_auth = self.root / 'base-authorization.md'
        self.r2_auth = self.root / 'r2-authorization.md'
        self.repair_auth = self.root / 'repair-authorization.md'
        for path, content in ((self.base_auth, 'base owner authorization'),
                              (self.r2_auth, 'R2 owner authorization'),
                              (self.repair_auth, 'separate bounded repair authorization')):
            path.write_text(content, encoding='utf-8')
        self.base = self.root / 'base.json'
        self.r2 = self.root / 'r2.json'
        self.snapshot = self.root / 'r2-terminal-snapshot.json'
        self.repair = self.root / 'r2-repair.json'
        self.journal.initialize(self.base, self.base_auth, [])
        self.journal.initialize(self.r2, self.r2_auth, [self.base], self.journal.POLICY_ID + '-R2')

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'native-test.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'bounded repair successor behavioral test',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def initialize(self):
        self.snapshot.write_bytes(self.r2.read_bytes())
        return self.journal.initialize(self.repair, self.repair_auth,
                                       [self.snapshot, self.r2], self.journal.REPAIR_ID)

    def succeed(self, operation, number):
        request = self.request(operation, f'repair-{number}')
        self.journal.reserve(self.repair, request)
        expected = dict(self.journal.REPAIR_SEQUENCE)[operation]
        self.journal.finish(self.repair, request['runId'], request['owner'], 0,
                            expected, [])

    def test_exact_finite_limits_preserve_r2(self):
        before = self.r2.read_bytes()
        status = self.initialize()
        self.assertEqual(self.r2.read_bytes(), before)
        self.assertEqual(self.snapshot.read_bytes(), before)
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0,
                                               'build-sign': 0})
        for operation in ('maintenance', 'build-sign'):
            with self.assertRaises(ValueError):
                self.journal.reserve(self.repair, self.request(operation, operation), dry_run=True)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair, self.request('diagnostic', 'out-of-order'), dry_run=True)
        self.succeed('standard-token', 1)
        self.journal.reserve(self.repair, self.request('diagnostic', 'repair-diagnostic'))
        self.assertEqual(self.journal.status(self.repair)['remaining']['diagnostic'], 0)
        self.assertIsNone(self.journal.status(self.r2)['active'])

    def test_missing_or_reused_authorization_or_wrong_predecessors_rejected(self):
        self.snapshot.write_bytes(self.r2.read_bytes())
        for predecessors, authorization in (([self.snapshot], self.repair_auth),
                                            ([self.r2, self.r2], self.repair_auth),
                                            ([self.snapshot, self.r2], self.r2_auth)):
            with self.assertRaises(ValueError):
                self.journal.initialize(self.repair, authorization,
                                        predecessors, self.journal.REPAIR_ID)

    def test_snapshot_and_live_r2_must_match_and_remain_pinned(self):
        self.snapshot.write_bytes(self.r2.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair, self.repair_auth,
                                    [self.snapshot, self.r2], self.journal.REPAIR_ID)
        self.initialize()
        self.r2.write_bytes(self.r2.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.repair)

    def test_existing_successor_cannot_reset_or_refund(self):
        self.initialize()
        for number, operation in enumerate(('standard-token', 'diagnostic',
                                            'laptop-proof', 'desktop-proof')):
            self.succeed(operation, number)
        request = self.request('fullrelease', 'repair-fullrelease')
        self.journal.reserve(self.repair, request)
        self.journal.finish(self.repair, request['runId'], request['owner'], 2,
                            'BLOCKED', [])
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair, self.repair_auth,
                                    [self.snapshot, self.r2], self.journal.REPAIR_ID)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair,
                                 self.request('fullrelease', 'repair-second'), dry_run=True)

    def test_failed_qualification_blocks_later_phases(self):
        self.initialize()
        request = self.request('standard-token', 'repair-standard-failed')
        self.journal.reserve(self.repair, request)
        self.journal.finish(self.repair, request['runId'], request['owner'], 2,
                            'STANDARD_TOKEN_BLOCKED', [])
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair,
                                 self.request('diagnostic', 'repair-next'), dry_run=True)


if __name__ == '__main__':
    unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/tests/Test-CertificationOrchestratorVmFree.ps1

SHA256: dcde4386c6f0aaf2ea81d7c883cb4ca3f6a4fa12ea288a1a392e1d6ca2f686e1 | Bytes: 7598 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$skillRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$readinessScript = Join-Path $skillRoot 'scripts\Test-DevFleetCertificationReadiness.ps1'
$preflightScript = Join-Path $skillRoot 'scripts\Invoke-DevFleetCertificationPreflight.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-cert-orchestrator-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = $env:LOCALAPPDATA
$passes = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passes++
}
try {
    $moduleRoot = Join-Path $fixture 'automation\release-e2e\modules'
    $storeParent = Join-Path $fixture 'DevFleet\E2E'
    $tokenParent = Join-Path $fixture 'evidence'
    New-Item -ItemType Directory -Force -Path $moduleRoot,$storeParent,$tokenParent | Out-Null
    $env:LOCALAPPDATA = $fixture
    Set-Content -LiteralPath (Join-Path $storeParent 'secrets.json') -Value 'fixture metadata only' -NoNewline
    @'
function Get-CandidateFingerprint {
    [pscustomobject]@{
        repositoryHead='head'; gitCommit='build'; shippingInputIdentity='shipping'
        releaseFingerprintId='release'; toolingFingerprintId='tooling'
        candidate=[pscustomobject]@{sha256='exe'}
    }
}
Export-ModuleMember -Function Get-CandidateFingerprint
'@ | Set-Content -LiteralPath (Join-Path $moduleRoot 'Candidate.psm1')
    @'
function Get-HostSafetySnapshot {
    [pscustomobject]@{startSafe=$true; availableMemoryGiB=32; projectedPostStartAvailableMemoryGiB=24}
}
Export-ModuleMember -Function Get-HostSafetySnapshot
'@ | Set-Content -LiteralPath (Join-Path $moduleRoot 'HostSafety.psm1')
    'Export-ModuleMember -Function @()' | Set-Content -LiteralPath (Join-Path $moduleRoot 'GuestSession.psm1')
    Copy-Item -LiteralPath (Join-Path $skillRoot '..\..\..\automation\release-e2e\modules\BaselineLineage.psm1') -Destination (Join-Path $moduleRoot 'BaselineLineage.psm1')
    '{"runId":"fixture-token","status":"PASS","standardNonAdministratorToken":true,"repositoryHead":"head","candidateBuildCommit":"build","shippingInputIdentity":"shipping","releaseFingerprintId":"release","toolingFingerprintId":"tooling","exe":{"sha256":"exe"}}' |
        Set-Content -LiteralPath (Join-Path $tokenParent 'CURRENT-STANDARD-TOKEN.json')

    $script:mutations = 0
    $global:fixtureVmId = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
    $global:fixtureCleanId = [guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'
    function Get-VM { [pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=$global:fixtureVmId;State='Off'} }
    function Get-VMSnapshot { [pscustomobject]@{Name='DevFleet-E2E-CLEAN';Id=$global:fixtureCleanId;VMId=$global:fixtureVmId;ParentSnapshotId=[guid]::Empty} }
    function Restore-VMSnapshot { $script:mutations++; throw 'Fixture must never restore a VM.' }
    function Start-VM { $script:mutations++; throw 'Fixture must never start a VM.' }
    function Get-DevFleetE2ECredential { throw 'Fixture must never load a protected credential.' }

    $static = (& $readinessScript -WorkspaceRoot $fixture | ConvertFrom-Json)
    Assert-True ($static.status -ceq 'PASS_STATIC_REQUIRES_LIVE_GUEST_AUTH') 'Static readiness status was wrong.'
    Assert-True ($static.staticPrerequisitesPass -eq $true) 'Static prerequisites did not pass.'
    Assert-True ($static.credential.storePresent -eq $true -and $null -eq $static.credential.exactUser) 'Static readiness claimed credential contents.'
    Assert-True ($static.credential.available -eq $false) 'Static readiness claimed to have loaded a credential.'
    Assert-True ($script:mutations -eq 0) 'Static readiness mutated the lab.'

    $live = (& $readinessScript -WorkspaceRoot $fixture -LiveGuestAuth | ConvertFrom-Json)
    Assert-True ($live.status -ceq 'BLOCKED') 'Live readiness without diagnostic admission did not block.'
    Assert-True ($live.blockers -contains 'NATIVE_DIAGNOSTIC_ADMISSION_UNVERIFIED') 'Diagnostic admission blocker was missing.'
    Assert-True ($live.staticPrerequisitesPass -eq $true) 'Live admission blocker incorrectly changed static prerequisite status.'
    Assert-True ($script:mutations -eq 0) 'Unadmitted live readiness mutated the lab.'

    $invalidFresh = (& $readinessScript -WorkspaceRoot $fixture -LiveGuestAuth -FreshLedgerPath (Join-Path $fixture 'missing-ledger.json') -FreshRunId 'fixture-new' | ConvertFrom-Json)
    Assert-True ($invalidFresh.blockers -contains 'FRESH_DIAGNOSTIC_ADMISSION_INVALID') 'Invalid fresh journal was admitted.'
    Assert-True ($script:mutations -eq 0 -and $invalidFresh.credential.available -eq $false) 'Invalid fresh admission contacted the lab or loaded a credential.'

    $global:fixtureVmId = [guid]::NewGuid()
    $wrongVm = (& $readinessScript -WorkspaceRoot $fixture | ConvertFrom-Json)
    Assert-True ($wrongVm.blockers -contains 'EXACT_LAB_IDENTITY_MISMATCH') 'Wrong L1 GUID was accepted.'
    Assert-True ($wrongVm.status -ceq 'BLOCKED' -and $script:mutations -eq 0) 'Wrong L1 GUID reached mutation.'
    $global:fixtureVmId = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
    $global:fixtureCleanId = [guid]::NewGuid()
    $wrongClean = (& $readinessScript -WorkspaceRoot $fixture | ConvertFrom-Json)
    Assert-True ($wrongClean.blockers -contains 'EXACT_LAB_IDENTITY_MISMATCH') 'Wrong CLEAN GUID was accepted.'
    Assert-True ($wrongClean.status -ceq 'BLOCKED' -and $script:mutations -eq 0) 'Wrong CLEAN GUID reached mutation.'

    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($preflightScript,[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) 'Preflight script has a parser error.'
    $capture = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-Captured'},$true)
    Assert-True ($null -ne $capture) 'Preflight capture function is missing.'
    . ([scriptblock]::Create($capture.Extent.Text))
    $captureRoot = Join-Path $fixture 'capture'
    New-Item -ItemType Directory -Force -Path $captureRoot | Out-Null
    $outRoot = $captureRoot
    $nonterminating = Invoke-Captured -Name 'nonterminating' -Action { Write-Error 'synthetic fixture failure' }
    Assert-True ($nonterminating.status -ceq 'FAIL' -and $nonterminating.exitCode -ne 0) 'Nonterminating PowerShell error was masked.'
    $clean = Invoke-Captured -Name 'clean' -Action { 'fixture success' }
    Assert-True ($clean.status -ceq 'PASS' -and $clean.exitCode -eq 0) 'Clean PowerShell action was rejected.'
    $terminating = Invoke-Captured -Name 'terminating' -Action { throw 'synthetic terminating failure' }
    Assert-True ($terminating.status -ceq 'FAIL' -and $terminating.exitCode -ne 0) 'Terminating PowerShell error was masked.'
    $native = Invoke-Captured -Name 'native-exit' -Action { & $PSHOME\pwsh.exe -NoProfile -Command 'exit 7' }
    Assert-True ($native.status -ceq 'FAIL' -and $native.exitCode -eq 7) 'Native nonzero exit was masked.'
    $nativeWarning = Invoke-Captured -Name 'native-warning' -Action { & $PSHOME\pwsh.exe -NoProfile -Command '[Console]::Error.WriteLine("fixture warning"); exit 0' }
    Assert-True ($nativeWarning.status -ceq 'PASS' -and $nativeWarning.exitCode -eq 0) 'Successful native stderr was mistaken for a PowerShell error.'
    "PASS $passes VM-free orchestrator assertions"
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    Remove-Variable fixtureVmId,fixtureCleanId -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: .agents/skills/devfleet-certification-orchestrator/tests/Test-CurrentGuestCredentialImport.ps1

SHA256: 71710dbc9ae1aa8ce265687817253c904e9c431a9779a5ebd16fb0b6d18a5963 | Bytes: 1047 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$source=Join-Path $PSScriptRoot '../scripts/Test-CurrentGuestAccess.ps1'
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$t,[ref]$e)
if($e){throw 'Diagnostic source parse failed'}
$imports=$ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Import-Module'},$true)
foreach($node in $imports){. ([scriptblock]::Create($node.Extent.Text))}
$getter=$ast.Find({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '(^|\\)Get-DevFleetE2ECredential$'},$true)
if(-not $getter){throw 'Native credential getter was not found in production path'}
$command=Get-Command $getter.GetCommandName() -ErrorAction Stop
if($command.ModuleName -cne 'Secrets'){throw 'Credential getter resolved outside the native Secrets module'}
'PASS production import sequence resolves native credential getter; secret loads 0; VM operations 0'

```


## FILE: .agents/skills/devfleet-certification-orchestrator/tests/Test-FreshAttemptAdmission.ps1

SHA256: 73cf867cac54dee8f18bfa15567aeb304c8a664444d0f575077799b06a176347 | Bytes: 1390 | Git mode: 100644

```
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

```


## FILE: .agents/skills/devfleet-certification-orchestrator/tests/Test-FreshDateRoundTrip.ps1

SHA256: ba857c4eccf9df0cc8d80f9ab5f85aa2728980d6613b3e05fe69a76fd506675b | Bytes: 1706 | Git mode: 100644

```
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

```


## FILE: .agents/skills/devfleet-e2e-fastlane/SKILL.md

SHA256: f4c76aa1c783df6c9944ce48a2588425ee51ac4771e272c844d185254bd92372 | Bytes: 4062 | Git mode: 100644

````
---
name: devfleet-e2e-fastlane
description: Use when DevFleet certification is slow, repeated VM retries are proposed, current proofs may be reusable, lifecycle timing or checkpoint evidence is confusing, or a Warp Time/simulation shortcut is requested.
---

# DevFleet E2E fastlane

Speed up diagnosis, not the meaning of PASS. The same candidate must retain its current proofs unless a native material identity actually changes. This skill and its reports grant **no release credit** and cannot launch a VM.

## Entry

Read native authority and the release-control skill; current user model/ownership policy wins over historical model labels. Start zero helpers when the next action is an already-authorized run. Do not repeatedly ingest the whole audit.

From the repository root:

```powershell
& .\.venv-test\Scripts\python.exe .\.agents\skills\devfleet-e2e-fastlane\scripts\fastlane.py inspect --repo .
& .\.venv-test\Scripts\python.exe .\.agents\skills\devfleet-e2e-fastlane\scripts\fastlane.py test --repo . --area quick
```

`inspect` is **READ_ONLY_REVALIDATION** of the real prior proof/token/artifact binding, not a new proof. It uses the unchanged native validators. Exact lineage-bound receipts are copied only to a temporary outside-repository view, so the native nested/root evidence-layout difference does not waste another lab run. No timestamp-based file selection or edited native receipts.

`test` uses existing native regression functions with mocked VM/transport I/O and injected `ClockProvider`/sleep. Reports/logs go outside the checkout. Choose one area: `clock`, `observer`, `vault`, `acceptance`, `quick`, or `all`; do not blindly repeat all areas at every turn. A nonzero exit, timeout or material drift blocks reliance on the diagnostic. Inspect failure logs, not just the summary.

## Live boundary

The security scan or another ROOT on this checkout must be quiescent or independently isolated before live ownership. No raw/no-override HOST-SAFETY pass means no certified FullRelease; permission for an experimental proof is not a change to the final validator. Refresh native host, current tuple, exact L1/CLEAN and required nested L2 state immediately before reservation/runtime. Diagnostic reports are never admission tickets.

## Shorten the feedback loop

Before a VM retry: preserve the actual failure, reproduce it with an existing callback seam, fix the source, test the failure and controls, then classify shipping/tooling drift. Reuse valid tests/evidence rather than rebuilding for a chat or skill change. Never patch packaged EXE/TAR/ZIP contents in place.

A same-candidate checkpoint may accelerate a separately authorized diagnostic after exact native provenance verification. An old installed checkpoint cannot validate a newer payload. Final certification remains one coherent current FullRelease with actual install/reboot, backup/restore, U01–U05 and certified cleanup. No historical phase stitching.

After a late FullRelease failure, use the failed phase and its prerequisite checkpoint to narrow diagnosis before another full attempt. Run the relevant VM-free production-path test first. If that cannot establish the cause, design one separately admitted, non-certifying live diagnostic from the exact same-candidate checkpoint, with current HostSafety, guest authentication, ownership, and terminal L1/L2 cleanup. Do not call the native `Resume` mode a phase continuation or run a phase executor directly outside its admitted context. Read [late-phase guidance](references/acceleration.md#late-phase-failures) before proposing this shortcut.

Do not alter VM/host clocks, shrink real timeouts, pre-mark stages, replace real authentication/health with fixtures, turn partial backup into success, or suppress a verified security finding. A time simulation is not a VM simulation.

See [checkpoint and timing guidance](references/acceleration.md). On closeout, record exact results, next falsifiable action and actual ownership/cleanup. Never claim the remaining runtime gates were tested by this fastlane.

````


## FILE: .agents/skills/devfleet-e2e-fastlane/agents/openai.yaml

SHA256: f64b07d22a64a949556a38478c33efc3cff638af072f3138e78da7d7fc21e9ad | Bytes: 322 | Git mode: 100644

```
interface:
  display_name: "DevFleet E2E Fastlane"
  short_description: "Fast, VM-free certification prechecks and lifecycle regressions"
  default_prompt: "Use $devfleet-e2e-fastlane to revalidate current evidence and select the smallest VM-free regression suite before the next authorized real certification operation."

```


## FILE: .agents/skills/devfleet-e2e-fastlane/references/acceleration.md

SHA256: 5163ce839f4b0038ffedf4060094a649878391b56f93c1d6426c2ff4d7ccd1f8 | Bytes: 8484 | Git mode: 100644

```
# Faster diagnosis without counterfeit E2E evidence

## Evidence levels and commands

| Level | What it proves | Command |
|---|---|---|
| Source/mock regression | Decision logic on synthetic inputs; no VM | `fastlane.py test --repo . --area quick` |
| Native prior-evidence revalidation | Previously completed real proofs still bind to this candidate | `fastlane.py inspect --repo .` |
| Owned checkpoint diagnostic | Specific installed behavior at a proven checkpoint | Only the existing native diagnostic entrypoint, after exact provenance/safety/authorization checks |
| Current certification | A coherent installed FullRelease and all native acceptance criteria | Existing release-control workflow, not this skill |

All commands require the repository's existing Python runtime. PowerShell tests need PowerShell 7. No global packages are installed. The test allowlist cannot select installers, live proof drivers, signing, or FullRelease. Results are written to a new external directory and execution stops at a failed/timeout suite. If a timeout leaves process cleanup uncertain, resolve the exact test descendants before considering the lab.

The `inspect` command imports ONLY the trusted live repository validator, not code extracted from a supplied archive. It verifies the live candidate, fresh genuine standard-token receipt, both current proof roles, their source/artifact bindings and independence. Its temporary proof views resolve missing root-level receipt copies ONLY from the exact phase and checkpoint lineage already named in that same proof, with matching hashes. Existing bad canonical files cause failure, not silent replacement. No native proof bytes are repaired or created.

## What to test first

| Symptom | Area | Existing native seam |
|---|---|---|
| Endless heartbeat, early/late timeout, reboot generation | `observer`, then `clock` | Actual lifecycle/WPF state machines with injected ClockProvider and SleepProvider |
| Multipass inventory hangs, readiness identity mismatch | `vault` | Real nested-readiness scriptblock with mocked service, daemon, VM and clock providers |
| Backup/delete/restore binds to wrong installation | `vault` | Configured Vault fixture/Primary identity guards and Python scenario tests |
| Proof file layout, source/tuple drift, audit closure | `inspect`, then `acceptance` | Unchanged proof and final-acceptance validators |
| Unknown class | `all` once | Eleven explicit offline suites; do not loop until green |

Only repeat relevant tests after a change. Never infer that a cached console PASS still applies: the runner records actual script hashes and checks material/native inputs before/after. It does not cache PASS or reset qualification budgets. The full original test suites remain available for release-required broad validation.

## Clock manipulation versus time-controlled testing

VirtualBox's Time Manager implements `WarpDrivePercentage` to change virtual clock rate. This is not extra CPU, disk or network bandwidth. Do not turn it on in DevFleet's certification lab: watchdog, reboot, authentication, package and external-service time would no longer have the ordinary timing semantics under test. Host and guest clocks remain untouched by the fastlane.

The supported shortcut is dependency-injected test time. DevFleet already exposes this in its production lifecycle observer and WPF contract. `Test-VirtualClock.ps1` tests actual native deadline functions over a 25-hour horizon and the real wait loop at a 30-minute no-progress cutoff without waiting those hours. Its temporary observations are outside the native proof directories and grant no release credit. This is not a whole operating-system/VM simulator.

Primary references:
- VirtualBox Time Manager source, `WarpDrivePercentage`: https://raw.githubusercontent.com/mirror/vbox/master/src/VBox/VMM/VMMR3/TM.cpp
- .NET deterministic time testing: https://learn.microsoft.com/en-us/dotnet/core/extensions/timeprovider-testing
- Hyper-V checkpoint semantics: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/checkpoints

## Checkpoint reuse rules

A checkpoint name is not provenance. Before a diagnostic restore compare exact L1 ID, checkpoint GUID, configured Primary/Vault identities, candidate build commit, payload hash, shipping/release/tooling tuple, installation transaction and origin RunId. Require the native provenance validator, not merely `checkpoint_assessment`'s offline field check. A hash of a manifest proves its byte identity, not that its claims were observed.

The old MAINTENANCE-READY checkpoint can contain old software even when its name matches. A shipping change invalidates reuse for testing the replacement product; do not restore an old installation and copy new PASS labels. An unchanged candidate with verified current checkpoint provenance can support a bounded diagnostic, but it does not replace independent CLEAN-start proofs or the single coherent final FullRelease.

Do not create/change canonical CLEAN to speed up the run. Standard snapshots retain VM memory, while production snapshots do not; restoring either affects state outside simple elapsed-time arithmetic. Never copy security tokens/SSH identity from a snapshot into unrelated machines. Do not share warmed test state between independent role proofs.

## Late-phase failures

When FullRelease passes early phases and blocks later, preserve that terminal RunId, phase records, checkpoint/provenance, and cleanup state. Diagnose the blocked phase with the narrowest production-path VM-free test. If the failure needs guest observation, a separately authorized diagnostic can use a checkpoint only after native validation of the exact current candidate, installation generation, checkpoint GUID, origin RunId, L1 identity, and safety/admission. The diagnostic may start near the failing scenario; it earns no FullRelease or earlier-phase credit and must leave the exact lab terminally safe.

For example, `PERMANENT-DELETE` normally restores the run's `MAINTENANCE-READY` checkpoint before its executor. A dedicated admitted diagnostic could test its nested Primary readiness without repeating installation phases, provided that checkpoint still belongs to the current tuple. Do not execute the product phase directly in an ad hoc shell: its normal executor mutates guest/nested resources and needs an owned context and cleanup. A timeout that exposes only the last Multipass command calls for a mocked deadline/telemetry regression first, then a scoped guest diagnostic if the cause remains unresolved.

The current `Invoke-FullReleaseRun` always starts at phase 1; top-level `Resume` only verifies identity. A failed RunId cannot be promoted by appending a later phase result. After the causal fix and required tuple qualification, a certifying attempt must rerun one coherent FullRelease, including phases previously observed as PASS. Building a true certifying resume would require a new native contract that binds an immutable checkpoint, phase state, product generation, candidate tuple, ownership, and validator acceptance to the same run; this skill does not authorize or simulate such a change.

## Immediate constraints in this campaign

At authoring, candidate `4f1ca4570466f1595c0f05fb84eab408f6e99b31` had two independently validated role proofs and a matching Developer receipt. The actual new FullRelease was not run. Reconcile live files; this sentence is not authority.

Recorded proof start-to-cleanup durations were about 14m25s for Laptop/Surrogate and 12m33s for Desktop/Primary. The historical failed FullRelease spent roughly 12m each on dependency matrix/fresh install/reboot, 15m on Linux, and 15m on MaintenanceReady. These observations concern different provenance; they are not a finish-time prediction or current phase credit.

A separate security scan on this checkout and raw/no-override memory admission have been current interlocks. Do not override either in this skill. Verified high-risk findings require triage and an explicit release-scope decision; an operational test pass is not a clean security audit. Isolate or quiesce other workloads before live mutations, without killing user applications automatically.

Package caches/preverified download staging may reduce repeated I/O in future work, but must preserve vendor signature/digest and expiry/revocation policy, native entrypoint behavior and independent clean-state tests. That optimization is NOT installed by this skill.

```


## FILE: .agents/skills/devfleet-e2e-fastlane/scripts/Test-VirtualClock.ps1

SHA256: 869d25b8891e4da21f57d86c0b2a95452e873e0ee710fc9316b0012a444db288 | Bytes: 5315 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Repository)
$ErrorActionPreference='Stop'
$Repository=(Resolve-Path -LiteralPath $Repository).Path
Import-Module (Join-Path $Repository 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $Repository 'automation/release-e2e/modules/HarnessBudget.psm1') -Force -DisableNameChecking
$watch=[Diagnostics.Stopwatch]::StartNew();$passed=0;$failures=[Collections.Generic.List[string]]::new()
function Check([bool]$Ok,[string]$Name){if($Ok){$script:passed++}else{$script:failures.Add($Name)}}
function Denied([scriptblock]$Body,[string]$Name){$caught=$false;try{&$Body|Out-Null}catch{$caught=$true};Check $caught $Name}
$base=[datetime]'2026-01-01T00:00:00Z';$deadline=$base.AddHours(25)
# Real native deadline functions; injected timestamps, no wall-clock changes.
Check ((Get-DeadlineRemainingSeconds -DeadlineUtc $deadline -NowUtc $base)-eq90000) '25-hour remaining budget'
Check ((Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 120 -DeadlineUtc $deadline -NowUtc $base)-eq120) 'child limit preserved'
Check ((Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 120 -DeadlineUtc $deadline -NowUtc $deadline.AddSeconds(-1.5))-eq1) 'fractional remainder floored'
Denied {Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 120 -DeadlineUtc $deadline -NowUtc $deadline} 'exact expiration rejects child'
Denied {Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 120 -DeadlineUtc $deadline -NowUtc $deadline.AddDays(1)} 'expired owner cannot restart budget'
Denied {Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 0 -DeadlineUtc $deadline -NowUtc $base} 'zero child timeout rejected'
$prior=[pscustomobject]@{checkpointGeneration=1;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}
$next=[pscustomobject]@{checkpointPresent=$true;checkpoint=[pscustomobject]@{checkpointGeneration=2;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;terminalFailure=$false}
Check ((Get-DurableProgressClassification -Observation $next -PriorCheckpoint $prior -MaxGeneration 3)-ceq'NEXT_REBOOT') 'same transaction next-generation boundary'
$next.checkpoint.transactionId='c'*32
Check ((Get-DurableProgressClassification -Observation $next -PriorCheckpoint $prior -MaxGeneration 3)-ceq'TERMINAL_FAILURE') 'foreign transaction rejected'
$pending=[pscustomobject]@{checkpointPresent=$false;checkpoint=$null;matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;terminalFailure=$false;processTree=@();timestampUtc=$base.ToString('o');progress=[ordered]@{checkpointGeneration=1;checkpointState='waiting-for-reboot';completedStages=@('bootstrap');resumeStage='install';stages=@();cpuSeconds=0;installStateSha256=$null;ownershipSha256=$null;receiptMatch=$false;health=$false;hostAgentTaskState='Running';listener=$false}}
# Invoke the ACTUAL wait loop. Every observation and delay is injected.
# No guest session, external process or network operation is used by the provider.
$state=@{clock=$base;reads=0;sleeps=0};$clock={$now=$state.clock;$state.clock=$now.AddSeconds(300);$state.reads++;$now}.GetNewClosure()
$sleep={param($seconds)$state.sleeps++}.GetNewClosure()
$provider={param($context)$context.providerContext}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-fastlane-fixture-'+[guid]::NewGuid().ToString('N'))
try{
 New-Item -ItemType Directory -Path $temp -ErrorAction Stop|Out-Null
 $result=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Action FreshInstall -Role 'Primary / Desktop' -PriorGeneration 1 -MaxGeneration 3 -BudgetSeconds 90000 -NoProgressBudgetSeconds 1800 -AbsoluteBudgetSeconds 90000 -PollSeconds 5 -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationProvider $provider -ObservationProviderContext $pending -ClockProvider $clock -SleepProvider $sleep -EvidencePath (Join-Path $temp 'fixture-observer.json')
 Check ([string]$result.outcome-ceq'NO_PROGRESS_TIMEOUT') 'unchanged state reaches 30-minute virtual no-progress timeout'
 Check ([datetime]$result.absoluteLifecycleDeadlineUtc-eq$deadline) '25-hour native owner deadline remains unchanged'
 Check ($state.reads-lt100) 'virtual replay iteration count remains bounded'
 Check ([string]$result.outcome-cne'COMPLETED') 'no fabricated install completion'
 $simulated=[math]::Round(($state.clock-$base).TotalSeconds,2)
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
$watch.Stop()
$report=[ordered]@{status=if($failures.Count){'FAIL'}else{'PASS'};scope='INJECTED_CLOCK_NATIVE_FUNCTION_REGRESSION';passed=$passed;failed=@($failures);virtualOwnerHorizonSeconds=90000;virtualObserverSeconds=$simulated;wallSeconds=$watch.Elapsed.TotalSeconds;realVmOperations=0;hostClockChanged=$false;guestClockChanged=$false;certificationCredit=$false;nativeSourceModified=$false}
$report|ConvertTo-Json -Depth 6
if($failures.Count){exit 1}

```


## FILE: .agents/skills/devfleet-e2e-fastlane/scripts/fastlane.py

SHA256: 403c21899b19c79e0e8c3fe59d61c30e991927f2760b0193926f6a5494e409f4 | Bytes: 16420 | Git mode: 100644

```
#!/usr/bin/env python3
"""VM-free DevFleet diagnostics. No command here authorizes or launches a lab.

Native validators remain authoritative; fixture and replay results earn no credit.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
TUPLE = ('candidateCommit','shippingInputIdentity','releaseFingerprintId','toolingFingerprintId')
L1 = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
ROLES = {'Primary / Desktop':'REBOOT-RESUME','Laptop / Surrogate':'SURROGATE-DISPOSABLE'}
ROOT = Path(__file__).resolve().parents[1]
SUITES = {
 'clock': [('virtual-clock','skill','scripts/Test-VirtualClock.ps1')],
 'observer': [('lifecycle','ps','automation/release-e2e/tests/Test-LifecycleObserverBehavior.ps1'),
              ('wpf','ps','automation/release-e2e/tests/Test-WpfLaunchBoundaryBehavior.ps1'),
              ('launch-deferral','ps','automation/release-e2e/tests/Test-ProductLaunchObserverDeferral.ps1')],
 'vault': [('nested-readiness','ps','automation/release-e2e/tests/Test-NestedPrimaryReadiness.ps1'),
           ('vault-binding','ps','automation/release-e2e/tests/Test-MaintenanceVaultScenarioBinding.ps1'),
           ('vault-native-steps','ps','automation/release-e2e/tests/Test-MaintenanceVaultNativeSteps.ps1'),
           ('vault-scenarios','pytest','automation/release-e2e/tests/test_vault_scenario_contract.py')],
 'acceptance': [('proof-validator','pytest','tools/test_validate_native_proof.py'),
                ('release-validator','python','tools/test_validate_release_bundle.py'),
                ('final-acceptance','python','tools/test_final_acceptance_tools.py')]
}

def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

def checked_path(root,relative):
    """Reject path aliases/streams/links instead of trusting evidence-provided paths."""
    if not isinstance(relative,str) or not relative or '\\' in relative or ':' in relative or '\x00' in relative:
        raise ValueError('Unsafe evidence path')
    rel=PurePosixPath(relative)
    if rel.is_absolute() or any(p in ('','.','..') for p in relative.split('/')):
        raise ValueError('Unsafe evidence path')
    root=Path(root).resolve(strict=True);p=root
    for part in rel.parts:
        p=p/part
        if p.exists() or p.is_symlink():
            s=p.lstat()
            if stat.S_ISLNK(s.st_mode) or getattr(s,'st_file_attributes',0)&0x400:
                raise ValueError('Reparse/symlink evidence refused')
    if not p.resolve(strict=False).is_relative_to(root):raise ValueError('Evidence escapes root')
    return p

def read_json(path,max_bytes=16*1024*1024):
    def pairs(rows):
        out={}
        for k,v in rows:
            if k in out:raise ValueError('Duplicate JSON key')
            out[k]=v
        return out
    def constant(_):raise ValueError('Nonfinite JSON value')
    p=Path(path)
    if p.stat().st_size>max_bytes:raise ValueError('JSON input exceeds diagnostic budget')
    with p.open('rb') as f:raw=f.read(max_bytes+1)
    if len(raw)>max_bytes:raise ValueError('JSON input grew beyond diagnostic budget')
    return json.loads(raw.decode('utf-8-sig'),object_pairs_hook=pairs,parse_constant=constant)

def elapsed(start,end):
    try:
        a,b=(dt.datetime.fromisoformat(x.replace('Z','+00:00')) for x in (start,end))
        if a.tzinfo is None or b.tzinfo is None:return None
        n=(b-a).total_seconds()
        return round(n,3) if n>=0 else None
    except (TypeError,ValueError,AttributeError):return None

def checkpoint_assessment(authority,record):
    """Offline manifest assessment, NEVER permission to restore a VM/checkpoint."""
    issues=[];t=record.get('candidateTuple',{})
    for key in TUPLE:
        value=authority.get(key)
        pattern=r'[0-9a-f]{40}' if key=='candidateCommit' else r'[0-9a-f]{64}'
        if not isinstance(value,str) or not re.fullmatch(pattern,value) or t.get(key)!=value:issues.append(key)
    if record.get('l1Id')!=L1:issues.append('exact L1 identity')
    if record.get('configured') is not True:issues.append('configured installation')
    if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',str(record.get('checkpointId',''))):issues.append('checkpoint identity')
    if record.get('phase')!='MAINTENANCE-READY' or not re.fullmatch(r'(?:e2e-)?fullrelease-[A-Za-z0-9-]+',str(record.get('sourceRunId',''))):issues.append('origin')
    return {'diagnosticReusable':not issues,'mismatches':issues,'certificationCredit':False,
            'requiresFreshNativeIdentityCheck':True,'runtimeAuthorizationGranted':False}

def proof_view(repo,run_id,destination):
    """Make a temporary validation view using exact bound lineage, never latest mtime."""
    repo=Path(repo).resolve();destination=Path(destination)
    if destination.resolve().is_relative_to(repo):raise ValueError('Proof view must be outside repository')
    if not re.fullmatch(r'e2e-(?:exact-candidate-)?proof-[A-Za-z0-9-]+',run_id):raise ValueError('Invalid proof RunId')
    rd=checked_path(repo,'audit/automation-harness/runs/'+run_id)
    final=read_json(checked_path(rd,'proof-final.json'));binding=final.get('proofBinding',{})
    phase=binding.get('phaseId');lineage=binding.get('checkpointLineageId')
    if ROLES.get(final.get('role'))!=phase or not re.fullmatch(r'[0-9a-f]{32}',str(lineage)):
        raise ValueE