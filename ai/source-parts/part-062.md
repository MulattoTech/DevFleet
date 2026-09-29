# DevFleet source part 062

Full-source UTF-8 byte interval [2836500, 2883000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2ac67d4562ecd34e2dc53f6dd187397f07e624b05619f7feaa55835487ac0f62

<!-- BEGIN SOURCE SLICE -->
);
        AddText(zip, "backup-catalog.json", JsonSerializer.Serialize(new { verifiedUtc = DateTime.UtcNow.ToString("O"), backups = new ProjectDiscoveryService().Discover().Select(new BackupVerificationService().Verify).Select(x => new { x.ProjectId, x.BackupId, x.ArchivePath, x.ExpectedSha256, x.RestoreEligible, x.IsVerified }) }, new JsonSerializerOptions { WriteIndented = true }));
        AddText(zip, "dependency-inventory.json", JsonSerializer.Serialize(new { offlinePayload = false, note = "Third-party prerequisite installers are not bundled in this candidate." }, new JsonSerializerOptions { WriteIndented = true }));
        AddText(zip, "managed-integrations.json", JsonSerializer.Serialize(new { ssh = "managed blocks listed by ledger/source", vscode = "managed aliases listed by ledger/source", services = "DevFleet-owned service/task inventory required before removal", firewall = "exact DevFleet-owned rule inventory required before removal" }, new JsonSerializerOptions { WriteIndented = true }));
        AddText(zip, "recovery-instructions.txt", "Restore only to an explicitly selected DevFleet-owned destination after verifying identity and hashes. This package intentionally excludes raw private keys, tokens, passwords, and reusable credentials.\n");
        progress?.Invoke($"Recovery package created: {path}");
        return path;
    }

    private static void AddText(ZipArchive zip, string name, string value)
    {
        using var writer = new StreamWriter(zip.CreateEntry(name).Open()); writer.Write(value);
    }
}

public static class ControlPlaneSnapshotService
{
    public static string Capture(string transactionId, Action<string>? progress = null)
    {
        var source = AppPaths.InstallRoot;
        var target = Path.Combine(AppPaths.StateRoot, "Recovery", $"control-plane-{transactionId}");
        if (Directory.Exists(target)) Directory.Delete(target, true);
        if (Directory.Exists(source)) CopyDirectory(source, target);
        progress?.Invoke($"Transactional control-plane snapshot captured: {target}");
        return target;
    }

    public static void Restore(string snapshot, Action<string>? progress = null)
    {
        if (!Directory.Exists(snapshot)) throw new DirectoryNotFoundException($"Control-plane rollback snapshot is missing: {snapshot}");
        if (Directory.Exists(AppPaths.InstallRoot)) Directory.Delete(AppPaths.InstallRoot, true);
        CopyDirectory(snapshot, AppPaths.InstallRoot);
        progress?.Invoke("Transactional control-plane snapshot restored after failed replacement.");
    }

    public static void Delete(string snapshot)
    {
        if (Directory.Exists(snapshot)) Directory.Delete(snapshot, true);
    }

    private static void CopyDirectory(string source, string target)
    {
        Directory.CreateDirectory(target);
        foreach (var file in Directory.EnumerateFiles(source)) File.Copy(file, Path.Combine(target, Path.GetFileName(file)), true);
        foreach (var directory in Directory.EnumerateDirectories(source)) CopyDirectory(directory, Path.Combine(target, Path.GetFileName(directory)));
    }
}

public sealed class InstallerLogger
{
    private readonly string _path = Path.Combine(AppPaths.LogsRoot, $"setup-{DateTime.UtcNow:yyyyMMdd-HHmmss}.log");
    public string LogPath => _path;
    public InstallerLogger() => Directory.CreateDirectory(AppPaths.LogsRoot);
    public void Write(string message)
    {
        var safe = message.Replace("Bearer ", "Bearer [REDACTED]", StringComparison.OrdinalIgnoreCase);
        File.AppendAllText(_path, $"{DateTime.UtcNow:O} {safe}{Environment.NewLine}");
    }
}

public static class InstallerEngine
{
    public static string Execute(InstallerPlan plan, string role, Action<string>? progress = null) => LifecycleEngine.Execute(plan, role, progress);

    internal static void RemoveLedgerFiles(InstallLedger ledger, Action<string>? progress)
    {
        var root = Path.GetFullPath(AppPaths.InstallRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        foreach (var file in ledger.FilesInstalled.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var full = Path.GetFullPath(file);
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase) || !File.Exists(full)) continue;
            File.Delete(full);
            if (File.Exists(full)) throw new IOException($"Owned file remains after cleanup: {full}");
            progress?.Invoke($"Removed and verified owned file: {full}");
        }
    }

    private static void RemoveOwnedProjectResources(InstallLedger ledger, Action<string>? progress)
    {
        foreach (var resource in ledger.OwnedResources.Where(r => !string.IsNullOrWhiteSpace(r.ProjectId) && r.OwnerProof.Equals("DevFleetLedger", StringComparison.OrdinalIgnoreCase)))
        {
            if (string.IsNullOrWhiteSpace(resource.Path)) { progress?.Invoke($"Manual review required: owned project resource {resource.Identity} has no path."); continue; }
            var full = Path.GetFullPath(resource.Path);
            var root = Path.GetPathRoot(full);
            if (string.IsNullOrWhiteSpace(root) || full.TrimEnd(Path.DirectorySeparatorChar).Equals(root.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase) || full.TrimEnd(Path.DirectorySeparatorChar).Equals(Path.GetFullPath(AppPaths.StateRoot).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
            {
                progress?.Invoke($"Manual review required: refusing broad project target {full}.");
                continue;
            }
            if (Directory.Exists(full)) Directory.Delete(full, true);
            else if (File.Exists(full)) File.Delete(full);
            progress?.Invoke($"Removed independently proven owned project resource: {resource.Identity} ({full})");
        }
    }

    private static void CreateInstalledAppEntry(InstallLedger ledger)
    {
        using var key = Registry.LocalMachine.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\DevFleet");
        if (key is null) return;
        var exe = ledger.FilesInstalled.FirstOrDefault(p => Path.GetFileName(p).Equals("DevFleet.Setup.exe", StringComparison.OrdinalIgnoreCase)) ?? Environment.ProcessPath ?? "DevFleet.Setup.exe";
        key.SetValue("DisplayName", "DevFleet"); key.SetValue("Publisher", "M-TechLabs"); key.SetValue("DisplayVersion", PayloadManifest.DevFleetVersion); key.SetValue("InstallLocation", AppPaths.InstallRoot); key.SetValue("UninstallString", $"\"{exe}\" --maintenance --action uninstall");
        ledger.RegistryEntriesCreated.Add(@"HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\DevFleet");
    }

    private static void InstallStableLauncher(InstallLedger ledger, Action<string>? progress)
    {
        var current = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(current) || !File.Exists(current)) return;
        Directory.CreateDirectory(AppPaths.InstallRoot);
        var target = Path.Combine(AppPaths.InstallRoot, "DevFleet.Setup.exe");
        if (!Path.GetFullPath(current).Equals(Path.GetFullPath(target), StringComparison.OrdinalIgnoreCase)) File.Copy(current, target, true);
        ledger.FilesInstalled.Add(target); ledger.OwnedResources.Add(new OwnedResource("launcher", "DevFleet Setup", "DevFleetLedger", target)); progress?.Invoke($"Stable installed launcher recorded: {target}");
    }

    private static void CreateShortcuts(InstallLedger ledger, Action<string>? progress)
    {
        var exe = Environment.ProcessPath; if (string.IsNullOrWhiteSpace(exe)) return;
        var start = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "DevFleet"); Directory.CreateDirectory(start);
        foreach (var item in new[] { ("DevFleet", "--maintenance"), ("DevFleet Maintenance", "--maintenance") })
        {
            var path = Path.Combine(start, item.Item1 + ".lnk");
            try
            {
                var type = Type.GetTypeFromProgID("WScript.Shell"); if (type is null) continue;
                dynamic shell = Activator.CreateInstance(type)!; dynamic shortcut = shell.CreateShortcut(path); shortcut.TargetPath = exe; shortcut.Arguments = item.Item2; shortcut.WorkingDirectory = Path.GetDirectoryName(exe); shortcut.Description = "DevFleet maintenance and workspace tools"; shortcut.Save(); ledger.ShortcutsCreated.Add(path); progress?.Invoke($"Shortcut created: {path}");
            }
            catch { progress?.Invoke($"Shortcut creation unavailable; the stable maintenance entry remains available from Installed Apps."); }
        }
    }
}

```


## FILE: installer-source/DevFleet.Setup/app.manifest

SHA256: 78330ef35e9a02705b4d58730ee1483bda62e9998894873b2d4b497e9524c266 | Bytes: 427 | Git mode: 100644

```
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.4.1.0" name="MTechLabs.DevFleet.Setup" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>

```


## FILE: installer-source/DevFleet.Setup/dependencies.json

SHA256: b939c07de544806e87b8324c050a1a3aff6baac8b36fac57201d917ea8810b46 | Bytes: 19463 | Git mode: 100644

```
{
  "schemaVersion": 1,
  "manifestVersion": "1.2.13",
  "supportedProfile": "Windows 11 Pro x64, Internet-connected, administrator/UAC, hardware virtualization",
  "dependencies": [
    {
      "id": "powershell7",
      "displayName": "PowerShell 7",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["bootstrap", "installer"],
      "minimumSupportedVersion": "7.4.0",
      "maximumMajor": 7,
      "executableProbes": ["pwsh.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Microsoft\\PowerShellCore\\InstalledVersions"],
      "appPathsProbes": ["pwsh.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\PowerShell\\7\\pwsh.exe", "%LocalAppData%\\Microsoft\\powershell\\pwsh.exe"],
      "wingetPackageId": "Microsoft.PowerShell",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/PowerShell/PowerShell/releases/latest", "allowedHosts": ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], "assetRegex": "^PowerShell-7\\.[0-9.]+-win-x64\\.msi$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".msi"] },
      "silentInstallArguments": ["/qn", "/norestart"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["-NoProfile", "-NonInteractive", "-Command", "$PSVersionTable.PSVersion.ToString()"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, registry and known locations",
      "postInstallVersionVerification": "pwsh version >= minimum and major policy"
    },
    {
      "id": "git",
      "displayName": "Git",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["source-control", "guest-bootstrap"],
      "minimumSupportedVersion": "2.40.0",
      "maximumMajor": null,
      "executableProbes": ["git.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\GitForWindows", "HKCU:\\SOFTWARE\\GitForWindows"],
      "appPathsProbes": ["git.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Git\\cmd\\git.exe", "%LocalAppData%\\Programs\\Git\\cmd\\git.exe"],
      "wingetPackageId": "Git.Git",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/git-for-windows/git/releases/latest", "allowedHosts": ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], "assetRegex": "^Git-[0-9.]+-64-bit\\.exe$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Johannes Schindelin, O=Johannes Schindelin, L=Bruehl, C=DE"], "extensions": [".exe"] },
      "silentInstallArguments": ["/VERYSILENT", "/NORESTART", "/MERGETASKS=!runcode"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["--version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, registry and known locations",
      "postInstallVersionVerification": "git --version >= minimum"
    },
    {
      "id": "openssh-client",
      "displayName": "OpenSSH Client",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["ssh", "guest-bootstrap"],
      "minimumSupportedVersion": "8.1.0",
      "maximumMajor": null,
      "executableProbes": ["ssh.exe"],
      "registryProbes": [],
      "appPathsProbes": ["ssh.exe"],
      "knownVendorInstallLocations": ["%WINDIR%\\System32\\OpenSSH\\ssh.exe"],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "windows-capability", "metadataUri": "https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse", "allowedHosts": ["learn.microsoft.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".exe"] },
      "silentInstallArguments": [],
      "rebootSemantics": "capability-dependent",
      "versionProbe": { "arguments": ["-V"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, capability and known location",
      "postInstallVersionVerification": "ssh -V >= minimum"
    },
    {
      "id": "multipass",
      "displayName": "Multipass",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["virtualization", "ubuntu-provisioning"],
      "minimumSupportedVersion": "1.13.0",
      "maximumMajor": 1,
      "executableProbes": ["multipass.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Canonical\\Multipass"],
      "appPathsProbes": ["multipass.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Multipass\\bin\\multipass.exe", "%ProgramFiles(x86)%\\Multipass\\bin\\multipass.exe"],
      "wingetPackageId": "Canonical.Multipass",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/canonical/multipass/releases/latest", "allowedHosts": ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], "assetRegex": "(?i)^multipass.*win.*64.*\\.(msi|exe)$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=CANONICAL GROUP LIMITED, O=CANONICAL GROUP LIMITED, L=London, C=GB"], "installedExecutableTrust": "signed-installer-locked-path", "extensions": [".msi", ".exe"] },
      "silentInstallArguments": ["/quiet", "/norestart"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["version"], "regex": "(?m)^multipass\\s+(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, registry and known vendor locations",
      "postInstallVersionVerification": "multipass version and multipass list both succeed"
    },
    {
      "id": "virtualization-backend",
      "displayName": "Virtualization backend",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["multipass"],
      "minimumSupportedVersion": "0.0.0",
      "maximumMajor": null,
      "executableProbes": ["systeminfo.exe"],
      "registryProbes": [],
      "appPathsProbes": [],
      "knownVendorInstallLocations": [],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "windows-feature-or-virtualbox", "metadataUri": "https://documentation.ubuntu.com/multipass/latest/how-to-guides/install-multipass", "allowedHosts": ["documentation.ubuntu.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US", "CN=Oracle Corporation, O=Oracle Corporation, L=Redwood City, S=California, C=US"], "extensions": [] },
      "silentInstallArguments": [],
      "rebootSemantics": "feature-dependent",
      "versionProbe": { "arguments": ["/FO", "LIST"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "verify Hyper-V capability or VirtualBox installation and Multipass driver",
      "postInstallVersionVerification": "backend capability and selected driver are usable"
    },
    {
      "id": "virtualbox",
      "displayName": "Oracle VirtualBox",
      "classification": "FEATURE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["multipass", "windows-home"],
      "minimumSupportedVersion": "7.0.0",
      "maximumMajor": null,
      "executableProbes": ["VBoxManage.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Oracle\\VirtualBox", "HKLM:\\SOFTWARE\\WOW6432Node\\Oracle\\VirtualBox"],
      "appPathsProbes": ["VBoxManage.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Oracle\\VirtualBox\\VBoxManage.exe", "%ProgramFiles(x86)%\\Oracle\\VirtualBox\\VBoxManage.exe"],
      "wingetPackageId": "Oracle.VirtualBox",
      "directOfficialVendorResolver": { "type": "official-download-page", "metadataUri": "https://www.virtualbox.org/wiki/Downloads", "allowedHosts": ["www.virtualbox.org", "download.virtualbox.org"], "assetRegex": "(?i)^VirtualBox-[0-9.]+-Win\\.exe$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Oracle Corporation, O=Oracle Corporation, L=Redwood City, S=California, C=US"], "extensions": [".exe"] },
      "silentInstallArguments": ["--silent", "--msiparams", "REBOOT=ReallySuppress"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["--version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover VBoxManage from HKLM App Paths and canonical Oracle machine locations",
      "postInstallVersionVerification": "VBoxManage --version >= minimum and Multipass virtualbox driver is selected"
    },
    {
      "id": "tailscale",
      "displayName": "Tailscale",
      "classification": "ROLE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["network-pairing", "failover", "vault"],
      "minimumSupportedVersion": "1.60.0",
      "maximumMajor": 1,
      "executableProbes": ["tailscale.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Tailscale"],
      "appPathsProbes": ["tailscale.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Tailscale\\tailscale.exe", "%ProgramFiles(x86)%\\Tailscale\\tailscale.exe"],
      "wingetPackageId": "Tailscale.Tailscale",
      "directOfficialVendorResolver": { "type": "official-download-page", "metadataUri": "https://tailscale.com/download/windows", "allowedHosts": ["tailscale.com", "pkgs.tailscale.com"], "assetRegex": "(?i)^tailscale-setup-latest\\.(exe|msi)$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Tailscale Inc., O=Tailscale Inc., L=Toronto, S=Ontario, C=CA, SERIALNUMBER=1131559-5, OID.2.5.4.15=Private Organization, OID.1.3.6.1.4.1.311.60.2.1.3=CA"], "extensions": [".exe", ".msi"] },
      "silentInstallArguments": ["/quiet"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, registry and known locations",
      "postInstallVersionVerification": "tailscale version succeeds; auth remains explicit/deferred"
    },
    {
      "id": "vscode",
      "displayName": "VS Code",
      "classification": "RECOMMENDED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["editor", "remote-development"],
      "minimumSupportedVersion": "1.90.0",
      "maximumMajor": null,
      "executableProbes": ["code.cmd", "code.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"],
      "appPathsProbes": ["code.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Microsoft VS Code\\bin\\code.cmd", "%LocalAppData%\\Programs\\Microsoft VS Code\\bin\\code.cmd"],
      "wingetPackageId": "Microsoft.VisualStudioCode",
      "directOfficialVendorResolver": { "type": "official-download-page", "metadataUri": "https://code.visualstudio.com/Download", "directUri": "https://update.code.visualstudio.com/latest/win32-x64/stable", "allowedHosts": ["code.visualstudio.com", "update.code.visualstudio.com", "vscode.download.prss.microsoft.com"], "assetRegex": "(?i)^VSCodeSetup-x64-[0-9.]+\\.exe$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".exe"] },
      "silentInstallArguments": ["/VERYSILENT", "/NORESTART"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["--version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover code.cmd/code.exe via PATH, registry and known locations",
      "postInstallVersionVerification": "code --version >= minimum"
    },
    {
      "id": "github-cli",
      "displayName": "GitHub CLI",
      "classification": "RECOMMENDED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["GitHub integration"],
      "minimumSupportedVersion": "2.40.0",
      "maximumMajor": null,
      "executableProbes": ["gh.exe"],
      "registryProbes": [],
      "appPathsProbes": ["gh.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\GitHub CLI\\gh.exe", "%LocalAppData%\\Programs\\GitHub CLI\\gh.exe"],
      "wingetPackageId": "GitHub.cli",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/cli/cli/releases/latest", "allowedHosts": ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], "assetRegex": "(?i)^gh_.*_windows_amd64\\.msi$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=GitHub, Inc., O=GitHub, Inc., L=San Francisco, S=California, C=US"], "extensions": [".msi"] },
      "silentInstallArguments": ["/qn", "/norestart"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["--version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths and known locations",
      "postInstallVersionVerification": "gh --version >= minimum"
    },
    {
      "id": "sevenzip",
      "displayName": "7-Zip",
      "classification": "OPTIONAL",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["encrypted-transfer-bundle"],
      "minimumSupportedVersion": "23.0.0",
      "maximumMajor": null,
      "executableProbes": ["7z.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\7-Zip", "HKLM:\\SOFTWARE\\WOW6432Node\\7-Zip"],
      "appPathsProbes": ["7z.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\7-Zip\\7z.exe", "%ProgramFiles(x86)%\\7-Zip\\7z.exe"],
      "wingetPackageId": "7zip.7zip",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/ip7z/7zip/releases/latest", "officialPageUri": "https://www.7-zip.org/download.html", "expectedOwner": "ip7z", "expectedRepository": "7zip", "allowedHosts": ["api.github.com", "github.com", "release-assets.githubusercontent.com"], "assetRegex": "(?i)^7z\\d+-x64\\.exe$", "officialPageAssetRegex": "(?i)^7z\\d+-x64\\.exe$" },
      "installerAuthenticityPolicy": { "strategy": "VendorReleaseSha256", "required": true, "allowedSignerSubjectsExact": ["CN=Igor Pavlov"], "extensions": [".exe"] },
      "silentInstallArguments": ["/S"],
      "rebootSemantics": "0",
      "versionProbe": { "arguments": [], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, registry and known locations",
      "postInstallVersionVerification": "7z executable is present and responds"
    },
    {
      "id": "remote-ssh-extension",
      "displayName": "Remote SSH extension",
      "classification": "FEATURE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["remote-development"],
      "minimumSupportedVersion": "0.0.0",
      "maximumMajor": null,
      "executableProbes": ["code.cmd"],
      "registryProbes": [],
      "appPathsProbes": [],
      "knownVendorInstallLocations": [],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "vscode-extension", "metadataUri": "https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh", "allowedHosts": ["marketplace.visualstudio.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".vsix"] },
      "silentInstallArguments": ["--install-extension", "ms-vscode-remote.remote-ssh", "--force"],
      "rebootSemantics": "0",
      "versionProbe": { "arguments": [], "regex": null },
      "postInstallExecutableDiscovery": "resolve VS Code CLI and inspect extension list",
      "postInstallVersionVerification": "code --list-extensions contains ms-vscode-remote.remote-ssh"
    },
    {
      "id": "remote-explorer-extension",
      "displayName": "Remote Explorer extension",
      "classification": "FEATURE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["remote-development"],
      "minimumSupportedVersion": "0.0.0",
      "maximumMajor": null,
      "executableProbes": ["code.cmd"],
      "registryProbes": [],
      "appPathsProbes": [],
      "knownVendorInstallLocations": [],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "vscode-extension", "metadataUri": "https://marketplace.visualstudio.com/items?itemName=ms-vscode.remote-explorer", "allowedHosts": ["marketplace.visualstudio.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".vsix"] },
      "silentInstallArguments": ["--install-extension", "ms-vscode.remote-explorer", "--force"],
      "rebootSemantics": "0",
      "versionProbe": { "arguments": [], "regex": null },
      "postInstallExecutableDiscovery": "resolve VS Code CLI and inspect extension list",
      "postInstallVersionVerification": "code --list-extensions contains ms-vscode.remote-explorer"
    },
    {
      "id": "dev-containers-extension",
      "displayName": "Dev Containers extension",
      "classification": "FEATURE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["remote-development", "containers"],
      "minimumSupportedVersion": "0.0.0",
      "maximumMajor": null,
      "executableProbes": ["code.cmd"],
      "registryProbes": [],
      "appPathsProbes": [],
      "knownVendorInstallLocations": [],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "vscode-extension", "metadataUri": "https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers", "allowedHosts": ["marketplace.visualstudio.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".vsix"] },
      "silentInstallArguments": ["--install-extension", "ms-vscode-remote.remote-containers", "--force"],
      "rebootSemantics": "0",
      "versionProbe": { "arguments": [], "regex": null },
      "postInstallExecutableDiscovery": "resolve VS Code CLI and inspect extension list",
      "postInstallVersionVerification": "code --list-extensions contains ms-vscode-remote.remote-containers"
    }
  ]
}

```


## FILE: installer-source/FACTORY-RESET.md

SHA256: e1c8f955b9b807a059d0c5545f0d308ffd56ca2055e090bbd82da2bd4d935392 | Bytes: 411 | Git mode: 100644

```
# Factory Reset

Control-plane removal requires `DELETE DEVFLEET`. Project data is off by default and additionally requires `DELETE DEVFLEET PROJECT DATA`, individual VERIFIED project selection, independently verified ownership, a restore-eligible exact backup whose archive hash and identities match, and submission of that exact backup ID/SHA to the Host Agent. Ambiguous or unrelated VMs cannot be selected.

```


## FILE: installer-source/Fast-Rebuild-Installer.ps1

SHA256: 7b5fd125f969ae691b2af65e11f5ecb222cad8cca7f92eb30d2f046bb36f0d4d | Bytes: 1057 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[string]$DotNet='dotnet',[switch]$UnsignedDeveloperBuild)
$ErrorActionPreference='Stop';$root=$PSScriptRoot;$version=(Get-Content -LiteralPath (Join-Path $root '..\source\VERSION') -Raw -ErrorAction Stop).Trim();if(-not $version){throw 'Source VERSION is empty.'}
if(-not $UnsignedDeveloperBuild){throw 'Fast rebuild is developer-only and requires -UnsignedDeveloperBuild; it never produces a release artifact.'}
$publish=Join-Path $OutputDirectory 'publish-fast';New-Item -ItemType Directory -Path $publish -Force|Out-Null
& $DotNet publish (Join-Path $root 'DevFleet.Setup\DevFleet.Setup.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $publish
if($LASTEXITCODE){throw 'Fast installer rebuild failed.'}
Copy-Item -LiteralPath (Join-Path $publish 'DevFleet.Setup.exe') -Destination (Join-Path $OutputDirectory "DevFleet-Setup-v$version-win-x64.exe") -Force
Write-Warning "Fast installer rebuild complete as an explicitly unsigned developer artifact."

```


## FILE: installer-source/INSTALLER-ARCHITECTURE.md

SHA256: 1ad6db013cc9910bf74852c5de3b365f89183d94df9c82efaf2ed2257ffd10b1 | Bytes: 483 | Git mode: 100644

```
# Installer Architecture

The wizard is a native WPF shell around bounded services: preflight, payload hash verification, staging, TAR extraction, recovery packaging, atomic ledger writes, ownership-aware plan generation, and selective cleanup. The embedded DevFleet TAR is verified before it is staged or extracted.

The application does not use a browser UI, winget, runtime network downloads, broad VM wildcards, or the user's entire SSH/VS Code configuration as cleanup targets.

```


## FILE: installer-source/INSTALLER-BUILD-MANIFEST.json

SHA256: daec80a6ce234bbdf9c29b823e98b8d4878a5181203afe2a5162efbe8b126cb5 | Bytes: 594 | Git mode: 100644

```
{
  "installerProduct": "DevFleet Setup",
  "installerVersion": "1.4.1",
  "devfleetVersion": "1.2.13",
  "targetRuntime": "win-x64",
  "framework": "net8.0-windows",
  "selfContained": true,
  "singleFile": true,
  "payload": {
    "name": "devfleet-v1.2.13.tar.gz",
    "sha256": "e3176c500f652d6023dcb611ccd580567ed9448da343a5fd4c3649214ca0b654"
  },
  "signing": "PRIVATE SELF-SIGNED AUTHENTICODE — exact candidate signing and verification required before release eligibility",
  "runtimeNetworkDownloads": false,
  "productionMutationPerformed": false,
  "releaseInputsPrepared": true
}

```


## FILE: installer-source/INSTALLER-OWNERSHIP-MODEL.md

SHA256: 8a8ddc95b7204e0cfb2a934d57e0b66064361ba179d0ed699a6b32e99050cd70 | Bytes: 342 | Git mode: 100644

```
# Ownership Model

The ledger records files, shortcuts, registry entries, prerequisites installed by DevFleet, and DevFleet resource references. A ledger entry is not sufficient by itself for project VM deletion: project ID, resource identity, provider metadata, and backup identity must agree. Ambiguity means manual review and no deletion.

```


## FILE: installer-source/INSTALLER-RECOVERY-MODEL.md

SHA256: cfce34a874dc2598aca6fa6fc09481f219ea075edcd7c9d9abb9bd3f7925baca | Bytes: 343 | Git mode: 100644

```
# Recovery Model

Clean Reinstall, Uninstall, and Factory Reset create a metadata-only recovery ZIP before mutation. The package contains the ledger, payload hash, transaction ID, and instructions, never raw reusable private secrets. The operation log exposes failure and rollback limitations rather than claiming a hidden rollback succeeded.

```


## FILE: installer-source/INSTALLER-REMOVAL-SAFETY.md

SHA256: 36bd15741d36375c356ed67dc2a2e11fd3e79644d7ddd47ba2d5c1381d8c9f06 | Bytes: 401 | Git mode: 100644

```
# Removal Safety

Uninstall and Factory Reset remove only paths listed in the installer ledger and confined under the installed DevFleet root. Project-data deletion is separately gated by typed confirmation, a verified backup, and an independently proven project ownership record. Unrelated VMs, SSH entries, VS Code mappings, firewall rules, and shared prerequisites remain outside the action scope.

```


## FILE: installer-source/INSTALLER-THREAT-MODEL.md

SHA256: 4d567512f3cf645aa23661e5331bef819e3d30ccfc0d8c62e85ae6c70e4600a2 | Bytes: 792 | Git mode: 100644

```
# Installer Threat Model

- Corrupted embedded payload: rejected by SHA-256 before staging and again before extraction.
- Ambiguous ownership: destructive project-data scope is blocked unless a ledger resource has an explicit project ID and DevFleet ownership proof.
- Accidental cleanup: Factory Reset requires exact phrases; Clean Reinstall defaults to preservation.
- Interrupted mutation: transaction and log state are written before and after bounded operations; recovery packages are created before reinstall/removal.
- Secret leakage: recovery content is metadata-only and logs redact bearer tokens; private keys and reusable credentials are excluded.
- Supply chain: no third-party binaries are bundled; the build records the official SDK source and installer is explicitly unsigned.

```


## FILE: installer-source/INSTALLER_VERSION

SHA256: 7d072b48526b023950e4c48db01e8c273554a6401119f5691e7589ba9bc65d9d | Bytes: 6 | Git mode: 100644

```
1.4.1

```


## FILE: installer-source/MAINTENANCE.md

SHA256: cc39483c6b9f4a10009a752c3740b3cef7143ff644c65adc15f91bd6bd01524a | Bytes: 329 | Git mode: 100644

```
# Maintenance

The installed launcher supports Diagnostics, Repair, Local Update, Recovery Package, Clean Reinstall, Uninstall, Factory Reset, and deferred network pairing. Repair invokes the production install orchestrator. Local Update accepts an explicitly selected trusted local release; no unsecured update URL is invented.

```


## FILE: installer-source/MULTIPASS-E2E.md

SHA256: 621ea3f6cd12b061299b84d8bfc253fbdc61a3df6ae219adf49a73388a975e26 | Bytes: 328 | Git mode: 100644

```
# Multipass E2E

The mandatory clean-room gate requires real `multipass version`, `multipass list`, and
`multipass launch` on disposable Windows. Record backend, Ubuntu image, cloud-init,
guest bootstrap, Docker/runtime, SSH, service health, dashboard, stop/start, and cleanup.
Production VMs are never used for destructive QA.

```


## FILE: installer-source/OFFLINE-DEPENDENCIES.json

SHA256: ebae2e37de6de3d13ca931db09e4e88b96cf3ea2da6adea1400ce4cfb6937afa | Bytes: 811 | Git mode: 100644

```
{
  "schemaVersion": 2,
  "installerRevision": "1.4.1",
  "devfleetVersion": "1.2.13",
  "releaseBinding": "This manifest is part of the exact DevFleet release payload; the trusted internal release channel supplies the final release fingerprint.",
  "payloads": [],
  "bundledThirdPartyInstallers": [],
  "applicationNuGetDependencies": [],
  "buildSdk": {
    "product": ".NET SDK",
    "version": "8.0.424",
    "officialSource": "https://dotnet.microsoft.com/download/dotnet/8.0",
    "usedForBuildOnly": true
  },
  "offlineContract": "Offline installation accepts only an exact payload entry in this release-bound manifest. A sibling checksum file, duplicate, near-name candidate, or unsigned local replacement is never an authority. No offline dependency payloads are included in this private release."
}

```


## FILE: installer-source/OFFLINE-PAYLOAD-SHA256.txt

SHA256: c5841878571b984f9c696efc951eecf48e7035f218771a726e29dd858cfe93d3 | Bytes: 98 | Git mode: 100644

```
e3176c500f652d6023dcb611ccd580567ed9448da343a5fd4c3649214ca0b654  Payload/devfleet-v1.2.13.tar.gz

```


## FILE: installer-source/Prepare-ReleaseInputs.ps1

SHA256: abae53b5f93d9d403d089c9e8e99e2918d3a66e3d164072212fe660542b25b47 | Bytes: 15390 | Git mode: 100644

```
[CmdletBinding()]
param(
  [ValidateSet('Prepare','Verify')][string]$Mode = 'Prepare',
  [Parameter(Mandatory)][string]$SourceRoot,
  [Parameter(Mandatory)][string]$PreviousPortableZip,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [ValidateSet('PublicTrusted','PrivateSelfSigned')][string]$SigningProfile = 'PrivateSelfSigned',
  [string]$CandidateCommit,
  [switch]$ProveIdempotent
)
$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $normalized = [regex]::Replace($Text, "`r`n|`r", "`n")
  [IO.File]::WriteAllText($Path, $normalized, (New-Object Text.UTF8Encoding($false)))
}

function Get-Bytes([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return [IO.File]::ReadAllBytes($Path)
}

function Get-Snapshot([string]$Source, [string]$Installer) {
  $version = (Get-Content -LiteralPath (Join-Path $Source 'VERSION') -Raw).Trim()
  $payload = Join-Path $Installer "DevFleet.Setup\Payload\devfleet-v$version.tar.gz"
  $relative = @(
    'source/CHECKSUMS.sha256',
    'installer-source/DevFleet.Setup/dependencies.json',
    'installer-source/OFFLINE-PAYLOAD-SHA256.txt',
    'installer-source/DevFleet.Setup/PayloadManifest.cs',
    'installer-source/DevFleet.Setup/DevFleet.Setup.csproj',
    'installer-source/DevFleet.Setup/app.manifest',
    'installer-source/INSTALLER-BUILD-MANIFEST.json',
    "installer-source/DevFleet.Setup/Payload/devfleet-v$version.tar.gz"
  )
  $snapshot = [ordered]@{}
  foreach ($item in $relative) {
    $path = Join-Path (Split-Path -Parent $Source) ($item.Replace('/', '\'))
    if ($item.StartsWith('source/')) { $path = Join-Path $Source $item.Substring(7).Replace('/', '\') }
    elseif ($item.StartsWith('installer-source/')) { $path = Join-Path $Installer $item.Substring(17).Replace('/', '\') }
    $bytes = Get-Bytes $path
    $snapshot[$item] = if ($null -eq $bytes) { $null } else { [Convert]::ToBase64String($bytes) }
  }
  return $snapshot
}

function Invoke-Prepare([string]$Source, [string]$Installer, [string]$Previous, [string]$Outputs) {
  $devfleetVersion = (Get-Content -LiteralPath (Join-Path $Source 'VERSION') -Raw).Trim()
  $installerVersion = (Get-Content -LiteralPath (Join-Path $Installer 'INSTALLER_VERSION') -Raw).Trim()
  if ($devfleetVersion -notmatch '^\d+\.\d+\.\d+$') { throw "Release source VERSION is not semantic: $devfleetVersion" }
  if ($installerVersion -notmatch '^\d+\.\d+\.\d+$') { throw "Installer VERSION is not semantic: $installerVersion" }
  New-Item -ItemType Directory -Path $Outputs -Force | Out-Null

  $sourceDependencies = Join-Path $Source 'dependencies.json'
  $installerDependencies = Join-Path $Installer 'DevFleet.Setup\dependencies.json'
  Copy-Item -LiteralPath $sourceDependencies -Destination $installerDependencies -Force
  if ((Get-FileHash -LiteralPath $sourceDependencies -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $installerDependencies -Algorithm SHA256).Hash) {
    throw 'Installer dependency manifest is not byte-identical to the canonical source manifest.'
  }

  & python (Join-Path $Source 'tools\build_release.py') --source $Source --old-portable $Previous --output-dir $Outputs
  if ($LASTEXITCODE) { throw 'DevFleet TAR/portable release build failed while preparing release inputs.' }
  $tar = Join-Path $Outputs "devfleet-v$devfleetVersion.tar.gz"
  $hash = (Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash.ToLowerInvariant()
  $payload = Join-Path $Installer 'DevFleet.Setup\Payload'
  Get-ChildItem -LiteralPath $payload -Filter '*.tar.gz' -File -ErrorAction SilentlyContinue | Remove-Item -Force
  Copy-Item -LiteralPath $tar -Destination (Join-Path $payload (Split-Path -Leaf $tar)) -Force

  $manifestText = @"
namespace DevFleet.Setup;

internal static class PayloadManifest
{
    public const string DevFleetVersion = "$devfleetVersion";
    public const string InstallerVersion = "$installerVersion";
    public const string PayloadName = "devfleet-v$devfleetVersion.tar.gz";
    public const string PayloadSha256 = "$hash";
}
"@
  Write-Utf8NoBom (Join-Path $Installer 'DevFleet.Setup\PayloadManifest.cs') $manifestText

  $project = Join-Path $Installer 'DevFleet.Setup\DevFleet.Setup.csproj'
  $projectText = Get-Content -LiteralPath $project -Raw
  $projectText = [regex]::Replace($projectText, '<Version>[^<]+</Version>', "<Version>$installerVersion</Version>")
  $projectText = [regex]::Replace($projectText, '<FileVersion>[^<]+</FileVersion>', "<FileVersion>$installerVersion.0</FileVersion>")
  $projectText = [regex]::Replace($projectText, '<InformationalVersion>[^<]+</InformationalVersion>', "<InformationalVersion>DevFleet Setup $installerVersion for DevFleet $devfleetVersion</InformationalVersion>")
  $projectText = [regex]::Replace($projectText, '<EmbeddedResource Include="Payload\\devfleet-v[^"]+\.tar\.gz" />', "<EmbeddedResource Include=`"Payload\devfleet-v$devfleetVersion.tar.gz`" />")
  $projectText = [regex]::Replace($projectText, '<EmbeddedResource Include="dependencies\.json"[^>]*/>', '<EmbeddedResource Include="dependencies.json" LogicalName="DevFleet.Setup.dependencies.json" />')
  Write-Utf8NoBom $project ($projectText.TrimEnd("`r", "`n") + [Environment]::NewLine)

  $applicationManifest = Join-Path $Installer 'DevFleet.Setup\app.manifest'
  $applicationManifestText = Get-Content -LiteralPath $applicationManifest -Raw
  $assemblyVersion = "$installerVersion.0"
  $applicationManifestText = [regex]::Replace($applicationManifestText, '(<assemblyIdentity\s+version=")[^"]+("\s+name="MTechLabs\.DevFleet\.Setup"\s*/>)', ("`${1}" + $assemblyVersion + '$2'))
  Write-Utf8NoBom $applicationManifest $applicationManifestText

  $offline = "$( $hash )  Payload/devfleet-v$devfleetVersion.tar.gz`n"
  Write-Utf8NoBom (Join-Path $Installer 'OFFLINE-PAYLOAD-SHA256.txt') $offline

  $signing = if ($SigningProfile -eq 'PrivateSelfSigned') {
    'PRIVATE SELF-SIGNED AUTHENTICODE — exact candidate signing and verification required before release eligibility'
  } else {
    'PUBLIC TRUSTED AUTHENTICODE — exact candidate signing and verification required before release eligibility'
  }
  $buildManifest = [ordered]@{
    installerProduct = 'DevFleet Setup'
    installerVersion = $installerVersion
    devfleetVersion = $devfleetVersion
    targetRuntime = 'win-x64'
    framework = 'net8.0-windows'
    selfContained = $true
    singleFile = $true
    payload = [ordered]@{ name = "devfleet-v$devfleetVersion.tar.gz"; sha256 = $hash }
    signing = $signing
    runtimeNetworkDownloads = $false
    productionMutationPerformed = $false
    releaseInputsPrepared = $true
  }
  Write-Utf8NoBom (Join-Path $Installer 'INSTALLER-BUILD-MANIFEST.json') (($buildManifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine)
  return [pscustomobject]@{ Version = $devfleetVersion; Tar = $tar; Portable = (Join-Path $Outputs "DevFleet-v$devfleetVersion-Portable-Codebase-Verified-r1.zip"); TarSha256 = $hash }
}

function Assert-SameSnapshot($Before, $After, [string]$Label) {
  foreach ($key in $Before.Keys) {
    if ($Before[$key] -ne $After[$key]) { throw "Release input preparation is not idempotent ($Label): $key changed." }
  }
}

function Normalize-TextTree([string]$Root) {
  foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes -contains 0) { continue }
    try { $text = [Text.Encoding]::UTF8.GetString($bytes) } catch { continue }
    if ($text.IndexOf([char]0) -ge 0) { continue }
    $normalized = [regex]::Replace($text, "`r`n|`r", "`n")
    if ($normalized -cne $text) { Write-Utf8NoBom $file.FullName $normalized }
  }
}

function Copy-ReleaseTree([string]$Source, [string]$Destination) {
  $excluded = @('.git', '.test-runtime', '.pytest_cache', '__pycache__', 'runtime-migrations', 'bin', 'obj')
  foreach ($file in Get-ChildItem -LiteralPath $Source -Recurse -File) {
    $relative = $file.FullName.Substring($Source.Length).TrimStart('\')
    $parts = $relative -split '\\'
    if ($parts | Where-Object { $excluded -contains $_ -or $_ -like '.venv*' }) { continue }
    $target = Join-Path $Destination $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
  }
}

function Copy-PreparedShippingInputs([string]$PreparedSource, [string]$PreparedInstaller, [string]$Source, [string]$Installer) {
  $version = (Get-Content -LiteralPath (Join-Path $PreparedSource 'VERSION') -Raw).Trim()
  $copyPairs = @(
    @{ From = (Join-Path $PreparedSource 'CHECKSUMS.sha256'); To = (Join-Path $Source 'CHECKSUMS.sha256') },
    @{ From = (Join-Path $PreparedInstaller 'DevFleet.Setup\dependencies.json'); To = (Join-Path $Installer 'DevFleet.Setup\dependencies.json') },
    @{ From = (Join-Path $PreparedInstaller 'OFFLINE-PAYLOAD-SHA256.txt'); To = (Join-Path $Installer 'OFFLINE-PAYLOAD-SHA256.txt') },
    @{ From = (Join-Path $PreparedInstaller 'DevFleet.Setup\PayloadManifest.cs'); To = (Join-Path $Installer 'DevFleet.Setup\PayloadManifest.cs') },
    @{ From = (Join-Path $PreparedInstaller 'DevFleet.Setup\DevFleet.Setup.csproj'); To = (Join-Path $Installer 'DevFleet.Setup\Dev