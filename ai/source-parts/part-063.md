# DevFleet source part 063

Full-source UTF-8 byte interval [2883000, 2929500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 85d8a3c30c5a44fd8470e16e2a5aca79daf0e386b7f94ab9fa356830fed1982c

<!-- BEGIN SOURCE SLICE -->
Fleet.Setup.csproj') },
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
16dcbabf33e13d0f8c66db25e104366f877d8c99e0eff2933aad90ab47272fcc  MIGRATION-