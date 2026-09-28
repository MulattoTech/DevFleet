# DevFleet source part 036

Full-source UTF-8 byte interval [1627500, 1674000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 278f84a6cf840a5387a6521051c0eb181c025df15b7e0fe1a8629eb4f9da2fb5

<!-- BEGIN SOURCE SLICE -->
ption.Message}
            return [pscustomobject]@{ok=$false;timedOut=$false;value=$null;error=$providerError}
        }
    } finally {
        if(-not$quarantined){
            if($pipeline){$pipeline.Dispose()}
            if($runspace){$runspace.Close();$runspace.Dispose()}
        }
    }
}

function Wait-WpfBoundReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Specification,
        [Parameter(Mandatory)][scriptblock]$ReportProvider,
        [Parameter(Mandatory)][scriptblock]$WorkerStateProvider,
        [Parameter(Mandatory)][scriptblock]$StopWorker,
        [scriptblock]$ProgressProvider = { $null },
        [scriptblock]$ClockProvider = { (Get-Date).ToUniversalTime() },
        [scriptblock]$SleepProvider = { param($Seconds) Start-Sleep -Seconds $Seconds },
        [ValidateRange(1,60)][int]$ProviderCallTimeoutSeconds = 30,
        [Parameter(Mandatory)][scriptblock]$TerminalWriter
    )
    $deadline = ConvertTo-WpfUtcInstant (Get-WpfContractValue $Specification 'driverDeadlineUtc')
    $semanticNoProgressSeconds = [int](Get-WpfContractValue $Specification 'semanticNoProgressSeconds')
    if ($semanticNoProgressSeconds -le 0) { throw 'WPF semantic no-progress deadline is missing or invalid.' }
    $lastRejected = ''
    $lastSequence = 0
    $lastDurableStep = 'LAUNCH_REQUESTED'
    $lastSemanticSequence = 0
    $semanticDeadline = $null
    while ($true) {
        $now = ConvertTo-WpfUtcInstant (& $ClockProvider)
        if (-not $semanticDeadline) { $semanticDeadline = $now.AddSeconds($semanticNoProgressSeconds) }
        $reportCall=Invoke-WpfBoundProviderCall -Provider $ReportProvider -Kind 'REPORT_PROVIDER' -TimeoutSeconds $ProviderCallTimeoutSeconds
        if(-not $reportCall.ok){
            try{&$StopWorker}catch{}
            $failureNow=ConvertTo-WpfUtcInstant (&$ClockProvider)
            $failureClass=if($reportCall.timedOut){'REPORT_PROVIDER_TIMEOUT'}else{'REPORT_PROVIDER_FAILURE'}
            $failure=New-WpfSupervisorFailure -Specification $Specification -FailureClass $failureClass -Error ([string]$reportCall.error) -Now $failureNow -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            &$TerminalWriter $failure|Out-Null
            return $failure
        }
        $reportObservation = Resolve-WpfProviderObservation -ProviderValue $reportCall.value -Kind TERMINAL -Now $now
        $report = $reportObservation.value
        if ($null -ne $report) {
            $reason = ''
            $validReport = Test-WpfTerminalReport -Report $report -Specification $Specification -Reason ([ref]$reason) -MinimumSequenceExclusive $lastSequence
            if ($validReport -and $reportObservation.metadataValid -and $reportObservation.establishedAtUtc -lt $deadline) { return $report }
            if ($validReport -and $reportObservation.establishedAtUtc -ge $deadline) { $reason = 'matching terminal report was first established at or after the immutable deadline' }
            if (-not $reportObservation.metadataValid) { $reason = $reportObservation.reason }
            $lastRejected = $reason
            $sameLaunch = [string](Get-WpfContractValue $report 'runId') -ceq [string](Get-WpfContractValue $Specification 'runId') -and [string](Get-WpfContractValue $report 'launchId') -ceq [string](Get-WpfContractValue $Specification 'launchId')
            if ($sameLaunch -and $now -lt $deadline) {
                $reportSequence = 0;if([int]::TryParse([string](Get-WpfContractValue $report 'sequence'),[ref]$reportSequence) -and $reportSequence -gt $lastSequence){$lastSequence=$reportSequence}
                $failure = New-WpfSupervisorFailure -Specification $Specification -FailureClass 'MALFORMED_BOUND_REPORT' -Error "Matching launch emitted an invalid terminal report: $reason" -Now $now -LastSequence $lastSequence -LastDurableStep $lastDurableStep
                & $TerminalWriter $failure | Out-Null
                return $failure
            }
        }
        if (-not $reportObservation.metadataValid) { $lastRejected = $reportObservation.reason }
        if ($now -ge $deadline) {
            & $StopWorker
            $failure = New-WpfSupervisorFailure -Specification $Specification -FailureClass 'UIA_DEADLINE_EXHAUSTED' -Error "UIA worker exceeded the finite inherited deadline. lastRejected=$lastRejected" -Now $now -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            & $TerminalWriter $failure | Out-Null
            return $failure
        }
        $progressCall=Invoke-WpfBoundProviderCall -Provider $ProgressProvider -Kind 'PROGRESS_PROVIDER' -TimeoutSeconds $ProviderCallTimeoutSeconds
        if(-not $progressCall.ok){
            try{&$StopWorker}catch{}
            $failureNow=ConvertTo-WpfUtcInstant (&$ClockProvider)
            $failureClass=if($progressCall.timedOut){'PROGRESS_PROVIDER_TIMEOUT'}else{'PROGRESS_PROVIDER_FAILURE'}
            $failure=New-WpfSupervisorFailure -Specification $Specification -FailureClass $failureClass -Error ([string]$progressCall.error) -Now $failureNow -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            &$TerminalWriter $failure|Out-Null
            return $failure
        }
        $progressObservation = Resolve-WpfProviderObservation -ProviderValue $progressCall.value -Kind PROGRESS -Now $now
        if ($progressObservation.metadataValid -and $null -ne $progressObservation.value -and $progressObservation.establishedAtUtc -lt $deadline) {
            $progressSequence=0;$semanticSequence=0;$progressReason=''
            if(Test-WpfBoundProgress -Progress $progressObservation.value -Specification $Specification -MinimumSequenceExclusive $lastSequence -MinimumSemanticSequenceExclusive $lastSemanticSequence -Sequence ([ref]$progressSequence) -SemanticSequence ([ref]$semanticSequence) -Reason ([ref]$progressReason)){
                $lastSequence=$progressSequence;$lastSemanticSequence=$semanticSequence;$lastDurableStep=[string](Get-WpfContractValue $progressObservation.value 'phase');$semanticDeadline=$now.AddSeconds($semanticNoProgressSeconds)
            }elseif($progressReason){$lastRejected=$progressReason}
        }elseif(-not $progressObservation.metadataValid){$lastRejected=$progressObservation.reason}
        $workerStateCall=Invoke-WpfBoundProviderCall -Provider $WorkerStateProvider -Kind 'WORKER_STATE_PROVIDER' -TimeoutSeconds $ProviderCallTimeoutSeconds
        if(-not $workerStateCall.ok){
            try{&$StopWorker}catch{}
            $failureNow=ConvertTo-WpfUtcInstant (&$ClockProvider)
            $failureClass=if($workerStateCall.timedOut){'WORKER_STATE_PROVIDER_TIMEOUT'}else{'WORKER_STATE_PROVIDER_FAILURE'}
            $failure=New-WpfSupervisorFailure -Specification $Specification -FailureClass $failureClass -Error ([string]$workerStateCall.error) -Now $failureNow -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            &$TerminalWriter $failure|Out-Null
            return $failure
        }
        $workerState = [string]$workerStateCall.value
        if ($workerState -in @('Exited','Failed','Stopped','Completed')) {
            # The worker can atomically publish its terminal record and exit after the
            # report poll above but before this state poll. Re-read the terminal once
            # at the exit boundary so a valid, in-deadline handoff is not misclassified
            # as EARLY_WORKER_EXIT.
            $exitReportCall=Invoke-WpfBoundProviderCall -Provider $ReportProvider -Kind 'REPORT_PROVIDER' -TimeoutSeconds $ProviderCallTimeoutSeconds
            if($exitReportCall.ok){
                $exitNow=ConvertTo-WpfUtcInstant (&$ClockProvider)
                $exitObservation=Resolve-WpfProviderObservation -ProviderValue $exitReportCall.value -Kind TERMINAL -Now $exitNow
                $exitReport=$exitObservation.value
                if($null -ne $exitReport){
                    $exitReason=''
                    $validExitReport=Test-WpfTerminalReport -Report $exitReport -Specification $Specification -Reason ([ref]$exitReason) -MinimumSequenceExclusive $lastSequence
                    if($validExitReport -and $exitObservation.metadataValid -and $exitObservation.establishedAtUtc -lt $deadline){return $exitReport}
                    if($validExitReport -and $exitObservation.establishedAtUtc -ge $deadline){$exitReason='matching terminal report was first established at or after the immutable deadline'}
                    if(-not $exitObservation.metadataValid){$exitReason=$exitObservation.reason}
                    if($exitReason){$lastRejected=$exitReason}
                }elseif(-not $exitObservation.metadataValid){$lastRejected=$exitObservation.reason}
            }else{
                $lastRejected="final terminal recheck failed: $([string]$exitReportCall.error)"
            }
            $failure = New-WpfSupervisorFailure -Specification $Specification -FailureClass 'EARLY_WORKER_EXIT' -Error "UIA worker exited before a valid terminal report. lastRejected=$lastRejected" -Now $now -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            & $TerminalWriter $failure | Out-Null
            return $failure
        }
        if ($now -ge $semanticDeadline) {
            & $StopWorker
            $failure = New-WpfSupervisorFailure -Specification $Specification -FailureClass 'UIA_SEMANTIC_NO_PROGRESS' -Error "UIA worker produced no durable semantic product progress within $semanticNoProgressSeconds seconds. lastRejected=$lastRejected" -Now $now -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            & $TerminalWriter $failure | Out-Null
            return $failure
        }
        & $SleepProvider 1
    }
}

Export-ModuleMember -Function New-WpfLaunchSpecification,Copy-WpfLaunchSpecification,Assert-WpfDriverBinding,Test-WpfRegisteredTaskBinding,Test-WpfTerminalReport,Test-WpfBoundProgress,Wait-WpfBoundReport,Get-WpfCleanupDisposition,Get-WpfCandidateArguments,Get-WpfNavigationDisposition,Write-WpfAtomicJson,Get-WpfFileSha256,ConvertTo-WpfUtcInstant,ConvertTo-WpfCommandLine

```


## FILE: automation/release-e2e/tests/DependencyPolicyRunner/ArgumentAwareProcessRunner.cs

SHA256: f961705e4e4a12eceda370814e59b4fcdd6fab3871215ce8fed14232d702a25d | Bytes: 4263 | Git mode: 100644

```
using DevFleet.Setup;

namespace DependencyPolicyRunner;

public enum ProcessProbe
{
    Unknown,
    AppxPackageTrust,
    Authenticode,
    WingetVersion,
    WingetSourceList,
    WingetSearch,
    WingetDownload,
    Version,
    Other
}

public sealed record RecordedProcessInvocation(
    string FileName,
    IReadOnlyList<string> Arguments,
    string? WorkingDirectory,
    ProcessProbe IntendedProbe,
    ProcessResult Result);

internal sealed record FixtureKey(string Executable, string Arguments, ProcessProbe IntendedProbe);

/// <summary>
/// Deterministic test-only process runner. Fixtures are selected by the
/// executable, normalized argument vector, and classified probe. A missing
/// fixture is an explicit failure; it can never consume another probe's result
/// or silently turn an unmodeled operation into success.
/// </summary>
public sealed class ArgumentAwareProcessRunner : IProcessRunner
{
    private readonly Dictionary<FixtureKey, Queue<ProcessResult>> _fixtures = new();

    public List<RecordedProcessInvocation> Invocations { get; } = [];

    public void QueueResult(string fileName, IReadOnlyList<string> arguments, ProcessResult result, ProcessProbe? intendedProbe = null)
    {
        var probe = intendedProbe ?? Classify(fileName, arguments);
        var key = MakeKey(fileName, arguments, probe);
        if (!_fixtures.TryGetValue(key, out var queue))
        {
            queue = new Queue<ProcessResult>();
            _fixtures.Add(key, queue);
        }
        queue.Enqueue(result);
    }

    public ProcessResult Run(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null)
    {
        var probe = Classify(fileName, arguments);
        var key = MakeKey(fileName, arguments, probe);
        ProcessResult result;
        if (_fixtures.TryGetValue(key, out var queue) && queue.Count > 0)
        {
            result = queue.Dequeue();
        }
        else
        {
            result = new ProcessResult(127, "", $"No deterministic fixture for {probe}: {fileName} {string.Join(' ', arguments)}");
        }

        Invocations.Add(new RecordedProcessInvocation(fileName, arguments.ToArray(), workingDirectory, probe, result));
        return result;
    }

    public static ProcessProbe Classify(string fileName, IReadOnlyList<string> arguments)
    {
        var normalized = arguments.Select(argument => argument.Trim()).ToArray();
        var all = string.Join(" ", normalized);
        if (all.Contains("Get-AppxPackage", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.AppxPackageTrust;
        if (all.Contains("Get-AuthenticodeSignature", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.Authenticode;

        var executable = Path.GetFileName(fileName);
        if (executable.Equals("winget.exe", StringComparison.OrdinalIgnoreCase))
        {
            if (normalized.SequenceEqual(["--version"], StringComparer.OrdinalIgnoreCase)) return ProcessProbe.WingetVersion;
            if (normalized.Length >= 2 && normalized[0].Equals("source", StringComparison.OrdinalIgnoreCase) && normalized[1].Equals("list", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.WingetSourceList;
            if (normalized.Length >= 1 && normalized[0].Equals("search", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.WingetSearch;
            if (normalized.Length >= 1 && normalized[0].Equals("download", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.WingetDownload;
        }
        if (normalized.SequenceEqual(["--version"], StringComparer.OrdinalIgnoreCase)) return ProcessProbe.Version;
        return ProcessProbe.Other;
    }

    private static FixtureKey MakeKey(string fileName, IReadOnlyList<string> arguments, ProcessProbe probe)
        => new(NormalizeExecutable(fileName), NormalizeArguments(arguments), probe);

    private static string NormalizeExecutable(string fileName)
    {
        try { return Path.GetFullPath(fileName).TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant(); }
        catch { return fileName.Trim().ToUpperInvariant(); }
    }

    private static string NormalizeArguments(IReadOnlyList<string> arguments)
        => string.Join("\u001f", arguments.Select(argument => argument.Trim()));
}

```


## FILE: automation/release-e2e/tests/DependencyPolicyRunner/DependencyPolicyRunner.csproj

SHA256: 66171a9c8d3bad0472e75ec38cfa7045fd42c8e234525e4c971162f7c83d4f36 | Bytes: 924 | Git mode: 100644

```
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <EnableWindowsTargeting>true</EnableWindowsTargeting>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <!-- The referenced installer is a self-contained WinExe. Keep this
         executable in the same RID graph so NETSDK1151 cannot silently
         discard the real project reference. -->
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../../../../installer-source/DevFleet.Setup/DevFleet.Setup.csproj"
                      GlobalPropertiesToRemove="SelfContained;RuntimeIdentifier;PublishSingleFile"
                      AdditionalProperties="SelfContained=false;RuntimeIdentifier=;PublishSingleFile=false" />
  </ItemGroup>
</Project>

```


## FILE: automation/release-e2e/tests/DependencyPolicyRunner/Program.cs

SHA256: a2a05ddc6b7f7546d10955366ae3aea016031f2139796d86388520be47e8f188 | Bytes: 17382 | Git mode: 100644

```
using System.Net;
using System.Net.Http;
using DevFleet.Setup;
using DependencyPolicyRunner;

if (args.Contains("--runner-self-test", StringComparer.OrdinalIgnoreCase))
{
    RunRunnerSelfTest();
    return;
}

static object Row(string scenario, string branch, bool reached, ArgumentAwareProcessRunner runner, string? selectedFallback = null, string? detail = null, bool physicalPathExists = false)
    => new {
        scenario,
        requestedScenario = scenario,
        actualResolverBranch = branch,
        queuedProcessOutputs = runner.Invocations.Select(i => new { i.FileName, arguments = i.Arguments, intendedProbe = i.IntendedProbe.ToString(), result = i.Result }).ToArray(),
        actualInvocations = runner.Invocations.Count,
        selectedFallback,
        detectedVersionOrPath = detail,
        physicalPathExists,
        authenticityProbeReached = runner.Invocations.Any(i => i.IntendedProbe == ProcessProbe.Authenticode),
        versionProbeReached = runner.Invocations.Any(i => i.IntendedProbe is ProcessProbe.Version or ProcessProbe.WingetVersion),
        trustedPathPolicyReached = runner.Invocations.Count > 0,
        expectedOutcome = "policy branch exercised and fails closed on mismatch",
        actualOutcome = reached ? "intended branch reached" : "intended branch not reached",
        actualConditionProven = reached,
        status = reached ? "PASS" : "FAIL",
        evidenceClass = "ADVERSARIAL_PRODUCT_POLICY"
    };

var rows = new List<object>();

// Missing WinGet is a real resolver call with a process-scoped empty PATH.
var originalPath = Environment.GetEnvironmentVariable("PATH");
try
{
    Environment.SetEnvironmentVariable("PATH", "");
    var missingRunner = new ArgumentAwareProcessRunner();
    var missing = new DependencyService(missingRunner).GetWingetHealth();
    rows.Add(Row("WinGet-Missing", missing.Status, missing.Status == "Missing", missingRunner, detail: missing.Detail));
}
finally { Environment.SetEnvironmentVariable("PATH", originalPath); }

// These cases use the real dependency resolver with argument-aware fixtures.
// The AppX and Authenticode probes are keyed separately from the WinGet
// operation, so they cannot consume --version/source/search results.
foreach (var (scenario, expected) in new[] {
    ("WinGet-Broken", "Broken"),
    ("WinGet-Source-Broken", "SourceBroken")
})
{
    var runner = new ArgumentAwareProcessRunner();
    var physicalWinget = LocatePhysicalWingetPackage();
    ConfigureWingetFixtures(runner, scenario);
    var health = new DependencyService(runner).GetWingetHealth();
    rows.Add(Row(scenario, health.Status, health.Status.Equals(expected, StringComparison.OrdinalIgnoreCase), runner, detail: health.Detail, physicalPathExists: File.Exists(physicalWinget.Executable)));
}

// Official direct fallback is exercised with the real HttpClient injection,
// using an allowlisted synthetic metadata response and no machine mutation.
var fallbackRunner = new ArgumentAwareProcessRunner();
var handler = new StubHandler();
using var http = new HttpClient(handler);
var dependency = new DependencyDefinition {
    Id = "fixture-direct",
    DisplayName = "Fixture Direct",
    DirectOfficialVendorResolver = new OfficialResolver {
        Type = "official-download-page",
        MetadataUri = "https://downloads.example.invalid/release.json",
        DirectUri = "https://downloads.example.invalid/fixture.exe",
        AllowedHosts = ["downloads.example.invalid"],
        AssetRegex = "^fixture\\.exe$"
    }
};
var fallbackRoot = Path.Combine(Path.GetTempPath(), "devfleet-policy-runner-" + Guid.NewGuid().ToString("N"));
var fallbackPath = new DependencyService(fallbackRunner, http).DownloadOfficial(dependency, fallbackRoot);
var fallbackReached = File.Exists(fallbackPath) && string.Equals(Path.GetFileName(fallbackPath), "fixture.exe", StringComparison.OrdinalIgnoreCase);
rows.Add(Row("Official-Direct-Fallback", "DirectOfficialFallback", fallbackReached, fallbackRunner, selectedFallback: fallbackPath, detail: handler.LastUri));
try { Directory.Delete(fallbackRoot, recursive: true); } catch { }

// Nonstandard-path detection selects only a physically existing executable
// from real machine roots.  The selection is deliberately not a temp fixture:
// Detect() remains the authority for the unmodified shipping trust policy.
var nonstandardRunner = new ArgumentAwareProcessRunner();
var trustedFixtureCandidates = new[] {
    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"),
    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "where.exe"),
    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
}.Where(File.Exists).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
var trustedFixturePath = trustedFixtureCandidates.FirstOrDefault();
if (trustedFixturePath is null) {
    rows.Add(Row("Valid-Nonstandard-Path", "TrustedDiscoveryCompatible", false, nonstandardRunner, detail: "No physically existing executable was available in a real trusted-root candidate set.", physicalPathExists: false));
    rows.Add(Row("Outdated-Prerequisites", "OutdatedVersion", false, nonstandardRunner, detail: "No physically existing executable was available in a real trusted-root candidate set.", physicalPathExists: false));
    goto Emit;
}
QueueAuthenticodeFixture(nonstandardRunner, trustedFixturePath, new ProcessResult(1, "", "unsigned fixture is accepted by the explicit test policy"));
nonstandardRunner.QueueResult(trustedFixturePath, ["--version"], new ProcessResult(0, "7.4.0", ""));
var nonstandard = new DependencyService(nonstandardRunner).Detect(new DependencyDefinition {
    Id = "fixture-path", DisplayName = "Fixture Path", KnownVendorInstallLocations = [trustedFixturePath],
    MinimumSupportedVersion = "1.0.0", VersionProbe = new VersionProbe { Regex = "(\\d+\\.\\d+)" },
    InstallerAuthenticityPolicy = new InstallerAuthenticityPolicy { InstalledExecutableTrust = "signed-installer-locked-path" }
});
var nonstandardReached = nonstandard.Found && nonstandard.Version is not null && nonstandard.Compatible
    && string.Equals(nonstandard.ExecutablePath, trustedFixturePath, StringComparison.OrdinalIgnoreCase)
    && nonstandardRunner.Invocations.Count >= 2;
rows.Add(Row("Valid-Nonstandard-Path", "TrustedDiscoveryCompatible", nonstandardReached, nonstandardRunner, detail: $"{nonstandard.ExecutablePath}|version={nonstandard.Version}", physicalPathExists: File.Exists(trustedFixturePath)));

// Outdated prerequisites is represented by a real incompatible detection.
var outdatedRunner = new ArgumentAwareProcessRunner();
QueueAuthenticodeFixture(outdatedRunner, trustedFixturePath, new ProcessResult(1, "", "unsigned fixture is accepted by the explicit test policy"));
outdatedRunner.QueueResult(trustedFixturePath, ["--version"], new ProcessResult(0, "1.0.0", ""));
var outdated = new DependencyService(outdatedRunner).Detect(new DependencyDefinition {
    Id = "fixture-outdated", DisplayName = "Fixture Outdated", KnownVendorInstallLocations = [trustedFixturePath],
    MinimumSupportedVersion = "99.0.0", VersionProbe = new VersionProbe { Regex = "(\\d+\\.\\d+)" },
    InstallerAuthenticityPolicy = new InstallerAuthenticityPolicy { InstalledExecutableTrust = "signed-installer-locked-path" }
});
var outdatedReached = outdated.Found && outdated.Version is not null && outdated.Version < new Version("99.0.0")
    && !outdated.Compatible && outdated.Classification.Length > 0 && outdatedRunner.Invocations.Count >= 2;
rows.Add(Row("Outdated-Prerequisites", "OutdatedVersion", outdatedReached, outdatedRunner, detail: $"{outdated.ExecutablePath}|version={outdated.Version}|minimum=99.0.0", physicalPathExists: File.Exists(trustedFixturePath)));
Emit:
Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(rows));
var requiredScenarios = new[] { "WinGet-Missing", "WinGet-Broken", "WinGet-Source-Broken", "Official-Direct-Fallback", "Valid-Nonstandard-Path", "Outdated-Prerequisites" };
var actualScenarios = rows.Select(row => (string)row.GetType().GetProperty("scenario")!.GetValue(row)! ).ToArray();
if (actualScenarios.Length != requiredScenarios.Length || actualScenarios.Distinct(StringComparer.Ordinal).Count() != requiredScenarios.Length ||
    !requiredScenarios.All(id => actualScenarios.Contains(id, StringComparer.Ordinal)))
    Environment.ExitCode = 2;
if (rows.Any(row => !(bool)row.GetType().GetProperty("actualConditionProven")!.GetValue(row)!))
    Environment.ExitCode = 1;

static void ConfigureWingetFixtures(ArgumentAwareProcessRunner runner, string scenario)
{
    var (packageRoot, winget) = LocatePhysicalWingetPackage();
    var powershell = GetPowerShellPath();
    var appxArguments = new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' | ForEach-Object { Join-Path $_.InstallLocation 'winget.exe' }" };
    runner.QueueResult(powershell, appxArguments,
        new ProcessResult(0, winget, ""), ProcessProbe.AppxPackageTrust);
    var packageIdentityArguments = new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' | ForEach-Object { $_.Name + '|' + $_.PublisherId + '|' + $_.InstallLocation }" };
    runner.QueueResult(powershell, packageIdentityArguments,
        new ProcessResult(0, $"Microsoft.DesktopAppInstaller|8wekyb3d8bbwe|{packageRoot}", ""), ProcessProbe.AppxPackageTrust);
    QueueAuthenticodeFixture(runner, winget,
        new ProcessResult(0, "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US", ""));

    if (scenario.Equals("WinGet-Broken", StringComparison.OrdinalIgnoreCase))
    {
        runner.QueueResult(winget, ["--version"], new ProcessResult(1, "", "fixture winget failure"), ProcessProbe.WingetVersion);
        return;
    }

    runner.QueueResult(winget, ["--version"], new ProcessResult(0, "v1.9.0", ""), ProcessProbe.WingetVersion);
    runner.QueueResult(winget, ["source", "list", "--disable-interactivity"], new ProcessResult(1, "", "fixture source failure"), ProcessProbe.WingetSourceList);
}

static (string PackageRoot, string Executable) SelectPhysicalWingetPackage(IEnumerable<string> directories, string windowsApps)
{
    var appsRoot = Path.GetFullPath(windowsApps).TrimEnd(Path.DirectorySeparatorChar);
    const string prefix = "Microsoft.DesktopAppInstaller_";
    const string suffix = "_x64__8wekyb3d8bbwe";
    var matches = directories
        .Select(path => Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar))
        .Where(path => string.Equals(Path.GetDirectoryName(path)?.TrimEnd(Path.DirectorySeparatorChar), appsRoot, StringComparison.OrdinalIgnoreCase))
        .Where(path => !new DirectoryInfo(path).Attributes.HasFlag(FileAttributes.ReparsePoint))
        .Select(path => {
            var basename = Path.GetFileName(path);
            var versionText = basename.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) && basename.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)
                ? basename[prefix.Length..^suffix.Length]
                : "";
            return (Root: path, Version: Version.TryParse(versionText, out var version) ? version : null as Version, Executable: Path.Combine(path, "winget.exe"));
        })
        .Where(item => item.Version is not null && File.Exists(item.Executable) && !File.GetAttributes(item.Executable).HasFlag(FileAttributes.ReparsePoint))
        .OrderByDescending(item => item.Version)
        .ThenBy(item => item.Root, StringComparer.OrdinalIgnoreCase)
        .ToArray();
    if (matches.Length == 0) throw new InvalidOperationException("No physical Microsoft.DesktopAppInstaller x64 package with winget.exe was found.");
    return (matches[0].Root, matches[0].Executable);
}

static (string PackageRoot, string Executable) LocatePhysicalWingetPackage()
{
    if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("The dependency matrix requires the Windows physical WinGet package.");
    var windowsApps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsApps");
    return SelectPhysicalWingetPackage(
        Directory.EnumerateDirectories(windowsApps, "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe", SearchOption.TopDirectoryOnly),
        windowsApps);
}

static void QueueAuthenticodeFixture(ArgumentAwareProcessRunner runner, string executable, ProcessResult result)
{
    var escaped = executable.Replace("'", "''", StringComparison.Ordinal);
    var command = "$s=Get-AuthenticodeSignature -LiteralPath '" + escaped + "'; if($s.Status -ne 'Valid'){exit 9}; $s.SignerCertificate.Subject";
    runner.QueueResult(GetPowerShellPath(),
        ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command], result, ProcessProbe.Authenticode);
}

static string GetPowerShellPath()
{
    var candidates = new[]
    {
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    };
    return candidates.FirstOrDefault(File.Exists) ?? "pwsh.exe";
}

static void RunRunnerSelfTest()
{
    var winget = @"C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe";
    var runner = new ArgumentAwareProcessRunner();
    runner.QueueResult(winget, [" --version "], new ProcessResult(1, "", "exact version failure"), ProcessProbe.WingetVersion);
    runner.QueueResult(winget, ["source", "list", "--disable-interactivity"], new ProcessResult(0, "source-ok", ""), ProcessProbe.WingetSourceList);

    // Deliberately call source before version: keyed dispatch must preserve
    // each fixture's intended operation instead of consuming FIFO output.
    var source = runner.Run(winget, ["source", "list", "--disable-interactivity"]);
    var version = runner.Run(winget, ["--version"]);
    var unknown = runner.Run(winget, ["search", "--id", "fixture"]);
    if (source.ExitCode != 0 || source.StandardOutput != "source-ok" || source != runner.Invocations[0].Result ||
        version.ExitCode != 1 || version.StandardError != "exact version failure" || version != runner.Invocations[1].Result ||
        unknown.ExitCode != 127 || runner.Invocations.Count != 3 ||
        runner.Invocations[0].IntendedProbe != ProcessProbe.WingetSourceList ||
        runner.Invocations[1].IntendedProbe != ProcessProbe.WingetVersion ||
        runner.Invocations[2].IntendedProbe != ProcessProbe.WingetSearch)
        throw new InvalidOperationException("Argument-aware process runner self-test failed.");

    var selectionRoot = Path.Combine(Path.GetTempPath(), "devfleet-winget-selection-" + Guid.NewGuid().ToString("N"));
    var selectionWindowsApps = Path.Combine(selectionRoot, "WindowsApps");
    var selectionPackages = new[] {
        Path.Combine(selectionWindowsApps, "Microsoft.DesktopAppInstaller_1.0.0.0_x64__8wekyb3d8bbwe"),
        Path.Combine(selectionWindowsApps, "Microsoft.DesktopAppInstaller_1.0.0.1_x64__8wekyb3d8bbwe")
    };
    Directory.CreateDirectory(selectionWindowsApps);
    try
    {
        foreach (var package in selectionPackages)
        {
            Directory.CreateDirectory(package);
            File.WriteAllText(Path.Combine(package, "winget.exe"), "fixture");
        }
        var selected = SelectPhysicalWingetPackage(selectionPackages, selectionWindowsApps);
        if (!selected.PackageRoot.EndsWith("1.0.0.1_x64__8wekyb3d8bbwe", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Physical WinGet package selection did not choose the highest valid package version.");
    }
    finally { try { Directory.Delete(selectionRoot, recursive: true); } catch { } }

    Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new
    {
        status = "PASS",
        contract = "executable+normalized-arguments+intended-probe",
        invocationOrder = runner.Invocations.Select(i => new { i.IntendedProbe, i.FileName, arguments = i.Arguments, result = i.Result }).ToArray(),
        missingFixture = new { unknown.ExitCode, unknown.StandardError }
    }));
}

sealed class StubHandler : HttpMessageHandler
{
    public string LastUri { get; private set; } = "";
    private HttpResponseMessage Build(HttpRequestMessage request)
    {
        LastUri = request.RequestUri?.ToString() ?? "";
        var content = request.RequestUri?.AbsolutePath.EndsWith("fixture.exe", StringComparison.OrdinalIgnoreCase) == true
            ? new ByteArrayContent([0x4d, 0x5a, 0x46, 0x49, 0x58, 0x54, 0x55, 0x52, 0x45])
            : new StringContent("{\"tag_name\":\"fixture\",\"assets\":[]}");
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = content };
    }
    protected override HttpResponseMessage Send(HttpRequestMessage request, CancellationToken cancellationToken) => Build(request);
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        => Task.FromResult(Build(request));
}

```


## FILE: automation/release-e2e/tests/Invoke-HarnessTests.ps1

SHA256: 59d3982927f6d3637514917b0db42b974c38cec9e64c17fc7ee3fff1bdc496e8 | Bytes: 61808 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
$moduleRoot=Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\modules')).Path ''
foreach($m in @('Candidate','HostSafety','ResumeState','Cleanup','Evidence','FullRelease','HarnessBudget')){Import-Module (Join-Path $moduleRoot "$m.psm1") -Force}
$total=0;$passed=0;$failures=[System.Collections.Generic.List[string]]::new()
function Assert-That([bool]$Condition,[string]$Name){$script:total++;if($Condition){$script:passed++}else{$script:failures.Add($Name)}}
function Assert-DisposableNameTest([string]$Name) { return $Name -like 'DevFleet-E2E-*' }
function Get-HarnessCandidateFingerprint([string]$Root) {
    try { return Get-CandidateFingerprint -WorkspaceRoot $Root }
    catch {
        if ($_.Exception.Message -ne 'Candidate evidence says the candidate is stale or requires rebuild.') { throw }
        $version=(Get-Content -LiteralPath (Join-Path $Root 'source\VERSION') -Raw).Trim()
        $outputs=Join-Path $Root 'outputs'
        $exe=@(Get-ChildItem -LiteralPath $outputs -Filter "DevFleet-Setup-v$version-win-x64.exe" -File)
        $portable=@(Get-ChildItem -LiteralPath $outputs -Filter "DevFleet-v$version-Portable*.zip" -File)
        if($exe.Count -ne 1 -or $portable.Count -ne 1){throw 'Harness fixture artifact discovery is ambiguous.'}
        $release=Get-Content -LiteralPath (Join-Path $outputs 'release-fingerprint.json') -Raw|ConvertFrom-Json
        return [pscustomobject]@{
            releaseVersion=$version
            installerVersion=(Get-Content -LiteralPath (Join-Path $Root 'installer-source\INSTALLER_VERSION') -Raw).Trim()
            gitCommit=(& git -C $Root rev-parse HEAD).Trim()
            releaseFingerprintId=[string]$release.releaseFingerprintId
            toolingFingerprintId=[string]$release.toolingFingerprint.toolingFingerprintId
            candidate=Get-FileHashRecord -Path $exe[0].FullName
            tar=Get-FileHashRecord -Path (Join-Path $outputs "devfleet-v$version.tar.gz")
            portable=Get-FileHashRecord -Path $portable[0].FullName
            installerSource=Get-FileHashRecord -Path (Join-Path $outputs "DevFleet-v$version-Installer-Source.zip")
        }
    }
}
$temp=Join-Path $env:TEMP "DevFleet-E2E-HarnessTests-$([guid]::NewGuid().ToString('N'))"; New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $candidate=Get-HarnessCandidateFingerprint -Root $WorkspaceRoot
    Assert-That ($candidate.releaseVersion -match '^\d+\.\d+\.\d+$') 'version parsing'
    Assert-That ($candidate.candidate.sha256.Length -eq 64 -and $candidate.tar.sha256.Length -eq 64) 'artifact hashing'
    Assert-That ((Test-CandidateFingerprint -Expected $candidate -Actual (Get-HarnessCandidateFingerprint -Root $WorkspaceRoot)) -eq $true) 'candidate fingerprint equality'

    $unsafeProjection=Get-ProjectedHostMemorySafety -AvailableMemoryGiB 25.16 -ExpectedVmStartCostGiB 14.38 -InstalledUsableMemoryGiB 64 -CommitLimitGiB 64 -CommittedGiB 50
    Assert-That (-not $unsafeProjection.startSafe) 'projected post-start memory rejects unsafe VM start'
    Assert-That ($unsafeProjection.projectedPostStartAvailableMemoryGiB -eq 10.78) 'projected post-start memory records expected remainder'
    $overrideBlocked=Apply-RamPressureOverride -Snapshot ([pscustomobject]@{startSafe=$false;resourceExhaustion=$false})
    Assert-That (-not $overrideBlocked.effectiveE2EStartAuthorized -and -not $overrideBlocked.ramPressureOverrideAuthorized) 'RAM override defaults disabled'
    $overrideAllowed=Apply-RamPressureOverride -Snapshot ([pscustomobject]@{startSafe=$false;resourceExhaustion=$false}) -AllowRamPressure
    Assert-That ($overrideAllowed.effectiveE2EStartAuthorized -and -not $overrideAllowed.rawHostSafetyStartSafe -and $overrideAllowed.ramPressureOverrideAuthorized) 'RAM override authorizes memory-only failure and preserves raw result'
    $overrideDenied=Apply-RamPressureOverride -Snapshot ([pscustomobject]@{startSafe=$false;resourceExhaustion=$true}) -AllowRamPressure
    Assert-That (-not $overrideDenied.effectiveE2EStartAuthorized) 'RAM override cannot bypass resource exhaustion'
    $safeProjection=Get-ProjectedHostMemorySafety -AvailableMemoryGiB 35 -ExpectedVmStartCostGiB 14.38 -InstalledUsableMemoryGiB 64 -CommitLimitGiB 64 -CommittedGiB 30
    Assert-That $safeProjection.startSafe 'projected post-start memory accepts safe VM start'
    $runningProjection=Get-ProjectedHostMemorySafety -AvailableMemoryGiB 21 -ExpectedVmStartCostGiB 14.38 -InstalledUsableMemoryGiB 64 -CommitLimitGiB 64 -CommittedGiB 30 -VmAlreadyRunning $true
    Assert-That ($runningProjection.startSafe -and $runningProjection.expectedVmStartCostGiB -eq 0) 'running VM uses observed post-start memory'

    $space=Join-Path $temp 'path with spaces'; New-Item -ItemType Directory -Path $space | Out-Null
    $statePath=Join-Path $space 'run-state.json'; $obj=[pscustomobject]@{schemaVersion=1;candidate=$candidate.candidate.sha256}
    Write-AtomicJson -Path $statePath -Value $obj; $read=Read-StrictJson -Path $statePath
    Assert-That ($read.candidate -eq $candidate.candidate.sha256) 'atomic state write/read with spaces'
    Set-Content -LiteralPath $statePath -Value '{bad json' -Encoding utf8
    $invalidCaught=$false;try{Read-StrictJson -Path $statePath}catch{$invalidCaught=$true}; Assert-That $invalidCaught 'corrupted state rejection'
    Write-AtomicJson -Path $statePath -Value $obj

    $lockReady=Join-Path $space 'run-state-lock-ready.txt'
    $locker=Start-Job -ArgumentList @($statePath,$lockReady) -ScriptBlock {
        param([string]$Target,[string]$Ready)
        $handle=[IO.File]::Open($Target,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            [IO.File]::WriteAllText($Ready,'ready',[Text.UTF8Encoding]::new($false))
            Start-Sleep -Milliseconds 500
        } finally { $handle.Dispose() }
    }
    $lockDeadline=(Get-Date).AddSeconds(10)
    while(-not(Test-Path -LiteralPath $lockReady) -and (Get-Date) -lt $lockDeadline){Start-Sleep -Milliseconds 25}
    $replacement=[pscustomobject]@{schemaVersion=1;candidate='replacement-after-transient-contention'}
    $replacementSucceeded=$false
    try {
        if(-not(Test-Path -LiteralPath $lockReady)){throw 'test locker did not acquire the run-state file'}
        Write-AtomicJson -Path $statePath -Value $replacement
        $replacementSucceeded=([string](Read-StrictJson -Path $statePath).candidate -ceq [string]$replacement.candidate)
    } catch {
        $replacementSucceeded=$false
    } finally {
        Wait-Job -Job $locker -Timeout 5 | Out-Null
        Remove-Job -Job $locker -Force -ErrorAction SilentlyContinue
    }
    Assert-That $replacementSucceeded 'atomic state replace tolerates brief Windows destination contention'
    Assert-That (@(Get-ChildItem -LiteralPath $space -Filter 'run-state.json.*.tmp' -File -ErrorAction SilentlyContinue).Count -eq 0) 'atomic state replace removes temporary files after contention'

    $runState=[pscustomobject]@{candidateHashes=[pscustomobject]@{exe=$candidate.candidate.sha256;tar=$candidate.tar.sha256};vmId='expected'}
    $mismatchCaught=$false;try{Assert-ResumeIdentity -State $runState -Fingerprint $candidate -Vm ([pscustomobject]@{Id=[guid]::NewGuid()})|Out-Null}catch{$mismatchCaught=$true}; Assert-That $mismatchCaught 'checkpoint/VM identity mismatch rejection'
    $hashMismatch=[pscustomobject]@{candidateHashes=[pscustomobject]@{exe=('0'*64);tar=$candidate.tar.sha256}}
    $candidateCaught=$false;try{Assert-ResumeIdentity -State $hashMismatch -Fingerprint $candidate}catch{$candidateCaught=$true}; Assert-That $candidateCaught 'candidate hash mismatch rejection'

    $fakeVm=[pscustomobject]@{Name='DevFleet-E2E-Test';Id=([guid]::NewGuid())}; $manifest=New-CleanupManifest -Vm $fakeVm -RunId 'synthetic'; Assert-That (Test-CleanupManifest $manifest) 'cleanup manifest exact ownership'; Assert-That (-not (Assert-DisposableNameTest -Name 'devfleet-primary')) 'production name denied'
    $summaryRoot=Join-Path $temp 'cleanup-summary';$summaryEvidence=Join-Path $summaryRoot 'evidence';$summaryRunDir=Join-Path $summaryRoot 'audit\automation-harness\runs\unit-cleanup';New-Item -ItemType Directory -Force -Path $summaryEvidence,$summaryRunDir|Out-Null
    $summaryCleanupPath=Join-Path $summaryRunDir 'cleanup-state.json';$summaryCleanup=[ordered]@{runId='unit-cleanup';status='PASS';runOwnedOnly=$true;cleanupOwner='run-exact-candidate-proof.ps1';l1=[ordered]@{status='OFF';name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';observedUtc='2026-09-06T09:23:01.1613702Z'};l2=[ordered]@{status='ABSENT';expectedName='DevFleet-E2E-Linux-01';present=$false;exactMatchCount=0;verification='Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend';backendInventories=@([ordered]@{provider='Hyper-V';status='PASS';names=@();verification='bounded Hyper-V inventory'},[ordered]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VirtualBox inventory'});observedUtc='2026-09-06T09:22:55.9889986Z'}}
    Write-EvidenceJson -Path $summaryCleanupPath -Value $summaryCleanup;$published=Publish-DevFleetTerminalCleanupSummary -WorkspaceRoot $summaryRoot -CleanupEvidencePath $summaryCleanupPath;$publishedL2=Get-Content -LiteralPath (Join-Path $summaryEvidence 'l2-terminal-state.json') -Raw|ConvertFrom-Json
    $publishedL2TimestampValue=$publishedL2.timestampUtc
    $publishedL2Timestamp=if($publishedL2TimestampValue -is [datetime]){([datetime]$publishedL2TimestampValue).ToUniversalTime()}elseif($publishedL2TimestampValue -is [datetimeoffset]){([datetimeoffset]$publishedL2TimestampValue).UtcDateTime}else{[datetime]::ParseExact([string]$publishedL2TimestampValue,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}
    $publishedL2TimestampUtc=$publishedL2Timestamp.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
    Assert-That ([string]$published.sourceRunId -ceq 'unit-cleanup' -and $publishedL2TimestampUtc -ceq '2026-09-06T09:22:55.9889986Z' -and -not [bool]$publishedL2.certifiedReleaseCleanup -and @($publishedL2.backendInventories).Count -eq 2) 'terminal cleanup summary preserves exact source provenance and complete backend evidence without claiming release CLEANUP'
    $cliOnlyPath=Join-Path (New-Item -ItemType Directory -Force -Path (Join-Path $summaryRoot 'audit\automation-harness\runs\unit-cli-only')) 'cleanup-state.json';$cliOnly=$summaryCleanup|ConvertTo-Json -Depth 10|ConvertFrom-Json;$cliOnly.runId='unit-cli-only';$cliOnly.l2.backendInventories=@();$cliOnly.l2.verification='Multipass executable absent inside exact L1';Write-EvidenceJson -Path $cliOnlyPath -Value $cliOnly;$cliOnlyRejected=$false;try{Publish-DevFleetTerminalCleanupSummary -WorkspaceRoot $summaryRoot -CleanupEvidencePath $cliOnlyPath|Out-Null}catch{$cliOnlyRejected=$true};Assert-That $cliOnlyRejected 'terminal cleanup summary rejects CLI absence without complete in-L1 backend inventory'
    function Test-TerminalCleanupSummaryRejects([string]$RunSuffix,[scriptblock]$Mutation){
        $runId="unit-$RunSuffix";$runDir=Join-Path $script:summaryRoot (Join-Path 'audit\automation-harness\runs' $runId);New-Item -ItemType Directory -Force -Path $runDir|Out-Null
        $record=$script:summaryCleanup|ConvertTo-Json -Depth 10|ConvertFrom-Json;$record.runId=$runId;&$Mutation $record
        $path=Join-Path $runDir 'cleanup-state.json';Write-EvidenceJson -Path $path -Value $record
        try{Publish-DevFleetTerminalCleanupSummary -WorkspaceRoot $script:summaryRoot -CleanupEvidencePath $path|Out-Null;$false}catch{$true}
    }
    Assert-That (Test-TerminalCleanupSummaryRejects 'missing-exact-count' {param($r)$r.l2.PSObject.Properties.Remove('exactMatchCount')}) 'terminal cleanup summary rejects a missing nested exact-match count'
    Assert-That (Test-TerminalCleanupSummaryRejects 'boolean-exact-count' {param($r)$r.l2.exactMatchCount=$false}) 'terminal cleanup summary rejects a Boolean masquerading as nested exact-match count'
    Assert-That (Test-TerminalCleanupSummaryRejects 'host-only-method' {param($r)$r.l2.verification='Get-VM -Name exact returned no VM'}) 'terminal cleanup summary rejects a host-only inventory method even with backend rows'
    Assert-That (Test-TerminalCleanupSummaryRejects 'present-target' {param($r)$r.l2.backendInventories[0].names=@('DevFleet-E2E-Linux-01')}) 'terminal cleanup summary rejects a supported backend inventory containing the target L2'
    $fixtureVm=[pscustomobject]@{Name='DevFleet-E2E-Test';Id=([guid]::NewGuid())}; $fixtureSnapshot=[pscustomobject]@{Name='DevFleet-E2E-MAINTENANCE-READY';Id=([guid]::NewGuid())}; $generation=([guid]::NewGuid()).ToString('D')
    $fixtureProvenance=[pscustomobject]@{schemaVersion=1;contract='maintenance-ready-provenance-v1';vmName=$fixtureVm.Name;vmI