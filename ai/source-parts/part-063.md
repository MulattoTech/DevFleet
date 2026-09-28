# DevFleet source part 063

Full-source UTF-8 byte interval [2883000, 2929500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 08e761a9ddf8beab4521ebac83c69a3ffade833ddd66ef9576e40a68e545a497

<!-- BEGIN SOURCE SLICE -->
a
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

Import-Module (Join-Path $PSScriptRoot 'PrivateSelfSignedSigning.psm1') -Force
$identity = Initialize-DevFleetPrivateSigningIdentity -TrustSigningHost:$RequireTrusted
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$($identity.thumbprint)"
$scratchRoot = Join-Path $env:LOCALAPPDATA 'Temp\DevFleet-PrivateSigningProbe'
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
$probe = Join-Path $scratchRoot "probe-$([guid]::NewGuid().ToString('N')).exe"
$tampered = Join-Path $scratchRoot "tampered-$([guid]::NewGuid().ToString('N')).exe"
try {
    Copy-Item -LiteralPath $source -Destination $probe
    $setResult = Set-AuthenticodeSignature -LiteralPath $probe -Certificate $certificate -HashAlgorithm SHA256
    $signature = Get-AuthenticodeSignature -LiteralPath $probe
    $chainValid = $setResult.Status -eq 'Valid' -and $signature.Status -eq 'Valid'
    if ($RequireTrusted -and -not $chainValid) { throw "Private signing probe did not validate: set=$($setResult.Status); verify=$($signature.Status); message=$($signature.StatusMessage)" }
    if ($signature.SignerCertificate.Thumbprint -cne [string]$identity.thumbprint) { throw 'Private signing probe used an unexpected certificate.' }
    if ('1.3.6.1.5.5.7.3.3' -notin @($signature.SignerCertificate.EnhancedKeyUsageList | ForEach-Object { [string]$_.ObjectId })) { throw 'Private signing probe certificate lacks Code Signing EKU.' }

    Copy-Item -LiteralPath $probe -Destination $tampered
    $stream = [IO.File]::Open($tampered, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $stream.Position = 4096
        $originalByte = $stream.ReadByte()
        $stream.Position = 4096
        $stream.WriteByte(($originalByte -bxor 1))
    } finally {
        $stream.Dispose()
    }
    $tamperedSignature = Get-AuthenticodeSignature -LiteralPath $tampered
    if ($tamperedSignature.Status -eq 'Valid') { throw 'Tampered private signing probe unexpectedly validated.' }
    [ordered]@{
        status = if ($chainValid) { 'PASS' } else { 'BLOCKED — TRUST' }
        sourceStatus = [string]$sourceSignature.Status
        signedStatus = [string]$signature.Status
        subject = $signature.SignerCertificate.Subject
        thumbprint = $signature.SignerCertificate.Thumbprint
        codeSigningEkuVerified = $true
        timestampState = if ($signature.TimeStamperCertificate) { 'PRESENT' } else { 'NOT TIMESTAMPED' }
        tamperedCopyStatus = [string]$tamperedSignature.Status
        privateKeyExported = $false
    } | ConvertTo-Json -Depth 4
} finally {
    foreach ($path in @($probe, $tampered)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
}

```


## FILE: installer-source/Test-ReleaseClosure.ps1

SHA256: 813c9f586ed8d49213ee87dfd7cef43388534b6c24eb1e81ec701353f56dc902 | Bytes: 2436 | Git mode: 100644

```
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourceRoot,
  [Parameter(Mandatory)][string]$PreviousPortableZip,
  [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath $SourceRoot).Path | Split-Path -Parent
$commit = (git -C $workspace rev-parse HEAD).Trim()
if ($commit -notmatch '^[0-9a-fA-F]{40}$') { throw 'Release closure regression requires an explicit candidate commit.' }
$tool = Join-Path $workspace 'tools\compute_shipping_input_identity.py'
$candidateJson = & python $tool --workspace $workspace --candidate-commit $commit | Select-Object -Last 1
if ($LASTEXITCODE) { throw 'Could not compute candidate shipping identity.' }
$candidate = $candidateJson | ConvertFrom-Json
$verifyJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Prepare-ReleaseInputs.ps1') -Mode Verify -SourceRoot $SourceRoot -PreviousPortableZip $PreviousPortableZip -OutputDirectory $OutputDirectory -SigningProfile PrivateSelfSigned -CandidateCommit $commit | Select-Object -Last 1
if ($LASTEXITCODE) { throw 'Frozen release-input verification failed.' }
$verify = $verifyJson | ConvertFrom-Json
$beforeJson = & python $tool --source-root $verify.sourceRoot --installer-root $verify.installerRoot | Select-Object -Last 1
$before = $beforeJson | ConvertFrom-Json
$closureOutput = Join-Path $verify.outputDirectory 'closure-build'
New-Item -ItemType Directory -Path $closureOutput -Force | Out-Null
& python (Join-Path $verify.sourceRoot 'tools\build_release.py') --source $verify.sourceRoot --old-portable $PreviousPortableZip --output-dir $closureOutput
if ($LASTEXITCODE) { throw 'Prepared-commit build simulation failed.' }
$afterJson = & python $tool --source-root $verify.sourceRoot --installer-root $verify.installerRoot | Select-Object -Last 1
$after = $afterJson | ConvertFrom-Json
if ([string]$before.shippingInputIdentity -cne [string]$after.shippingInputIdentity -or [string]$before.shippingInputIdentity -cne [string]$candidate.candidateShippingInputIdentity) {
  throw 'FINAL BUILD AGAINST A PREPARED COMMIT failed: shipping identity before != after or candidate.'
}
[ordered]@{ status = 'PASS'; candidateCommit = $commit; shippingIdentityBefore = $before.shippingInputIdentity; shippingIdentityAfter = $after.shippingInputIdentity; candidateShippingIdentity = $candidate.candidateShippingInputIdentity } | ConvertTo-Json -Compress

```


## FILE: installer-source/UNINSTALL.md

SHA256: 7d993247762902ce9b79c712e2ffdc899e913c98680f7bd22aaeadbf2f83d1d5 | Bytes: 386 | Git mode: 100644

```
# Uninstall

Uninstall first creates recovery metadata, then removes only ledger-listed files, exact DevFleet tasks/services/firewall rules, the marked SSH block, the DevFleet VS Code reference file, exact shortcuts, and the Installed Apps entry. Project data and unrelated prerequisites remain unless separately authorized. The stable launcher schedules exact self-removal after exit.

```


## FILE: installer-source/WINGET-RECOVERY.md

SHA256: c1c5bae6e37edfde8026eccf9f09b8eb8397552427689a405c3fc931b80f199a | Bytes: 482 | Git mode: 100644

```
# WinGet recovery

WinGet is healthy only when version, `source list`, and an exact package search succeed.
Missing, Broken, SourceBroken, or incompatible WinGet is not silently treated as healthy.
The supported Microsoft repair path uses Microsoft.WinGet.Client and
`Repair-WinGetPackageManager -Force -Latest`; source reset is conservative and requires
administrator authority. If repair remains unavailable, mandatory dependencies use
their allowlisted official-vendor resolver.

```


## FILE: installer-source/third-party-license-inventory.json

SHA256: d74c0e92be53d174675bb68c2354e7f7f1751983a90ccb1e17860682e8bb8201 | Bytes: 198 | Git mode: 100644

```
{
  "bundledThirdPartyInstallers": [],
  "notes": ["No third-party runtime binary is redistributed by this build.", "DevFleet application source remains subject to its repository license files."]
}

```


## FILE: installer-source/third-party-signature-verification.json

SHA256: 6ca692d68b18e596e9739f81d839238c9dcb98eee159bc983bed19ea2481dac2 | Bytes: 340 | Git mode: 100644

```
{
  "bundledThirdPartyBinaries": [],
  "verification": "Not applicable: no third-party prerequisite binary is embedded.",
  "sdk": {
    "product": ".NET SDK 8.0.408",
    "officialSource": "https://dotnet.microsoft.com/download/dotnet/8.0",
    "signerVerification": "Build toolchain metadata recorded; final installer is unsigned."
  }
}

```


## FILE: source/.test-runtime/config.json

SHA256: 8d52563b8a721ed66650dfa8a684751e481790e47a9690b00cd63db06e2f903c | Bytes: 1292 | Git mode: 100644

```
{"node_name": "test-node", "deployment_id": "deployment-123", "node_role": "primary", "friendly_name": "CodexDevVM", "portal_port": 8787, "workspaces": "C:\\Users\\Dylan\\Documents\\Codex\\2026-08-12\\ex-2\\work\\DevFleet-v1.2.13-development\\source\\.test-runtime\\workspaces", "quarantine": "C:\\Users\\Dylan\\Documents\\Codex\\2026-08-12\\ex-2\\work\\DevFleet-v1.2.13-development\\source\\.test-runtime\\quarantine", "peer_file": "C:\\Users\\Dylan\\Documents\\Codex\\2026-08-12\\ex-2\\work\\DevFleet-v1.2.13-development\\source\\.test-runtime\\peer.json", "runtime_root": "C:\\Users\\Dylan\\Documents\\Codex\\2026-08-12\\ex-2\\work\\DevFleet-v1.2.13-development\\source\\.test-runtime\\runtime", "cache_root": "C:\\Users\\Dylan\\Documents\\Codex\\2026-08-12\\ex-2\\work\\DevFleet-v1.2.13-development\\source\\.test-runtime\\cache", "ollama_base_url": "http://127.0.0.1:11434/v1", "ollama_model": "test-model", "ollama_profile": "stable-interactive", "development_profile": "balanced", "docker_mode": "rootless", "enable_shared_caches": true, "enable_analyzer_cache": true, "auto_start_codexpro": true, "allow_tailnet_ports": true, "backup_before_rebuild": false, "backup_before_quarantine": true, "require_tailscale": false, "tailnet_cidr": "100.64.0.0/10", "public_binding_allowed": true}
```


## FILE: source/.test-runtime/peer.json

SHA256: 44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a | Bytes: 2 | Git mode: 100644

```
{}
```


## FILE: source/BASELINE-v1.0.0-FILES.txt

SHA256: 7c52807b9916d34cb980d01c85049e1443be953d813106b7931fe8e8d02feb50 | Bytes: 2825 | Git mode: 100644

```
Bootstrap-Install.ps1
CHANGELOG.md
CHECKSUMS.sha256
INSTALL-CHECKLIST.txt
Install-DevFleet.ps1
README-FIRST.md
SECURITY-NOTES.txt
START-HERE-DESKTOP.cmd
START-HERE-LAPTOP.cmd
app/devfleet/__init__.py
app/devfleet/analyzer.py
app/devfleet/auth.py
app/devfleet/core.py
app/devfleet/main.py
app/devfleet/projects.py
app/devfleet/status.py
app/requirements.txt
app/static/style.css
app/systemd/devfleet-backup.service
app/systemd/devfleet-backup.timer
app/systemd/devfleet.service
app/templates/index.html
cloud-init/compute.yaml
cloud-init/vault.yaml
config/devfleet.config.json
docs/00-HARD-STOPS-AND-ASSUMPTIONS.md
docs/01-ARCHITECTURE.md
docs/02-INSTALL-ORDER.md
docs/03-DAILY-USE.md
docs/04-RECOVERY.md
docs/05-SECURITY-MODEL.md
docs/06-CODEXPRO-INTEGRATION.md
docs/07-OFFICIAL-SOURCES.md
linux/bootstrap-compute.sh
linux/bootstrap-vault.sh
linux/devfleet-backup
linux/devfleet-configure-backup
linux/devfleet-health
linux/devfleet-purge-quarantine
linux/devfleet-repair
linux/devfleet-restore-project
linux/devfleet-safe-update
linux/devfleet-set-peer
linux/devfleet-user-repair
linux/devfleet-vault-health
linux/devfleet-vault-maintenance
templates/generic/.devcontainer/devcontainer.json
templates/generic/.devfleet/codexpro-bootstrap.sh
templates/generic/.devfleet/codexpro.env.example
templates/generic/.gitignore
templates/generic/README.md
templates/generic/compose.yaml
templates/node/.devcontainer/devcontainer.json
templates/node/.devfleet/codexpro-bootstrap.sh
templates/node/.devfleet/codexpro.env.example
templates/node/.gitignore
templates/node/README.md
templates/node/compose.yaml
templates/node/package.json
templates/python/.devcontainer/devcontainer.json
templates/python/.devfleet/codexpro-bootstrap.sh
templates/python/.devfleet/codexpro.env.example
templates/python/.gitignore
templates/python/README.md
templates/python/compose.yaml
templates/python/pyproject.toml
templates/python/src/app/__init__.py
tests/test_analyzer.py
tools/Verify-Package.ps1
tools/verify_package.py
windows/00-Preflight.ps1
windows/01-Install-Prerequisites.ps1
windows/02-Provision-ComputeNode.ps1
windows/03-Provision-Vault.ps1
windows/04-Connect-Tailscale.ps1
windows/04a-Connect-WindowsTailscale.ps1
windows/05-Configure-LocalVaultClient.ps1
windows/06-Import-Laptop-Bootstrap.ps1
windows/08-Install-Shortcuts.ps1
windows/09-Export-Laptop-Bootstrap.ps1
windows/10-Export-Desktop-Pairing.ps1
windows/Complete-Cluster.ps1
windows/Configure-GitHub.ps1
windows/DevFleet.Common.psm1
windows/Export-Diagnostics.ps1
windows/Export-Vault-OfflineCopy.ps1
windows/Invoke-Quarantine-Maintenance.ps1
windows/Invoke-Vault-Maintenance.ps1
windows/Repair-DevFleet.ps1
windows/Show-DevFleet-Credentials.ps1
windows/Start-DevFleet.ps1
windows/Stop-DevFleet.ps1
windows/Test-DevFleet.ps1
windows/Update-DevFleet.ps1
windows/Update-Vault.ps1

```


## FILE: source/Bootstrap-Install.ps1

SHA256: 30f522b051e90266c8307537a661b458cfb8ddd092e30e0c0e6e2fc04f7e0554 | Bytes: 8139 | Git mode: 100644

```
# Compatible with Windows PowerShell 5.1. It bootstraps PowerShell 7 for a
# connected clean-room installation from an official Microsoft release.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role,
  [string]$BootstrapBundlePath,
  [string]$PackageRoot,
  [ValidateSet('Connected')][string]$InstallationMode='Connected',
  [switch]$NonInteractive,
  [switch]$SkipWindowsUpdates,
  [switch]$DeferNetworkPairing,
  [switch]$AcknowledgeRootfulDocker,
  [string]$TransactionDeadlineUtc,
  [string]$TransactionId,
  [string]$TransactionPayloadSha256,
  [string]$TransactionAction,
  [string]$TransactionRole,
  [string]$TransactionPreparedUtc,
  [string]$DeadlinePolicyVersion = '1.0.0'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$packageRoot=if($PackageRoot){(Resolve-Path -LiteralPath $PackageRoot).Path}else{$root}
$manifestPath=Join-Path $packageRoot 'dependencies.json'
if(-not(Test-Path -LiteralPath $manifestPath)){throw "Canonical dependency manifest is missing: $manifestPath"}
Import-Module (Join-Path $root 'windows\DevFleet.Common.psm1') -Force
if($DeadlinePolicyVersion -ne '1.0.0'){throw "Unsupported deadline policy version: $DeadlinePolicyVersion"}
$transactionDeadline = if($TransactionDeadlineUtc){try{[datetime]::Parse($TransactionDeadlineUtc).ToUniversalTime()}catch{throw 'Transaction deadline is not a valid UTC timestamp.'}}else{[datetime]::UtcNow.AddSeconds((Get-DevFleetTransactionBudgetSeconds $Role))}
Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'bootstrap' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'bootstrap') | Out-Null
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
$powershellDependency=@($manifest.dependencies)|Where-Object id -eq 'powershell7'|Select-Object -First 1
if(-not $powershellDependency){throw 'Canonical PowerShell 7 dependency record is missing.'}
function Find-Pwsh {
  foreach($base in @(${env:ProgramFiles},${env:ProgramFiles(x86)})){
    if(-not $base){continue};$known=Join-Path $base 'PowerShell\7\pwsh.exe';if(Test-Path -LiteralPath $known){return $known}
  }
  return $null
}
function Get-OfficialPowerShellPayload {
  $context=Get-DevFleetDeadlineContext
  $remaining=if($context){[int][math]::Floor(([datetime]$context.StageDeadlineUtc-[datetime]::UtcNow).TotalSeconds)}else{60}
  if($remaining -le 0){throw 'Bootstrap stage deadline expired before resolving the PowerShell payload.'}
  $release=Invoke-RestMethod -UseBasicParsing -TimeoutSec ([math]::Min(60,$remaining)) -Uri $powershellDependency.directOfficialVendorResolver.metadataUri -Headers @{'User-Agent'='DevFleet-Setup/1.4.1'}
  if(-not $release.tag_name -or $release.prerelease -or $release.draft){throw 'The official PowerShell stable release metadata was not usable.'}
  $asset=$release.assets|Where-Object name -Match $powershellDependency.directOfficialVendorResolver.assetRegex|Select-Object -First 1
  if(-not $asset -or ([Uri]$asset.browser_download_url).Host -notin @($powershellDependency.directOfficialVendorResolver.allowedHosts)){throw 'The official PowerShell x64 MSI asset was not found on an allowlisted host.'}
  $directory=Join-Path $env:ProgramData 'DevFleet\InstallerCache\Bootstrap';New-Item -ItemType Directory -Path $directory -Force|Out-Null
  & icacls.exe $directory /inheritance:r /grant:r 'BUILTIN\Administrators:(OI)(CI)(F)' 'NT AUTHORITY\SYSTEM:(OI)(CI)(F)' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Unable to establish the protected PowerShell staging ACL.'}
  $payload=Join-Path $directory $asset.name
  $assetUri=[Uri]$asset.browser_download_url
  $assetName=[IO.Path]::GetFileName($assetUri.AbsolutePath)
  if($assetName -ne [string]$asset.name -or $assetName -notmatch $powershellDependency.directOfficialVendorResolver.assetRegex -or [IO.Path]::GetExtension($assetName) -ne '.msi'){throw 'The resolved PowerShell payload is not the canonical x64 MSI asset.'}
  Save-AllowlistedHttpsDownload -Uri $assetUri -AllowedHosts @($powershellDependency.directOfficialVendorResolver.allowedHosts) -Path $payload
  if(-not (Test-Path -LiteralPath $payload) -or (Get-Item -LiteralPath $payload).Length -lt 1){throw 'Official PowerShell MSI download failed or produced an empty payload.'}
  Test-OfficialSigner -Path $payload -Policy $powershellDependency.installerAuthenticityPolicy
  return $payload
}
$pwsh=Find-Pwsh
function Get-PwshVersion([string]$Path) {
  $context=Get-DevFleetDeadlineContext
  $remaining=if($context){[int][math]::Floor(([datetime]$context.StageDeadlineUtc-[datetime]::UtcNow).TotalSeconds)}else{60}
  if($remaining -le 0){throw 'Bootstrap stage deadline expired before querying PowerShell.'}
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$Path;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $psi.Arguments='-NoProfile -NonInteractive -Command "' + '$PSVersionTable.PSVersion.ToString()' + '"'
  $process=New-Object Diagnostics.Process
  $process.StartInfo=$psi
  try {
    if(-not $process.Start()){throw "Unable to start PowerShell executable: $Path"}
    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit([math]::Min(60,$remaining)*1000)){try{$process.Kill()}catch{};throw "PowerShell version query exceeded its bootstrap deadline: $Path"}
    [void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5)))
    $text=(($stdout.GetAwaiter().GetResult())+"`n"+($stderr.GetAwaiter().GetResult()))
  } finally { $process.Dispose() }
  $match=[regex]::Match($text,'(?<!\d)(\d+\.\d+(?:\.\d+){0,2})')
  if(-not $match.Success){return $null}
  return [Version]$match.Groups[1].Value
}
$minimumPowerShell=[Version]$powershellDependency.minimumSupportedVersion
$pwshVersion=if($pwsh){Get-PwshVersion $pwsh}else{$null}
if(-not $pwsh -or -not $pwshVersion -or $pwshVersion -lt $minimumPowerShell){
  $payload=Get-OfficialPowerShellPayload
  $msiexec=Join-Path $env:WINDIR 'System32\msiexec.exe'
  if(-not (Test-Path -LiteralPath $msiexec)){throw 'Trusted Windows Installer executable was not found.'}
  $context=Get-DevFleetDeadlineContext
  $remaining=if($context){[int][math]::Floor(([datetime]$context.StageDeadlineUtc-[datetime]::UtcNow).TotalSeconds)}else{60}
  if($remaining -le 0){throw 'Bootstrap stage deadline expired before installing PowerShell.'}
  $p=Start-Process $msiexec -ArgumentList @('/i',$payload,'/qn','/norestart') -PassThru
  if(-not $p.WaitForExit([math]::Min(60,$remaining)*1000)){try{$p.Kill()}catch{};throw 'PowerShell MSI installation exceeded its bootstrap deadline.'}
  if($p.ExitCode -notin @(0,3010)){throw "PowerShell 7 bootstrap failed with exit code $($p.ExitCode)."}
  $pwsh=Find-Pwsh
  if(-not $pwsh){throw 'PowerShell 7 installer completed but pwsh.exe was not found.'}
  $pwshVersion=Get-PwshVersion $pwsh
}
if(-not $pwshVersion -or $pwshVersion -lt $minimumPowerShell){throw "Resolved PowerShell is below the supported minimum ${minimumPowerShell}: $pwshVersion"}
$args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'Install-DevFleet.ps1'),'-Role',$Role,'-InstallationMode',$InstallationMode,'-PackageRoot',$packageRoot,'-TransactionDeadlineUtc',$transactionDeadline.ToString('o'),'-DeadlinePolicyVersion',$DeadlinePolicyVersion)
if($TransactionId -and $TransactionPayloadSha256 -and $TransactionAction -and $TransactionRole -and $TransactionPreparedUtc){$args+=@('-TransactionId',$TransactionId,'-TransactionPayloadSha256',$TransactionPayloadSha256,'-TransactionAction',$TransactionAction,'-TransactionRole',$TransactionRole,'-TransactionPreparedUtc',$TransactionPreparedUtc)}
if($BootstrapBundlePath){$args+=@('-BootstrapBundlePath',$BootstrapBundlePath)}
if($NonInteractive){$args+='-NonInteractive'}
if($SkipWindowsUpdates){$args+='-SkipWindowsUpdates'}
if($DeferNetworkPairing){$args+='-DeferNetworkPairing'}
if($AcknowledgeRootfulDocker){$args+='-AcknowledgeRootfulDocker'}
& $pwsh @args
exit $LASTEXITCODE

```


## FILE: source/CHANGELOG.md

SHA256: 349fbb021aae248702a626433c983e6b1aeadb42da92323f0f6df7c53383188d | Bytes: 3950 | Git mode: 100644

```
# Changelog

## 1.2.5

- Added safe legacy lifecycle-command resolution and preflight reporting for dedicated-VM migrations.
- Corrected stopped-source VM lifecycle preservation and identity-safe pre/post-import rollback cleanup.
- Added managed Ed25519 SSH host-key pinning with authenticated alias verification and fixed cloud-init permission typing.

## 1.2.4

- Completed safe dedicated-VM creation, project SSH alias management, and early worktree rejection.
- Added confirmed, capacity-aware environment migration with lifecycle preservation, transactional rollback, and retained previous-environment metadata.
- Added provider-aware VM backup history, inspection, staged restore with safety backup, and generated-directory archive exclusions.
- Reduced the canonical `devfleet-primary` control-plane memory allocation from 32G to 12G without changing project VM profiles or host reserve policy.

## 1.2.3

- Fixed asynchronous project-action submission, session throttling, and status-probe concurrency.
- Added transactional environment assignment verification, explicit rollback-incomplete state, workspace restore, backup history/restore, and the existing-project environment wizard.
- Added runtime-aware VS Code Remote-SSH workspace links and regenerated release identity.

## 1.2.1
- Removed synchronous infrastructure, peer, Docker, Git, analyzer, and Host Agent probes from ordinary navigation with cached stale-while-revalidate snapshots.
- Replaced browser Basic Auth challenges with a DevFleet login page, opaque session cookies, session CSRF, logout, and safe redirects while preserving token-authenticated APIs.
- Added persistent client navigation, in-page log controls, and cache-aware infrastructure refresh behavior.

## 1.2.0
- Added provider-routed project commands, verified VM workspace archives, backup-bound destruction gates, and safe VM workspace export.
- Added runtime-versus-application health semantics and normalized host capacity for the dashboard.

## 1.1.0
- Preserved every v1.0.0 path, the three-VM recovery architecture, and internal instance names.
- Added schema-2 migration with configuration backup and stopped-state Multipass snapshots.
- Added Strict, Balanced, and Fast Trusted profiles.
- Added rootless/rootful Docker selection, reports, explicit acknowledgement, stopped-state snapshots, and non-destructive switching.
- Added BuildKit and dependency-manager caches through trusted controller overrides.
- Added language policy and 20 templates, including 10 core templates.
- Replaced the CodexPro no-op with a verified project-scoped adapter and status view.
- Added auto-refreshing operation IDs/progress/logs, analyzer caching, ownership leases, guided transfer, peer controls, and preserved non-destructive repair.
- Added Windows Ollama profiles/testing and remote SSH/Docker-context/VS Code client setup.

## 1.0.0
Original safe remote-development baseline, preserved separately.
## 1.2.6

- Reconcile owned Multipass project VM IPv4 addresses after create/start/restart without reprovisioning.
- Preserve deterministic HostKeyAlias/known-host pinning while refreshing managed SSH host addresses.
- Make stopped Dedicated VM runtime/status health inspection side-effect-free.
- Add explicit running-only Open Workspace refresh semantics and portable verification documentation.
## v1.2.7 — Project UX and readiness hotfix

- Fixed project action controls after SPA navigation with one delegated submit handler and lifecycle idempotency keys.
- Added exact-port same-origin validation, transition-aware lifecycle metadata, and operation progress continuity.
- Added canonical dedicated-VM workspace readiness with managed SSH/host-key/authentication proofs.
- Gated Open workspace until readiness is verified and exposed live allocation cards, including VM PID semantics.
- Added Host Agent-owned stable/Insiders VS Code `remote.SSH.remotePlatform` reconciliation with JSONC-safe backups.

```


## FILE: source/CHECKSUMS.sha256

SHA256: 9a68f8aae772cd3e761b58075618fe35b01a76fd1668059a7a5b33c255a951c4 | Bytes: 77967 | Git mode: 100644

```
7c52807b9916d34cb980d01c85049e1443be953d813106b7931fe8e8d02feb50  BASELINE-v1.0.0-FILES.txt
30f522b051e90266c8307537a661b458cfb8ddd092e30e0c0e6e2fc04f7e0554  Bootstrap-Install.ps1
349fbb021aae248702a626433c983e6b1aeadb42da92323f0f6df7c53383188d  CHANGELOG.md
1bf9481ca5be5676e0070de024f05e66fa60a6e817c1999b71d3194ac79af892  DevFleet-v1.1.0-FILE-CHANGES.md
28666495394ce7fa029bbf0c0d0949512333328d28181fb238bd901345af30f2  DevFleet-v1.1.0-MIGRATION.md
9b3a513c9e8dc3a351bcb721eaf6ab05044f1d0583c61f2eaff41e1c88abcd38  DevFleet-v1.1.0-VALIDATION.md
1eaa7f8e5513960dce8b9ef1501f9d1f6a60383aa6f0529c906666a08b04a163  INSTALL-CHECKLIST.txt
a6eb7b82456f5de4c0d9446aa1901b70311e2dc8adf8bd8311affa25688d494e  Install-DevFleet.ps1
16dcbabf33e13d0f8c66db25e104366f877d8c99e0eff2933aad90ab47272fcc  MIGRATION-ROLLBACK.md
5ec4487ad07cec2145a6ade137e641047c19769957c03628978218a06dfb05a4  README-FIRST.md
85ba7a2aa2c127e12f830f96aa1787f237598fae20e3ae7543828552b161f469  SECURITY-NOTES.txt
155b462f564dd1c2ae210029544d39194c14c0c85fb8062d31eb2a614e84d42f  START-HERE-DESKTOP.cmd
97b7b3a91ffa320f1729e1662da3d615bf82bc6aa116e276c2bf373d0b6fd065  START-HERE-LAPTOP.cmd
3905ac18b10325246b765a33daac907f548c000372a1144ef736f44ef9136b2a  Upgrade-DevFleet.ps1
c21698334b1e2308b8556ac1d10402342b8d3e837f65fa1c431eb23392824b1d  VERSION
2736ff45f82f5c2ae6fd243801f786562d4ddfa6326f19cce66a72c6b9e28602  app/devfleet/__init__.py
0ebb618f06b728c84a5e8cfeeb04485536824f11bce37e752f5ed9c9a160e785  app/devfleet/analyzer.py
9810905e7e2ab9d1f1a426ffb9644e2c388de5d199aedf9848f953918ff7cb3d  app/devfleet/auth.py
9772d26aae5fa5d81142a9e1e29361886b9effbaa92f3eef8a99724bd985441d  app/devfleet/caches.py
30b25cb2a5e7479b08aeb3e1b161fe5b53d6eafe21f6b53ea6d2b827df5689a4  app/devfleet/codexpro.py
3ad7879d81b09b62d176c5483204281caf4d7f81a57d03d6fd77cf9a7f4c1ee1  app/devfleet/configuration.py
56dc9aa80609796d45523c4d701e05afde736cccbc9a925fab4f8d50304dc600  app/devfleet/containers.py
244499e96e005ac615042edbe10082a93110f186de8340cdc8a77c95341ac77c  app/devfleet/core.py
cd69e5b29293e828ef6c7cfcbc4538e73456e3ac3041fffb3ce2059375f81e5d  app/devfleet/failover.py
47b084d09edea59545bad7d16bf197892edfd2fd1905e06f8fb418e5a466ce53  app/devfleet/host_control.py
d3c417f349ee93e1aefe323f09233c8e4e8d3f612914e97f0b9e32df5b81b289  app/devfleet/language_policy.py
968255eb2ab9f4121cb561dc474a382b3c47e7dcbe8c08936cda7022abfb7b31  app/devfleet/leases.py
1da87d821f4910f3d0e86f39592593a351b55ab83a62174b90ffa62a80add618  app/devfleet/main.py
188ee5ed02c51d802e85cfa75a1017e9fc2c5a897a51083ba4a09bd564afd290  app/devfleet/metadata_io.py
ffd562d4c2685dacea1e183e708530ea4ccf04c20f19e2969d827190b286600b  app/devfleet/node_registry.py
5805e067353f237924b00fff0b0c595db779ccea061b7ad5e34186052dec0e6e  app/devfleet/ollama.py
d60334d923abed24439342e38ce4061e702b76a64813082718d29946e6832437  app/devfleet/operations.py
1cd0b8e2b31ac2ff724837205ac8f83d2ee6cb0916a679512f543b8557f2dcc5  app/devfleet/profiles.py
69e28afc1b739e74d8118ac34f4222db40f58b80a87fbef2f58c3be368bc4671  app/devfleet/projects.py
5162c54a20a1dfa99eea6eeed3773127a7f4714d067e7f5455b3adff1632f83a  app/devfleet/request_guards.py
9bec3c14f6019fe4439065f8419dd7f11cc2de01ed9e9bd15bbbc5bf94102eb1  app/devfleet/resource_profiles.py
0fde1265ee3895e9dd1b0369256eca1e55fa51532ff1918982ad03ee4f5e4aad  app/devfleet/runtime.py
d5c260df7828b383aa6c7f1d6ff2735783430e5db5457bdd2d5989316164607c  app/devfleet/status.py
a0a9c477ebd09f6fa0713427174d3f86c685de2004badcd8f0c8dfc039dd4251  app/devfleet/version.py
fcc44f267e3c4d0e8f9a674fa52a1675d46a5cb9877af27f8bc3868643605c0f  app/devfleet/workspace_archives.py
fe238c807b668a2f7e0f2b929e24859260e6a7f76bd6762ac7b6b10ad7daac33  app/requirements-hashed.txt
f9a988a58e9e3b9df6e7e78963ec1a074a5642b77fb6541f4463592f6eee6346  app/requirements.txt
8e100c7cc4c96993212aaabfc30e7ed1bbc1167b8f2eb5db840671aee6b0599a  app/static/app.js
9e95e0103e58d5d59f47b099381beb3f0e9af60b34a9a30fe00c121c04833128  app/static/style.css
4262827dc7134b7a52088898b25c35eba6359089ca24b4149acc5053c5c877c9  app/systemd/devfleet-backup.service
52148ce1d51758771ea6aa53c5168ab750af865b40a4b084334359f800796a7e  app/systemd/devfleet-backup.timer
9bfd790f5f2152ac43bdc78fb56efc3924c1f10975f31c0995a1cb690d64836f  app/systemd/devfleet-vault-broker.socket
4431ccb294f011419df43b9475954cfed6ff3f570d600074b4b5bda5037ef1da  app/systemd/devfleet-vault-broker@.service
f33f84cc58fc18f2217a064cc40d9a55bbb14a008a664609b29d0518183a5cca  app/systemd/devfleet.service
00862e8161b5dbe817a5e4a4e2ce662c67b43fa45c160a9070b5b624db1f8069  app/systemd/mutable-paths.json
0fdd41703ebacd3f0231d7f18a74d908dbdc19f629f120d6af65c49b3707e559  app/templates/index.html
2545054327bb69d476b2fdb4b28ed75b12e1d30222a34cab8a46ebb82d2af4d1  app/templates/login.html
d27ae17fba723ce41695a05d644d6ac5e4eb99557f6ff9296005e23e8e587058  client/Configure-DockerContext.ps1
9376560ad72753307bf3ce174039807ad00e2bb13b12b9f6c2087ff630e141dc  client/Configure-SSH.ps1
38e8948c6ae1e6f3c9b5d605d5650666939fbe477d23b9b2c9329fdc22b92ad1  client/Configure-VSCode.ps1
f299ee1509445c514d3faf5d91db10f071768f6f62b5cc90223856bf2afbdeff  client/ssh-config.example
4cd73e74d6ab46ccbe37cb08c46200aa203747f3b6ac79bb823a1c03226911c1  client/vscode-extensions-core.txt
56eee44c27cdc6b543a8f58f580629bc9197a7123a74d4f05f063aac54745eb9  client/vscode-extensions-enterprise.txt
aaa364399deda68c33ac158dbf32dad3dc4a4a522f66567df618d7bb3a48e131  client/vscode-extensions-python.txt
25b7b8985b0071eeaa9a69e1304dec94beb5919b14f1303a6353124d2c3455c8  client/vscode-extensions-systems.txt
8eefa88fd78c091f9ac23130aef1399a649929fc6a895a05be4f3742c0aa874d  client/vscode-extensions-web.txt
c5b88bbcff8c96b667cb46ea26eaabfb7336f2d7b5243f7a528553b825da0cf9  client/vscode-settings.jsonc
00316cd0d11900a961163b07a24f26e9ebfc71830100847ce2cc10ef650ea4cf  cloud-init/compute.yaml
02799e2f3cac7df71db945030cce0d122d3663564db761197ade7e34d09f18ca  cloud-init/vault.yaml
e2db65056b5030e3547c8659563bdb0db197d71d6c6dfd50a609efddbd514279  config/compose-security-policy.json
e6d6d298e5437f994eeab4579253b1ef1bf49fe2ebeeffe01cd6e9ca30c65b5d  config/devfleet.config.json
3e3b592adfe477dbc58c3995f8f34602f14d4145ef01b9b4cad117053c32b148  config/ollama-profiles.json
8e93275c24263491338ac3939a808acdf07f15c3d0c45badda90edb51646de8d  config/resource-policy.json
b939c07de544806e87b8324c050a1a3aff6baac8b36fac57201d917ea8810b46  dependencies.json
95f36460eee2e88d097ca0dc1f7cb4062292fc24e9702aaf2c28326127934c8f  docs/00-HARD-STOPS-AND-ASSUMPTIONS.md
6b2d8c54bdef789c3fd80a6b6512a38d657c38bfb1a2e9a0b8bddd86809f3dc9  docs/01-ARCHITECTURE.md
4ed32904f5194bf15804565bbd254bcb91479b7b87552780723c737f6b92d75e  docs/02-INSTALL-ORDER.md
9c528be76c5285ec85c9eb2ae71fb68ac551dff06c54aef64d5b5c4f67013eb4  docs/03-DAILY-USE.md
ab36d4634d1477f69ef0c4b910dcfa16b6eb157e7e72b081066ce643f36ce2e3  docs/04-RECOVERY.md
cc5a849cfe183f417cc6ee4600c0605e5258dddf9e3fc71f7de9451a7019bf2c  docs/05-SECURITY-MODEL.md
04a3d4244d99396de9a9b17ed21567aa4a491e724a551b8b211cd556de88fe80  docs/06-CODEXPRO-INTEGRATION.md
24dc3b375dd5380ad3eef4d4a2b9ea3c90f02352136ceee936edde8865773429  docs/07-OFFICIAL-SOURCES.md
78cdead576d5def42520f8276f09d14ebacd60fc19edf3e29f79d98a9fc1a02d  docs/08-DEVELOPMENT-PROFILES.md
fc1505fce91fcbc2c07793e56e49d1b1595c8fe1d1c5d0a06d61ce99d61dc9a1  docs/09-LANGUAGE-SELECTION.md
1c62c6d556381f532b86eb7fe737d9e39a5726a4a457127e1adfe4a8404d9992  docs/10-OLLAMA-AND-GPU.md
adf463bf6333f1ff118433701d9bccb9038dc12c1c512a95f2932b46f5e3ad6b  docs/11-REMOTE-VSCODE.md
28666495394ce7fa029bbf0c0d0949512333328d28181fb238bd901345af30f2  docs/12-UPGRADING-FROM-1.0.0.md
04264853da9e3a2d5baa1002ccf43018df4af3c2d79bbf8236909e262a44501f  docs/13-PERFORMANCE-TUNING.md
0e83ab1f2f01961b14ddc261a76128fa8f27ad35c04c63e732ef5824620ec80f  docs/RELEASE-FINGERPRINT-SCHEMA.md
b7c8271409e747cc03a5214b7d082b9673e3e69131edd6a534db613bf6bb8faf  docs/host-agent-portability.md
512bc920be2372e2211f897ba6b83dcfa72b4c5c8973f5f8f548363425880645  linux/bootstrap-compute.sh
9f91b7f6d75029c4fbe47004e5ba85a11442eb92cbabc053fbb857b78be984ad  linux/bootstrap-input.sh
08899264e01566206e13f36f04cffda80991c39bc54babfa75f593ae09e7102c  linux/bootstrap-vault.sh
81a515050e5d312ac4a453fa1bdaa999cfc11ad6a652659776bf5747c6b69168  linux/dependency-advisory-allowlist.json
9754d4c72b9a3c608f1ed1efda0d1ff7ae12f8d6be555ccd618466b8125c9269  linux/dependency-policy.json
c1334694748167d8781713b3a74fe184b8a549dfde457a500233a97999e8f644  linux/devfleet-backup
f12c94fa0f12ba9482cbf8b10de3dfc5211d46f01863498af2a1a5d14849479e  linux/devfleet-configure-backup
ad369c63d0363aa359ce1e34d37deeeb2947fc7d90f8a137cc4c14756b3e0017  linux/devfleet-docker-mode-report
11e17775c3f5a9dc5a59e79d70aeb2adcb0f25a0a1a6b4ecaafb1feefd1fd78a  linux/devfleet-health
9a542f43851dfe31cc37928d650463e5724e6f0156fbe484b95a101645ec16cf  linux/devfleet-join-deployment
cf80700961b1878e3de64867c67b293c44832cb0b70e59510081cbe7bfc487a1  linux/devfleet-purge-quarantine
2d46e7a6e2797b33eb61c8c7aa516cad8f735a65725ff4819ce6abd5516d9b13  linux/devfleet-register-node
0a3bc23dcf346c88d89fcc37bea30033b7d94b2f5649df6ab23e9721aefe32f5  linux/devfleet-repair
426640f394e023de9d6f9be723b58d1ac2a42c83c528e0221a7c1a7018f13c23  linux/devfleet-restore-project
226ad81de29d261ac0cfb014556729cb97004305cf151c60261ca5ae1505d09e  linux/devfleet-rotate-compute-secrets
31cffd4c26ea1fd3e50ca108f7dced492159e5504673a17b6b7c0a624f347724  linux/devfleet-rotate-vault-secrets
4a64a44a1d8a921bdededc65b093541ebd7c613430b414e0ea0445af4c04a7a6  linux/devfleet-safe-update
502799d1a0beca07f2605b1b767aaf8babc938c8e55f6d8af0ff4827b08fa830  linux/devfleet-set-peer
6773950522775354abe07a698c24bdce8b7f73b458e5963e308e8b64f44cf056  linux/devfleet-switch-docker-mode
eb6f98d1459e8fdae8b0bc3f7c8ba7d0164ce964a86d9d8c7277f936430c6e5a  linux/devfleet-user-repair
fcdfdcd5762286fafa0b2ce8a14353f9bf404717472515a8d43efa4f3e3a54b9  linux/devfleet-vault-broker
aef4f5a6daa89f7a2e669a1e773e32e358801c242458b4a36da0e02769114763  linux/devfleet-vault-health
bd9c01d8bf3ae54bbeba5f37b23d7dedc7e0a4a0778559d9c388f1b085e0c073  linux/devfleet-vault-maintenance
245458f58ef1a87ffd19abe2d6e3112e812d9b4ca6151158658be5f32b563fbb  linux/devfleet-vault-request
f754f18cf80416026dea3f0a0b37772b419751aaec0198fd914c1ab87d8b5aec  linux/upgrade-compute.sh
6a96ba0e2d5a8296fb90f474da9d2f0173d3e41eba18965513f711104155f913  pytest.ini
ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f  templates/cpp-cmake/.ai-bridge/chatgpt-memory.md
95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd  templates/cpp-cmake/.ai-bridge/codexpro-project-instructions.md
7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb  templates/cpp-cmake/.ai-bridge/current-plan.template.md
d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135  templates/cpp-cmake/.ai-bridge/prompts/broken-session-recovery.md
a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02  templates/cpp-cmake/.ai-bridge/prompts/handoff-template.md
5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab  templates/cpp-cmake/.ai-bridge/prompts/reconnect.md
95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd  templates/cpp-cmake/.ai-bridge/prompts/session-bootstrap.md
445934f639925a25401e37333f549c7f1a0cb1cbd7521b7ee6309da00f64e622  templates/cpp-cmake/.devcontainer/devcontainer.json
0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a  templates/cpp-cmake/.devfleet/bootstrap.sh
18459cba289cd6d0dd94081388234128aff3b7ac8e3609488569764af30ede0b  templates/cpp-cmake/.devfleet/codexpro-bootstrap.sh
c7e30a70af40b8cbc64cd6db3f091ee908a8ccc70549780005b797fc9108fb44  templates/cpp-cmake/.devfleet/codexpro-profile.json
86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30  templates/cpp-cmake/.devfleet/codexpro.env.example
04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311  templates/cpp-cmake/.devfleet/health-check.sh
cd4d78db29dabe909a6929b0a1dfb066d98d2b80bd59e490c1bd10a4fd6a0cb5  templates/cpp-cmake/.devfleet/project-tools.json
95f6ec94983aec4d5f36460826e0d26aac2db481c25966728953d2f566f6cd31  templates/cpp-cmake/.devfleet/smoke-test.sh
e8b1109631cc35fe43568d05bcea8b28ce2128bbd52569515296c481a901ab95  templates/cpp-cmake/.devfleet/template.json
05f9463d683e5957ca2f7cad77a5fec2986298b1ea3c6ca314174805fa1aff44  templates/cpp-cmake/.editorconfig
8844bf55ab9a454e01fbeec045b6747de22e56d73b2e5dbb6dfd27228e84c7fe  templates/cpp-cmake/.gitignore
228588bd8182b53ca0721b1342685e32c7afcb7f681cb513b87ab3e705cc8850  templates/cpp-cmake/README.md
0aa515e43796e07025f2cfdcb121e0d6edad4cfea877399c65fa066a4ced6231  templates/cpp-cmake/compose.yaml
7f2df08e2676a8a97abf899c5b7c2caa96209ba308a6fde7c1fd527cb09fea23  templates/cpp-cmake/docs/architecture.md
ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f  templates/data-r/.ai-bridge/chatgpt-memory.md
95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd  templates/data-r/.ai-bridge/codexpro-project-instructions.md
7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb  templates/data-r/.ai-bridge/current-plan.template.md
d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135  templates/data-r/.ai-bridge/prompts/broken-session-recovery.md
a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02  templates/data-r/.ai-bridge/prompts/handoff-template.md
5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab  templates/data-r/.ai-bridge/prompts/reconnect.md
95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd  templates/data-r/.ai-bridge/prompts/session-bootstrap.md
31743d0b403e9a20eb3dffd87c5033c90bd0c28a0f522633bef1b18235b2c065  templates/data-r/.devcontainer/devcontainer.json
0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a  templates/data-r/.devfleet/bootstrap.sh
18459cba289cd6d0dd94081388234128aff3b7ac8e3609488569764af30ede0b  templates/data-r/.devfleet/codexpro-bootstrap.sh
c7e30a70af40b8cbc64cd6db3f091ee908a8ccc70549780005b797fc9108fb44  templates/data-r/.devfleet/codexpro-profile.json
86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30  templates/data-r/.devfleet/codexpro.env.example
04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311  templates/data-r/.devfleet/health-check.sh
808c6a308c2e68d82e7f1c74e27f98b5dbf5903e1bfac70b9f777c890ca22ba2  templates/data-r/.devfleet/project-tools.json
95f6ec94983aec4d5f36460826e0d26aac2db481c25966728953d2f566f6cd31  templates/data-r/.devfleet/smoke-test.sh
dea898a52612bca2c9967c01ec0b59e60d44992986a9ec64fbdde3045321573c  templates/data-r/.devfleet/template.json
05f9463d683e5957ca2f7cad77a5fec2986298b1ea3c6ca314174805fa1aff44  templates/data-r/.editorconfig
8844bf55ab9a454e01fbeec045b6747de22e56d73b2e5dbb6dfd27228e84c7fe  templates/data-r/.gitignore
ec91ebe76515639ed04056aa7dfe14f3c47c5c3c776de81f647565c4d6acfacd  templates/data-r/README.md
1c84cd5554f19af11ea76022af21546d1e08f6bb4abb34bf8ad42ec3b6009581  templates/data-r/compose.yaml
6cd72cb5a51cac627cba6256f617c70778cdb34113460b0fb596310a276240f8  templates/data-r/docs/architecture.md
ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f  templates/dotnet-service/.ai-bridge/chatgpt-memory.md
95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd  templates/dotnet-service/.ai-bridge/codexpro-project-instructions.md
7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb  templates/dotnet-service/.ai-bridge/current-plan.template.md
d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135  templates/dotnet-service/.ai-bridge/prompts/broken-session-recovery.md
a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02  templates/dotnet-service/.ai-bridge/prompts/handoff-template.md
5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab  templates/dotnet-service/.ai-bridge/prompts/reconnect.md
95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd  templates/dotnet-service/.ai-bridge/prompts/session-bootstrap.md
445934f639925a25401e37333f549c7f1a0cb1cbd7521b7ee6309da00f64e622  templates/dotnet-service/.devcontainer/devcontainer.json
ec1e677581abb22ca7a86b4ef7e3c86708659f0784584daf6afb44125415a074  templates/dotnet-service/.devfleet/bootstrap.sh
18459cba289cd6d0dd94081388234128aff3b7ac8e3609488569764af30ede0b  templates/dotnet-service/.devfleet/codexpro-bootstrap.sh
c7e30a70af40b8cbc64cd6db3f091ee908a8ccc70549780005b797fc9108fb44  templates/dotnet-service/.devfleet/codexpro-profile.json
86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30  templates/dotnet-service/.devfleet/codexpro.env.example
04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311  templates/dotnet-service/.devfleet/health-check.sh
26721a1313e9b66ca20366a2046829a6e9525653ad509d68f5349c5ccd7c5e4d  templates/dotnet-service/.devfleet/project-tools.json
95f6ec94983aec4d5f36460826e0d26aac2db481c25966728953d2f566f6cd31  templates/dotnet-service/.devfleet/smoke-test.sh
cc65f3a10f3a1bf7574b82bccbba88dddb891571c56be4cf007cc42a7efb012c  templates/dotnet-service/.