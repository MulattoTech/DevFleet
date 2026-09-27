# DevFleet source part 055

Full-source UTF-8 byte interval [2511000, 2557500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: bc02e9b6a8da3b4a5d0b66570341666c536f443687137aba6a3d3f43c1b63132

<!-- BEGIN SOURCE SLICE -->
lf-test");
    try
    {
        TestEnvironment.EnableForSelfTest(selfTestAclRoot);
        var selfTestAcl = SecureStagingService.BuildDirectorySecurity(selfTestCache);
        var selfTestSids = selfTestAcl.GetAccessRules(true, false, typeof(SecurityIdentifier)).Cast<FileSystemAccessRule>().Select(rule => rule.IdentityReference.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var currentSid = WindowsIdentity.GetCurrent().User?.Value ?? throw new InvalidOperationException("Test caller has no Windows SID.");
        Assert(selfTestSids.SetEquals(["S-1-5-18", "S-1-5-32-544", currentSid]), "Self-test staging ACL must add only the exact current-user SID.");
        Assert(!selfTestSids.Overlaps(["S-1-1-0", "S-1-5-11", "S-1-5-32-545"]), "Self-test staging ACL must not grant Everyone, Authenticated Users, or Users.");
        SecureStagingService.EnsureDirectory(selfTestCache);
        SecureStagingService.EnsureDirectory(selfTestTransaction);
        var writeProbe = Path.Combine(selfTestTransaction, "write-probe.txt");
        File.WriteAllText(writeProbe, "exact-current-user-only");
        Assert(File.ReadAllText(writeProbe) == "exact-current-user-only", "Self-test caller could not use the secured transaction directory.");
        Console.WriteLine("PASS production and exact-current-user self-test staging ACL profiles");
    }
    finally
    {
        try { if (Directory.Exists(selfTestAclRoot)) Directory.Delete(selfTestAclRoot, true); } catch { }
        TestEnvironment.ClearSelfTestRoot();
    }
}

// Integration branch proofs are safe and read-only with respect to protected
// roots.  They run only on Windows, where ACL and Authenticode APIs exist.
if (OperatingSystem.IsWindows())
{
    var trustedExecutable = new[] {
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "dotnet", "dotnet.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "where.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    }.FirstOrDefault(File.Exists);
    Assert(trustedExecutable is not null, "ACL regression N requires a real existing executable beneath Program Files or Windows.");
    Assert(OwnedPathSafety.TryGetTrustedSystemRoot(trustedExecutable!, out var trustedRoot), "ACL regression N could not resolve the exact trusted root.");
    Assert(Path.GetFullPath(trustedExecutable!).StartsWith(Path.GetFullPath(trustedRoot) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase), "Trusted executable is not below its exact trusted root.");
    var priorPath = Environment.GetEnvironmentVariable("PATH");
    try
    {
        Environment.SetEnvironmentVariable("PATH", Environment.GetFolderPath(Environment.SpecialFolder.System) + Path.PathSeparator + priorPath);
        var trustedRunner = new RecordingProcessRunner();
        trustedRunner.QueueResult(new ProcessResult(1, "", "unsigned fixture is accepted by explicit test policy"));
        trustedRunner.QueueResult(new ProcessResult(0, "9.9.9", ""));
        var trustedDetection = new DependencyService(trustedRunner).Detect(new DependencyDefinition {
            Id = "acl-safe-existing", DisplayName = "ACL safe existing fixture", ExecutableProbes = [Path.GetFileName(trustedExecutable!)], KnownVendorInstallLocations = [trustedExecutable!],
            MinimumSupportedVersion = "1.0.0", VersionProbe = new VersionProbe { Regex = "(\\d+\\.\\d+)" },
            InstallerAuthenticityPolicy = new InstallerAuthenticityPolicy { InstalledExecutableTrust = "signed-installer-locked-path" }
        });
        Assert(trustedDetection.Found && trustedDetection.Compatible && trustedDetection.Version is not null && trustedRunner.Invocations.Count >= 2,
            $"ACL regression N did not reach signer/version branch: found={trustedDetection.Found}, compatible={trustedDetection.Compatible}, version={trustedDetection.Version}, invocations={trustedRunner.Invocations.Count}, path={trustedDetection.ExecutablePath}.");
        Assert(trustedRunner.Invocations.Any(i => i.Arguments.Any(a => a.Contains("Authenticode", StringComparison.OrdinalIgnoreCase))), "ACL regression N signer probe was not reached.");
    Assert(trustedRunner.Invocations.Any(i => string.Equals(i.FileName, trustedExecutable, StringComparison.OrdinalIgnoreCase)), "ACL regression N version probe did not execute the real trusted executable.");
    Console.WriteLine("PASS ACL safe trusted-root executable signer/version branch proof N");

    // WinGet package-root structure is fail-closed: only the exact physical
    // package root beneath Program Files\\WindowsApps may supply winget.exe.
    var approvedWindowsApps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsApps");
    string? package = null;
    if (Directory.Exists(approvedWindowsApps))
    {
        try
        {
            package = Directory.EnumerateDirectories(approvedWindowsApps, "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe", SearchOption.TopDirectoryOnly)
                .Where(path => !new DirectoryInfo(path).Attributes.HasFlag(FileAttributes.ReparsePoint))
                .FirstOrDefault(path => File.Exists(Path.Combine(path, "winget.exe")));
        }
        catch (UnauthorizedAccessException)
        {
            Console.WriteLine("SKIP physical WindowsApps package-root branch: current test token cannot enumerate the protected directory.");
        }
    }
    if (package is not null)
    {
        var packageWinget = Path.Combine(package, "winget.exe");
        Assert(OwnedPathSafety.IsExactWindowsAppxPackageCandidate(packageWinget, package, approvedWindowsApps, "Microsoft.DesktopAppInstaller", "8wekyb3d8bbwe"), "Valid physical WinGet package candidate was rejected.");
        Assert(!OwnedPathSafety.IsExactWindowsAppxPackageCandidate(Path.Combine(approvedWindowsApps, "winget.exe"), approvedWindowsApps, approvedWindowsApps, "Microsoft.DesktopAppInstaller", "8wekyb3d8bbwe"), "WindowsApps root executable must not be accepted.");
        Assert(!OwnedPathSafety.IsExactWindowsAppxPackageCandidate(Path.Combine(package, "..", "winget.exe"), package, approvedWindowsApps, "Microsoft.DesktopAppInstaller", "8wekyb3d8bbwe"), "Non-canonical parent traversal must not be accepted.");
        Assert(!OwnedPathSafety.IsExactWindowsAppxPackageCandidate(packageWinget, package, approvedWindowsApps, "Wrong.Name", "8wekyb3d8bbwe"), "Wrong AppX name must not be accepted.");
        Assert(!OwnedPathSafety.IsExactWindowsAppxPackageCandidate(packageWinget, package, approvedWindowsApps, "Microsoft.DesktopAppInstaller", "wrongpublisher"), "Wrong AppX publisher must not be accepted.");
        Assert(!OwnedPathSafety.IsExactWindowsAppxPackageCandidate(packageWinget, package.Replace("_x64__", "_arm64__", StringComparison.OrdinalIgnoreCase), approvedWindowsApps, "Microsoft.DesktopAppInstaller", "8wekyb3d8bbwe"), "Non-x64 AppX package root must not be accepted.");
        Assert(!OwnedPathSafety.IsExactWindowsAppxPackageCandidate(Path.Combine(package, "nested", "winget.exe"), package, approvedWindowsApps, "Microsoft.DesktopAppInstaller", "8wekyb3d8bbwe"), "Nested winget executable must not be accepted.");
        Console.WriteLine("PASS exact physical WindowsApps package-root negative fixtures");
    }
    }
    finally { Environment.SetEnvironmentVariable("PATH", priorPath); }

    // Multiple distinct canonical AppX roots are an ambiguity, not a reason
    // to choose the first result.  These disposable physical roots exercise
    // the same validate-then-distinct selection contract used by WinGet.
    var selectionFixture = Path.Combine(Path.GetTempPath(), "devfleet-appx-selection-" + Guid.NewGuid().ToString("N"));
    var selectionWindowsApps = Path.Combine(selectionFixture, "WindowsApps");
    var selectionRoots = new[] {
        Path.Combine(selectionWindowsApps, "Microsoft.DesktopAppInstaller_1.0.0.0_x64__8wekyb3d8bbwe"),
        Path.Combine(selectionWindowsApps, "Microsoft.DesktopAppInstaller_1.0.0.1_x64__8wekyb3d8bbwe")
    };
    Directory.CreateDirectory(selectionWindowsApps);
    try
    {
        foreach (var root in selectionRoots)
        {
            Directory.CreateDirectory(root);
            File.Copy(trustedExecutable!, Path.Combine(root, "winget.exe"));
        }
        var appxRecords = selectionRoots.Select(root => new {
            Name = "Microsoft.DesktopAppInstaller",
            PublisherId = "8wekyb3d8bbwe",
            InstallLocation = root,
            Executable = Path.Combine(root, "winget.exe")
        }).ToArray();
        var exactMatches = appxRecords
            .Where(record => OwnedPathSafety.IsExactWindowsAppxPackageCandidate(record.Executable, record.InstallLocation, selectionWindowsApps, record.Name, record.PublisherId))
            .Select(record => Path.GetFullPath(record.InstallLocation).TrimEnd(Path.DirectorySeparatorChar))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        Assert(appxRecords.All(record => OwnedPathSafety.IsExactWindowsAppxPackageCandidate(record.Executable, record.InstallLocation, selectionWindowsApps, record.Name, record.PublisherId)), "Multiple-root fixture did not individually satisfy exact AppX validation.");
        Assert(exactMatches.Length == 2, $"Multiple-root fixture did not retain two distinct canonical matches: {exactMatches.Length}.");
        var selected = exactMatches.Length == 1 ? exactMatches[0] : null;
        Assert(selected is null, "Multiple distinct exact AppX roots must fail closed rather than select a trusted WinGet candidate.");
        Console.WriteLine("PASS multiple-distinct physical AppX package-root selection fail-closed fixture");
    }
    finally { try { Directory.Delete(selectionFixture, recursive: true); } catch { } }

    // O: a real temporary broad-user-writable directory remains rejected.  The
    // ACL is applied only to this disposable fixture, never Program Files or
    // Windows, and the product resolver must not trust the resulting path.
    var broadFixture = Path.Combine(Path.GetTempPath(), "devfleet-acl-broad-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(broadFixture);
    try
    {
        var security = new DirectoryInfo(broadFixture).GetAccessControl();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User ?? throw new InvalidOperationException("Test caller has no Windows SID."), FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule("BUILTIN\\Users", FileSystemRights.WriteData, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        new DirectoryInfo(broadFixture).SetAccessControl(security);
        var observed = new DirectoryInfo(broadFixture).GetAccessControl().GetAccessRules(true, true, typeof(NTAccount)).OfType<FileSystemAccessRule>();
        Assert(observed.Any(rule => OwnedPathSafety.IsBroadUntrustedPrincipal(rule.IdentityReference.Value) && OwnedPathSafety.HasPrimitiveMutationRights(rule.FileSystemRights)), "ACL regression O did not observe a genuine broad-user mutation ACE.");
        var broadExecutable = Path.Combine(broadFixture, "broad.exe");
        File.Copy(trustedExecutable!, broadExecutable);
        var broadDetection = new DependencyService(new RecordingProcessRunner()).Detect(new DependencyDefinition {
            Id = "acl-broad-writable", DisplayName = "ACL broad writable fixture", KnownVendorInstallLocations = [broadExecutable],
            MinimumSupportedVersion = "1.0.0", VersionProbe = new VersionProbe { Regex = "(\\d+\\.\\d+)" },
            InstallerAuthenticityPolicy = new InstallerAuthenticityPolicy { InstalledExecutableTrust = "signed-installer-locked-path" }
        });
        Assert(!broadDetection.Found && !broadDetection.Compatible, "ACL regression O trusted a genuinely broad-user-writable path.");
        Console.WriteLine("PASS ACL broad-user-writable path rejection O");
    }
    finally { try { Directory.Delete(broadFixture, recursive: true); } catch { } }
}

var blocked = PlanService.Build(InstallerMode.FactoryReset, true, true, false, true, false, "", "");
Assert(!blocked.IsAllowed, "Factory Reset must block without phrases and an individual project selection.");
Assert(blocked.Items.Any(i => i.Action.Contains("fresh safety backup", StringComparison.OrdinalIgnoreCase)), "Fresh safety backup plan item missing.");

var stateRoot = Path.Combine(Path.GetTempPath(), "DevFleet-Setup-SelfTest-" + Guid.NewGuid().ToString("N"));
TestEnvironment.EnableForSelfTest(stateRoot);
Environment.SetEnvironmentVariable("DEVFLEET_SETUP_STATE_ROOT", stateRoot);
Environment.SetEnvironmentVariable("DEVFLEET_SETUP_INSTALL_ROOT", Path.Combine(stateRoot, "install"));
var durableJsonPath = Path.Combine(stateRoot, "durable-state.json");
StateStore.WriteJsonAtomically(durableJsonPath, new { marker = "durable-checkpoint", generation = 1 });
var durableJsonBytes = File.ReadAllBytes(durableJsonPath);
using (var durableJson = JsonDocument.Parse(durableJsonBytes))
    Assert(durableJson.RootElement.GetProperty("marker").GetString() == "durable-checkpoint" && durableJson.RootElement.GetProperty("generation").GetInt32() == 1, "Durably flushed atomic JSON did not survive exact readback.");
Assert(durableJsonBytes.Length > 0 && durableJsonBytes.Any(value => value != 0), "Durably flushed atomic JSON was empty or zero-filled.");
Assert(!Directory.EnumerateFiles(stateRoot, "durable-state.json.tmp-*", SearchOption.TopDirectoryOnly).Any(), "Atomic JSON left a temporary file after commit.");
Console.WriteLine("PASS durable atomic JSON flush and readback");
var stagedResumePath = PayloadService.StageVerifiedPayload("resume-stage");
var stagedResumePathAgain = PayloadService.StageVerifiedPayload("resume-stage");
Assert(stagedResumePath == stagedResumePathAgain && File.Exists(stagedResumePath), "Reboot resume must reuse the exact verified staged payload.");
File.WriteAllBytes(stagedResumePath, [0x44, 0x65, 0x76, 0x46, 0x6C, 0x65, 0x65, 0x74]);
var stagedMismatchBlocked = false;
try { PayloadService.StageVerifiedPayload("resume-stage"); } catch (InvalidDataException) { stagedMismatchBlocked = true; }
Assert(stagedMismatchBlocked, "A mismatching staged payload must be rejected rather than overwritten or trusted.");
File.Delete(stagedResumePath);
StateStore.WriteLedger(new InstallLedger { OwnedResources = [new OwnedResource("project-vm", "demo", "DevFleetLedger", Path.Combine(stateRoot, "demo"), "project-demo")] });
var allowed = PlanService.Build(InstallerMode.FactoryReset, true, true, false, true, true, "DELETE DEVFLEET", "DELETE DEVFLEET PROJECT DATA");
Assert(!allowed.IsAllowed, "Factory Reset must require an individual project selection.");

var preserveGuard = PlanService.Build(InstallerMode.CleanReinstall, false, true, false, false, false, "", "");
Assert(!preserveGuard.IsAllowed, "Clean Reinstall must not silently become project-data deletion.");

Console.WriteLine("PASS destructive safety plan tests");

var priorMarkerPlan = new InstallerPlan { Mode = InstallerMode.FreshInstall, TransactionId = new string('a', 32), AcknowledgeRootfulDocker = true };
RebootCheckpointService.PrepareScriptTransaction(priorMarkerPlan, "Primary / Desktop");
var staleStateMarker = Path.Combine(stateRoot, "stage-host-agent.complete");
var staleInstallerMarker = Path.Combine(stateRoot, "Installer", "stage-prereqs-Desktop.complete");
Directory.CreateDirectory(Path.GetDirectoryName(staleInstallerMarker)!);
var staleMarker = JsonSerializer.Serialize(new { transactionId = priorMarkerPlan.TransactionId, payloadSha256 = PayloadManifest.PayloadSha256, action = "FreshInstall", role = "Desktop", stage = "stage-host-agent", completedUtc = DateTime.UtcNow.ToString("O") });
File.WriteAllText(staleStateMarker, staleMarker);
File.WriteAllText(staleInstallerMarker, staleMarker);
var nextMarkerPlan = new InstallerPlan { Mode = InstallerMode.FreshInstall, TransactionId = new string('b', 32), AcknowledgeRootfulDocker = true };
RebootCheckpointService.PrepareScriptTransaction(nextMarkerPlan, "Primary / Desktop");
Assert(!File.Exists(staleStateMarker) && !File.Exists(staleInstallerMarker), "A new transaction must clear only stale top-level DevFleet stage markers from both canonical stage roots.");
File.WriteAllText(staleStateMarker, staleMarker.Replace(priorMarkerPlan.TransactionId, nextMarkerPlan.TransactionId, StringComparison.Ordinal));
RebootCheckpointService.PrepareScriptTransaction(nextMarkerPlan, "Primary / Desktop");
Assert(File.Exists(staleStateMarker), "Preparing the same transaction for reboot resume must preserve its stage markers.");
File.Delete(staleStateMarker);
Console.WriteLine("PASS stale stage-marker transition and same-transaction resume preservation");

var rebootPlan = new InstallerPlan { Mode = InstallerMode.FreshInstall, AcknowledgeRootfulDocker = true };
RebootCheckpointService.PrepareScriptTransaction(rebootPlan, "Primary / Desktop");
using (var activeTransaction = JsonDocument.Parse(File.ReadAllText(Path.Combine(stateRoot, "active-transaction.json"))))
    Assert(activeTransaction.RootElement.GetProperty("acknowledgeRootfulDocker").GetBoolean(), "Active transaction did not retain the reviewed rootful Docker acknowledgement.");
RebootCheckpointService.Write(rebootPlan, "Primary / Desktop", null);
var checkpointBytes = File.ReadAllBytes(RebootCheckpointService.Path);
using (var firstCheckpoint = JsonDocument.Parse(checkpointBytes))
{
    Assert(firstCheckpoint.RootElement.GetProperty("checkpointGeneration").GetInt32() == 1, "First reboot checkpoint must start at generation one.");
    Assert(firstCheckpoint.RootElement.GetProperty("resumeStage").GetString() == "bootstrap-entrypoint", "First reboot resume stage is incorrect.");
    Assert(firstCheckpoint.RootElement.GetProperty("acknowledgeRootfulDocker").GetBoolean(), "Reviewed rootful Docker acknowledgement was not persisted for reboot resume.");
}
File.WriteAllText(Path.Combine(stateRoot, "stage-prereqs-Desktop.complete"), JsonSerializer.Serialize(new { transactionId = rebootPlan.TransactionId, payloadSha256 = PayloadManifest.PayloadSha256, action = "FreshInstall", role = "Desktop", stage = "stage-prereqs-Desktop", completedUtc = DateTime.UtcNow.ToString("O") }));
RebootCheckpointService.Write(rebootPlan, "Primary / Desktop", null);
var secondCheckpointBytes = File.ReadAllBytes(RebootCheckpointService.Path);
using (var secondCheckpoint = JsonDocument.Parse(secondCheckpointBytes))
{
    Assert(secondCheckpoint.RootElement.GetProperty("checkpointGeneration").GetInt32() == 2, "Second reboot checkpoint did not advance its generation.");
    Assert(secondCheckpoint.RootElement.GetProperty("completedStages").EnumerateArray().Any(x => x.GetString() == "stage-prereqs-Desktop"), "Completed prerequisite stage was not persisted.");
    Assert(secondCheckpoint.RootElement.GetProperty("resumeStage").GetString() == "host-agent", "Second reboot resume stage did not advance.");
}
var resumedPlan = new InstallerPlan { Mode = InstallerMode.FreshInstall };
var acknowledgementMismatchBlocked = false;
try { RebootCheckpointService.ValidateIfPresent(new InstallerPlan { Mode = InstallerMode.FreshInstall, TransactionId = rebootPlan.TransactionId }, "Primary / Desktop"); } catch (InvalidDataException) { acknowledgementMismatchBlocked = true; }
Assert(acknowledgementMismatchBlocked, "Resume validation accepted a plan that omitted the durable reviewed rootful Docker acknowledgement.");
Assert(RebootCheckpointService.BindPlanIfPresent(resumedPlan, "Primary / Desktop"), "Reboot checkpoint was not discovered for plan binding.");
Assert(resumedPlan.TransactionId == rebootPlan.TransactionId && resumedPlan.AcknowledgeRootfulDocker && RebootCheckpointService.ValidateIfPresent(resumedPlan, "Primary / Desktop"), "Resume did not bind the exact transaction, reviewed acknowledgement, and generation.");
RebootCheckpointService.Consume(resumedPlan, "Primary / Desktop");
Assert(!File.Exists(RebootCheckpointService.Path), "Consumed reboot checkpoint remains present.");
Directory.CreateDirectory(Path.GetDirectoryName(RebootCheckpointService.Path)!);
File.WriteAllBytes(RebootCheckpointService.Path, checkpointBytes);
var replayBlocked = false;
try { RebootCheckpointService.BindPlanIfPresent(new InstallerPlan { Mode = InstallerMode.FreshInstall }, "Primary / Desktop"); } catch (InvalidDataException) { replayBlocked = true; }
Assert(replayBlocked, "A copied consumed reboot checkpoint must be rejected as replay.");
File.Delete(RebootCheckpointService.Path);
Console.WriteLine("PASS durable reboot transaction, generation, consumption, and replay tests");

var integrationGeneration = Guid.NewGuid().ToString("D");
var integrationLedgerPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleetHostAgent", "integration-ownership.json");
var validIntegrationLedger = new InstallLedger
{
    InstallationGeneration = integrationGeneration,
    WindowsIntegrationOwnershipPath = integrationLedgerPath,
    WindowsIntegrations =
    [
        new OwnedWindowsIntegration("ScheduledTask", "DevFleet Host Agent", integrationGeneration, "M-TechLabs DevFleet Host Agent", Executable: @"C:\Program Files\PowerShell\7\pwsh.exe", Arguments: "-File agent.ps1", Principal: "SYSTEM", LogonType: "ServiceAccount", RunLevel: "Highest", Description: $"DevFleet generation={integrationGeneration}"),
        new OwnedWindowsIntegration("FirewallRule", "DevFleetHostAgent-8790-Multipass", integrationGeneration, "M-TechLabs DevFleet Host Agent", Description: $"DevFleet generation={integrationGeneration}", DisplayName: "DevFleet Host Agent 8790 - Multipass", Group: "M-TechLabs DevFleet Host Agent", Direction: "Inbound", Action: "Allow", Protocol: "TCP", LocalPort: "8790", InterfaceAlias: "vEthernet (Default Switch)", RemoteAddress: "172.20.0.0/20", Profile: "Any")
    ]
};
OwnedPathSafety.ValidateLedger(validIntegrationLedger);
var wildcardIntegrationBlocked = false;
try
{
    var invalid = new InstallLedger { InstallationGeneration = integrationGeneration, WindowsIntegrationOwnershipPath = integrationLedgerPath, WindowsIntegrations = [validIntegrationLedger.WindowsIntegrations[0] with { Name = "DevFleet*" }] };
    OwnedPathSafety.ValidateLedger(invalid);
}
catch (InvalidDataException) { wildcardIntegrationBlocked = true; }
Assert(wildcardIntegrationBlocked, "Wildcard Windows integration ownership must be rejected.");
var partialIntegrationBlocked = false;
try
{
    var invalid = new InstallLedger { InstallationGeneration = integrationGeneration, WindowsIntegrationOwnershipPath = integrationLedgerPath, WindowsIntegrations = [validIntegrationLedger.WindowsIntegrations[1] with { RemoteAddress = "" }] };
    OwnedPathSafety.ValidateLedger(invalid);
}
catch (InvalidDataException) { partialIntegrationBlocked = true; }
Assert(partialIntegrationBlocked, "Partial Windows integration ownership must be rejected.");
Console.WriteLine("PASS Windows integration ownership ledger tests");

var desktopStages = InstallerStageCatalog.ForRole("Primary / Desktop").Select(s => s.Name).ToArray();
Assert(desktopStages.Contains("Primary compute") && !desktopStages.Contains("Vault"), "Desktop role stage map must provision Primary only.");
var laptopStages = InstallerStageCatalog.ForRole("Companion Laptop / Failover + Vault").Select(s => s.Name).ToArray();
Assert(laptopStages.Contains("Failover compute") && laptopStages.Contains("Vault"), "Laptop role stage map must provision Failover and Vault.");

var installFixture = Path.Combine(stateRoot, "release");
Directory.CreateDirectory(installFixture);
File.WriteAllText(Path.Combine(installFixture, "Install-DevFleet.ps1"), "# fixture entry point");
var desktopRunner = new RecordingProcessRunner();
var desktopReport = new InstallService(desktopRunner).Run(installFixture, "Primary / Desktop", "FreshInstall");
Assert(desktopRunner.Invocations.Count == 1, "Fresh Install must invoke the real entry point exactly once.");
Assert(desktopRunner.Invocations[0].Arguments.Contains("-Role") && desktopRunner.Invocations[0].Arguments.Contains("Desktop"), "Desktop role was not forwarded to the real installer chain.");
Assert(desktopRunner.Invocations[0].Arguments.Contains("-NonInteractive") && desktopRunner.Invocations[0].Arguments.Contains("-PackageRoot") && desktopRunner.Invocations[0].Arguments.Contains("Connected"), "Connected noninteractive contract was not forwarded.");
Assert(desktopReport.Stages.Contains("Verification"), "Verification stage is mandatory.");

var backupArchive = Path.Combine(stateRoot, "backup.tar");
File.WriteAllText(backupArchive, "verified backup");
var backupManifest = Path.Combine(stateRoot, "backup.json");
var backupHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(backupArchive))).ToLowerInvariant();
File.WriteAllText(backupManifest, System.Text.Json.JsonSerializer.Serialize(new { project_id = "project-demo", backup_id = "backup-demo", archive = backupArchive, sha256 = backupHash }));
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
                var output = Environment.GetEnvironmentVariable("DEVFLEET_SELF_TE