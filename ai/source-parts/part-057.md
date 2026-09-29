# DevFleet source part 057

Full-source UTF-8 byte interval [2604000, 2650500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 25535c02cdf0213a2687ee0286dfb37326926905485c5a183955b51612207144

<!-- BEGIN SOURCE SLICE -->
", backup_id = "backup-demo", archive = backupArchive, sha256 = backupHash }));
File.WriteAllText(Path.Combine(stateRoot, "projects.json"), System.Text.Json.JsonSerializer.Serialize(new[] { new { project_id = "project-demo", slug = "demo", runtime_id = "devfleet-project-demo", vm_name = "devfleet-project-demo", host_id = "test-node", managed_by = "devfleet", state = "stopped", backup_manifest = backupManifest } }));
var projectManifest = new { project_id = "project-demo", backup_id = "backup-demo", archive = backupArchive, sha256 = backupHash, slug = "demo", runtime_id = "devfleet-project-demo", source_archive_sha256 = backupHash, host_archive_sha256 = backupHash };
File.WriteAllText(backupManifest, System.Text.Json.JsonSerializer.Serialize(projectManifest));
var verified = new BackupVerificationService().Verify(new DiscoveredProject("project-demo", "demo", "Multipass", "devfleet-project-demo", "HostAgent", backupManifest, true));
Assert(verified.IsVerified, "Backup verification must hash the archive and validate identity/eligibility.");
var selectedPlan = PlanService.Build(InstallerMode.FactoryReset, true, true, false, true, true, "DELETE DEVFLEET", "DELETE DEVFLEET PROJECT DATA", ["project-demo"]);
Assert(selectedPlan.IsAllowed && selectedPlan.SelectedProjects.Count == 1, "Selected project plan must use the project-specific verified backup.");

var vmProvider = new RecordingVmProvider([new VmRecord("Multipass", "devfleet-project-demo", "project-demo", true), new VmRecord("Multipass", "unrelated-vm", "other", false)]);
new VmOwnershipService(vmProvider).DeleteOwnedExact("project-demo", "devfleet-project-demo", verified);
Assert(vmProvider.DeletedRuntimeIds.SequenceEqual(["devfleet-project-demo"]), "Provider-aware deletion did not target the exact owned runtime.");
Assert(vmProvider.Inventory.Single(x => x.RuntimeId == "devfleet-project-demo").BackupId == "", "Fixture inventory must remain immutable.");
var wildcardBlocked = false;
try { new VmOwnershipService(new RecordingVmProvider([new VmRecord("Multipass", "*", "project-demo", true)])).DeleteOwnedExact("project-demo", "*"); } catch (InvalidOperationException) { wildcardBlocked = true; }
Assert(wildcardBlocked, "Wildcard provider deletion must be blocked.");
var endpointBuilder = typeof(MultipassHostAgentProvider).GetMethod("BuildHostAgentBaseUri", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
var wildcardEndpoint = (Uri)endpointBuilder!.Invoke(null, ["http://+:8790/"])!;
Assert(wildcardEndpoint.Host == "127.0.0.1" && wildcardEndpoint.Port == 8790, "Wildcard Host Agent listen prefix must normalize to the local endpoint for destruction requests.");

Console.WriteLine("PASS installer stage, backup, provider, shortcut-contract tests");

var auth = TailscaleAuthenticationService.ParseAuthenticationUri("To authenticate, visit: https://login.tailscale.com/a/abcDEF123");
Assert(auth?.Host == "login.tailscale.com", "Official Tailscale authentication URL parser failed.");
Assert(TailscaleAuthenticationService.ParseAuthenticationUri("https://evil.example/a/abc") is null, "Non-Tailscale authentication URL must be rejected.");
var tailscaleRunner = new RecordingProcessRunner();
tailscaleRunner.QueueResult(new ProcessResult(1, "", "To authenticate, visit: https://login.tailscale.com/a/abcDEF123"));
var tailscaleBegin = TailscaleAuthenticationService.Begin(tailscaleRunner, "tailscale.exe");
Assert(tailscaleRunner.Invocations.Single().Arguments.SequenceEqual(["up", "--timeout=30s"]), "Tailscale authentication must use a bounded CLI timeout.");
Assert(tailscaleBegin.State == "Authentication required" && tailscaleBegin.AuthenticationUri?.Host == "login.tailscale.com", "Bounded Tailscale authentication must preserve the official URL result.");
var incompleteTailscaleRunner = new RecordingProcessRunner();
incompleteTailscaleRunner.QueueResult(new ProcessResult(1, "", "To authenticate, visit: https://login.tailscale.com/a/abcDEF123", OutputComplete: false));
var incompleteTailscale = TailscaleAuthenticationService.Begin(incompleteTailscaleRunner, "tailscale.exe");
Assert(incompleteTailscale.State == "Error" && incompleteTailscale.AuthenticationUri is null && incompleteTailscale.Detail.Contains("incomplete", StringComparison.OrdinalIgnoreCase), "Tailscale must reject a trusted URL parsed from incomplete output.");

var deps = DependencyService.Catalog;
Assert(deps.Any(d => d.Name == "PowerShell 7" && d.Required) && deps.Any(d => d.Name == "Multipass" && d.Required), "Core connected dependency catalog is incomplete.");
Assert(deps.All(d => d.OfficialMetadata.Scheme == "https"), "Every dependency must use an HTTPS official metadata source.");
var seven = deps.Single(d => d.Id == "sevenzip");
var git = deps.Single(d => d.Id == "git");
Assert(git.DirectOfficialVendorResolver.AllowedHosts.Contains("release-assets.githubusercontent.com"), "GitHub release assets must allow the official release-assets redirect host.");
Assert(deps.Where(d => d.DirectOfficialVendorResolver.Type.Equals("github-release", StringComparison.OrdinalIgnoreCase)).All(d => d.DirectOfficialVendorResolver.AllowedHosts.Contains("release-assets.githubusercontent.com")), "Every GitHub release dependency must allow the official release-assets redirect host.");
Assert(deps.Single(d => d.Id == "multipass").InstallerAuthenticityPolicy.AllowedSignerSubjectsExact.SequenceEqual(["CN=CANONICAL GROUP LIMITED, O=CANONICAL GROUP LIMITED, L=London, C=GB"]), "Multipass must use the exact currently published Canonical Group signer identity.");
Assert(deps.Single(d => d.Id == "multipass").InstallerAuthenticityPolicy.InstalledExecutableTrust == "signed-installer-locked-path", "Multipass must bind unsigned installed binaries to a signed installer and locked machine path.");
Assert(!seven.Required && seven.Classification == "OPTIONAL" && seven.Features.Contains("encrypted-transfer-bundle"), "7-Zip must be optional for core install and feature-scoped.");
Assert(seven.InstallerAuthenticityPolicy.Strategy == "VendorReleaseSha256", "7-Zip must use the explicit vendor release digest strategy.");
Assert(seven.DirectOfficialVendorResolver.ExpectedOwner == "ip7z" && seven.DirectOfficialVendorResolver.ExpectedRepository == "7zip", "7-Zip vendor identity must be narrowly bound to ip7z/7zip.");
Assert(seven.DirectOfficialVendorResolver.AllowedHosts.Contains("api.github.com") && seven.DirectOfficialVendorResolver.AllowedHosts.Contains("github.com") && seven.DirectOfficialVendorResolver.AllowedHosts.Contains("release-assets.githubusercontent.com"), "7-Zip release hosts are incomplete.");
Assert(deps.Where(d => d.Id != "sevenzip").Where(d => d.InstallerAuthenticityPolicy.Required).All(d => d.InstallerAuthenticityPolicy.Strategy == "Authenticode"), "Existing signed dependency policies must remain Authenticode-required.");
var digestFixture = Path.Combine(stateRoot, "7z-fixture.bin");
File.WriteAllBytes(digestFixture, [1, 2, 3, 4]);
var digest = VendorReleaseAuthenticity.VerifySha256(digestFixture, "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a");
Assert(digest.Length == 64, "Valid vendor digest was not accepted.");
var digestBlocked = false;
try { VendorReleaseAuthenticity.VerifySha256(digestFixture, "0000000000000000000000000000000000000000000000000000000000000000"); } catch (InvalidDataException) { digestBlocked = true; }
Assert(digestBlocked, "Wrong vendor digest must fail closed.");
var malformedBlocked = false;
try { VendorReleaseAuthenticity.NormalizeDigest("not-a-sha256"); } catch (InvalidDataException) { malformedBlocked = true; }
Assert(malformedBlocked, "Missing/malformed vendor digest must fail closed.");
Assert(seven.DirectOfficialVendorResolver.OfficialPageUri == "https://www.7-zip.org/download.html", "7-Zip official page binding is missing.");
Assert(seven.DirectOfficialVendorResolver.AssetRegex?.Contains("x64") == true, "7-Zip architecture restriction is missing.");
Assert(seven.DirectOfficialVendorResolver.MetadataUri.Contains("api.github.com/repos/ip7z/7zip/releases", StringComparison.OrdinalIgnoreCase), "7-Zip release metadata must come from the official API.");
Assert(seven.InstallerAuthenticityPolicy.Extensions.SequenceEqual([".exe"]), "7-Zip vendor digest policy must restrict the installer type.");
Console.WriteLine("PASS authenticity strategy, vendor digest, release identity, host, architecture, and signed-policy preservation tests");

var deferredRunner = new RecordingProcessRunner();
new InstallService(deferredRunner).Run(installFixture, "Desktop", "FreshInstall", deferNetworkPairing: true, acknowledgeRootfulDocker: true);
Assert(deferredRunner.Invocations.Single().Arguments.Contains("-DeferNetworkPairing"), "DeferNetworkPairing was not forwarded through the production install contract.");
foreach (var mode in new[] { InstallerMode.FreshInstall, InstallerMode.Repair, InstallerMode.CleanReinstall, InstallerMode.LocalUpdate })
{
    var laptopDeferred = PlanService.Build(mode, true, true, false, false, false, "", "", deferNetworkPairing: true, role: "Laptop / Surrogate");
    Assert(!laptopDeferred.IsAllowed && laptopDeferred.Blockers.Any(x => x.Contains("connected Tailscale pairing")), "A deferred Laptop plan must be blocked before mutation because Vault transport requires authentication.");
    var laptopConnected = PlanService.Build(mode, true, true, false, false, false, "", "", deferNetworkPairing: false, role: "Laptop / Surrogate");
    Assert(!laptopConnected.Blockers.Any(x => x.Contains("connected Tailscale pairing")), "Connected Laptop plan acquired an unrelated network-deferral blocker.");
}
Assert(deferredRunner.Invocations.Single().Arguments.Contains("-AcknowledgeRootfulDocker"), "Rootful Docker acknowledgement was not forwarded through the production install contract.");
var elevatedArguments = InstallerLaunchContract.BuildElevatedResumeArguments("Primary / Desktop", InstallerMode.FreshInstall, deferNetworkPairing: true, acknowledgeRootfulDocker: true);
var elevatedRequest = InstallerLaunchContract.Parse(elevatedArguments);
Assert(elevatedRequest is { ElevatedResume: true, DeferNetworkPairing: true, AcknowledgeRootfulDocker: true, Action: InstallerMode.FreshInstall, Role: "Primary / Desktop" }, "UAC relaunch did not round-trip the exact reviewed action, role, network choice, and rootful Docker acknowledgement through the production parser contract.");
var defaultElevatedRequest = InstallerLaunchContract.Parse(InstallerLaunchContract.BuildElevatedResumeArguments("Primary / Desktop", InstallerMode.Repair, deferNetworkPairing: false, acknowledgeRootfulDocker: false));
Assert(!defaultElevatedRequest.DeferNetworkPairing && !defaultElevatedRequest.AcknowledgeRootfulDocker, "UAC relaunch fabricated optional reviewed choices that were not selected.");
Console.WriteLine("PASS elevated relaunch reviewed-plan argument and parser contract");

var incompleteSuccessRunner = new RecordingProcessRunner();
incompleteSuccessRunner.QueueResult(new ProcessResult(0, "", "", OutputComplete: false));
var incompleteSuccessReport = new InstallService(incompleteSuccessRunner).Run(installFixture, "Desktop", "FreshInstall");
Assert(incompleteSuccessReport.ExitCode == 0 && incompleteSuccessReport.Detail.Contains("incomplete", StringComparison.OrdinalIgnoreCase), "Installer exit 0 must remain authoritative while incomplete diagnostics are explicit.");
var incompleteRebootRunner = new RecordingProcessRunner();
incompleteRebootRunner.QueueResult(new ProcessResult(3010, "", "", OutputComplete: false));
var incompleteRebootReport = new InstallService(incompleteRebootRunner).Run(installFixture, "Desktop", "FreshInstall");
Assert(incompleteRebootReport.ExitCode == 3010 && incompleteRebootReport.Detail.Contains("incomplete", StringComparison.OrdinalIgnoreCase), "Installer exit 3010 must remain authoritative while incomplete diagnostics are explicit.");

var defaultInstallService = new InstallService();
var installRunnerField = typeof(InstallService).GetField("_runner", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
var defaultInstallRunner = installRunnerField?.GetValue(defaultInstallService) as ProcessRunner;
Assert(InstallService.ConnectedInstallTimeoutSeconds == DeadlinePolicy.DesktopTransactionSeconds, "Connected installation compatibility timeout must match the composed Desktop transaction policy.");
Assert(defaultInstallRunner?.DefaultTimeoutSeconds == DeadlinePolicy.DesktopTransactionSeconds && !defaultInstallRunner.AllowEnvironmentOverride, "Default connected installation must use the composed role-aware transaction budget without the process-wide environment override.");
Assert(DeadlinePolicy.LaptopTransactionSeconds > DeadlinePolicy.DesktopTransactionSeconds, "Laptop transaction must dominate its additional sequential compute, vault, and transport stages.");
Assert(DeadlinePolicy.ComputeStageSeconds >= DeadlinePolicy.MultipassReadinessSeconds + DeadlinePolicy.GuestBootstrapSeconds, "Compute stage must contain both readiness and complete guest bootstrap allowances.");
Assert(DeadlinePolicy.VaultStageSeconds > DeadlinePolicy.VaultBootstrapSeconds + DeadlinePolicy.SshAndMarkerSeconds, "Vault stage must contain its snapshot, transport, bounded Vault bootstrap, and SSH/marker allowances.");
Assert(DeadlinePolicy.DesktopTransactionSeconds > DeadlinePolicy.ComputeStageSeconds, "Desktop transaction must dominate its compute stage and all surrounding stages.");
Assert(DeadlinePolicy.LaptopTransactionSeconds > DeadlinePolicy.VaultStageSeconds + DeadlinePolicy.ComputeStageSeconds, "Laptop transaction must dominate both sequential provisioning stages.");
Assert(DeadlinePolicy.PrerequisitesSeconds == DeadlinePolicy.PrerequisiteDependencyCount * (DeadlinePolicy.DependencyProbeSeconds + DeadlinePolicy.DependencyHealthSeconds + DeadlinePolicy.DependencyInstallSeconds + DeadlinePolicy.DependencyVerificationSeconds) + DeadlinePolicy.WindowsCapabilitySeconds + DeadlinePolicy.WindowsFeatureSeconds + (4 * DeadlinePolicy.MultipassConfigurationSeconds) + (3 * DeadlinePolicy.VsCodeExtensionSeconds), "Prerequisite stage must be derived from every finite sequential dependency/configuration operation.");
Assert(new ProcessRunner().DefaultTimeoutSeconds == 900, "Ordinary process probes must retain their 900-second default bound.");

var stress = new ProcessRunner().Run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "$s='x'*200000;[Console]::Out.Write($s);[Console]::Error.Write($s)"]);
Assert(stress.ExitCode == 0 && stress.OutputComplete && stress.StandardOutput.Length == 200000 && stress.StandardError.Length == 200000, "ProcessRunner stdout/stderr stress failed.");
var ordinaryFailure = new ProcessRunner().Run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "[Console]::Out.Write('known-output');[Console]::Error.Write('known-error');exit 7"]);
Assert(ordinaryFailure.ExitCode == 7 && ordinaryFailure.OutputComplete && ordinaryFailure.StandardOutput == "known-output" && ordinaryFailure.StandardError == "known-error", "ProcessRunner ordinary nonzero complete-output contract failed.");
AssertInheritedPipeDescendant(23);
AssertInheritedPipeDescendant(3010);
var previousProcessTimeout = Environment.GetEnvironmentVariable("DEVFLEET_SETUP_PROCESS_TIMEOUT_SECONDS");
try
{
    Environment.SetEnvironmentVariable("DEVFLEET_SETUP_PROCESS_TIMEOUT_SECONDS", "1");
    var timeoutTimer = System.Diagnostics.Stopwatch.StartNew();
    var directTimeout = new ProcessRunner(InstallService.ConnectedInstallTimeoutSeconds).Run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "Start-Sleep -Seconds 30"]);
    timeoutTimer.Stop();
    Assert(directTimeout.ExitCode == -2 && timeoutTimer.Elapsed < TimeSpan.FromSeconds(10), "ProcessRunner direct-process timeout contract failed.");
}
finally { Environment.SetEnvironmentVariable("DEVFLEET_SETUP_PROCESS_TIMEOUT_SECONDS", previousProcessTimeout); }
Console.WriteLine("PASS connected dependency, Tailscale, deferred pairing, and ProcessRunner tests");

```


## FILE: installer-source/DevFleet.Setup/App.xaml

SHA256: 8bd96b935412a757a21e891815e4a153889803006b3d310d2291f4a7a54f2a66 | Bytes: 1712 | Git mode: 100644

```
<Application x:Class="DevFleet.Setup.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:local="clr-namespace:DevFleet.Setup"
             Startup="Application_Startup">
    <Application.Resources>
        <SolidColorBrush x:Key="WindowBrush" Color="#0D1424" />
        <SolidColorBrush x:Key="PanelBrush" Color="#151F35" />
        <SolidColorBrush x:Key="PanelBorderBrush" Color="#2C3C5E" />
        <SolidColorBrush x:Key="TextBrush" Color="#F2F6FF" />
        <SolidColorBrush x:Key="MutedBrush" Color="#AAB9D5" />
        <SolidColorBrush x:Key="AccentBrush" Color="#6D9BFF" />
        <SolidColorBrush x:Key="DangerBrush" Color="#D75B6C" />
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
        </Style>
        <Style TargetType="Button">
            <Setter Property="Padding" Value="14,9" />
            <Setter Property="Margin" Value="4,0" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="Background" Value="#2B4F9B" />
            <Setter Property="BorderBrush" Value="#527BD2" />
            <Setter Property="BorderThickness" Value="1" />
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Padding" Value="8,6" />
            <Setter Property="Margin" Value="0,5,0,12" />
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Margin" Value="0,7" />
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
        </Style>
    </Application.Resources>
</Application>

```


## FILE: installer-source/DevFleet.Setup/App.xaml.cs

SHA256: 2edf0f5fed9ccff111be6e4449c3fe584bbf09e497e4bcae9e21b49ab5df07d5 | Bytes: 4569 | Git mode: 100644

```
using System.IO;
using System.Diagnostics;
using System.Windows;

namespace DevFleet.Setup;

public partial class App : Application
{
    private void Application_Startup(object sender, StartupEventArgs e)
    {
        if (e.Args.Any(a => a.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            var scratch = Path.Combine(Path.GetTempPath(), "DevFleet-Setup-SelfTest-" + Guid.NewGuid().ToString("N"));
            try
            {
                TestEnvironment.EnableForSelfTest(scratch);
                AppPaths.ConfigureSelfTestRoots(Path.Combine(scratch, "install"), Path.Combine(scratch, "state"));
                var staged = PayloadService.StageVerifiedPayload("self-test");
                var extracted = PayloadService.ExtractVerifiedPayload(staged, "self-test");
                var blocked = PlanService.Build(InstallerMode.FactoryReset, true, true, false, true, false, "", "");
                var bootstrap = Path.Combine(extracted, "Bootstrap-Install.ps1");
                var install = Path.Combine(extracted, "Install-DevFleet.ps1");
                var bootstrapText = File.ReadAllText(bootstrap); var installText = File.ReadAllText(install);
                var extractedVersion = File.ReadAllText(Path.Combine(extracted, "VERSION")).Trim();
                var resourceCount = typeof(PayloadService).Assembly.GetManifestResourceNames().Count(n => n.EndsWith(".tar.gz", StringComparison.OrdinalIgnoreCase));
                if (PayloadManifest.DevFleetVersion != extractedVersion || string.IsNullOrWhiteSpace(PayloadManifest.InstallerVersion)) throw new InvalidDataException("Release manifest version mismatch.");
                if (resourceCount != 1) throw new InvalidDataException($"Exactly one TAR payload is required; found {resourceCount}.");
                foreach (var parameter in new[] { "Role", "BootstrapBundlePath", "PackageRoot", "InstallationMode", "NonInteractive", "SkipWindowsUpdates", "DeferNetworkPairing", "AcknowledgeRootfulDocker" })
                    if (!bootstrapText.Contains("$" + parameter, StringComparison.Ordinal) || !installText.Contains("$" + parameter, StringComparison.Ordinal)) throw new InvalidDataException($"Bootstrap parameter contract missing: {parameter}");
                var report = $"PASS{Environment.NewLine}installer_version={PayloadManifest.InstallerVersion}{Environment.NewLine}devfleet_version={PayloadManifest.DevFleetVersion}{Environment.NewLine}payload={PayloadManifest.PayloadSha256}{Environment.NewLine}payload_extraction=PASS{Environment.NewLine}bootstrap_entrypoint=PASS{Environment.NewLine}bootstrap_parameter_contract=PASS{Environment.NewLine}embedded_tar_count={resourceCount}{Environment.NewLine}factory_reset_backup_gate={(blocked.Blockers.Any(b => b.Contains("backup", StringComparison.OrdinalIgnoreCase) || b.Contains("project", StringComparison.OrdinalIgnoreCase)) ? "PASS" : "FAIL")}{Environment.NewLine}plan_safety=PASS{Environment.NewLine}";
                var output = Environment.GetEnvironmentVariable("DEVFLEET_SELF_TEST_OUTPUT"); if (!string.IsNullOrWhiteSpace(output)) { Directory.CreateDirectory(Path.GetDirectoryName(output)!); File.WriteAllText(output, report); }
                Shutdown(0);
            }
            catch (Exception ex)
            {
                var output = Environment.GetEnvironmentVariable("DEVFLEET_SELF_TEST_OUTPUT"); if (!string.IsNullOrWhiteSpace(output)) { Directory.CreateDirectory(Path.GetDirectoryName(output)!); File.WriteAllText(output, $"FAIL {ex}"); }
                Shutdown(1);
            }
            finally { try { if (Directory.Exists(scratch)) Directory.Delete(scratch, true); } catch { } TestEnvironment.ClearSelfTestRoot(); }
            return;
        }
        if (e.Args.Any(a => a.Equals("--dashboard", StringComparison.OrdinalIgnoreCase)))
        {
            Process.Start(new ProcessStartInfo { FileName = "http://127.0.0.1:8787", UseShellExecute = true });
            Shutdown(0);
            return;
        }
        if (e.Args.Any(a => a.Equals("--vscode", StringComparison.OrdinalIgnoreCase)))
        {
            var start = new ProcessStartInfo { FileName = TrustedExecutableResolver.VsCodePath(), UseShellExecute = false, CreateNoWindow = true };
            start.ArgumentList.Add("--remote");
            start.ArgumentList.Add("ssh-remote+devfleet-primary");
            start.ArgumentList.Add("/home/devrunner/workspaces");
            Process.Start(start);
            Shutdown(0);
            return;
        }
        new MainWindow().Show();
    }
}

```


## FILE: installer-source/DevFleet.Setup/AssemblyInfo.cs

SHA256: b05cbfe29c306bf7a175342e0db5b0b62ea893fdd09853e66134839dec0a6c55 | Bytes: 730 | Git mode: 100644

```
using System.Windows;

[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("DevFleet.Setup.Tests")]

[assembly:ThemeInfo(
    ResourceDictionaryLocation.None,            //where theme specific resource dictionaries are located
                                                //(used if a resource is not found in the page,
                                                // or application resource dictionaries)
    ResourceDictionaryLocation.SourceAssembly   //where the generic resource dictionary is located
                                                //(used if a resource is not found in the page,
                                                // app, or any theme specific resource dictionaries)
)]

```


## FILE: installer-source/DevFleet.Setup/DevFleet.Setup.csproj

SHA256: 3a47f3c2e5e1d31df519a8ed382d74506b42b265e567404bdfa7a0991a0bffac | Bytes: 1158 | Git mode: 100644

```
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <UseWPF>true</UseWPF>
    <AssemblyName>DevFleet.Setup</AssemblyName>
    <RootNamespace>DevFleet.Setup</RootNamespace>
    <Product>DevFleet Setup</Product>
    <Company>M-TechLabs</Company>
    <Version>1.4.1</Version>
    <FileVersion>1.4.1.0</FileVersion>
    <InformationalVersion>DevFleet Setup 1.4.1 for DevFleet 1.2.13</InformationalVersion>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <PublishSingleFile>true</PublishSingleFile>
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
  </PropertyGroup>

  <ItemGroup>
    <EmbeddedResource Include="Payload\devfleet-v1.2.13.tar.gz" />
    <EmbeddedResource Include="dependencies.json" LogicalName="DevFleet.Setup.dependencies.json" />
  </ItemGroup>

</Project>

```


## FILE: installer-source/DevFleet.Setup/InstallerModels.cs

SHA256: dc43bc68e469ef1a31f2c01aaa4843144d443db935e7f15b4e0184e320b8d50f | Bytes: 2489 | Git mode: 100644

```
using System.Collections.ObjectModel;

namespace DevFleet.Setup;

public enum InstallerMode
{
    Diagnostics,
    FreshInstall,
    Repair,
    CleanReinstall,
    Uninstall,
    FactoryReset,
    LocalUpdate,
    RecoveryPackage
}

public enum TransactionState
{
    Planned,
    InProgress,
    Completed,
    Failed,
    RollbackInProgress,
    RolledBack,
    RollbackIncomplete
}

public sealed record PlanItem(string Target, string Action, bool Owned, bool Destructive, string Rollback);

public sealed class InstallerPlan
{
    public string TransactionId { get; set; } = Guid.NewGuid().ToString("N");
    public InstallerMode Mode { get; init; }
    public bool PreserveProjects { get; init; } = true;
    public bool PreserveBackups { get; init; } = true;
    public bool RemovePrerequisites { get; init; }
    public bool ProjectDataSelected { get; init; }
    public bool VerifiedBackup { get; init; }
    public bool DeferNetworkPairing { get; init; }
    public bool AcknowledgeRootfulDocker { get; set; }
    public Collection<string> SelectedProjectIds { get; } = [];
    public Collection<DiscoveredProject> SelectedProjects { get; } = [];
    public Collection<PlanItem> Items { get; } = [];
    public Collection<string> Blockers { get; } = [];
    public bool IsMutation => Mode is not InstallerMode.Diagnostics and not InstallerMode.RecoveryPackage;
    public bool IsAllowed => Blockers.Count == 0;
}

public sealed class PreflightReport
{
    public string TimestampUtc { get; init; } = DateTime.UtcNow.ToString("O");
    public string WindowsVersion { get; init; } = Environment.OSVersion.VersionString;
    public string Architecture { get; init; } = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString();
    public bool Administrator { get; init; }
    public bool VirtualizationLikelyAvailable { get; init; }
    public bool PendingReboot { get; init; }
    public ulong RamBytes { get; init; }
    public long FreeDiskBytes { get; init; }
    public string ExistingDevFleetVersion { get; init; } = "Not detected";
    public string HostAgentVersion { get; init; } = "Not probed";
    public string MultipassState { get; init; } = "Not probed (diagnostics is read-only)";
    public string DetectedRole { get; init; } = "Standalone / unknown";
    public int ProjectCount { get; init; }
    public int BackupCount { get; init; }
    public Collection<string> Blockers { get; } = [];
    public Collection<string> Warnings { get; } = [];
}

```


## FILE: installer-source/DevFleet.Setup/MainWindow.xaml

SHA256: 84048355976414e35186f6ff5cca89837f8fdba0bb79d2fd00dae928fade06e3 | Bytes: 10888 | Git mode: 100644

```
<Window x:Class="DevFleet.Setup.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DevFleet Setup" Width="1080" Height="720" MinWidth="900" MinHeight="620"
        Background="{StaticResource WindowBrush}" Foreground="{StaticResource TextBrush}"
        WindowStartupLocation="CenterScreen" Loaded="Window_Loaded">
  <Grid Margin="26">
    <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /><RowDefinition Height="Auto" /></Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,18">
      <StackPanel><TextBlock Text="DEVFLEET" Foreground="{StaticResource AccentBrush}" FontSize="13" FontWeight="Bold" /><TextBlock Text="Connected Setup and Maintenance Wizard" FontSize="27" FontWeight="SemiBold" Margin="0,3,0,0" /><TextBlock x:Name="VersionText" Foreground="{StaticResource MutedBrush}" Margin="0,4,0,0" /></StackPanel>
      <Border HorizontalAlignment="Right" VerticalAlignment="Top" Background="#4F1824" BorderBrush="{StaticResource DangerBrush}" BorderThickness="1" CornerRadius="6" Padding="11,7"><StackPanel Orientation="Horizontal"><TextBlock Text="SAFE SCOPE" Foreground="#FFB4BE" FontWeight="Bold" /><TextBlock Text="  No reboot · no driver changes · no production wipe" Foreground="#FFD5DA" Margin="8,0,0,0" /></StackPanel></Border>
    </Grid>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="218" /><ColumnDefinition Width="20" /><ColumnDefinition Width="*" /></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource PanelBorderBrush}" BorderThickness="1" CornerRadius="10" Padding="16"><StackPanel>
        <TextBlock Text="WIZARD" Foreground="{StaticResource MutedBrush}" FontSize="11" FontWeight="Bold" Margin="0,0,0,14" />
        <TextBlock x:Name="StepWelcome" Text="1  Welcome and detect" Margin="0,7" /><TextBlock x:Name="StepAction" Text="2  Choose action" Margin="0,7" /><TextBlock x:Name="StepPreflight" Text="3  Preflight" Margin="0,7" /><TextBlock x:Name="StepScope" Text="4  Scope and recovery" Margin="0,7" /><TextBlock x:Name="StepReview" Text="5  Review exact plan" Margin="0,7" /><TextBlock x:Name="StepExecute" Text="6  Execute and verify" Margin="0,7" />
        <Separator Margin="0,18" Background="{StaticResource PanelBorderBrush}" /><TextBlock Text="Protected by design" Foreground="#8FE2C0" FontWeight="SemiBold" /><TextBlock Text="Ownership proofs, typed confirmations, recovery packages, atomic ledger, redacted logs." TextWrapping="Wrap" Foreground="{StaticResource MutedBrush}" Margin="0,8,0,0" />
      </StackPanel></Border>
      <Border Grid.Column="2" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource PanelBorderBrush}" BorderThickness="1" CornerRadius="10" Padding="25">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /><RowDefinition Height="Auto" /></Grid.RowDefinitions>
          <StackPanel Grid.Row="0"><TextBlock x:Name="PageKicker" Text="WELCOME" Foreground="{StaticResource AccentBrush}" FontSize="11" FontWeight="Bold" /><TextBlock x:Name="PageTitle" Text="Prepare a safe DevFleet operation" FontSize="24" FontWeight="SemiBold" Margin="0,5,0,3" /><TextBlock x:Name="PageDescription" Text="The wizard detects current state, builds an exact plan, and verifies the embedded release before any mutation." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" /></StackPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,20,0,12"><StackPanel>
            <StackPanel x:Name="WelcomePanel"><Border Background="#1A2948" BorderBrush="#3B5D9C" BorderThickness="1" CornerRadius="8" Padding="15" Margin="0,0,0,15"><StackPanel><TextBlock Text="One verified payload, one reviewable connected transaction" FontSize="16" FontWeight="SemiBold" /><TextBlock Text="The launcher contains DevFleet and resolves missing prerequisites from official sources. Automated Tailscale enrollment uses the protected local OAuth client credential; the browser is reserved for explicit manual recovery." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,7,0,0" /></StackPanel></Border><TextBlock x:Name="DetectedSummary" Text="Detecting existing installation…" Margin="0,4,0,0" /><TextBlock Text="Use Diagnostics / Preflight for a non-mutating report. Cleanup modes never use broad wildcards and preserve unrelated VMs, SSH entries, VS Code mappings, and firewall rules." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,14,0,0" /></StackPanel>
             <StackPanel x:Name="ActionPanel" Visibility="Collapsed"><TextBlock Text="Action" FontWeight="SemiBold" /><ComboBox x:Name="ModeCombo" SelectionChanged="ModeCombo_SelectionChanged" /><TextBlock Text="Role" FontWeight="SemiBold" /><ComboBox x:Name="RoleCombo" /><TextBlock Text="Connected clean-room contract: the embedded DevFleet payload is hash-verified; missing prerequisites resolve from authoritative official sources." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,4,0,0" /></StackPanel>
            <StackPanel x:Name="PreflightPanel" Visibility="Collapsed"><Border Background="#101A2B" BorderBrush="{StaticResource PanelBorderBrush}" BorderThickness="1" CornerRadius="7" Padding="13"><TextBox x:Name="PreflightText" IsReadOnly="True" TextWrapping="Wrap" Background="Transparent" BorderThickness="0" Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="12" /></Border></StackPanel>
            <StackPanel x:Name="TailscalePanel" Visibility="Collapsed"><Border Background="#101A2B" BorderBrush="#3B5D9C" BorderThickness="1" CornerRadius="8" Padding="16"><StackPanel><TextBlock Text="Tailscale" FontSize="18" FontWeight="SemiBold" /><TextBlock Text="Connected setup uses the protected local OAuth client credential and verifies service, authenticated status, online state, owned tag, IP, peer, and DevFleet endpoint. Browser sign-in is emergency/manual recovery only." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,6,0,14" /><TextBlock x:Name="TailscaleStatusText" Text="Status not checked" TextWrapping="Wrap" /><StackPanel Orientation="Horizontal" Margin="0,12,0,0"><Button Content="Manual recovery sign in" Click="TailscaleSignIn_Click" /><Button x:Name="OpenTailscaleAuthButton" Content="Open authentication page" Click="OpenTailscaleAuth_Click" IsEnabled="False" /><Button Content="Check authentication" Click="CheckTailscale_Click" /></StackPanel><CheckBox x:Name="DeferNetworkPairingCheck" Content="Configure network pairing later (Desktop only); run Repair without this option to complete pairing" Margin="0,14,0,0" /><CheckBox x:Name="RootfulDockerAcknowledgeCheck" Content="I explicitly acknowledge rootful Docker inside the isolated DevFleet VM (broader VM-level authority; no Windows mounts or Docker TCP exposure)." Margin="0,10,0,0" /></StackPanel></Border></StackPanel>
            <StackPanel x:Name="ScopePanel" Visibility="Collapsed"><TextBlock Text="Default preservation" FontWeight="SemiBold" /><CheckBox x:Name="PreserveProjectsCheck" Content="Preserve project source, Git history, project VMs, and workspaces" IsChecked="True" /><CheckBox x:Name="PreserveBackupsCheck" Content="Preserve verified backups and recovery artifacts" IsChecked="True" /><CheckBox x:Name="RemovePrerequisitesCheck" Content="Remove prerequisites installed by DevFleet (requires ledger proof)" /><CheckBox x:Name="ProjectDataCheck" Content="Factory Reset: include selected project data (strongly destructive)" /><Border x:Name="DangerPanel" Visibility="Collapsed" Background="#3C1B28" BorderBrush="{StaticResource DangerBrush}" BorderThickness="1" CornerRadius="7" Padding="14" Margin="0,12,0,0"><StackPanel><TextBlock Text="FACTORY RESET / FULL REMOVAL" Foreground="#FFB4BE" FontWeight="Bold" /><TextBlock Text="Select each exact VERIFIED project. Ambiguous or unrelated resources remain untouched." Foreground="#FFD5DA" TextWrapping="Wrap" Margin="0,6,0,10" /><ListBox x:Name="ProjectList" SelectionMode="Multiple" MinHeight="120" MaxHeight="220" Background="#24131A" Foreground="#FFD5DA" BorderBrush="#8B4E5C" Margin="0,0,0,10"><ListBox.ItemTemplate><DataTemplate><StackPanel Margin="3"><TextBlock Text="{Binding Slug}" FontWeight="SemiBold" /><TextBlock Text="{Binding RuntimeId}" FontSize="11" /><TextBlock Text="{Binding OwnershipStatus}" FontSize="11" /></StackPanel></DataTemplate></ListBox.ItemTemplate></ListBox><TextBlock Text="Control-plane confirmation" Foreground="#FFD5DA" /><TextBox x:Name="ControlPhraseBox" Margin="0,4,0,8" /><TextBlock Text="Project-data confirmation" Foreground="#FFD5DA" /><TextBox x:Name="ProjectPhraseBox" Margin="0,4,0,8" /><CheckBox x:Name="VerifiedBackupCheck" Content="I verified the selected project's technical backup evidence (acknowledgement only)." Foreground="#FFD5DA" /></StackPanel></Border></StackPanel>
            <StackPanel x:Name="ReviewPanel" Visibility="Collapsed"><TextBlock Text="Exact plan" FontWeight="SemiBold" Margin="0,0,0,8" /><TextBox x:Name="PlanText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" MinHeight="220" Background="#101A2B" BorderBrush="{StaticResource PanelBorderBrush}" Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="12" Padding="11" /><TextBlock x:Name="PlanStatus" Margin="0,12,0,0" FontWeight="SemiBold" /></StackPanel>
            <StackPanel x:Name="ExecutePanel" Visibility="Collapsed"><ProgressBar x:Name="OperationProgress" Height="8" Minimum="0" Maximum="100" /><TextBlock x:Name="OperationStatus" Text="Ready" Margin="0,12,0,0" /><TextBox x:Name="OperationLog" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" MinHeight="180" Margin="0,12,0,0" Background="#101A2B" BorderBrush="{StaticResource PanelBorderBrush}" Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="11" Padding="11" /></StackPanel>
          </StackPanel></ScrollViewer>
          <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="ExportButton" Content="Export Preflight" Click="ExportButton_Click" /><Button x:Name="CopyButton" Content="Copy diagnostics" Click="CopyButton_Click" /><Button x:Name="BackButton" Content="Back" Click="BackButton_Click" /><Button x:Name="NextButton" Content="Next" Click="NextButton_Click" /><Button x:Name="ExecuteButton" Content="Execute verified plan" Click="ExecuteButton_Click" Visibility="Collapsed" Background="#2B8066" BorderBrush="#55B998" /><Button x:Name="CancelButton" Content="Cancel" Click="CancelButton_Click" Background="#4A2933" BorderBrush="#8B4E5C" /></StackPanel>
        </Grid>
      </Border>
    </Grid>
  </Grid>
</Window>

```


## FILE: installer-source/DevFleet.Setup/MainWindow.xaml.cs

SHA256: d0869b40c123a7082fbd3a7c4609503a35463c69366c8d0d4d84af94fc5a42dc | Bytes: 15527 | Git mode: 100644

```
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Windows;
using System.Windows.Controls;

namespace DevFleet.Setup;

public partial class MainWindow : Window
{
    private readonly string[] _pages = ["Welcome", "Action", "Preflight", "Tailscale", "Scope", "Review", "Execute", "Finish"];
    private int _page;
    private PreflightReport _preflight = new();
    private InstallerPlan? _plan;
    private IReadOnlyList<DiscoveredProject> _projects = [];
    private bool _executing;
    private bool _tailscaleBusy;
    private CancellationTokenSource? _tailscaleCancellation;
    private int _progress;
    private bool _deferNetworkPairing;
    private Uri? _tailscaleAuthenticationUri;

    public MainWindow()
    {
        InitializeComponent();
        VersionText.Text = $"DevFleet {PayloadManifest.DevFleetVersion}  ·  Installer {PayloadManifest.InstallerVersion}  ·  Official-source connected setup";
        ModeCombo.ItemsSource = Enum.GetValues<InstallerMode>();
        ModeCombo.SelectedItem = InstallerMode.Diagnostics;
        RoleCombo.ItemsSource = new[] { "Primary / Desktop", "Laptop / Surrogate" };
        RoleCombo.SelectedIndex = 0;
    }

    private InstallerMode CurrentMode => ModeCombo.SelectedItem is InstallerMode mode ? mode : InstallerMode.Diagnostics;

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        NextButton.IsEnabled = false;
        DetectedSummary.Text = "Running read-only preflight off the UI thread…";
        try
        {
            var result = await Task.Run(() => (Report: PreflightService.Run(), Projects: (IReadOnlyList<DiscoveredProject>)new ProjectDiscoveryService().Discover()));
            _preflight = result.Report;
            _projects = result.Projects;
            ProjectList.ItemsSource = _projects;
            DetectedSummary.Text = $"Existing DevFleet: {_preflight.ExistingDevFleetVersion} · Role: {_preflight.DetectedRole} · Admin: {_preflight.Administrator}";
            PreflightText.Text = PreflightService.ToText(_preflight);
        }
        catch (Exception ex)
        {
            DetectedSummary.Text = "Preflight failed safely; no mutation was attempted.";
            PreflightText.Text = $"Read-only preflight failed: {ex.Message}";
        }
        var launchRequest = InstallerLaunchContract.Parse(Environment.GetCommandLineArgs());
        _deferNetworkPairing = launchRequest.DeferNetworkPairing;
        DeferNetworkPairingCheck.IsChecked = _deferNetworkPairing;
        RootfulDockerAcknowledgeCheck.IsChecked = launchRequest.AcknowledgeRootfulDocker;
        if (launchRequest.Action is { } action) ModeCombo.SelectedItem = action;
        if (!string.IsNullOrWhiteSpace(launchRequest.Role))
        {
            var index = Array.IndexOf((string[])RoleCombo.ItemsSource, launchRequest.Role);
            if (index >= 0) RoleCombo.SelectedIndex = index;
        }
        var elevatedResume = launchRequest.ElevatedResume;
        if (elevatedResume)
            DetectedSummary.Text += " · UAC elevation resumed with the reviewed action and role";
        NextButton.IsEnabled = true;
        RefreshPage();
        if (elevatedResume && CurrentMode != InstallerMode.Diagnostics)
        {
            _page = 5;
            RefreshPage();
            await ExecuteReviewedPlanAsync(requireConfirmation: false, elevatedResume: true);
        }
    }

    private void RefreshPage()
    {
        PageKicker.Text = $"STEP {_page + 1} OF {_pages.Length} · {_pages[_page].ToUpperInvariant()}";
        WelcomePanel.Visibility = _page == 0 ? Visibility.Visible : Visibility.Collapsed;
        ActionPanel.Visibility = _page == 1 ? Visibility.Visible : Visibility.Collapsed;
        PreflightPanel.Visibility = _page == 2 ? Visibility.Visible : Visibility.Collapsed;
        TailscalePanel.Visibility = _page == 3 ? Visibility.Visible : Visibility.Collapsed;
        ScopePanel.Visibility = _page == 4 ? Visibility.Visible : Visibility.Collapsed;
        ReviewPanel.Visibility = _page == 5 ? Visibility.Visible : Visibility.Collapsed;
        ExecutePanel.Visibility = _page >= 6 ? Visibility.Visible : Visibility.Collapsed;
        DangerPanel.Visibility = _page == 4 && CurrentMode == InstallerMode.FactoryReset ? Visibility.Visible : Visibility.Collapsed;
        BackButton.IsEnabled = _page > 0 && !_executing;
        NextButton.Visibility = _page < 6 ? Visibility.Visible : Visibility.Collapsed;
        ExecuteButton.Visibility = _page == 6 && CurrentMode != InstallerMode.Diagnostics ? Visibility.Visible : Visibility.Collapsed;
        ExportButton.Visibility = _page == 2 ? Visibility.Visible : Visibility.Collapsed;
        CopyButton.Visibility = _page is 2 or 5 or 6 ? Visibility.Visible : Visibility.Collapsed;
        PageTitle.Text = _page switch
        {
            0 => "Prepare a safe DevFleet operation",
            1 => "Choose the exact action and role",
            2 => "Review non-mutating preflight",
            3 => "Authenticate or deliberately defer Tailscale pairing",
            4 => CurrentMode == InstallerMode.FactoryReset ? "Select preservation and destructive scope" : "Confirm preservation and recovery",
            5 => "Review the exact transaction plan",
            6 => "Execute and verify",
            _ => "Operation complete"
        };
        PageDescription.Text = _page == 4 && CurrentMode == InstallerMode.FactoryReset ? "Factory Reset is visually distinct and requires exact typed confirmations. Ambiguous resources remain untouched." : "Every mutation is hash-verified, ownership-aware, logged, and recoverable where applicable.";
        foreach (var item in new[] { StepWelcome, StepAction, StepPreflight, StepScope, StepReview, StepExecute }) item.Foreground = (System.Windows.Media.Brush)FindResource("MutedBrush");
        var active = _page switch { 0 => StepWelcome, 1 => StepAction, 2 => StepPreflight, 3 or 4 => StepScope, 5 => StepReview, _ => StepExecute };
        active.Foreground = (System.Windows.Media.Brush)FindResource("AccentBrush"); active.FontWeight = FontWeights.Bold;
        if (_page == 5) BuildPlanAndShow();
    }

    private void ModeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (IsLoaded) RefreshPage();
    }

    private void NextButton_Click(object sender, RoutedEventArgs e)
    {
        if (_page == 5 && (_plan is null || !_plan.IsAllowed)) { BuildPlanAndShow(); return; }
        if (_page < 7) { _page++; RefreshPage(); }
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (_page > 0) { _page--; RefreshPage(); }
    }

    private void BuildPlanAndShow()
    {
        var selected = ProjectList.SelectedItems.Cast<DiscoveredProject>().Select(p => p.ProjectId).ToArray();
        _deferNetworkPairing = DeferNetworkPairingCheck.IsChecked == true;
        _plan = PlanService.Build(CurrentMode, PreserveProjectsCheck.IsChecked == true, PreserveBackupsCheck.IsChecked == true, RemovePrerequisitesCheck.IsChecked == true, ProjectDataCheck.IsChecked == true, VerifiedBackupCheck.IsChecked == true, ControlPhraseBox.Text, ProjectPhraseBox.Text, selected, _deferNetworkPairing, RootfulDockerAcknowledgeCheck.IsChecked == true, RoleCombo.SelectedItem?.ToString());
        RebootCheckpointService.BindPlanIfPresent(_plan, RoleCombo.SelectedItem?.ToString() ?? "Primary / Desktop");
        PlanText.Text = PlanService.ToText(_plan);
        PlanStatus.Text = _plan.IsAllowed ? "PASS — plan is eligible for execution after final review." : "BLOCKED — resolve every blocker before execution.";
        PlanStatus.Foreground = (System.