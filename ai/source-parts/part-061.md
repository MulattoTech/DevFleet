# DevFleet source part 061

Full-source UTF-8 byte interval [2790000, 2836500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 0adff67ca3d3ce68cf6c535c68539b0bc68aff4a3c1bbcffab0ec9cf77a5b9c0

<!-- BEGIN SOURCE SLICE -->
.com/Download", "directUri": "https://update.code.visualstudio.com/latest/win32-x64/stable", "allowedHosts": ["code.visualstudio.com", "update.code.visualstudio.com", "vscode.download.prss.microsoft.com"], "assetRegex": "(?i)^VSCodeSetup-x64-[0-9.]+\\.exe$" },
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

SHA256: cef183d146be489ce3b0c9f868b26c6125a5f7733b5a51271ffcadfaf0cf4dcd | Bytes: 594 | Git mode: 100644

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
    "sha256": "48a41161394f5743808eec150631d87de6619ad2c3315f037a7bd23050adb29a"
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

SHA256: 5b09b852e593be0807c384c9375c76a3d5a9a858cb706b8fceae9d06459e4f56 | Bytes: 98 | Git mode: 100644

```
48a41161394f5743808eec150631d87de6619ad2c3315f037a7bd23050adb29a  Payload/devfleet-v1.2.13.tar.gz

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
    @{ From = (Join-Path $PreparedInstaller 'DevFleet.Setup\DevFleet.Setup.csproj'); To = (Join-Path $Installer 'DevFleet.Setup\DevFleet.Setup.csproj') },
    @{ From = (Join-Path $PreparedInstaller 'DevFleet.Setup\app.manifest'); To = (Join-Path $Installer 'DevFleet.Setup\app.manifest') },
    @{ From = (Join-Path $PreparedInstaller 'INSTALLER-BUILD-MANIFEST.json'); To = (Join-Path $Installer 'INSTALLER-BUILD-MANIFEST.json') },
    @{ From = (Join-Path $PreparedInstaller "DevFleet.Setup\Payload\devfleet-v$version.tar.gz"); To = (Join-Path $Installer "DevFleet.Setup\Payload\devfleet-v$version.tar.gz") }
  )
  foreach ($pair in $copyPairs) { Copy-Item -LiteralPath $pair.From -Destination $pair.To -Force }
}

function Assert-ReleaseStagePath([string]$Path,[string]$Parent,[string]$LeafPattern) {
  $resolved=[IO.Path]::GetFullPath($Path)
  $expectedParent=[IO.Path]::GetFullPath($Parent).TrimEnd('\','/')
  if((Split-Path -Parent $resolved) -cne $expectedParent -or (Split-Path -Leaf $resolved) -cnotmatch $LeafPattern){throw 'Release staging path escaped its owned parent.'}
  foreach($candidate in @($expectedParent,$resolved)){
    if((Test-Path -LiteralPath $candidate) -and ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Release staging path is a reparse point.'}
  }
}

function Invoke-NormalizedPrepare([string]$Source, [string]$Installer, [string]$Previous, [string]$Outputs) {
  $root = Join-Path ([IO.Path]::GetTempPath()) "devfleet-release-prepare-$([guid]::NewGuid().ToString('N'))"
  $preparedSource = Join-Path $root 'source'
  $preparedInstaller = Join-Path $root 'installer-source'
  $preparedOutputs = Join-Path $root 'outputs'
  try {
    Assert-ReleaseStagePath $root ([IO.Path]::GetTempPath()) '^devfleet-release-prepare-[0-9a-f]{32}$'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Copy-ReleaseTree $Source $preparedSource
    Copy-ReleaseTree $Installer $preparedInstaller
    Normalize-TextTree $preparedSource
    Normalize-TextTree $preparedInstaller
    New-Item -ItemType Directory -Path $preparedOutputs -Force | Out-Null
    $result = Invoke-Prepare $preparedSource $preparedInstaller $Previous $preparedOutputs
    Copy-PreparedShippingInputs $preparedSource $preparedInstaller $Source $Installer
    Copy-Item -Path (Join-Path $preparedOutputs '*') -Destination $Outputs -Force -Recurse
    return [pscustomobject]@{ Version = $result.Version; Tar = (Join-Path $Outputs (Split-Path -Leaf $result.Tar)); Portable = (Join-Path $Outputs (Split-Path -Leaf $result.Portable)); TarSha256 = $result.TarSha256 }
  } finally {
    Assert-ReleaseStagePath $root ([IO.Path]::GetTempPath()) '^devfleet-release-prepare-[0-9a-f]{32}$'
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

if ($Mode -eq 'Prepare') {
  $source = (Resolve-Path -LiteralPath $SourceRoot).Path
  $installer = $PSScriptRoot
  $previous = (Resolve-Path -LiteralPath $PreviousPortableZip).Path
  $output = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Path $OutputDirectory -Force)).Path
  $first = Invoke-NormalizedPrepare $source $installer $previous $output
  if ($ProveIdempotent) {
    $afterFirst = Get-Snapshot $source $installer
    [void](Invoke-NormalizedPrepare $source $installer $previous $output)
    $afterSecond = Get-Snapshot $source $installer
    Assert-SameSnapshot $afterFirst $afterSecond 'second prepare pass'
    Write-Output 'RELEASE_INPUT_PREPARE_IDEMPOTENCE=PASS'
  }
  [ordered]@{ mode = 'Prepare'; version = $first.Version; tar = $first.Tar; portable = $first.Portable; tarSha256 = $first.TarSha256 } | ConvertTo-Json -Compress
  exit 0
}

if ($ProveIdempotent) { throw '-ProveIdempotent is valid only with -Mode Prepare.' }
$sourcePath = (Resolve-Path -LiteralPath $SourceRoot).Path
$workspace = Split-Path -Parent $sourcePath
if ($CandidateCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'Verify mode requires an explicit 40-character candidate commit.' }
$previous = (Resolve-Path -LiteralPath $PreviousPortableZip).Path
$verificationRoot = Join-Path ((Resolve-Path -LiteralPath (New-Item -ItemType Directory -Path $OutputDirectory -Force)).Path) '.release-input-stage'
Assert-ReleaseStagePath $verificationRoot ((Resolve-Path -LiteralPath $OutputDirectory).Path) '^\.release-input-stage$'
if (Test-Path -LiteralPath $verificationRoot) { Remove-Item -LiteralPath $verificationRoot -Recurse -Force }
New-Item -ItemType Directory -Path $verificationRoot -Force | Out-Null
$archive = Join-Path $verificationRoot 'candidate.tar'
& git -C $workspace -c core.autocrlf=false archive --format=tar --output=$archive $CandidateCommit source installer-source tools automation
if ($LASTEXITCODE) { throw "Could not materialize candidate commit $CandidateCommit for release-input verification." }
$candidateTree = Join-Path $verificationRoot 'candidate'
$buildTree = Join-Path $verificationRoot 'build'
New-Item -ItemType Directory -Path $candidateTree,$buildTree -Force | Out-Null
& tar -xf $archive -C $candidateTree
if ($LASTEXITCODE) { throw 'Candidate shipping tree extraction failed during release-input verification.' }
Copy-Item -LiteralPath (Join-Path $candidateTree 'source') -Destination $buildTree -Recurse
Copy-Item -LiteralPath (Join-Path $candidateTree 'installer-source') -Destination $buildTree -Recurse
Copy-Item -LiteralPath (Join-Path $candidateTree 'tools') -Destination $buildTree -Recurse -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $candidateTree 'automation') -Destination $buildTree -Recurse -ErrorAction SilentlyContinue
$buildSource = Join-Path $buildTree 'source'
$buildInstaller = Join-Path $buildTree 'installer-source'
$buildOutputs = Join-Path $verificationRoot 'artifacts'
$expected = Get-Snapshot $candidateTree\source $candidateTree\installer-source
[void](Invoke-Prepare $buildSource $buildInstaller $previous $buildOutputs)
$actual = Get-Snapshot $buildSource $buildInstaller
Assert-SameSnapshot $expected $actual 'candidate commit'
[ordered]@{ mode = 'Verify'; candidateCommit = $CandidateCommit; sourceRoot = $buildSource; installerRoot = $buildInstaller; outputDirectory = $buildOutputs; status = 'PASS' } | ConvertTo-Json -Compress

```


## FILE: installer-source/PrivateSelfSignedSigning.psm1

SHA256: 7f60833369394740699c4fbc6ef410e1f302844c5b53bfe70dcd3b57b33afc11 | Bytes: 8933 | Git mode: 100644

```
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PrivateSigningSubject = 'CN=DevFleet Private Personal Code Signing'
$script:CodeSigningEku = '1.3.6.1.5.5.7.3.3'

function Get-PrivateKeyExportable {
    param([Parameter(Mandatory)]$Certificate)
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if ($null -eq $rsa) { throw 'DevFleet private signing certificate does not expose an RSA private key.' }
    try {
        if ($rsa -is [System.Security.Cryptography.RSACng]) {
            $policy = $rsa.Key.ExportPolicy
            return [bool](
                ($policy -band [System.Security.Cryptography.CngExportPolicies]::AllowExport) -or
                ($policy -band [System.Security.Cryptography.CngExportPolicies]::AllowPlaintextExport)
            )
        }
        if ($rsa -is [System.Security.Cryptography.RSACryptoServiceProvider]) {
            return [bool]$rsa.CspKeyContainerInfo.Exportable
        }
        throw "Unsupported RSA private-key provider: $($rsa.GetType().FullName)"
    } finally {
        $rsa.Dispose()
    }
}

function Test-UsablePrivateSigningCertificate {
    param([Parameter(Mandatory)]$Certificate)
    $eku = @($Certificate.EnhancedKeyUsageList | ForEach-Object { [string]$_.ObjectId })
    if ($Certificate.Subject -cne $script:PrivateSigningSubject) { return $false }
    if (-not $Certificate.HasPrivateKey) { return $false }
    if ($Certificate.NotBefore -gt (Get-Date)) { return $false }
    if ($Certificate.NotAfter -le (Get-Date).AddDays(30)) { return $false }
    if ($script:CodeSigningEku -notin $eku) { return $false }
    return -not (Get-PrivateKeyExportable -Certificate $Certificate)
}

function Assert-PrivateSigningCertificate {
    param([Parameter(Mandatory)]$Certificate)
    if (-not (Test-UsablePrivateSigningCertificate -Certificate $Certificate)) {
        throw 'DevFleet private signing certificate failed exact subject, validity, EKU, private-key, or non-exportable-key policy.'
    }
    if ([int]$Certificate.PublicKey.Key.KeySize -lt 3072) {
        throw 'DevFleet private signing certificate RSA key is smaller than 3072 bits.'
    }
}

function Import-PublicCertificateForPrivateTrust {
    param(
        [Parameter(Mandatory)][string]$PublicCertificatePath,
        [Parameter(Mandatory)][string]$Thumbprint
    )
    foreach ($storeName in @('TrustedPublisher')) {
        $storePath = "Cert:\CurrentUser\$storeName"
        $present = Get-ChildItem -LiteralPath $storePath | Where-Object { $_.Thumbprint -ceq $Thumbprint }
        if (-not $present) {
            & (Join-Path $env:SystemRoot 'System32\certutil.exe') -user -f -addstore $storeName $PublicCertificatePath | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "certutil failed to install the DevFleet public certificate in CurrentUser/$storeName." }
        }
        $verified = Get-ChildItem -LiteralPath $storePath | Where-Object { $_.Thumbprint -ceq $Thumbprint }
        if (-not $verified) { throw "DevFleet public signing certificate was not installed in CurrentUser/$storeName." }
    }
    $trustedRoot = @(Get-ChildItem -LiteralPath 'Cert:\CurrentUser\Root' | Where-Object { $_.Thumbprint -ceq $Thumbprint })
    if ($trustedRoot.Count -ne 1) {
        throw "USER ACTION REQUIRED — Windows requires interactive consent before trusting DevFleet private signing certificate $Thumbprint in CurrentUser/Root."
    }
}

function Initialize-DevFleetPrivateSigningIdentity {
    [CmdletBinding()]
    param(
        [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'DevFleet\Signing\PrivateSelfSigned'),
        [switch]$TrustSigningHost,
        [string]$RequiredThumbprint,
        [switch]$RequireExisting
    )

    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    $metadataPath = Join-Path $StateRoot 'identity.json'
    $publicCertificatePath = Join-Path $StateRoot 'DevFleet-Private-Personal-Code-Signing.cer'
    $persisted = $null
    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
        try { $persisted = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json }
        catch { throw "DevFleet private signing identity metadata is malformed: $($_.Exception.Message)" }
        if ([string]$persisted.subject -cne $script:PrivateSigningSubject) {
            throw 'DevFleet private signing identity metadata has an unexpected subject.'
        }
        if ([string]$persisted.thumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
            throw 'DevFleet private signing identity metadata has an invalid thumbprint.'
        }
    }

    $store = 'Cert:\CurrentUser\My'
    $exactSubject = @(Get-ChildItem -LiteralPath $store | Where-Object { $_.Subject -ceq $script:PrivateSigningSubject })
    $certificate = $null
    $rolloverFrom = $null
    $created = $false
    if ($persisted) {
        $rolloverFrom = ([string]$persisted.thumbprint).ToUpperInvariant()
        $candidate = @($exactSubject | Where-Object { $_.Thumbprint -ceq $rolloverFrom })
        if ($candidate.Count -gt 1) { throw 'Multiple certificates matched the persisted DevFleet private signing thumbprint.' }
        if ($candidate.Count -eq 1 -and (Test-UsablePrivateSigningCertificate -Certificate $candidate[0])) {
            $certificate = $candidate[0]
            $rolloverFrom = $null
        }
    } else {
        $usable = @($exactSubject | Where-Object { Test-UsablePrivateSigningCertificate -Certificate $_ })
        if ($usable.Count -gt 1) {
            throw 'Multiple usable DevFleet private signing identities exist without persisted exact-thumbprint authority.'
        }
        if ($usable.Count -eq 1) { $certificate = $usable[0] }
    }

    if ($RequireExisting) {
        if (-not $RequiredThumbprint -or $RequiredThumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
            throw 'DevFleet private signing requires an explicit existing certificate thumbprint.'
        }
        $required = @(Get-ChildItem -LiteralPath $store | Where-Object { $_.Thumbprint -ceq $RequiredThumbprint.ToUpperInvariant() })
        if ($required.Count -ne 1 -or -not (Test-UsablePrivateSigningCertificate -Certificate $required[0])) {
            throw "RELEASE BLOCKED — required existing DevFleet signing certificate $RequiredThumbprint is unavailable or fails policy; replacement creation is forbidden."
        }
        $certificate = $required[0]
        if ($persisted -and ([string]$persisted.thumbprint).ToUpperInvariant() -cne $certificate.Thumbprint.ToUpperInvariant()) {
            throw 'Persisted DevFleet private signing identity does not match the required existing certificate thumbprint.'
        }
    }
    if (-not $certificate) {
        $certificate = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject $script:PrivateSigningSubject `
            -FriendlyName 'DevFleet PRIVATE/PERSONAL Code Signing' `
            -CertStoreLocation $store `
            -KeyAlgorithm RSA `
            -KeyLength 3072 `
            -HashAlgorithm SHA256 `
            -KeyExportPolicy NonExportable `
            -NotAfter (Get-Date).AddYears(3)
        $created = $true
    }

    Assert-PrivateSigningCertificate -Certificate $certificate
    Export-Certificate -Cert $certificate -FilePath $publicCertificatePath -Force | Out-Null
    if ($TrustSigningHost) {
        Import-PublicCertificateForPrivateTrust -PublicCertificatePath $publicCertificatePath -Thumbprint $certificate.Thumbprint
    }

    $metadata = [ordered]@{
        schemaVersion = 1
        profile = 'PRIVATE_SELF_SIGNED'
        subject = $certificate.Subject
        thumbprint = $certificate.Thumbprint
        codeSigningEku = $script:CodeSigningEku
        notBefore = $certificate.NotBefore.ToUniversalTime().ToString('o')
        notAfter = $certificate.NotAfter.ToUniversalTime().ToString('o')
        keyAlgorithm = $certificate.PublicKey.Oid.FriendlyName
        keySize = [int]$certificate.PublicKey.Key.KeySize
        privateKeyExportable = $false
        privateKeyExported = $false
        publicCertificatePath = $publicCertificatePath
        trustStores = if ($TrustSigningHost) { @('CurrentUser/Root', 'CurrentUser/TrustedPublisher') } else { @() }
        createdThisRun = $created
        rolloverFromThumbprint = $rolloverFrom
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $temporary = "$metadataPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, (($metadata | ConvertTo-Json -Depth 6) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $metadataPath -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
    return [pscustomobject]$metadata
}

Export-ModuleMember -Function Initialize-DevFleetPrivateSigningIdentity

```


## FILE: installer-source/RELEASING.md

SHA256: c06c804c4fdb8c8262ea4d6993b1e3785eb07df8799b00deb34ee4a18f32607f | Bytes: 399 | Git mode: 100644

```
# Releasing

The canonical sequence is source tests, the current `VERSION` TAR, portable ZIP, unsigned build and
self-test, clean-room and maintenance E2E, Authenticode signing and timestamping,
signature verification, signed self-test, final hashes, installer-source ZIP, and audit
ZIP. A release stops on signing or required E2E failure. Fast rebuild is explicitly
unsigned developer output only.

```


## FILE: installer-source/TAILSCALE-AUTH.md

SHA256: bb622751864f369df29b393cf085d839af3df2c3e9d7d4270d25d67cbbd8b754 | Bytes: 2219 | Git mode: 100644

````
# Tailscale authentication

Installation and authentication are separate. The normal automated provider is the
DPAPI-bound `OAuthClientSecretStore` in the existing DevFleet E2E/local secret store.
When authentication is genuinely needed, DevFleet passes the secret through a
tightly ACL-protected temporary file using the installed client's supported
`--client-secret=file:<path>` form. Disposable enrollment adds
`ephemeral=true&preauthorized=true`; persistent enrollment uses
`ephemeral=false&preauthorized=true`, `tag:devfleet`, and unattended Windows
semantics when supported. The secret file is wiped and removed immediately after the
single bounded enrollment call.

The recovery state machine is intentionally small:

1. A healthy service and authenticated node are validated and left unchanged.
2. A stopped service is started once and rechecked.
3. `NeedsLogin`/`NoState` invokes the configured provider once and rechecks structured
   readiness.
4. Other states fail with a specific sanitized classification.

Authentication is not readiness. The final gate also requires a Running backend,
online self, expected deterministic hostname and tag, a Tailscale IPv4, no blocking
health error, the expected peer reachable through the supported Tailscale ping, and
the configured DevFleet service endpoint reachable over the tailnet. These checks are
evidenced as structured metadata without credentials.

If the OAuth provider is unavailable, a protected tagged/preauthorized short-lived
auth-key can be selected explicitly as `AUTH_KEY_FALLBACK`. It follows the same
file-backed, bounded, redacted, and cleanup rules. Browser/device login is emergency
manual recovery only; it is not the normal release path.

Tailnet Lock is read-only inspected before enrollment. Enabled or indeterminate Lock
state fails closed as `TAILNET_LOCK_SIGNING_REQUIRED`; DevFleet never disables or
bypasses Tailnet Lock.

For local secure entry, run the repository-supported script in a local Administrator
PowerShell:

```powershell
& '<repository>\source\windows\Set-DevFleetTailscaleOAuthCredential.ps1'
```

Never pass an OAuth secret, auth key, bearer token, or API token as a command-line
argument or paste one into Codex/chat.

````


## FILE: installer-source/TAILSCALE-SETUP.md

SHA256: d541e8e4771d5d59e1f33ecbecb9d0e76227979881690023aad74ba440487c74 | Bytes: 1637 | Git mode: 100644

````
# Tailscale setup

Normal unattended pairing uses the protected DevFleet OAuth client-secret store. The
pairing code creates a short-lived ACL-protected `file:` input, invokes the installed
Tailscale client once, and removes the file in a `finally` path. The client secret is
never placed in argv, logs, evidence, audit bundles, or installer output.

The one-time local setup command is:

```powershell
& '<repository>\source\windows\Set-DevFleetTailscaleOAuthCredential.ps1'
```

Run it in a local Administrator PowerShell. It uses the existing DevFleet protected
store and a secure prompt; do not paste the secret into Codex, chat, a script file, or
the command line.

Persistent nodes use `tag:devfleet`, deterministic hostnames, and non-ephemeral
registration. Disposable E2E nodes use `tag:devfleet-e2e`, deterministic
collision-safe hostnames, preauthorization where supported, and ephemeral
registration. A healthy authenticated node is validated without reauthentication.

Readiness is layered: the service must run; machine-readable state must show a
Running/authenticated/online node with an expected identity, tag, Tailscale IPv4, and
no blocking health error; the expected peer must answer the supported Tailscale ping;
and the scenario's configured DevFleet endpoint must answer over the tailnet.

`--defer-network-pairing` carries `DeferNetworkPairing` through both PowerShell
entrypoints and leaves a deliberate Maintenance completion path. Browser pairing is
manual recovery only. If Tailnet Lock is enabled or cannot be read safely, automatic
enrollment stops with `TAILNET_LOCK_SIGNING_REQUIRED`; it is never bypassed.

````


## FILE: installer-source/TROUBLESHOOTING.md

SHA256: 5b836b6d9771c53df03b0d2aed9b5b08acd053bfe3c2c938b4477494d01a1354 | Bytes: 396 | Git mode: 100644

```
# Troubleshooting

Use read-only preflight first. For dependency failures record detected path/version,
WinGet health, official source, download hash/signer, installer exit code, rediscovered
path/version, and reboot state. Network failures use bounded retries and preserve the
resumable transaction. Do not delete arbitrary AppX/WinGet state or use production as a
destructive test environment.

```


## FILE: installer-source/Test-PrivateSelfSignedSigning.ps1

SHA256: 39679218d9071d16b503321ab878e1862a9067595e574a4898891a0da45dc3c7 | Bytes: 3133 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UnsignedExecutable,
    [switch]$RequireTrusted
)
$ErrorActionPreference = 'Stop'

$source = (Resolve-Path -LiteralPath $UnsignedExecutable).Path
$sourceSignature = Get-AuthenticodeSignature -LiteralPath $source
if ($sourceSignature.Status -ne 'NotSigned') { throw 'Private signing probe requires an unsigned source executable.' }

Import-Module (Join-Path $PSScr