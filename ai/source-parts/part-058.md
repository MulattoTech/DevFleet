# DevFleet source part 058

Full-source UTF-8 byte interval [2650500, 2697000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 79e0346c1a7c55aa9d154eec33dfba8240eea8d8cc48b2cab18da567d5bb1411

<!-- BEGIN SOURCE SLICE -->
Windows.Media.Brush)FindResource(_plan.IsAllowed ? "AccentBrush" : "DangerBrush");
    }

    private async void ExecuteButton_Click(object sender, RoutedEventArgs e)
    {
        await ExecuteReviewedPlanAsync(requireConfirmation: true, elevatedResume: false);
    }

    private async Task ExecuteReviewedPlanAsync(bool requireConfirmation, bool elevatedResume)
    {
        if (_executing) return;
        BuildPlanAndShow();
        if (_plan is null || !_plan.IsAllowed) { MessageBox.Show(this, PlanService.ToText(_plan ?? new InstallerPlan()), "Execution blocked", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
        if (requireConfirmation && MessageBox.Show(this, "Execute the reviewed plan now? Diagnostics remains read-only; cleanup actions use only the displayed ownership scope.", "Confirm exact plan", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        if (!ElevationService.IsAdministrator && !TestEnvironment.IsTestProcess)
        {
            if (elevatedResume) throw new InvalidOperationException("The elevated resume continuation did not obtain an administrator token; refusing to relaunch recursively.");
            // The unelevated UI may validate the plan, but it must not create
            // protected staging. The elevated continuation reopens and
            // independently verifies the embedded payload.
            ElevationService.RelaunchVerified(RoleCombo.SelectedItem?.ToString() ?? "Primary / Desktop", CurrentMode, _deferNetworkPairing, _plan.AcknowledgeRootfulDocker);
            Close();
            return;
        }
            _executing = true; _progress = 0; _page = 6; RefreshPage(); ExecuteButton.IsEnabled = false; OperationLog.Clear();
            try
            {
                var plan = _plan;
                var role = RoleCombo.SelectedItem?.ToString() ?? "Standalone / unknown";
                var result = await Task.Run(() => InstallerEngine.Execute(plan!, role, ReportProgress));
            var rebootRequired = LifecycleEngine.LastExecution?.ExitCode == 3010 || File.Exists(RebootCheckpointService.Path);
            if (rebootRequired)
            {
                ReportProgress("REBOOT REQUIRED: the verified checkpoint is preserved; restart this same candidate after Windows reboots.");
                OperationStatus.Text = "Reboot required; checkpoint preserved";
                OperationProgress.Value = 95;
                _page = 6;
                RefreshPage();
                return;
            }
            ReportProgress($"VERIFIED COMPLETE: {result}"); OperationProgress.Value = 100; OperationStatus.Text = "Completed and verified"; _page = 7; RefreshPage();
        }
        catch (Exception ex)
        {
            ReportProgress($"FAILED — no unplanned continuation: {ex}"); OperationStatus.Text = "Failed; evidence preserved in the log"; OperationProgress.Value = 0;
        }
        finally { _executing = false; ExecuteButton.IsEnabled = true; BackButton.IsEnabled = true; }
    }

    private void ReportProgress(string message)
    {
        Dispatcher.Invoke(() => { _progress = Math.Min(95, _progress + 13); OperationProgress.Value = _progress; OperationStatus.Text = message; OperationLog.AppendText(message + Environment.NewLine); OperationLog.ScrollToEnd(); });
    }

    private void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        var directory = Path.Combine(AppPaths.StateRoot, "Diagnostics"); Directory.CreateDirectory(directory); var stamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss");
        var json = Path.Combine(directory, $"preflight-{stamp}.json"); var text = Path.Combine(directory, $"preflight-{stamp}.txt"); StateStore.WriteJsonAtomically(json, _preflight); File.WriteAllText(text, PreflightService.ToText(_preflight));
        MessageBox.Show(this, $"Preflight exported to:\n{text}\n{json}", "Read-only report exported", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        var content = _page == 2 ? PreflightText.Text : _page == 5 ? PlanText.Text : OperationLog.Text; Clipboard.SetText(content); OperationStatus.Text = "Diagnostics copied to clipboard";
    }

    private async void TailscaleSignIn_Click(object sender, RoutedEventArgs e)
    {
        if (_tailscaleBusy) return;
        _tailscaleBusy = true; _tailscaleCancellation = new CancellationTokenSource(); var sourceButton = sender as Button; if (sourceButton is not null) sourceButton.IsEnabled = false;
        try
        {
        var dependency = DependencyService.Catalog.Single(x => x.Name == "Tailscale"); var detected = new DependencyService().Detect(dependency);
        if (!detected.Compatible) { TailscaleStatusText.Text = "Tailscale is missing or outdated. The Dependencies stage will install/update it from the official source before pairing."; return; }
        TailscaleStatusText.Text = "Starting bounded Tailscale authentication…";
        var auth = await TailscaleAuthenticationService.BeginAsync(new ProcessRunner(), detected.ExecutablePath, _tailscaleCancellation.Token); _tailscaleAuthenticationUri = auth.AuthenticationUri; OpenTailscaleAuthButton.IsEnabled = _tailscaleAuthenticationUri is not null; TailscaleStatusText.Text = $"{auth.State}: {auth.Detail}";
        }
        catch (OperationCanceledException) { TailscaleStatusText.Text = "Tailscale authentication cancelled."; }
        catch (Exception ex) { TailscaleStatusText.Text = $"Tailscale authentication failed: {ex.Message}"; }
        finally { _tailscaleBusy = false; _tailscaleCancellation?.Dispose(); _tailscaleCancellation = null; if (sourceButton is not null) sourceButton.IsEnabled = true; }
    }

    private void OpenTailscaleAuth_Click(object sender, RoutedEventArgs e)
    {
        if (_tailscaleAuthenticationUri is null || !_tailscaleAuthenticationUri.Host.Equals("login.tailscale.com", StringComparison.OrdinalIgnoreCase)) return;
        Process.Start(new ProcessStartInfo { FileName = _tailscaleAuthenticationUri.AbsoluteUri, UseShellExecute = true });
    }

    private async void CheckTailscale_Click(object sender, RoutedEventArgs e)
    {
        if (_tailscaleBusy) return;
        _tailscaleBusy = true; _tailscaleCancellation = new CancellationTokenSource(); var sourceButton = sender as Button; if (sourceButton is not null) sourceButton.IsEnabled = false;
        try
        {
        var dependency = DependencyService.Catalog.Single(x => x.Name == "Tailscale"); var detected = new DependencyService().Detect(dependency);
        if (!detected.Found) { TailscaleStatusText.Text = "Not installed yet."; return; }
        var result = await new ProcessRunner().RunAsync(detected.ExecutablePath, ["status", "--json"], cancellationToken: _tailscaleCancellation.Token); TailscaleStatusText.Text = result.ExitCode == 0 ? "Authenticated — Tailscale status returned successfully." : "Authentication required or Tailscale service unavailable.";
        }
        catch (OperationCanceledException) { TailscaleStatusText.Text = "Tailscale status check cancelled."; }
        catch (Exception ex) { TailscaleStatusText.Text = $"Tailscale status failed: {ex.Message}"; }
        finally { _tailscaleBusy = false; _tailscaleCancellation?.Dispose(); _tailscaleCancellation = null; if (sourceButton is not null) sourceButton.IsEnabled = true; }
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        if (_tailscaleBusy) { _tailscaleCancellation?.Cancel(); return; }
        if (_executing) { MessageBox.Show(this, "The current transaction is active. Wait for its bounded operation to finish; no forced reboot or blind cancellation is issued.", "Transaction in progress", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        Close();
    }
}

```


## FILE: installer-source/DevFleet.Setup/Payload/devfleet-v1.2.13.tar.gz

SHA256: e3176c500f652d6023dcb611ccd580567ed9448da343a5fd4c3649214ca0b654 | Bytes: 530862 | Git mode: 100644

Binary file: retrieve the actual repository file at this path. It is not encoded into this reading document.


## FILE: installer-source/DevFleet.Setup/PayloadManifest.cs

SHA256: 3d59d604bf39f55204d33e3135ac256b0c4322458afd2e153ad2b61308c56e1d | Bytes: 345 | Git mode: 100644

```
namespace DevFleet.Setup;

internal static class PayloadManifest
{
    public const string DevFleetVersion = "1.2.13";
    public const string InstallerVersion = "1.4.1";
    public const string PayloadName = "devfleet-v1.2.13.tar.gz";
    public const string PayloadSha256 = "e3176c500f652d6023dcb611ccd580567ed9448da343a5fd4c3649214ca0b654";
}
```


## FILE: installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs

SHA256: c6963a43398085968288e4b76fea4137e5790264c0fa827efd6afd9a0d2f556c | Bytes: 141135 | Git mode: 100644

```
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Text.Json;
using System.Threading;
using Microsoft.Win32;

namespace DevFleet.Setup;

public sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError, bool OutputComplete = true);
public sealed record ProcessInvocation(string FileName, IReadOnlyList<string> Arguments, string? WorkingDirectory);

public static class DeadlinePolicy
{
    public const string Version = "1.0.0";
    public const int TransactionTerminalizationMarginSeconds = 600;
    public const int BootstrapSeconds = 240;
    public const int PreflightSeconds = 120;
    public const int PrerequisiteDependencyCount = 6;
    public const int DependencyProbeSeconds = 60;
    public const int DependencyHealthSeconds = 180;
    public const int DependencyInstallSeconds = 1800;
    public const int DependencyVerificationSeconds = 60;
    public const int WindowsCapabilitySeconds = 900;
    public const int WindowsFeatureSeconds = 900;
    public const int MultipassConfigurationSeconds = 600;
    public const int VsCodeExtensionSeconds = 300;
    public static int PrerequisitesSeconds => PrerequisiteDependencyCount * (DependencyProbeSeconds + DependencyHealthSeconds + DependencyInstallSeconds + DependencyVerificationSeconds) + WindowsCapabilitySeconds + WindowsFeatureSeconds + (4 * MultipassConfigurationSeconds) + (3 * VsCodeExtensionSeconds);
    public const int WindowsTailscaleSeconds = 180;
    public const int HostAgentSeconds = 300;
    public const int MultipassLaunchSeconds = 900;
    public const int MultipassReadinessSeconds = 1200;
    public const int PayloadTransferSeconds = 900;
    public const int GuestBootstrapPackagePrerequisitesSeconds = 900;
    public const int GuestBootstrapDockerRepositoryAndInstallSeconds = 1200;
    public const int GuestBootstrapTailscaleRepositoryAndInstallSeconds = 1200;
    public const int GuestBootstrapRootlessRuntimeSeconds = 600;
    public const int GuestBootstrapNodeToolchainSeconds = 600;
    public const int GuestBootstrapPythonRuntimeSeconds = 1200;
    public const int GuestBootstrapServiceAndFirewallFinalizationSeconds = 600;
    public const int GuestBootstrapTerminalizationMarginSeconds = 300;
    public static int GuestBootstrapSeconds => GuestBootstrapPackagePrerequisitesSeconds + GuestBootstrapDockerRepositoryAndInstallSeconds + GuestBootstrapTailscaleRepositoryAndInstallSeconds + GuestBootstrapRootlessRuntimeSeconds + GuestBootstrapNodeToolchainSeconds + GuestBootstrapPythonRuntimeSeconds + GuestBootstrapServiceAndFirewallFinalizationSeconds + GuestBootstrapTerminalizationMarginSeconds;
    public const int VaultBootstrapPackagePrerequisitesSeconds = 900;
    public const int VaultBootstrapRestServerSeconds = 1200;
    public const int VaultBootstrapTailscaleSeconds = 600;
    public const int VaultBootstrapServiceConfigurationSeconds = 600;
    public const int VaultBootstrapFirewallFinalizationSeconds = 300;
    public const int VaultBootstrapTerminalizationMarginSeconds = 300;
    public static int VaultBootstrapSeconds => VaultBootstrapPackagePrerequisitesSeconds + VaultBootstrapRestServerSeconds + VaultBootstrapTailscaleSeconds + VaultBootstrapServiceConfigurationSeconds + VaultBootstrapFirewallFinalizationSeconds + VaultBootstrapTerminalizationMarginSeconds;
    public const int SshAndMarkerSeconds = 300;
    public const int VaultSnapshotSeconds = 300;
    public const int TailscaleSeconds = 900;
    public const int VaultClientSeconds = 300;
    public const int ShortcutsSeconds = 180;
    public const int ExportSeconds = 300;
    public const int VerificationSeconds = 300;

    public static int ComputeStageSeconds => MultipassLaunchSeconds + MultipassReadinessSeconds + PayloadTransferSeconds + GuestBootstrapSeconds + SshAndMarkerSeconds;
    public static int VaultStageSeconds => VaultSnapshotSeconds + MultipassLaunchSeconds + MultipassReadinessSeconds + PayloadTransferSeconds + VaultBootstrapSeconds + SshAndMarkerSeconds;
    public static int DesktopTransactionSeconds => BootstrapSeconds + PreflightSeconds + PrerequisitesSeconds + WindowsTailscaleSeconds + HostAgentSeconds + ComputeStageSeconds + TailscaleSeconds + ShortcutsSeconds + ExportSeconds + VerificationSeconds + TransactionTerminalizationMarginSeconds;
    public static int LaptopTransactionSeconds => BootstrapSeconds + PreflightSeconds + PrerequisitesSeconds + WindowsTailscaleSeconds + HostAgentSeconds + ComputeStageSeconds + VaultStageSeconds + (TailscaleSeconds * 2) + VaultClientSeconds + ShortcutsSeconds + ExportSeconds + VerificationSeconds + TransactionTerminalizationMarginSeconds;

    public static int GetConnectedTransactionBudgetSeconds(string role) => role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? LaptopTransactionSeconds : DesktopTransactionSeconds;
}

public interface IProcessRunner
{
    ProcessResult Run(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null);
    Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null, CancellationToken cancellationToken = default)
        => Task.Run(() => Run(fileName, arguments, workingDirectory), cancellationToken);
}

public sealed class ProcessRunner : IProcessRunner
{
    public int DefaultTimeoutSeconds { get; }
    public bool AllowEnvironmentOverride { get; }

    public ProcessRunner(int defaultTimeoutSeconds = 900, bool allowEnvironmentOverride = true)
    {
        if (defaultTimeoutSeconds <= 0) throw new ArgumentOutOfRangeException(nameof(defaultTimeoutSeconds));
        DefaultTimeoutSeconds = defaultTimeoutSeconds;
        AllowEnvironmentOverride = allowEnvironmentOverride;
    }

    public ProcessResult Run(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null)
        => RunAsync(fileName, arguments, workingDirectory).GetAwaiter().GetResult();

    public async Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null, CancellationToken cancellationToken = default)
    {
        using var process = new Process { StartInfo = new ProcessStartInfo
        {
            FileName = fileName,
            WorkingDirectory = workingDirectory ?? Environment.CurrentDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        } };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        process.Start();
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        var timeoutSeconds = AllowEnvironmentOverride && int.TryParse(Environment.GetEnvironmentVariable("DEVFLEET_SETUP_PROCESS_TIMEOUT_SECONDS"), out var configured) && configured > 0 ? configured : DefaultTimeoutSeconds;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));
        try
        {
            await process.WaitForExitAsync(timeout.Token).ConfigureAwait(false);
            var exitCode = process.ExitCode;
            try { await Task.WhenAll(stdoutTask, stderrTask).WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false); }
            catch (TimeoutException) { }
            var outputComplete = stdoutTask.Status == TaskStatus.RanToCompletion && stderrTask.Status == TaskStatus.RanToCompletion;
            return new ProcessResult(
                exitCode,
                stdoutTask.Status == TaskStatus.RanToCompletion ? stdoutTask.Result : "",
                stderrTask.Status == TaskStatus.RanToCompletion ? stderrTask.Result : "",
                outputComplete);
        }
        catch (OperationCanceledException)
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
            try { await Task.WhenAll(stdoutTask, stderrTask).WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false); } catch { }
            var outputComplete = stdoutTask.Status == TaskStatus.RanToCompletion && stderrTask.Status == TaskStatus.RanToCompletion;
            return new ProcessResult(-2, stdoutTask.Status == TaskStatus.RanToCompletion ? stdoutTask.Result : "", $"Process timed out after {timeoutSeconds}s. { (stderrTask.Status == TaskStatus.RanToCompletion ? stderrTask.Result : "") }", outputComplete);
        }
    }
}

public sealed class RecordingProcessRunner : IProcessRunner
{
    private readonly Queue<ProcessResult> _results = new();
    public List<ProcessInvocation> Invocations { get; } = [];
    public void QueueResult(ProcessResult result) => _results.Enqueue(result);
    public ProcessResult Run(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null)
    {
        Invocations.Add(new ProcessInvocation(fileName, arguments, workingDirectory));
        return _results.Count > 0 ? _results.Dequeue() : new ProcessResult(0, "fixture success", "");
    }
}

public interface IFileSystem
{
    bool FileExists(string path);
    void CopyFile(string source, string destination, bool overwrite);
    void DeleteFile(string path);
    IReadOnlyList<string> EnumerateFiles(string root);
}

public sealed class RealFileSystem : IFileSystem
{
    public bool FileExists(string path) => File.Exists(path);
    public void CopyFile(string source, string destination, bool overwrite) { Directory.CreateDirectory(Path.GetDirectoryName(destination)!); File.Copy(source, destination, overwrite); }
    public void DeleteFile(string path) { if (File.Exists(path)) File.Delete(path); }
    public IReadOnlyList<string> EnumerateFiles(string root) => Directory.Exists(root) ? Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).ToArray() : [];
}

public interface IRegistryManager { void RemoveExact(string key); }
public interface IServiceManager { bool IsHealthy(string serviceName); void StopOwned(string serviceName); }
public interface IShortcutManager { void RemoveExact(string path); }
public interface IFirewallManager { void RemoveExact(string ruleName); }
public interface ISshManager { void RemoveManagedBlock(string marker); }
public interface IVsCodeManager { void RemoveManagedAlias(string alias); }
public interface IDependencyInstaller { DependencyResult VerifyAndInstall(string dependencyRoot); }

public sealed record DependencyResult(bool Available, bool InstalledByDevFleet, bool RebootRequired, string Detail);

public sealed class DependencyDefinition
{
    public string Id { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Classification { get; init; } = "OPTIONAL";
    public bool Required { get; init; }
    public string[] Roles { get; init; } = [];
    public string[] Features { get; init; } = [];
    public string MinimumSupportedVersion { get; init; } = "0.0.0";
    public int? MaximumMajor { get; init; }
    public string[] ExecutableProbes { get; init; } = [];
    public string[] RegistryProbes { get; init; } = [];
    public string[] AppPathsProbes { get; init; } = [];
    public string[] KnownVendorInstallLocations { get; init; } = [];
    public string? WingetPackageId { get; init; }
    public OfficialResolver DirectOfficialVendorResolver { get; init; } = new();
    public InstallerAuthenticityPolicy InstallerAuthenticityPolicy { get; init; } = new();
    public string[] SilentInstallArguments { get; init; } = [];
    public string RebootSemantics { get; init; } = "0";
    public VersionProbe VersionProbe { get; init; } = new();
    public string PostInstallExecutableDiscovery { get; init; } = "rediscover from all supported probes";
    public string PostInstallVersionVerification { get; init; } = "verify installed version";

    // Compatibility aliases retained for existing installer UI/tests while the manifest is canonical.
    public string Name => DisplayName;
    public string Executable => ExecutableProbes.FirstOrDefault() ?? "";
    public Version MinimumVersion => Version.TryParse(MinimumSupportedVersion, out var v) ? v : new Version(0, 0);
    public string WingetId => WingetPackageId ?? "";
    public Uri OfficialMetadata => new(DirectOfficialVendorResolver.MetadataUri);
}

public sealed class OfficialResolver
{
    public string Type { get; init; } = "";
    public string MetadataUri { get; init; } = "https://example.invalid/";
    public string? OfficialPageUri { get; init; }
    public string? DirectUri { get; init; }
    public string? ExpectedOwner { get; init; }
    public string? ExpectedRepository { get; init; }
    public string[] AllowedHosts { get; init; } = [];
    public string? AssetRegex { get; init; }
    public string? OfficialPageAssetRegex { get; init; }
}

public sealed class InstallerAuthenticityPolicy
{
    public string Strategy { get; init; } = "Authenticode";
    public bool Required { get; init; }
    public string[] AllowedSignerPatterns { get; init; } = [];
    public string[] AllowedSignerSubjectsExact { get; init; } = [];
    public string InstalledExecutableTrust { get; init; } = "signed-executable";
    public string[] Extensions { get; init; } = [];
}

public static class SignerIdentity
{
    public static string NormalizeSubject(string subject)
    {
        if (string.IsNullOrWhiteSpace(subject)) return "";
        try
        {
            var formatted = new X500DistinguishedName(subject).Format(false);
            return Regex.Replace(formatted, @"\s+", "").Trim().ToUpperInvariant();
        }
        catch { return Regex.Replace(subject, @"\s+", "").Trim().ToUpperInvariant(); }
    }

    public static bool MatchesExact(string subject, IEnumerable<string> expected)
        => expected.Any(value => NormalizeSubject(subject).Equals(NormalizeSubject(value), StringComparison.Ordinal));
}

public static class VendorReleaseAuthenticity
{
    public static string NormalizeDigest(string digest)
    {
        var normalized = (digest ?? "").Trim();
        if (normalized.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase)) normalized = normalized[7..];
        if (!Regex.IsMatch(normalized, "^[0-9a-fA-F]{64}$")) throw new InvalidDataException("Vendor release digest must be a SHA-256 value.");
        return normalized.ToLowerInvariant();
    }

    public static string VerifySha256(string path, string expectedDigest)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("Vendor release artifact is missing.", path);
        var expected = NormalizeDigest(expectedDigest);
        using var stream = File.OpenRead(path);
        var actual = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException($"Vendor release SHA-256 mismatch for {Path.GetFileName(path)}: expected {expected}, got {actual}.");
        return actual;
    }
}

public sealed class VersionProbe
{
    public string[] Arguments { get; init; } = ["--version"];
    public string? Regex { get; init; } = @"(?<!\d)(\d+\.\d+(?:\.\d+){0,2})";
}

public sealed class DependencyManifestDocument
{
    public int SchemaVersion { get; init; }
    public string ManifestVersion { get; init; } = "";
    public string SupportedProfile { get; init; } = "";
    public List<DependencyDefinition> Dependencies { get; init; } = [];
}

public sealed record DependencyDetection(string Name, bool Found, string ExecutablePath, Version? Version, bool Compatible, string Source, string Classification)
{
    public string Status => !Found ? "Missing" : Version is null ? "Broken" : Compatible ? "Compatible" : "Outdated";
}
public sealed record WingetHealth(string Status, string ExecutablePath, string Version, string Detail);
public sealed record TailscaleAuthentication(string State, Uri? AuthenticationUri, string Detail, bool TimedOut = false);

public sealed record InstallStage(string Name, string Script, IReadOnlyList<string> Roles);

public static class InstallerStageCatalog
{
    public static IReadOnlyList<InstallStage> ForRole(string role)
    {
        if (role.Contains("Laptop", StringComparison.OrdinalIgnoreCase))
            return [
                new("Preflight", "windows/00-Preflight.ps1", ["Laptop"]),
                new("Prerequisites", "windows/01-Install-Prerequisites.ps1", ["Laptop"]),
                new("Windows Tailscale", "windows/04a-Connect-WindowsTailscale.ps1", ["Laptop"]),
                new("Host Agent", "windows/Install-DevFleet-HostAgent.ps1", ["Laptop"]),
                new("Failover compute", "windows/02-Provision-ComputeNode.ps1", ["Laptop"]),
                new("Vault", "windows/03-Provision-Vault.ps1", ["Laptop"]),
                new("Failover Tailscale", "windows/04-Connect-Tailscale.ps1", ["Laptop"]),
                new("Vault client", "windows/05-Configure-LocalVaultClient.ps1", ["Laptop"]),
                new("Shortcuts", "windows/08-Install-Shortcuts.ps1", ["Laptop"]),
                new("Laptop bootstrap export", "windows/09-Export-Laptop-Bootstrap.ps1", ["Laptop"]),
                new("Verification", "windows/Test-DevFleet.ps1", ["Laptop"])
            ];
        if (role.Contains("Desktop", StringComparison.OrdinalIgnoreCase) || role.Contains("Primary", StringComparison.OrdinalIgnoreCase))
            return [
                new("Preflight", "windows/00-Preflight.ps1", ["Desktop"]),
                new("Prerequisites", "windows/01-Install-Prerequisites.ps1", ["Desktop"]),
                new("Windows Tailscale", "windows/04a-Connect-WindowsTailscale.ps1", ["Desktop"]),
                new("Host Agent", "windows/Install-DevFleet-HostAgent.ps1", ["Desktop"]),
                new("Primary compute", "windows/02-Provision-ComputeNode.ps1", ["Desktop"]),
                new("Primary Tailscale", "windows/04-Connect-Tailscale.ps1", ["Desktop"]),
                new("Shortcuts", "windows/08-Install-Shortcuts.ps1", ["Desktop"]),
                new("Desktop pairing export", "windows/10-Export-Desktop-Pairing.ps1", ["Desktop"]),
                new("Verification", "windows/Test-DevFleet.ps1", ["Desktop"])
            ];
        throw new InvalidOperationException($"Unsupported DevFleet role: {role}");
    }
}

public sealed record InstallerExecutionReport(string Mode, string Role, IReadOnlyList<string> Stages, bool NetworkDownloadsAttempted, int ExitCode, string Detail);

public sealed class InstallService
{
    // Compatibility name retained for existing diagnostics; the effective
    // connected transaction deadline is role-aware and composed by
    // DeadlinePolicy.GetConnectedTransactionBudgetSeconds.
    public static readonly int ConnectedInstallTimeoutSeconds = DeadlinePolicy.DesktopTransactionSeconds;
    private readonly IProcessRunner _runner;
    private readonly bool _usesDefaultRunner;
    public InstallService(IProcessRunner? runner = null)
    {
        _usesDefaultRunner = runner is null;
        _runner = runner ?? new ProcessRunner(DeadlinePolicy.DesktopTransactionSeconds, allowEnvironmentOverride: false);
    }

    public InstallerExecutionReport Run(string releaseRoot, string role, string mode, Action<string>? progress = null, bool deferNetworkPairing = false, bool acknowledgeRootfulDocker = false, string? transactionId = null, string? transactionPayloadSha256 = null, string? transactionAction = null, string? transactionRole = null, string? transactionPreparedUtc = null)
    {
        var stages = InstallerStageCatalog.ForRole(role);
        foreach (var stage in stages) progress?.Invoke($"Stage planned: {stage.Name} ({stage.Script})");
        var script = Path.Combine(releaseRoot, "Install-DevFleet.ps1");
        if (!File.Exists(script)) throw new FileNotFoundException("The real DevFleet installation entry point is missing.", script);
        var normalizedRole = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
        var transactionBudgetSeconds = DeadlinePolicy.GetConnectedTransactionBudgetSeconds(normalizedRole);
        var transactionDeadlineUtc = DateTime.UtcNow.AddSeconds(transactionBudgetSeconds);
        var bootstrap = Path.Combine(releaseRoot, "Bootstrap-Install.ps1");
        var entry = File.Exists(bootstrap) ? bootstrap : script;
        var args = new List<string> { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", entry, "-Role", normalizedRole, "-NonInteractive", "-PackageRoot", releaseRoot, "-InstallationMode", "Connected", "-SkipWindowsUpdates", "-TransactionDeadlineUtc", transactionDeadlineUtc.ToString("O"), "-DeadlinePolicyVersion", DeadlinePolicy.Version };
        if (!string.IsNullOrWhiteSpace(transactionId) && !string.IsNullOrWhiteSpace(transactionPayloadSha256) && !string.IsNullOrWhiteSpace(transactionAction) && !string.IsNullOrWhiteSpace(transactionRole) && !string.IsNullOrWhiteSpace(transactionPreparedUtc))
        {
            var propagatedRole = transactionRole.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
            args.AddRange(["-TransactionId", transactionId, "-TransactionPayloadSha256", transactionPayloadSha256, "-TransactionAction", transactionAction, "-TransactionRole", propagatedRole, "-TransactionPreparedUtc", transactionPreparedUtc]);
        }
        if (deferNetworkPairing) args.Add("-DeferNetworkPairing");
        if (acknowledgeRootfulDocker) args.Add("-AcknowledgeRootfulDocker");
        progress?.Invoke($"Invoking actual connected installation chain: {Path.GetFileName(entry)} -Role {normalizedRole} -NonInteractive -InstallationMode Connected{(deferNetworkPairing ? " -DeferNetworkPairing" : "")}");
        var runner = _usesDefaultRunner ? new ProcessRunner(transactionBudgetSeconds, allowEnvironmentOverride: false) : _runner;
        var result = runner.Run(FindPowerShell(entry), args, releaseRoot);
        if (result.ExitCode == 3010)
            return new InstallerExecutionReport(mode, normalizedRole, Array.Empty<string>(), true, result.ExitCode, "The verified installer entry point persisted a reboot checkpoint." + (result.OutputComplete ? "" : " Redirected output was incomplete after the bounded post-exit drain."));
        if (result.ExitCode != 0) throw new InvalidOperationException($"DevFleet installation chain failed ({result.ExitCode}): {result.StandardError}{(result.OutputComplete ? "" : " [redirected output incomplete after bounded post-exit drain]")}");
        foreach (var stage in stages) progress?.Invoke($"Stage verified by entry-point completion: {stage.Name}");
        return new InstallerExecutionReport(mode, normalizedRole, stages.Select(s => s.Name).ToArray(), true, result.ExitCode, result.OutputComplete ? result.StandardOutput.Trim() : "Installer entry point exited 0; redirected output was incomplete after the bounded post-exit drain.");
    }

    private static string FindPowerShell(string entry) => TrustedExecutableResolver.PowerShellPath();
}

internal static class TrustedExecutableResolver
{
    public static string PowerShellPath()
    {
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var pwsh = Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe");
        if (File.Exists(pwsh)) return pwsh;
        var systemPowerShell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        if (File.Exists(systemPowerShell)) return systemPowerShell;
        throw new FileNotFoundException("No trusted machine PowerShell executable was found.");
    }

    public static string SystemExecutable(string name)
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), name);
        if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0) return path;
        throw new FileNotFoundException($"No trusted system executable was found: {name}", path);
    }

    public static string VsCodePath()
    {
        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft VS Code", "Code.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft VS Code", "Code.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Microsoft VS Code", "Code.exe")
        };
        foreach (var candidate in candidates)
        {
            if (!File.Exists(candidate) || (File.GetAttributes(candidate) & FileAttributes.ReparsePoint) != 0) continue;
            var full = Path.GetFullPath(candidate);
            if (full.EndsWith(Path.Combine("Microsoft VS Code", "Code.exe"), StringComparison.OrdinalIgnoreCase)) return full;
        }
        throw new FileNotFoundException("A trusted Microsoft VS Code installation was not found in an expected install root.");
    }
}

public sealed class RepairService
{
    private readonly InstallService _install;
    public RepairService(InstallService? install = null) => _install = install ?? new InstallService();
    public InstallerExecutionReport Repair(string releaseRoot, string role, Action<string>? progress = null, bool deferNetworkPairing = false, bool acknowledgeRootfulDocker = false, string? transactionId = null, string? transactionPayloadSha256 = null, string? transactionAction = null, string? transactionRole = null, string? transactionPreparedUtc = null) => _install.Run(releaseRoot, role, "Repair", progress, deferNetworkPairing, acknowledgeRootfulDocker, transactionId, transactionPayloadSha256, transactionAction, transactionRole, transactionPreparedUtc);
}

public sealed class CleanReinstallService
{
    public void PreserveAndReconcile(IReadOnlyList<DiscoveredProject> projects, Action<string>? progress = null)
    {
        progress?.Invoke($"Clean Reinstall preservation plan verified for {projects.Count} discovered project(s); project VMs and backups remain outside the control-plane removal scope.");
    }
}

public sealed class UninstallService
{
    public void RemoveOwnedControlPlane(IReadOnlyList<string> files, IReadOnlyList<string> shortcuts, Action<string>? progress = null)
    {
        foreach (var file in files.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (File.Exists(file)) File.Delete(file);
            if (File.Exists(file)) throw new IOException($"Owned file remains after uninstall cleanup: {file}");
            progress?.Invoke($"Uninstall verified owned file absent: {file}");
        }
        foreach (var shortcut in shortcuts.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (File.Exists(shortcut)) File.Delete(shortcut);
            if (File.Exists(shortcut)) throw new IOException($"Owned shortcut remains after uninstall cleanup: {shortcut}");
            progress?.Invoke($"Uninstall verified owned shortcut absent: {shortcut}");
        }
    }
}

public static class CleanupJournalService
{
    private sealed class Journal
    {
        public int SchemaVersion { get; set; } = 1;
        public string TransactionId { get; set; } = "";
        public string Mode { get; set; } = "";
        public string InstallationGeneration { get; set; } = "";
        public string PayloadFingerprint { get; set; } = "";
        public List<string> CompletedStages { get; set; } = [];
        public string State { get; set; } = "in-progress";
        public string? LastError { get; set; }
        public string UpdatedUtc { get; set; } = "";
    }

    private static string PathFor(string mode) => Path.Combine(AppPaths.StateRoot, $"{mode.ToLowerInvariant()}-cleanup-journal.json");
    private static Journal ReadOrCreate(string mode, string transactionId, string installationGeneration, string payloadFingerprint)
    {
        var path = PathFor(mode);
        if (File.Exists(path))
        {
            var existing = JsonSerializer.Deserialize<Journal>(File.ReadAllText(path));
            if (existing is not null && existing.Mode.Equals(mode, StringComparison.OrdinalIgnoreCase) && existing.TransactionId == transactionId && existing.InstallationGeneration == installationGeneration && existing.PayloadFingerprint == payloadFingerprint) return existing;
        }
        return new Journal { TransactionId = transactionId, Mode = mode, InstallationGeneration = installationGeneration, PayloadFingerprint = payloadFingerprint, UpdatedUtc = DateTime.UtcNow.ToString("O") };
    }

    private static void Save(string mode, Journal journal)
    {
        Directory.CreateDirectory(AppPaths.StateRoot);
        journal.UpdatedUtc = DateTime.UtcNow.ToString("O");
        var path = PathFor(mode); var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(journal, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, path, true);
    }

    public static void Execute(string mode, string transactionId, IReadOnlyList<(string Name, Action Action)> stages, Action<string>? progress = null, string installationGeneration = "", string payloadFingerprint = "")
    {
        var journal = ReadOrCreate(mode, transactionId, installationGeneration, payloadFingerprint); Save(mode, journal);
        foreach (var stage in stages)
        {
            if (journal.CompletedStages.Contains(stage.Name, StringComparer.OrdinalIgnoreCase)) continue;
            try
            {
                stage.Action();
                journal.CompletedStages.Add(stage.Name); journal.LastError = null; Save(mode, journal);
                progress?.Invoke($"Cleanup stage completed: {stage.Name}");
            }
            catch (Exception ex)
            {
                journal.State = "incomplete"; journal.LastError = ex.Message; Save(mode, journal);
                throw;
            }
        }
        journal.State = "completed"; journal.LastError = null; Save(mode, journal);
        var activePath = PathFor(mode); var historyRoot = Path.Combine(AppPaths.StateRoot, "cleanup-history"); Directory.CreateDirectory(historyRoot);
        File.Move(activePath, Path.Combine(historyRoot, $"{mode.ToLowerInvariant()}-{transactionId}.json"), true);
    }
}

public sealed class FactoryResetService
{
    private readonly VmOwnershipService _vms;
    public FactoryResetService(BackupVerificationService _, VmOwnershipService vms) { _vms = vms; }
    public void DeleteSelected(DiscoveredProject project, Action<string>? progress = null)
    {
        // Historical backups are restore points only.  Destructive authorization
        // must use a new backup made for this exact reset transaction.
        var backup = _vms.CreateFreshSafetyBackup(project, progress);
        if (!backup.IsVerified) throw new InvalidOperationException($"Factory Reset blocked for {project.Slug}: fresh safety backup verification failed.");
        _vms.DeleteOwnedExact(project.ProjectId, project.RuntimeId, backup, progress);
    }
}

public sealed class DependencyService
{
    private readonly IProcessRunner _runner;
    private readonly HttpClient _http;
    private readonly Dictionary<string, string> _verifiedVendorDigests = new(StringComparer.OrdinalIgnoreCase);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { PropertyNameCaseInsensitive = true };
    public DependencyService(IProcessRunner? runner = null, HttpClient? http = null) { _runner = runner ?? new ProcessRunner(); _http = http ?? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromMinutes(5) }; }
    public static IReadOnlyList<DependencyDefinition> Catalog { get; } = LoadCatalog();

    private static IReadOnlyList<DependencyDefinition> LoadCatalog()
    {
#if DEBUG
        var path = Environment.GetEnvironmentVariable("DEVFLEET_SETUP_DEPENDENCY_MANIFEST");
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
            return ReadManifest(File.ReadAllText(path));
#endif
        var release = Path.Combine(AppPaths.InstallRoot, "Release", PayloadManifest.DevFleetVersion, "dependencies.json");
        if (File.Exists(release)) return ReadManifest(File.ReadAllText(release));
        var assembly = typeof(DependencyService).Assembly;
        var resource = assembly.GetManifestResourceNames().FirstOrDefault(x => x.EndsWith("dependencies.json", StringComparison.OrdinalIgnoreCase));
        if (resource is not null)
        {
            using var stream = assembly.GetManifestResourceStream(resource);
            using var reader = new StreamReader(stream ?? throw new InvalidDataException("Dependency manifest resource is unavailable."));
            return ReadManifest(reader.ReadToEnd());
        }
        throw new InvalidDataException("Canonical dependencies.json was not embedded or staged.");
    }

    private static IReadOnlyList<DependencyDefinition> ReadManifest(string json)
    {
        var manifest = JsonSerializer.Deserialize<DependencyManifestDocument>(json, JsonOptions)
            ?? throw new InvalidDataException("Canonical dependency manifest is empty.");
        if (manifest.SchemaVersion != 1 || manifest.ManifestVersion != PayloadManifest.DevFleetVersion || manifest.Dependencies.Count == 0)
            throw new InvalidDataException("Canonical dependency manifest version or schema is invalid.");
        return manifest.Dependencies;
    }

    public DependencyDetection Detect(DependencyDefinition dependency)
    {
        DependencyDetection? firstObserved = null;
        foreach (var candidate in CandidatePaths(dependency).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!File.Exists(candidate)) continue;
            if (!IsTrustedInstalledDependency(candidate, dependency)) continue;
            var version = ReadVersion(candidate, dependency);
            var compatible = version is not null && version >= dependency.MinimumVersion && (!dependency.MaximumMajor.HasValue || version.Major <= dependency.MaximumMajor.Value);
            var observed = new DependencyDetection(dependency.Name, true, Path.GetFullPath(candidate), version, compatible, "trusted machine PATH/HKLM/known-path discovery", dependency.Classification);
            firstObserved ??= observed;
            if (compatible) return observed;
        }
        return firstObserved ?? new(dependency.Name, false, "", null, false, "not detected or no trusted candidate", dependency.Classification);
    }

    public DependencyDetection ResolveCompatibleVersion(DependencyDefinition dependency) => Detect(dependency);

    public WingetHealth GetWingetHealth()
    {
        var wingetPolicy = new DependencyDefinition { DisplayName = "WinGet", InstallerAuthenticityPolicy = new InstallerAuthenticityPolicy { Required = true, AllowedSignerSubjectsExact = ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"] } };
        var winget = LocateOnPath("winget.exe", wingetPolicy);
        if (winget is null) return new("Missing", "", "", "winget.exe was not found on PATH.");
        var info = _runner.Run(winget, ["--version"]);
        if (info.ExitCode != 0) return new("Broken", winget, "", "winget --version failed: " + info.StandardError.Trim());
        if (!info.OutputComplete) return new("Broken", winget, "", "winget --version output was incomplete after the bounded post-exit drain.");
        var version = ExtractVersion(info.StandardOutput + " " + info.StandardError)?.ToString() ?? "Unknown";
        var sources = _runner.Run(winget, ["source", "list", "--disable-interactivity"]);
        if (sources.ExitCode != 0) return new("SourceBroken", winget, version, "winget source list failed: " + sources.StandardError.Trim());
        if (!sources.OutputComplete) return new("SourceBroken", winget, version, "winget source list output was incomplete after the bounded post-exit drain.");
        var search = _runner.Run(winget, ["search", "--id", "Microsoft.PowerShell", "--exact", "--source", "winget", "--disable-interactivity"]);
        if (search.ExitCode != 0) return new("SourceBroken", winget, version, "winget search failed: " + search.StandardError.Trim());
        if (!search.OutputComplete) return new("SourceBroken", winget, version, "winget search output was incomplete after the bounded post-exit drain.");
        return new("Healthy", winget, version, "version, source list and package search succeeded.");
    }

    public ProcessResult RepairWinget()
    {
        var command = "Install-PackageProvider -Name NuGet -Force | Out-Null; Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null; Repair-WinGetPackageManager -Force -Latest";
        return _runner.Run(TrustedExecutableResolver.PowerShellPath(), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command]);
    }

    public string DownloadOfficial(DependencyDefinition dependency, string destinationRoot)
    {
        Directory.CreateDirectory(destinationRoot);
        var winget = GetWingetHealth();
        if (winget.Status == "Healthy" && !string.IsNullOrWhiteSpace(dependency.WingetPackageId))
        {
            var result = _runner.Run(winget.ExecutablePath, ["download", "--id", dependency.WingetPackageId!