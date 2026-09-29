# DevFleet source part 082

Full-source UTF-8 byte interval [3766500, 3813000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: f521fd5295c5e93b2ceb42d5e4038cc8359e22eb80ac42e5e6f4ff84583b0eab

<!-- BEGIN SOURCE SLICE -->
rInstallLocations": ["%ProgramFiles%\\Git\\cmd\\git.exe", "%LocalAppData%\\Programs\\Git\\cmd\\git.exe"],
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


## FILE: source/docs/00-HARD-STOPS-AND-ASSUMPTIONS.md

SHA256: 95f36460eee2e88d097ca0dc1f7cb4062292fc24e9702aaf2c28326127934c8f | Bytes: 3228 | Git mode: 100644

```
# Hard stops and assumptions

No unanswered design question blocked creation of this package. The installer performs preflight checks and stops before VM provisioning when a required condition is missing.

## Actual hard stops while installing

1. **Hardware virtualization must be enabled in UEFI/BIOS.**
2. **Windows Package Manager (`winget`) must work.** The included bootstrap can install PowerShell 7, but cannot repair a missing or damaged App Installer installation.
3. **Free storage:** approximately 120 GB on the desktop and 100 GB on the laptop with the default sparse VM sizes. The preflight script adjusts CPU/RAM conservatively but does not silently shrink disks.
4. **Tailscale approval:** sign in the laptop Windows host, desktop Windows host, primary VM, failover VM, and vault VM. Existing authenticated hosts are detected and skipped.
5. **Reboot:** enabling Hyper-V requires a reboot. Run the same START-HERE file again afterward.
6. **Private GitHub repositories:** browser/device authorization cannot be scripted away.
7. **Encrypted bundle passphrase:** choose at least 12 characters and keep it until both pairing transfers are complete.

## One decision to review before running

You use MuMu Player. Hyper-V can affect some Android-emulator configurations. The preflight warns when emulator/virtualization processes are running. Close MuMu before provisioning and confirm your current MuMu build works with Hyper-V before allowing a Windows edition that supports Hyper-V to enable it. On Windows Home, the package uses VirtualBox instead.

## Defaults used

- Desktop primary: up to 12 vCPU, 32 GB RAM, 220 GB sparse disk; automatically reduced for smaller hardware.
- Laptop failover: up to 4 vCPU, 8 GB RAM, 70 GB sparse disk.
- Laptop vault: up to 2 vCPU, 3 GB RAM, 160 GB sparse disk.
- Ubuntu 24.04 LTS guests.
- Ollama remains on MulattoTechBox using `oaksight-gpt-oss-20b:latest`. DevFleet prefers the configured tailnet hostname and retains `http://192.168.1.243:11434/v1` as the supported LAN fallback.
- Git identity: `Dylan Mellor <dylanmellor@gmail.com>`.
- Backups every 15 minutes.
- Quarantine review window: 30 days.
- Vault retention maintenance default: 90 days.

Edit `config/devfleet.config.json` **before the first run** to change these defaults.

## CodexPro hard limit

The package creates a project-scoped `.devfleet/codexpro-bootstrap.sh` hook, but does not contain your private CodexPro installer, credentials, or ChatGPT connector authorization. The hook executes **inside the selected project container**, which is not given the Docker socket. Exact CodexPro authentication remains an interactive/product-specific step.

## v1.1.0 additions

Clean installation defaults to Balanced/rootless on CodexDevVM and rootless on failover. Upgrade defaults remain Strict/rootless. Rootful bootstrap requires a separately provisioned privileged helper and fails closed when it is unavailable. Installation stops for missing virtualization, winget, disk capacity, reboot requirements, Tailscale/GitHub authorization, failed mount isolation, failed snapshots, or missing encrypted-bundle passphrases. CodexPro private authorization remains the only intentionally manual adapter input.

```


## FILE: source/docs/01-ARCHITECTURE.md

SHA256: 6b2d8c54bdef789c3fd80a6b6512a38d657c38bfb1a2e9a0b8bddd86809f3dc9 | Bytes: 2879 | Git mode: 100644

````
# Architecture

```text
Laptop Windows — trusted recovery side
├─ Tailscale client + VS Code
├─ devfleet-failover Ubuntu VM
│  ├─ rootless Docker by default
│  ├─ project containers
│  └─ DevFleet dashboard/API
├─ devfleet-vault Ubuntu VM
│  ├─ no Docker
│  ├─ append-only rest-server
│  └─ client-side encrypted restic repository
└─ optional encrypted offline vault exports

Desktop Windows — heavy disposable compute
├─ Tailscale client + VS Code
├─ Ollama / RX 7900 XTX service remains on Windows
└─ devfleet-primary Ubuntu VM (friendly name: CodexDevVM)
   ├─ rootless Docker on a clean Balanced install
   ├─ project containers
   └─ DevFleet dashboard/API

GitHub
└─ off-device committed history
```

## Isolation layers

1. Windows files are outside the VMs.
2. Multipass host-directory mounting is disabled globally with `local.privileged-mounts=false`.
3. Docker runs inside each disposable compute VM. Clean installations use rootless Docker. Strict mode requires rootless Docker; an explicit rootful configuration requires acknowledgement and a separately provisioned privileged helper. Bootstrap does not grant docker-group access or provision that helper. Docker TCP and Windows folder mounts remain disabled.
4. A project may bind only relative paths within its own project directory. Absolute, parent-directory, Windows, UNC, and Docker-socket mounts are blocked before startup.
5. CodexPro hooks run inside project containers, not on the VM control plane.
6. Compute nodes receive append-only vault credentials. Vault pruning requires a separate laptop-admin action.

## Dashboard redundancy

The two dashboards are stateless peers. Either one can display/control its local node and proxy safe project actions to the other over a random API token on Tailscale.

The dashboards are deliberately **not** a shared multi-writer database and do not automatically promote a project. Projects are recovered to the other node from restic or GitHub. Peer-unreachable and peer-running states require explicit override before start.

## What the dashboard cannot do

- start a Windows VM that is currently stopped—the desktop shortcut performs that job;
- delete or purge a Multipass VM;
- access the vault filesystem directly;
- prune/forget vault snapshots;
- permanently delete quarantined projects;
- mount or browse Windows drives.

Keeping these powers out of the web service is part of the security design, not an unfinished feature.

## v1.1.0 control plane

`devfleet-primary` is displayed as `CodexDevVM`; it is not renamed. Both compute VMs run the same authenticated FastAPI dashboard. The VM-level controller can use the selected Docker socket, while application containers cannot. The laptop remains the primary UI and hosts failover plus the Docker-free append-only vault.

````


## FILE: source/docs/02-INSTALL-ORDER.md

SHA256: 4ed32904f5194bf15804565bbd254bcb91479b7b87552780723c737f6b92d75e | Bytes: 4071 | Git mode: 100644

````
# Exact installation order

Extract the package into a local folder on both computers. Keep the same package version on each computer.

## Phase A — laptop first

Double-click:

```text
START-HERE-LAPTOP.cmd
```

Or run manually from an elevated PowerShell 7 window:

```powershell
pwsh -File .\Install-DevFleet.ps1 -Role Laptop
```

The laptop phase:

1. checks virtualization, disk, RAM, CPU, Windows edition, and emulator conflicts;
2. installs/updates PowerShell, Git, VS Code, Tailscale, 7-Zip, GitHub CLI, OpenSSH Client, Multipass, and Hyper-V or VirtualBox;
3. disables Multipass host mounts;
4. connects the Windows host to Tailscale;
5. creates `devfleet-failover` and `devfleet-vault`;
6. installs rootless Docker and the failover dashboard;
7. installs the Vault Tailscale client from its verified signed repository, performs protected OAuth enrollment, verifies its authenticated private address, then installs the append-only vault service;
8. connects the failover VM to Tailscale;
9. initializes encrypted 15-minute backups;
10. creates shortcuts;
11. writes an encrypted `devfleet-laptop-bootstrap-*.dfe` bundle under `C:\ProgramData\DevFleet\exports`.

If Windows requests a reboot, reboot and double-click the same file again. Existing completed resources are reused; the installer refuses automatic VM destruction.

Laptop / Failover / Vault installation and Repair require connected Tailscale pairing. Normal setup uses the protected OAuth client-secret workflow with deterministic `tag:devfleet` identities; browser/device approval is manual recovery only. The Desktop-only deferral option cannot complete this role because Vault service and backup transport require authenticated Tailscale addresses. On Desktop, complete deferred pairing by running Repair with the deferral option cleared.

Copy the generated encrypted bundle to the desktop. Keep its passphrase.

## Phase B — desktop

Double-click:

```text
START-HERE-DESKTOP.cmd
```

Enter the laptop bootstrap bundle path when prompted. Manual equivalent:

```powershell
pwsh -File .\Install-DevFleet.ps1 -Role Desktop `
  -BundlePath "X:\Path\devfleet-laptop-bootstrap-YYYYMMDD-HHMMSS.dfe"
```

The desktop phase creates the primary VM, imports vault access, pairs primary-to-failover control, and outputs `devfleet-desktop-pairing-*.dfe` under `C:\ProgramData\DevFleet\exports`.

Copy that pairing bundle back to the laptop.

## Phase C — finish two-way pairing on laptop

Open PowerShell 7 as Administrator in the extracted package folder:

```powershell
pwsh -File .\windows\Complete-Cluster.ps1 `
  -DesktopPairingBundlePath "X:\Path\devfleet-desktop-pairing-YYYYMMDD-HHMMSS.dfe"
```

## Phase D — GitHub authentication

Run the command only on the physical computer that locally owns each VM:

```powershell
# Desktop
pwsh -File .\windows\Configure-GitHub.ps1 -InstanceName devfleet-primary

# Laptop
pwsh -File .\windows\Configure-GitHub.ps1 -InstanceName devfleet-failover
```

Approve the browser/device flow.

## Phase E — validate before real work

```powershell
pwsh -File .\windows\Test-DevFleet.ps1 -AllLocalInstances
pwsh -File .\tools\Verify-Package.ps1
```

Then:

1. use **DevFleet – Show Credentials**;
2. open **DevFleet – Open Dashboard**;
3. create a `generic` project named `devfleet-smoke-test`;
4. start it and confirm the analyzer has no blockers;
5. wait at least 15 minutes and confirm a backup timestamp appears;
6. quarantine and restore the test project;
7. stop/delete the test project only after confirming recovery works.

## v1.1.0 client completion

After pairing, `Complete-Cluster.ps1` configures the SSH aliases and core VS Code extensions. Re-run `client\Configure-VSCode.ps1` for optional language groups, optionally run `client\Configure-DockerContext.ps1`, then configure/test Ollama on MulattoTechBox. The clean desktop install uses rootless Docker; a v1.0 upgrade stays rootless. Existing explicit Docker mode choices are preserved during schema-2 migration. For upgrades, use `Upgrade-DevFleet.ps1` rather than the clean installer.

````


## FILE: source/docs/03-DAILY-USE.md

SHA256: 9c528be76c5285ec85c9eb2ae71fb68ac551dff06c54aef64d5b5c4f67013eb4 | Bytes: 2726 | Git mode: 100644

````
# Daily use

## Start from either computer

Double-click **DevFleet – Open Dashboard**. The shortcut starts that computer's local compute VM, finds its Tailscale IP, and opens the dashboard. Use **DevFleet – Show Credentials** for the random local dashboard password.

Double-click **DevFleet – Open VS Code** to connect through standard OpenSSH over Tailscale. Select a project and run:

```text
Dev Containers: Reopen in Container
```

## Create a project

The dashboard accepts:

- a lowercase project slug;
- display name;
- generic, Python, or Node template;
- optional GitHub HTTPS/SSH repository URL;
- local or peer target node.

Each generated project has `.devcontainer`, `.devfleet`, and a hardened Compose definition. The analyzer blocks startup for privileged containers, host networking, dangerous capabilities, Docker sockets, absolute host paths, Windows/UNC paths, or `../` sibling-workspace mounts.

## Delete safely

The dashboard action is named **Quarantine**, not permanent delete. It:

1. stops the container;
2. requires a successful immediate backup;
3. moves the directory to a timestamped quarantine path;
4. leaves it available for one-click restore.

Permanent purge is separate and confirmation-protected:

```powershell
pwsh -File .\windows\Invoke-Quarantine-Maintenance.ps1 `
  -InstanceName devfleet-primary -OlderThanDays 30
```

Run the equivalent against `devfleet-failover` only after checking its backups.

## Failover

When the desktop is unavailable:

1. open the laptop dashboard;
2. restore a new copy from the vault or clone from GitHub;
3. verify the primary is truly down/not writing;
4. check **failover override**;
5. start the recovered project.

When the desktop returns, stop one writer first. Commit/push or back up the failover changes, then restore/merge on the primary. Never intentionally run the same project on both nodes.

## Updates

Ubuntu unattended security updates are enabled. Use **DevFleet – Update Safely** for reviewed host/guest updates. Multipass is excluded by default because hypervisor upgrades deserve a current backup and explicit `-IncludeMultipass` choice.

## Offline vault copy

On the laptop, periodically use **DevFleet – Export Offline Vault Copy** and choose an external drive. The export stops the REST service briefly, copies the already encrypted repository, writes a SHA-256 file, and restarts the service. Disconnect the drive afterward.

## v1.1.0 daily workflow

Open the dashboard shortcut on either computer, create a language-aware project, then use `ssh CodexDevVM` or VS Code Remote SSH. Routine start/stop/health/test/rebuild operations are nonblocking and expose operation IDs, progress, timestamps, results, and logs.

````


## FILE: source/docs/04-RECOVERY.md

SHA256: ab36d4634d1477f69ef0c4b910dcfa16b6eb157e7e72b081066ce643f36ce2e3 | Bytes: 2082 | Git mode: 100644

````
# Recovery

## Quarantined project

Use the dashboard **Restore** button. The original project path is recreated without overwriting an existing folder.

## Corrupted or missing project

Use **Restore copy from vault**. DevFleet searches snapshots newest-first and restores the newest snapshot that actually contains that project into a new `PROJECT-recovered-TIMESTAMP` directory. Existing files are not overwritten.

## Primary VM destroyed

1. Re-run the desktop START-HERE installer; it creates a new primary without automatically deleting anything.
2. Supply the laptop bootstrap bundle.
3. authenticate Tailscale/GitHub;
4. restore projects from the vault or clone from GitHub;
5. re-run the desktop pairing export and laptop completion step if credentials changed.

## Failover VM destroyed

Re-run the laptop installer **without deleting `devfleet-vault`**. Reconfigure/restore projects from the existing vault.

## Vault VM damaged

Committed work remains in GitHub. Live primary/failover copies remain usable. Restore the vault from your newest offline encrypted export only after preserving the damaged VM and validating the export checksum.

## Manual retention and integrity check

Compute nodes never run `forget` or `prune`. From the laptop only:

```powershell
pwsh -File .\windows\Invoke-Vault-Maintenance.ps1
```

The script snapshots the vault VM, stops append-only service access, applies retention locally, prunes, checks the repository, and restarts the service.

## Diagnostics

```powershell
pwsh -File .\windows\Export-Diagnostics.ps1 -AllLocalInstances
```

The resulting ZIP contains host/VM status and service logs but intentionally excludes DevFleet secrets.

## v1.1.0 guided ownership transfer

When both nodes are reachable, Transfer stops the active copy, creates/verifies an append-only backup, restores a canonical copy on the peer, transfers the ownership lease by starting only the target, and reports progress. A peer-unreachable failover requires explicit split-brain acknowledgement. Read-only status/log/backup inspection remains available.

````


## FILE: source/docs/05-SECURITY-MODEL.md

SHA256: cc5a849cfe183f417cc6ee4600c0605e5258dddf9e3fc71f7de9451a7019bf2c | Bytes: 3166 | Git mode: 100644

```
# Security model

## Project-container restrictions

Startup is blocked for:

- privileged containers;
- host networking;
- `ALL` or `SYS_ADMIN` capabilities;
- Docker socket mounts;
- absolute Linux host paths;
- Windows drive-letter or UNC paths;
- `../` parent/sibling workspace bind mounts;
- published ports that do not bind to VM loopback (`127.0.0.1` or `::1`);
- device passthrough, `volumes_from`, host namespaces, or unconfined security profiles;
- invalid Compose/devcontainer configuration.

Only project-relative bind paths and named Docker volumes are accepted by the analyzer. Generated templates also drop all capabilities and set `no-new-privileges:true`.

## Rootless control plane

Docker runs as `devrunner` inside each compute VM. Rootful Docker services are disabled. The dashboard can control the rootless daemon and VM project folders, but cannot see Windows files because none are mounted.

The dashboard's repair button runs an unprivileged user-service repair. Root/VM/package repair remains a separate Windows administrator shortcut that takes a Multipass snapshot first.

## Network and web security

- Windows hosts and all VMs connect to Tailscale.
- UFW denies inbound traffic except SSH/dashboard/vault ports on `tailscale0`.
- VS Code uses ordinary OpenSSH keys over the encrypted Tailscale network; Tailscale SSH interception is not required.
- The dashboard uses random HTTP Basic credentials and same-origin POST checks.
- Peer APIs use separate random tokens.
- Security headers disable framing and restrict content/form origins.
- Docker TCP is never exposed.

The dashboard is HTTP rather than public TLS because traffic is restricted to the encrypted tailnet. Do not expose its port through router forwarding, Funnel, Serve, public reverse proxies, or a LAN-wide firewall rule.

## Backup security

Restic encrypts before upload. The vault server is append-only and uses private per-user repository paths. Compute-node credentials can read/add snapshots but cannot prune or delete prior snapshots through the REST interface. Vault-admin retention credentials never leave the vault VM.

## Remaining risks

- Windows administrator activity or administrator-level ransomware can delete Multipass VM files.
- Laptop disk failure can destroy the online vault unless an offline export exists.
- Compromised Tailscale, GitHub, or Windows accounts can expose access.
- Malicious code can exfiltrate data present inside its own project/container.
- Explicit failover override can create divergent writers.
- A software defect in Multipass, Docker, the Linux kernel, or this package could weaken isolation.

This is defense in depth and recovery-oriented isolation, not a mathematical guarantee.

## v1.1.0 profile invariant

Balanced is a practical development profile inside an already disposable VM, not a removal of host-file or vault boundaries. Fast Trusted can relax VM-internal container hardening only after explicit acknowledgement. No profile enables Windows mounts, Docker 2375, public dashboard exposure, ordinary docker.sock mounts, vault-admin credentials, sibling-workspace access, or deletion outside approved roots.

```


## FILE: source/docs/06-CODEXPRO-INTEGRATION.md

SHA256: 04a3d4244d99396de9a9b17ed21567aa4a491e724a551b8b211cd556de88fe80 | Bytes: 3732 | Git mode: 100644

````
# CodexPro integration

DevFleet separates **VM/container lifecycle authority** from **repository-scoped coding access**.

- The authenticated DevFleet VM controller may use the selected rootless or rootful Docker socket.
- Ordinary project containers, including CodexPro tooling inside them, are not automatically given `docker.sock`.
- New projects, sibling-container operations, failover, backup, quarantine, and restore go through DevFleet.
- Each project keeps its own allowed root, metadata, logs, runtime state, prompts, and `.ai-bridge` continuity files.

Each generated project includes:

```text
.devfleet/codexpro-bootstrap.sh
.devfleet/codexpro.env.example
.devfleet/codexpro-profile.json
.devfleet/prompts/session-bootstrap.md
.devfleet/prompts/reconnect.md
.devfleet/prompts/broken-session-recovery.md
.ai-bridge/handoff-template.md
```

## Verified live capabilities

The live CodexPro interface used while building v1.1.0 exposed:

- configuration/status inspection;
- opening one configured workspace;
- project and global skill discovery;
- bounded context, file reads, writes, and exact edits;
- controlled verification commands;
- Git status/diff review;
- handoff files and read-only session browsing.

It did **not** expose a documented multi-root registration API, a connector-authorization command, hidden ChatGPT headers, model-routing controls, quota bypasses, or a public context-cache control. DevFleet does not invent those capabilities. Its closest supported architecture is a shared VM lifecycle/status controller plus a project-local CodexPro adapter and profile.

## Idempotent bootstrap adapter

When a project starts, DevFleet executes `.devfleet/codexpro-bootstrap.sh` inside that project's running container. The adapter:

1. requires the canonical root `/workspaces/<project-slug>`;
2. creates `.devfleet/runtime` and `.ai-bridge/local-agent/logs`;
3. checks the loopback health endpoint first;
4. detects the `codexpro` executable;
5. starts it with the verified `codexpro start` interface when available;
6. writes an actionable status file and log;
7. exits successfully when already healthy or when installation/authorization is the only missing manual step.

No private credential or connector URL is embedded. The only verified environment variable placed in the example file is `CODEXPRO_TOOL_CARDS=1`. The exact private/local installation source and ChatGPT connector authorization remain manual because they are not exposed by the connected tool interface.

## Project profile

The observed workspace-scoped values are preserved as documentation, not treated as a universal installer schema:

```text
defaultRoot=/workspaces/<project-slug>
allowedRoots=[/workspaces/<project-slug>]
authEnabled=true
bashMode=full
bashTranscript=full
writeMode=workspace
toolMode=full
inheritEnv=false
contextDir=.ai-bridge
maxReadBytes=180000
maxWriteBytes=1000000
maxOutputBytes=120000
maxSearchResults=200
```

Keep `.git`, dependencies, `.env*`, private keys, `.ssh`, build outputs, models, caches, coverage, and `.ai-bridge/local-agent` excluded from broad context loading. One project must not broaden its allowed root to a sibling repository. VM-level Docker actions belong to DevFleet rather than arbitrary repository code.

## Efficient session startup

The generated session prompt directs the connected assistant to call configuration/status first, self-test only when fresh/broken/reconfigured, open without a full tree, load skills and authoritative instructions, inspect Git/context selectively, prefer diffs and changed-file manifests, and update a compact handoff before context becomes crowded. This improves practical throughput without claiming that model rate limits can be changed.

````


## FILE: source/docs/07-OFFICIAL-SOURCES.md

SHA256: 24dc3b375dd5380ad3eef4d4a2b9ea3c90f02352136ceee936edde8865773429 | Bytes: 1748 | Git mode: 100644

```
# Official implementation references

These are the primary references used for the package design. Re-check them before making major architecture changes because software behavior can change.

- Microsoft Hyper-V overview: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/overview
- Canonical Multipass documentation: https://documentation.ubuntu.com/multipass/
- Multipass `local.privileged-mounts`: https://documentation.ubuntu.com/multipass/latest/reference/settings/local-privileged-mounts/
- Docker Engine install on Ubuntu: https://docs.docker.com/engine/install/ubuntu/
- Docker rootless mode: https://docs.docker.com/engine/security/rootless/
- VS Code remote Docker host / Remote SSH + Dev Containers: https://code.visualstudio.com/remote/advancedcontainers/develop-remote-host
- Tailscale Windows installation: https://tailscale.com/docs/install/windows
- restic repository preparation and password automation: https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html
- rest-server append-only and private repository behavior: https://github.com/restic/rest-server
- Ubuntu unattended upgrades: https://documentation.ubuntu.com/server/how-to/software/automatic-updates/

## v1.1.0 additional sources

- PowerShell binary/archive and installation methods: https://learn.microsoft.com/powershell/scripting/install/alternate-install-methods
- Ollama FAQ and environment configuration: https://docs.ollama.com/faq
- Ollama OpenAI compatibility: https://docs.ollama.com/openai
- VS Code remote Docker host: https://code.visualstudio.com/remote/advancedcontainers/develop-remote-host
- Multipass snapshots: https://documentation.ubuntu.com/multipass/latest/how-to-guides/manage-instances/create-a-snapshot/

```


## FILE: source/docs/08-DEVELOPMENT-PROFILES.md

SHA256: 78cdead576d5def42520f8276f09d14ebacd60fc19edf3e29f79d98a9fc1a02d | Bytes: 1940 | Git mode: 100644

````
# Development profiles

**Strict** preserves v1.0-equivalent behavior for unknown repositories, third-party Compose files, security-sensitive work, and unreviewed automation. Rootless Docker is expected; tailnet ports/shared caches are disabled; missing hardening can block.

**Balanced** is the recommended normal profile. It retains Windows-host, workspace, ownership, and vault boundaries while enabling trusted orchestration, shared caches, loopback/authenticated-tailnet ports, routine operations without repeated confirmation, and analyzer caching. Missing non-root USER, no-new-privileges, healthchecks, or fully pinned development images are warnings unless combined with a boundary escape.

**Fast Trusted Development** is explicit, visible, logged, and reversible. It can use rootful Docker inside the disposable VM and declared devices/capabilities. Application containers still do not receive docker.sock automatically. Windows folders, unauthenticated Docker TCP, vault-admin credentials, public exposure, and path/deletion boundaries remain protected.

Docker mode is a node property. Run `devfleet-docker-mode-report`, stop projects, then use `sudo devfleet-switch-docker-mode rootful --acknowledge-rootful` or `rootless`. Stores are separate and never silently migrated.

## Changing Docker mode safely

Use the Windows administrator wrapper so the authoritative schema-2 configuration and the selected VM stay aligned:

```powershell
pwsh -File .\windows\Set-DevFleetDockerMode.ps1 -NodeRole Primary -Mode rootful -AcknowledgeRootful
pwsh -File .\windows\Set-DevFleetDockerMode.ps1 -NodeRole Primary -Mode rootless
```

The wrapper verifies host-mount isolation, takes a stopped-state Multipass snapshot, records both Docker stores, requires all projects to be stopped, switches services, updates configuration, and runs a health check. It never copies, prunes, or deletes images, containers, or volumes from either store.

````


## FILE: source/docs/09-LANGUAGE-SELECTION.md

SHA256: fc1505fce91fcbc2c07793e56e49d1b1595c8fe1d1c5d0a06d61ce99d61dc9a1 | Bytes: 1091 | Git mode: 100644

```
# Language selection

These rankings are Dylan's engineering preferences, not claimed scientific model benchmarks. Defaults: Python for automation/AI/data/FastAPI; PowerShell for Windows administration; Bash/Python for Linux administration; Go for cross-platform/infrastructure CLIs; TypeScript for frontend/full-stack/extensions; C# for Windows/.NET; Java/Kotlin for enterprise; Rust for memory-sensitive components; Swift for Apple; Flutter for cross-platform mobile; SQL migrations plus typed models for relational persistence.

Core templates: `generic`, `python`, `python-fastapi`, `node`, `typescript-node`, `typescript-next`, `go-service`, `dotnet-service`, `java-spring`, `rust-service`.

Preview templates: `kotlin-service`, `php-laravel`, `ruby-rails`, `flutter`, `elixir-phoenix`, `cpp-cmake`, `shell-automation`, `data-r`, `scientific-julia`, `sql-project`.

Every generated project records language/framework/rationale/scale/intent/testing/profile/Ollama/worktree metadata in `.devfleet/project.json`, README, and architecture documentation. Avoid unnecessary polyglot designs.

```


## FILE: source/docs/10-OLLAMA-AND-GPU.md

SHA256: 1c62c6d556381f532b86eb7fe737d9e39a5726a4a457127e1adfe4a8404d9992 | Bytes: 1347 | Git mode: 100644

```
# Ollama and RX 7900 XTX

Keep Ollama on MulattoTechBox Windows unless real testing proves a better supported path. Do not assume Hyper-V/Multipass GPU passthrough. DevFleet prefers the desktop's authenticated Tailscale address and retains `http://192.168.1.243:11434/v1` as fallback. The one authoritative endpoint lives in installed schema-2 configuration and is propagated during project generation.

Profiles: Stable Interactive (low latency, 1–2 requests), Large Context (one primary analysis task), Parallel Agents (more concurrency with smaller contexts). `Configure-Ollama.ps1` uses documented `OLLAMA_HOST`, `OLLAMA_CONTEXT_LENGTH`, `OLLAMA_NUM_PARALLEL`, `OLLAMA_MAX_LOADED_MODELS`, `OLLAMA_MAX_QUEUE`, and `OLLAMA_KEEP_ALIVE`. `Test-Ollama.ps1` checks `/v1/models`, expected model availability, optional chat completion, and `ollama ps` GPU/CPU o