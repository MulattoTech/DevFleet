# DevFleet source part 050

Full-source UTF-8 byte interval [2278500, 2325000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2a53a0571bab8ff45696f866adede912d330211b5e808246209dad0a12e42803

<!-- BEGIN SOURCE SLICE -->
 } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:throwingProviderStopped=$true } `
        -ProviderCallTimeoutSeconds 2 `
        -ClockProvider { [datetime]'2026-09-05T20:00:00Z' } `
        -SleepProvider { param($seconds) } `
        -TerminalWriter { param($value) $script:throwingProviderTerminalWrites++; $value }
    Check ([string]$throwingProvider.failureClass -eq 'REPORT_PROVIDER_FAILURE' -and [string]$throwingProvider.error -match 'controlled original report-provider error' -and $script:throwingProviderStopped -and $script:throwingProviderTerminalWrites -eq 1) 'a throwing report provider preserves the original error while stopping and terminalizing once'

    $script:neverProgressStopped=$false;$script:neverProgressTerminalWrites=0
    $neverProgress=Wait-WpfBoundReport -Specification $expected `
        -ReportProvider { $null } `
        -ProgressProvider { while($true){Start-Sleep -Milliseconds 100} } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:neverProgressStopped=$true } `
        -ProviderCallTimeoutSeconds 1 `
        -ClockProvider { [datetime]'2026-09-05T20:00:00Z' } `
        -SleepProvider { param($seconds) } `
        -TerminalWriter { param($value) $script:neverProgressTerminalWrites++; $value }
    Check ([string]$neverProgress.failureClass -eq 'PROGRESS_PROVIDER_TIMEOUT' -and $neverProgress.productStarted -eq $true -and $script:neverProgressStopped -and $script:neverProgressTerminalWrites -eq 1) 'a progress provider that never returns after product start is cancelled, stops the exact worker, and terminalizes once'

    $longComplete = $complete | Select-Object *
    $longComplete.launchId = $longOwner.launchId
    $longComplete.deadlineUtc = $longOwner.driverDeadlineUtc
    $script:clock = $now
    $script:round = 0
    $script:stopped = $false
    $script:terminalWrites = 0
    $longSilence = Wait-WpfBoundReport -Specification $longOwner -ReportProvider { $script:round++; if($script:round -ge 5){$longComplete}else{$null} } -WorkerStateProvider { 'Running' } -StopWorker { $script:stopped = $true } -ClockProvider { $value=$script:clock; $script:clock=$value.AddSeconds(200); $value } -SleepProvider { param($seconds) } -TerminalWriter { param($value) $script:terminalWrites++; $value }
    Check ([string]$longSilence.status -eq 'PASS' -and -not $script:stopped -and $script:terminalWrites -eq 0) 'a real product operation may remain semantically quiet for more than five minutes while still bounded by inherited deadlines'

    $script:clock = $now
    $script:round = 0
    $script:semantic = 0
    $script:terminalWrites = 0
    $eventual = Wait-WpfBoundReport -Specification $expected -ReportProvider { $script:round++; if($script:round -ge 3){$complete}else{$null} } -WorkerStateProvider { 'Running' } -StopWorker { $script:stopped=$true } -ProgressProvider { $script:semantic++; [pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$resume.runId;launchId=$resume.launchId;transactionId=$resume.transactionId;payloadSha256=$resume.payloadSha256;candidateSha256=$resume.candidateSha256;deadlineUtc=$resume.driverDeadlineUtc;sequence=(8+$script:semantic);phase='PRODUCT_STATUS_CHANGED';semanticProgressSequence=$script:semantic;semanticProgressKind='OBSERVER_BREADCRUMB'} } -ClockProvider { $value=$script:clock; $script:clock=$value.AddSeconds(240); $value } -SleepProvider { param($seconds) } -TerminalWriter { param($value) $script:terminalWrites++; $value }
    Check ([string]$eventual.status -eq 'OBSERVER_FAILURE' -and [string]$eventual.failureClass -eq 'UIA_DEADLINE_EXHAUSTED' -and $script:terminalWrites -eq 1) 'a report first produced after the immutable cutoff cannot revive the launch and UI breadcrumbs cannot extend it'

    $lateCollectedSpecCommon = @{} + $common
    $lateCollectedSpecCommon.LaunchId = ('e' * 32)
    $lateCollected = New-WpfLaunchSpecification @lateCollectedSpecCommon -LaunchMode resume -ElevatedResume
    $lateCollectedReport = $complete | Select-Object *
    $lateCollectedReport.launchId = $lateCollected.launchId
    $lateCollectedReport.deadlineUtc = $lateCollected.driverDeadlineUtc
    $script:clock = $now.AddSeconds(480)
    $collected = Wait-WpfBoundReport -Specification $lateCollected -ReportProvider { [pscustomobject]@{contract='devfleet-wpf-file-observation-v1';kind='TERMINAL';value=$lateCollectedReport;fileWriteUtc=$now.AddSeconds(400).ToString('o')} } -WorkerStateProvider { 'Running' } -StopWorker { throw 'an in-deadline terminal must not be stopped merely because collection was delayed' } -ClockProvider { $script:clock } -SleepProvider { param($seconds) } -TerminalWriter { param($value) throw 'an in-deadline terminal must not be replaced' }
    Check ([string]$collected.status -eq 'PASS') 'a valid terminal atomically established before cutoff remains collectable after cutoff'

    $wrongProgressCommon = @{} + $common
    $wrongProgressCommon.LaunchId = ('f' * 32)
    $wrongProgress = New-WpfLaunchSpecification @wrongProgressCommon -LaunchMode resume -ElevatedResume -SemanticNoProgressSeconds 300
    $script:clock = $now
    $script:terminalWrites = 0
    $wrongIdentityProgress = Wait-WpfBoundReport -Specification $wrongProgress -ReportProvider { $null } -WorkerStateProvider { 'Running' } -StopWorker { $script:stopped=$true } -ProgressProvider { [pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$wrongProgress.runId;launchId=$wrongProgress.launchId;transactionId=('9'*32);payloadSha256=$wrongProgress.payloadSha256;candidateSha256=$wrongProgress.candidateSha256;deadlineUtc=$wrongProgress.driverDeadlineUtc;sequence=9;phase='PRODUCT_STATUS_CHANGED';semanticProgressSequence=1;semanticProgressKind='DURABLE_PRODUCT_PROGRESS'} } -ClockProvider { $value=$script:clock;$script:clock=$value.AddSeconds(150);$value } -SleepProvider { param($seconds) } -TerminalWriter { param($value)$script:terminalWrites++;$value }
    Check ([string]$wrongIdentityProgress.failureClass -eq 'UIA_SEMANTIC_NO_PROGRESS' -and $script:terminalWrites -eq 1) 'wrong-transaction progress cannot extend the semantic deadline'

    $validProgressCommon = @{} + $common
    $validProgressCommon.LaunchId = ('a' * 32)
    $validProgressCommon.OwnerDeadlineUtc = $now.AddSeconds(1200)
    $validProgress = New-WpfLaunchSpecification @validProgressCommon -LaunchMode resume -ElevatedResume -SemanticNoProgressSeconds 300
    $validProgressReport = $complete | Select-Object *
    $validProgressReport.launchId = $validProgress.launchId
    $validProgressReport.deadlineUtc = $validProgress.driverDeadlineUtc
    $validProgressReport.sequence = 100
    $script:clock=$now;$script:round=0;$script:semantic=0;$script:terminalWrites=0
    $progressThenComplete=Wait-WpfBoundReport -Specification $validProgress -ReportProvider {$script:round++;if($script:round-ge5){$validProgressReport}else{$null}} -WorkerStateProvider {'Running'} -StopWorker {throw 'valid in-deadline progress must preserve the worker'} -ProgressProvider {$script:semantic++;[pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$validProgress.runId;launchId=$validProgress.launchId;transactionId=$validProgress.transactionId;payloadSha256=$validProgress.payloadSha256;candidateSha256=$validProgress.candidateSha256;deadlineUtc=$validProgress.driverDeadlineUtc;sequence=(10+$script:semantic);phase='PRODUCT_DURABLE_PROGRESS';semanticProgressSequence=$script:semantic;semanticProgressKind='DURABLE_PRODUCT_PROGRESS';progressSource='DURABLE_PRODUCT_OBSERVER'}} -ClockProvider {$value=$script:clock;$script:clock=$value.AddSeconds(150);$value} -SleepProvider {param($seconds)} -TerminalWriter {param($value)$script:terminalWrites++;$value}
    Check ([string]$progressThenComplete.status -eq 'PASS' -and $script:terminalWrites -eq 0) 'only exact transaction/payload-bound durable product progress can extend the semantic deadline inside the immutable cutoff'

    foreach($badProgressCase in @('MALFORMED','NONMONOTONIC')){
        $script:clock=$now;$script:semantic=0;$script:terminalWrites=0
        $badProgress=Wait-WpfBoundReport -Specification $wrongProgress -ReportProvider {$null} -WorkerStateProvider {'Running'} -StopWorker {$script:stopped=$true} -ProgressProvider {if($badProgressCase-eq'MALFORMED'){[pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$wrongProgress.runId;launchId=$wrongProgress.launchId;transactionId=$wrongProgress.transactionId;payloadSha256=$wrongProgress.payloadSha256;candidateSha256=$wrongProgress.candidateSha256;deadlineUtc=$wrongProgress.driverDeadlineUtc;sequence='bad';phase='PRODUCT_DURABLE_PROGRESS';semanticProgressSequence='bad';semanticProgressKind='DURABLE_PRODUCT_PROGRESS';progressSource='DURABLE_PRODUCT_OBSERVER'}}else{[pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$wrongProgress.runId;launchId=$wrongProgress.launchId;transactionId=$wrongProgress.transactionId;payloadSha256=$wrongProgress.payloadSha256;candidateSha256=$wrongProgress.candidateSha256;deadlineUtc=$wrongProgress.driverDeadlineUtc;sequence=9;phase='PRODUCT_DURABLE_PROGRESS';semanticProgressSequence=1;semanticProgressKind='DURABLE_PRODUCT_PROGRESS';progressSource='DURABLE_PRODUCT_OBSERVER'}}} -ClockProvider {$value=$script:clock;$script:clock=$value.AddSeconds(150);$value} -SleepProvider {param($seconds)} -TerminalWriter {param($value)$script:terminalWrites++;$value}
        Check ([string]$badProgress.failureClass -eq 'UIA_SEMANTIC_NO_PROGRESS' -and $script:terminalWrites -eq 1) "$badProgressCase progress cannot extend the semantic deadline"
    }

    $raceReport = $observerHandoff | Select-Object *
    $raceReport.sequence = 9
    $script:raceReportReads = 0
    $script:raceTerminalWrites = 0
    $raceObserved = Wait-WpfBoundReport -Specification $expected -ReportProvider {
        $script:raceReportReads++
        if ($script:raceReportReads -ge 2) { $raceReport } else { $null }
    } -WorkerStateProvider { 'Exited' } -StopWorker {
        throw 'terminal handoff written immediately before worker exit must not be stopped'
    } -ClockProvider { $now } -SleepProvider { param($seconds) } -TerminalWriter {
        param($value)
        $script:raceTerminalWrites++
        $value
    }
    Check ([string]$raceObserved.status -eq 'OBSERVER_HANDOFF' -and $script:raceReportReads -eq 2 -and $script:raceTerminalWrites -eq 0) 'worker exit rechecks a just-written valid terminal handoff before classifying EARLY_WORKER_EXIT'

    $script:terminalWrites = 0
    $early = Wait-WpfBoundReport -Specification $expected -ReportProvider { $null } -WorkerStateProvider { 'Exited' } -StopWorker { throw 'must not stop an already exited worker' } -ClockProvider { $now } -SleepProvider { param($seconds) } -TerminalWriter { param($value) $script:terminalWrites++; $value }
    Check ([string]$early.status -eq 'OBSERVER_FAILURE' -and [string]$early.failureClass -eq 'EARLY_WORKER_EXIT' -and $script:terminalWrites -eq 1) 'early startup failure writes the minimal primary observer error'

    Check ((Get-WpfCleanupDisposition -Status 'ALREADY_RUNNING' -CompletionVerified:$false) -eq 'CONTINUE_OBSERVATION') 'already-running execution cannot be treated as completed or cleaned up'
    Check ((Get-WpfCleanupDisposition -Status 'DURABLE_PENDING' -CompletionVerified:$false) -eq 'RELINQUISH_VERIFIED_PENDING') 'durable pending transfers cleanup ownership'
    Check ((Get-WpfCleanupDisposition -Status 'OBSERVER_HANDOFF' -CompletionVerified:$false) -eq 'RELINQUISH_LIFECYCLE_OWNER') 'observer handoff transfers exact candidate cleanup ownership without a pending claim'
    Check ((Get-WpfCleanupDisposition -Status 'OBSERVER_FAILURE' -CompletionVerified:$false) -eq 'RELINQUISH_LIFECYCLE_OWNER') 'observer failure does not kill the in-flight candidate'
    Check ((Get-WpfCleanupDisposition -Status 'PASS' -CompletionVerified:$true) -eq 'CLEANUP_EXACT_CANDIDATE') 'completed candidate returns exact cleanup ownership to the driver'

    $summary = [pscustomobject]@{status=if($failures.Count){'FAIL'}else{'PASS'};passed=$passed;total=($passed+$failures.Count);failures=@($failures)}
    $summary | ConvertTo-Json -Depth 6
    if ($failures.Count) { exit 1 }
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: automation/release-e2e/tests/Test-WpfProviderPowerShell51Compatibility.ps1

SHA256: d926276c5c06f209eaec7a4241a5252907c39daedd220f89cf4366466cd55237 | Bytes: 5664 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

$modulePath = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\WpfLaunchContract.psm1'
$passed = 0
$failures = New-Object 'System.Collections.Generic.List[string]'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-wpf-ps51-provider-' + [guid]::NewGuid().ToString('N'))

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

function New-TestSpecification([string]$LaunchId) {
    [pscustomobject]@{
        runId = 'wpf-ps51-provider-regression'
        launchId = $LaunchId
        transactionId = ('2' * 32)
        payloadSha256 = ('3' * 64)
        candidateSha256 = ('4' * 64)
        driverDeadlineUtc = [datetime]::UtcNow.AddMinutes(5).ToString('o')
        semanticNoProgressSeconds = 120
    }
}

function New-CapturedTerminal([object]$Specification, [string]$Capture) {
    [pscustomobject]@{
        schemaVersion = 2
        contract = 'devfleet-wpf-terminal-v2'
        status = 'PASS'
        terminal = $true
        completionVerified = $true
        runId = [string]$Specification.runId
        launchId = [string]$Specification.launchId
        transactionId = [string]$Specification.transactionId
        payloadSha256 = [string]$Specification.payloadSha256
        candidateSha256 = [string]$Specification.candidateSha256
        sequence = 8
        cleanupDisposition = 'CLEANUP_EXACT_CANDIDATE'
        deadlineUtc = [string]$Specification.driverDeadlineUtc
        capture = $Capture
    }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $modulePath -Force

    Check ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) 'regression executes under actual Windows PowerShell 5.1 semantics'

    $capturedValue = 'captured-through-provider-closure'
    $script:successStopped = $false
    $script:successTerminalWrites = 0
    $successSpec = New-TestSpecification -LaunchId ('5' * 32)
    $success = Wait-WpfBoundReport -Specification $successSpec `
        -ReportProvider { New-CapturedTerminal -Specification $successSpec -Capture $capturedValue } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:successStopped = $true } `
        -ProviderCallTimeoutSeconds 2 `
        -TerminalWriter { param($value) $script:successTerminalWrites++; $value }
    Check ([string]$success.status -eq 'PASS' -and [string]$success.capture -ceq $capturedValue -and -not $script:successStopped -and $script:successTerminalWrites -eq 0) 'PowerShell 5.1 provider execution preserves captured variables and caller helper functions'

    $script:throwingStopped = $false
    $script:throwingTerminalWrites = 0
    $throwingSpec = New-TestSpecification -LaunchId ('6' * 32)
    $throwing = Wait-WpfBoundReport -Specification $throwingSpec `
        -ReportProvider { throw 'controlled PS51 original provider error' } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:throwingStopped = $true } `
        -ProviderCallTimeoutSeconds 2 `
        -TerminalWriter { param($value) $script:throwingTerminalWrites++; $value }
    Check ([string]$throwing.failureClass -eq 'REPORT_PROVIDER_FAILURE' -and [string]$throwing.error -match 'controlled PS51 original provider error' -and $throwing.productStarted -eq $true -and $script:throwingStopped -and $script:throwingTerminalWrites -eq 1) 'PowerShell 5.1 provider failure preserves the original error and terminalizes once'

    $cancelledPath = Join-Path $scratch 'never-provider-cancelled.txt'
    $script:neverStopped = $false
    $script:neverTerminalWrites = 0
    $neverSpec = New-TestSpecification -LaunchId ('7' * 32)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $never = Wait-WpfBoundReport -Specification $neverSpec `
        -ReportProvider { try { while ($true) { Start-Sleep -Milliseconds 100 } } finally { [IO.File]::WriteAllText($cancelledPath, 'cancelled') } } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:neverStopped = $true } `
        -ProviderCallTimeoutSeconds 1 `
        -TerminalWriter { param($value) $script:neverTerminalWrites++; $value }
    $timer.Stop()
    $cancelDeadline = [datetime]::UtcNow.AddSeconds(2)
    while (-not (Test-Path -LiteralPath $cancelledPath -PathType Leaf) -and [datetime]::UtcNow -lt $cancelDeadline) { Start-Sleep -Milliseconds 50 }
    Check ([string]$never.failureClass -eq 'REPORT_PROVIDER_TIMEOUT' -and $never.productStarted -eq $true -and $script:neverStopped -and $script:neverTerminalWrites -eq 1 -and $timer.Elapsed.TotalMilliseconds -ge 800 -and $timer.Elapsed.TotalSeconds -lt 6) 'PowerShell 5.1 never-returning provider cannot defeat the bounded supervisor deadline'
    Check (Test-Path -LiteralPath $cancelledPath -PathType Leaf) 'PowerShell 5.1 never-returning provider is actively cancelled before terminalization completes'

    $summary = [pscustomobject]@{
        status = if ($failures.Count) { 'FAIL' } else { 'PASS' }
        engine = $PSVersionTable.PSVersion.ToString()
        startThreadJobAvailable = [bool](Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
        passed = $passed
        total = $passed + $failures.Count
        failures = @($failures)
    }
    $summary | ConvertTo-Json -Depth 6
    if ($failures.Count) { exit 1 }
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: automation/release-e2e/tests/fixtures/host-health-server.py

SHA256: 2bc918964dc465cc6faf8cf7aa54d129c69cdc012758948b5b367734f6f83745 | Bytes: 2020 | Git mode: 100644

```
import hashlib
import hmac
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

root = Path(sys.argv[1])
key = b'x' * 48

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        case = (root / 'case.txt').read_text().strip()
        timestamp = self.headers.get('X-DevFleet-Host-Timestamp', '')
        nonce = self.headers.get('X-DevFleet-Host-Nonce', '')
        host = self.headers.get('X-DevFleet-Host-Expected', '')
        material = f'GET\n{self.path}\n{timestamp}\n{nonce}\n\n{host}'.encode()
        valid = hmac.compare_digest(hmac.new(key, material, hashlib.sha256).hexdigest(), self.headers.get('X-DevFleet-Host-Signature', ''))
        if case == 'timeout':
            time.sleep(4)
        status = 200 if valid and case != 'unauthorized' else 401
        healthy = 'false' if case == 'string-health' else status == 200 and case != 'not-ok'
        body = json.dumps({'ok': healthy}, separators=(',', ':')).encode()
        response_host = 'OTHER-FIXTURE' if case == 'wrong-host' else host
        response_material = f'GET\n{self.path}\n{timestamp}\n{nonce}\n{status}\n'.encode() + body + b'\n' + response_host.encode()
        signature = hmac.new(key, response_material, hashlib.sha256).hexdigest()
        if case == 'bad-signature':
            signature = '0' * 64
        try:
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            if case != 'unauthorized':
                self.send_header('X-DevFleet-Host-Response-Signature', signature)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
(root / 'port.txt').write_text(str(server.server_port))
server.serve_forever()

```


## FILE: automation/release-e2e/tests/test_real_use_acceptance.py

SHA256: 9352ea907b44f0526339cf47ad5821e0be177c2b8681b2992958170338425ee6 | Bytes: 32592 | Git mode: 100644

```
"""Isolated driver-contract tests. These fixtures do not earn live acceptance."""
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import time
import urllib.parse
import uuid

import pytest


DRIVER = Path(__file__).parents[1] / "modules" / "executors" / "Invoke-RealUseAcceptance.py"
SPEC = importlib.util.spec_from_file_location("real_use_acceptance_driver", DRIVER)
driver = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = driver
SPEC.loader.exec_module(driver)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


@pytest.fixture
def request_data(tmp_path):
    paths = {key: str(tmp_path / key) for key in ("workspaces", "quarantine", "runtimeRoot")}
    for path in paths.values():
        Path(path).mkdir()
    (Path(paths["runtimeRoot"]) / "operations").mkdir()
    return {
        "schemaVersion": 1, "runId": "fullrelease-unit-real-use-20260916T000000Z",
        "deadlineUtc": (datetime.now(timezone.utc) + timedelta(hours=12)).isoformat(),
        "runnerSha256": driver.digest(DRIVER),
        "candidate": {
            "repositoryHead": "a" * 40, "candidateCommit": "b" * 40,
            "shippingInputIdentity": "c" * 64, "releaseFingerprintId": "d" * 64,
            "toolingFingerprintId": "e" * 64, "exeSha256": "f" * 64, "tarSha256": "1" * 64,
        },
        "execution": {
            "role": "Laptop / Surrogate", "vmName": "DevFleet-E2E-Unit", "vmId": str(uuid.uuid4()),
            "computeInstanceName": "DevFleetFailover", "vaultInstanceName": "DevFleetVault",
            "deploymentId": str(uuid.uuid4()), "nodeId": str(uuid.uuid4()), "nodeName": "unit-surrogate",
            "transactionId": str(uuid.uuid4()), "invocationId": str(uuid.uuid4()),
            "surrogateEvidenceSha256": "2" * 64,
        },
        "paths": paths, "baseUrl": "http://127.0.0.1:8787",
    }


class FakeDaemon:
    """Small product transport adapter; models receipts, not success-state bypass."""
    def __init__(self, request):
        self.request_data = request
        self.root = Path(request["paths"]["workspaces"])
        self.quarantine = Path(request["paths"]["quarantine"])
        self.runtime = Path(request["paths"]["runtimeRoot"])
        self.sequence = 0
        self.operations = {}
        self.container_data = {}
        self.requests = []
        self.snapshots = {}
        self.logged_in = False
        self.csrf = "csrf-sensitive-fixture-value"
        self.password = "password-sensitive-fixture-value"
        self.cookie = "session-sensitive-fixture-value"
        self.fault = ""

    def secrets(self):
        return [self.cookie]

    def form(self, action, fields=None):
        inputs = {"csrf_token": self.csrf, **(fields or {})}
        return '<form method="post" action="' + action + '">' + "".join(
            f'<input name="{key}" value="{value}">' for key, value in inputs.items()) + "</form>"

    def response(self, value, status=200, headers=None):
        return driver.Response(status, headers or {}, json.dumps(value) if isinstance(value, dict) else value)

    def metadata(self, slug):
        return json.loads((self.root / slug / ".devfleet/project.json").read_text())

    def save_metadata(self, slug, meta):
        write_json(self.root / slug / ".devfleet/project.json", meta)

    def request(self, method, route, fields, timeout):
        assert 0 < timeout <= 30
        self.requests.append((method, route, dict(fields or {})))
        parsed = urllib.parse.urlsplit(route)
        query = urllib.parse.parse_qs(parsed.query)
        if route == "/login" and method == "GET":
            return self.response(self.form("/login"))
        if route == "/login" and method == "POST":
            assert fields["csrf_token"] == self.csrf
            if fields.get("username") != "unit-admin" or fields.get("password") != self.password:
                return self.response("not logged in", 401)
            self.logged_in = True
            return self.response("", 303, {"location": "/"})
        if not self.logged_in:
            return self.response("", 303, {"location": "/login"})
        if method == "GET" and parsed.path.startswith("/ui/operations/"):
            value = copy.deepcopy(self.operations[parsed.path.rsplit("/", 1)[-1]])
            return self.response(value)
        if method == "GET" and parsed.path.startswith("/containers/"):
            identifier = parsed.path.split("/")[2]
            return self.response(copy.deepcopy(self.container_data[identifier]))
        if method == "GET":
            body = self.form("/logout")
            if "operation" in query:
                op_id = query["operation"][0]
                state = self.operations[op_id]["state"]
                css = "complete" if state == "completed" else "failed" if state == "failed" else ""
                if self.fault == "rendered-disagreement":
                    css = "failed" if css == "complete" else "complete"
                body += f'<section class="operation-banner {css}" data-operation-id="{op_id}"></section>'
            if query.get("view") == ["projects"]:
                body += self.form("/projects/create")
            if query.get("view") == ["settings"]:
                for path in self.quarantine.iterdir():
                    if path.is_dir():
                        body += self.form("/quarantine/restore", {"name": path.name})
            if parsed.path.startswith("/projects/"):
                slug = parsed.path.split("/")[2]
                if (self.root / slug).is_dir() and (self.root / slug / ".devfleet/project.json").exists():
                    meta = self.metadata(slug)
                    body += f'<section data-project-state="{meta["lifecycle_status"]}"></section>'
                    for action in ("start", "stop", "restart", "health", "test", "backup", "quarantine", "restore-vault"):
                        body += self.form(f"/projects/{slug}/{action}")
            return self.response(body)
        assert method == "POST" and fields["csrf_token"] == self.csrf
        if parsed.path.startswith("/projects/"):
            slug = parsed.path.split("/")[2]
            if "-recovered-" in slug and parsed.path.endswith("/start"):
                if self.fault == "copy-admitted":
                    return self.admit("start", slug, "completed", "")
                if self.fault == "copy-operation-created":
                    self.admit("start", slug, "failed", "")
                return self.response("recovery-only", 409)
        if parsed.path == "/projects/create":
            kind, slug = "create", fields["slug"]
        elif parsed.path == "/quarantine/restore":
            kind, slug = "restore-quarantine", fields["name"]
        else:
            slug, kind = parsed.path.split("/")[2:4]
        try:
            value = self.action(kind, slug, fields)
            return self.admit(kind, slug, "completed", value)
        except ValueError as exc:
            return self.admit(kind, slug, "failed", "", str(exc))

    def admit(self, kind, slug, state, result, error=""):
        self.sequence += 1
        op_id = f"op-{self.sequence:08d}"
        value = {"id": op_id, "kind": kind, "project": slug, "state": state,
                 "result": result, "error": error, "log": [{"message": "private arbitrary log " + self.password}]}
        self.operations[op_id] = value
        write_json(self.runtime / "operations" / (op_id + ".json"), value)
        return self.response("", 303, {"location": "/?operation=" + op_id})

    def action(self, kind, slug, fields):
        path = self.root / slug
        if kind == "create":
            assert fields["template"] == "generic"
            assert fields["runtime_isolation"] == "container" and fields["git_url"] == ""
            assert fields["profile"] == "balanced" and fields.get("use_ollama", "") == ""
            path.mkdir()
            (path / ".devfleet").mkdir()
            (path / ".devcontainer").mkdir()
            (path / "compose.yaml").write_text("services:\n  dev:\n    image: harmless\n")
            (path / ".devcontainer/devcontainer.json").write_text("{}")
            for name in ("smoke-test", "health-check"):
                (path / ".devfleet" / (name + ".sh")).write_text("#!/bin/sh\ntrue\n")
            meta = {"schema_version": 3, "managed_by": "devfleet", "slug": slug,
                    "project_id": str(uuid.uuid4()), "runtime_id": "df_" + slug.replace("-", "_"),
                    "runtime_provider": "docker-compose", "deployment_id": self.request_data["execution"]["deploymentId"],
                    "host_id": self.request_data["execution"]["nodeName"], "template": "generic",
                    "lifecycle_status": "ready", "health_status": "unknown"}
            self.save_metadata(slug, meta)
            write_json(path / ".devfleet/ownership-lease.json", {"active": False, "active_node": meta["host_id"]})
            return meta
        if kind == "restore-quarantine":
            quarantined = self.quarantine / slug
            meta = json.loads((quarantined / ".devfleet/project.json").read_text())
            target = self.root / meta["slug"]
            if target.exists():
                raise ValueError("Quarantine restore blocked: path already exists.")
            quarantined.rename(target)
            return str(target)
        meta = self.metadata(slug)
        if kind == "start":
            lease = json.loads((path / ".devfleet/ownership-lease.json").read_text())
            if lease.get("active") and lease.get("active_node") != meta["host_id"]:
                raise ValueError("Ownership lease belongs to a foreign node.")
            if "future_execution_field" in (path / "compose.yaml").read_text():
                raise ValueError("Security analyzer found blocking boundary violations.")
            meta["lifecycle_status"] = "running"
            self.save_metadata(slug, meta)
            identifier = hashlib.sha256((slug + str(self.sequence)).encode()).hexdigest()
            self.container_data[identifier] = {
                "Id": identifier, "State": {"Running": True, "Health": {"Status": "healthy"}},
                "Config": {"Labels": {
                    **{label: meta[key] for key, label in driver.LABELS.items()},
                    "com.docker.compose.project": meta["runtime_id"], "com.docker.compose.service": "dev",
                }},
            }
            return "started"
        if kind == "stop":
            self.container_data = {key: item for key, item in self.container_data.items()
                                   if item["Config"]["Labels"]["io.devfleet.project-id"] != meta["project_id"]}
            meta["lifecycle_status"] = "stopped"
            self.save_metadata(slug, meta)
            return "stopped"
        if kind in {"health", "test"}:
            if self.fault == "health-failure" and kind == "health":
                raise ValueError("health failure with " + self.password)
            if kind == "health":
                meta["health_status"] = "healthy"
                self.save_metadata(slug, meta)
            return "Template smoke test passed."
        if kind == "backup":
            backup_id = slug + "-20260916-000000-" + f"{self.sequence:08x}"
            backup_dir = self.runtime / "workspace-backups" / backup_id
            backup_dir.mkdir(parents=True)
            archive = backup_dir / (slug + ".tar.gz")
            archive.write_bytes(b"fake archive " + (path / driver.SENTINEL_FILE).read_bytes())
            archive_hash = driver.digest(archive)
            manifest = {"schema_version": 1, "backup_id": backup_id, "project_id": meta["project_id"], "slug": slug,
                        "verification": {"status": "verified", "integrity_verified": True},
                        "workspace": {"archive_sha256": archive_hash}}
            write_json(backup_dir / "manifest.json", manifest)
            meta.update(backup_id=backup_id, backup_path=str(archive), backup_sha256=archive_hash, backup_status="verified")
            self.save_metadata(slug, meta)
            snapshot = self.runtime / "fake-remote-snapshots" / backup_id
            shutil.copytree(path, snapshot)
            self.snapshots[slug] = snapshot
            if self.fault == "broker-failed-after-archive":
                raise ValueError("Vault broker unavailable")
            return json.dumps({"ok": True, "backup_id": backup_id, "backup_sha256": archive_hash,
                               "backup_status": "verified", "vault_upload_status": "verified",
                               "durability_level": "local" if self.fault == "local-only-backup" else "vault"})
        if kind == "quarantine":
            assert fields["confirm_quarantine"] == "true"
            self.action("stop", slug, {})
            self.action("backup", slug, {})
            destination = self.quarantine / ("20260916-000000-" + slug)
            path.rename(destination)
            return str(destination)
        if kind == "restore-vault":
            destination = self.root / (slug + "-recovered-20260916-000000-1234abcd")
            shutil.copytree(self.snapshots[slug], destination)
            if self.fault == "copy-content":
                (destination / driver.SENTINEL_FILE).write_text("changed")
            return str(destination)
        raise AssertionError(kind)


class FakeProbe:
    def __init__(self, daemon):
        self.daemon = daemon
        self.generation = "a"
        self.boot = str(uuid.uuid4())

    def service(self):
        return {"invocationId": self.generation * 32, "pid": 123 if self.generation == "a" else 124,
                "active": True, "user": "devfleet-control", "bootId": self.boot}

    def preflight(self, request):
        return {"service": self.service(), "brokerAccessible": True, "vaultTransport": "tailscale-rest"}

    def containers(self, project_id):
        return [copy.deepcopy(item) for item in self.daemon.container_data.values()
                if item["Config"]["Labels"]["io.devfleet.project-id"] == project_id]


def make_runner(request, tmp_path):
    daemon = FakeDaemon(request)
    probe = FakeProbe(daemon)
    ui = driver.Dashboard(daemon, driver.instant(request["deadlineUtc"]))
    runner = driver.AcceptanceRunner(request, tmp_path / "state.json", ui, probe)
    return runner, daemon, probe


def resume_runner(request, runner, daemon, probe):
    ui = driver.Dashboard(daemon, driver.instant(request["deadlineUtc"]))
    return driver.AcceptanceRunner(request, runner.state_path, ui, probe, state=driver.read_json(runner.state_path))


def test_two_stage_real_route_contract(request_data, tmp_path):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    prepared = runner.execute("prepare", ("unit-admin", daemon.password))
    assert prepared["status"] == "PREPARED", prepared
    assert [row["status"] for row in prepared["journeys"]] == ["PASS", "PASS", "IN_PROGRESS", "NOT_RUN", "NOT_RUN"]
    assert prepared["cleanup"]["status"] == "NOT_RUN"
    probe.generation = "b"
    resumed = resume_runner(request_data, runner, daemon, probe)
    report = resumed.execute("resume", ("unit-admin", daemon.password))
    assert report["status"] == "PASS", report
    assert [row["id"] for row in report["journeys"]] == ["U01", "U02", "U03", "U04", "U05"]
    assert all(row["assertions"] == {key: True for key in driver.ASSERTIONS[row["id"]]} for row in report["journeys"])
    copy_start = report["journeys"][4]["observations"]["copyStart"]
    assert copy_start["httpStatus"] == 409 and copy_start["operationCreated"] is False
    assert copy_start["beforeInventorySha256"] == copy_start["afterInventorySha256"]
    assert report["journeys"][4]["observations"]["copyAdopted"] is False
    assert report["cleanup"]["status"] == "PASS"
    assert not list(Path(request_data["paths"]["workspaces"]).iterdir())
    assert not list(Path(request_data["paths"]["quarantine"]).iterdir())
    assert daemon.container_data == {}
    serialized = json.dumps(report)
    for secret in (daemon.password, daemon.csrf, daemon.cookie, "unit-admin"):
        assert secret not in serialized
    assert "private arbitrary log" not in serialized
    assert report["execution"]["browserJavascriptExercised"] is False
    assert not any("/api/" in route for _, route, _ in daemon.requests)


@pytest.mark.parametrize("fault,code", [
    ("health-failure", "OPERATION_UNEXPECTED_TERMINAL"),
    ("rendered-disagreement", "RENDERED_OPERATION_DISAGREES"),
])
def test_prepare_failures_cleanup_without_laundering_primary(request_data, tmp_path, fault, code):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    daemon.fault = fault
    report = runner.execute("prepare", ("unit-admin", daemon.password))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == code
    assert daemon.password not in json.dumps(report)
    assert any(row["state"] in {"failed", "completed"} for row in report["operations"])
    assert not any(row["status"] == "PASS" for row in report["journeys"] if row["id"] in {"U02", "U03", "U04", "U05"})


@pytest.mark.parametrize("fault,code", [
    ("local-only-backup", "VAULT_UPLOAD_NOT_VERIFIED"),
    ("copy-content", "FIXTURE_SENTINEL_MISMATCH"),
    ("copy-admitted", "RECOVERED_COPY_START_NOT_REJECTED"),
    ("copy-operation-created", "RECOVERED_COPY_OPERATION_WAS_CREATED"),
])
def test_resume_rejects_false_recovery_proofs(request_data, tmp_path, fault, code):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    assert runner.execute("prepare", ("unit-admin", daemon.password))["status"] == "PREPARED"
    probe.generation = "b"
    daemon.fault = fault
    report = resume_runner(request_data, runner, daemon, probe).execute("resume", ("unit-admin", daemon.password))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == code, report
    assert report["journeys"][4]["status"] != "PASS"
    assert daemon.password not in json.dumps(report)
    if fault == "copy-content":
        assert report["cleanup"]["status"] == "BLOCKED"
        assert report["cleanupFailure"]["code"] == "CLEANUP_UNVERIFIED_RECOVERY_REQUIRES_PARENT"


def test_failed_broker_archive_is_discovered_and_cleaned(request_data, tmp_path):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    probe.generation = "b"
    daemon.fault = "broker-failed-after-archive"
    report = resume_runner(request_data, runner, daemon, probe).execute("resume", ("unit-admin", daemon.password))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == "OPERATION_UNEXPECTED_TERMINAL"
    assert report["cleanup"]["status"] == "PASS", report
    assert not list((Path(request_data["paths"]["runtimeRoot"]) / "workspace-backups").iterdir())
    assert any(row["kind"] == "backup" and row["status"] == "REMOVED" for row in report["cleanup"]["resources"])


@pytest.mark.parametrize("restart,reboot,code", [
    (False, False, "SERVICE_RESTART_NOT_OBSERVED"),
    (True, True, "UNEXPECTED_GUEST_REBOOT"),
])
def test_resume_requires_service_only_restart(request_data, tmp_path, restart, reboot, code):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    if restart:
        probe.generation = "b"
    if reboot:
        probe.boot = str(uuid.uuid4())
    report = resume_runner(request_data, runner, daemon, probe).execute("resume", ("unit-admin", daemon.password))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == code


def test_cleanup_failure_does_not_replace_primary(request_data, tmp_path, monkeypatch):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    daemon.fault = "health-failure"
    def bad_cleanup():
        raise RuntimeError("cleanup leaked " + daemon.password)
    monkeypatch.setattr(runner, "cleanup", bad_cleanup)
    report = runner.execute("prepare", ("unit-admin", daemon.password))
    assert report["failure"]["code"] == "OPERATION_UNEXPECTED_TERMINAL"
    assert report["cleanupFailure"]["code"] == "UNEXPECTED_DRIVER_FAILURE"
    assert report["cleanup"]["status"] == "BLOCKED"
    assert daemon.password not in json.dumps(report)
    assert "cleanup leaked" not in json.dumps(report)


def test_owner_mismatch_refuses_cleanup(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    path = Path(runner.fixture["originalPath"])
    write_json(path / driver.OWNER_FILE, {"runId": "someone-else"})
    with pytest.raises(driver.AcceptanceError, match="FIXTURE_OWNER_MISMATCH"):
        runner.cleanup()
    assert path.is_dir()


@pytest.mark.parametrize("mutation,code", [
    ("path", "RESTORE_COPY_PATH_INVALID"),
    ("name", "RESTORE_COPY_NAME_INVALID"),
    ("identity", "PROJECT_IDENTITY_CHANGED"),
    ("content", "FIXTURE_SENTINEL_MISMATCH"),
    ("owner", "FIXTURE_OWNER_MISMATCH"),
])
def test_copy_path_identity_checksum_are_independent(request_data, tmp_path, mutation, code):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    original = Path(runner.fixture["originalPath"])
    target = original.with_name(original.name + "-recovered-20260916-000000-1234abcd")
    shutil.copytree(original, target)
    supplied = str(target)
    if mutation == "path":
        supplied = str(target.parent / ".." / target.name)
    elif mutation == "name":
        different = target.with_name("another-project")
        target.rename(different)
        supplied = str(different)
    elif mutation == "identity":
        value = json.loads((target / ".devfleet/project.json").read_text())
        value["project_id"] = str(uuid.uuid4())
        write_json(target / ".devfleet/project.json", value)
    elif mutation == "content":
        (target / driver.SENTINEL_FILE).write_text("not the snapshot")
    else:
        write_json(target / driver.OWNER_FILE, {"runId": "foreign"})
    with pytest.raises(driver.AcceptanceError, match=code):
        runner.store.verify_copy(supplied, runner.fixture, request_data["execution"])
    assert original.is_dir()


def test_fixture_edit_restores_exact_bytes_when_body_fails(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    path = Path(runner.fixture["originalPath"]) / "compose.yaml"
    original = path.read_bytes()
    with pytest.raises(ValueError):
        with runner.fixture_edit("compose.yaml", b"temporary fixture"):
            raise ValueError("failure")
    assert path.read_bytes() == original
    assert runner.state["temporaryEdits"] == []


def test_request_rejects_external_origin_and_changed_hash(request_data):
    assert driver.normalized_request(request_data, driver.digest(DRIVER))["runId"] == request_data["runId"]
    changed = copy.deepcopy(request_data)
    changed["baseUrl"] = "http://100.1.2.3:8787"
    with pytest.raises(driver.AcceptanceError, match="DASHBOARD_ORIGIN_INVALID"):
        driver.normalized_request(changed, driver.digest(DRIVER))
    with pytest.raises(driver.AcceptanceError, match="RUNNER_HASH_MISMATCH"):
        driver.normalized_request(request_data, "0" * 64)


def test_request_and_fixture_binding_cannot_be_changed_on_resume(request_data, tmp_path):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    changed = copy.deepcopy(request_data)
    changed["candidate"]["tarSha256"] = "0" * 64
    with pytest.raises(driver.AcceptanceError, match="RESUME_BINDING_MISMATCH"):
        resume_runner(changed, runner, daemon, probe)
    state = driver.read_json(runner.state_path)
    state["fixture"]["slug"] = "real-user-project"
    with pytest.raises(driver.AcceptanceError, match="RESUME_FIXTURE_SCOPE_MISMATCH"):
        driver.AcceptanceRunner(request_data, runner.state_path, runner.ui, probe, state=state)


def test_resume_cannot_extend_owner_deadline(request_data, tmp_path):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    changed = copy.deepcopy(request_data)
    changed["deadlineUtc"] = (datetime.now(timezone.utc) + timedelta(hours=13)).isoformat()
    with pytest.raises(driver.AcceptanceError, match="RESUME_CANNOT_EXTEND_DEADLINE"):
        resume_runner(changed, runner, daemon, probe)


def test_forged_pass_without_five_assertion_sets_is_not_pass(request_data, tmp_path):
    runner, _, _ = make_runner(request_data, tmp_path)
    runner.state["prepared"] = runner.state["resumed"] = True
    runner.state["cleanup"]["status"] = "PASS"
    for row in runner.state["journeys"]:
        row["status"] = "PASS"
    assert runner.report("resume")["status"] == "BLOCKED"


def test_failed_login_never_creates_fixture_or_prints_credentials(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    report = runner.execute("prepare", ("unit-admin", "wrong-password-sensitive"))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == "DASHBOARD_LOGIN_FAILED"
    assert not list(Path(request_data["paths"]["workspaces"]).iterdir())
    assert "wrong-password-sensitive" not in json.dumps(report)


def test_missing_csrf_form_is_not_submitted():
    page = driver.Page('<form method="post" action="/projects/create"><input name="slug" value="demo"></form>')
    with pytest.raises(driver.AcceptanceError, match="DA