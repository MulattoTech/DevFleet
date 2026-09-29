# DevFleet source part 056

Full-source UTF-8 byte interval [2557500, 2604000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ff4163df6b01c4bc6a1a9423fc08ec826a18948a174af2918be9129ac901a73a

<!-- BEGIN SOURCE SLICE -->
ceptance gates remain unpromoted until exact-candidate evidence exists.') | Set-Content -LiteralPath (Join-Path $workspaceRoot 'finalization-state.txt') -Encoding utf8
$preSignExe=[ordered]@{path="outputs/DevFleet-Setup-v$devfleetVersion-win-x64.exe";bytes=(Get-Item $unsignedExe).Length;sha256=(Get-FileHash $unsignedExe -Algorithm SHA256).Hash.ToLowerInvariant();authenticodeStatus=[string](Get-AuthenticodeSignature -LiteralPath $unsignedExe).Status}
if(-not $UnsignedDeveloperBuild){
  if($preSignExe.authenticodeStatus -ne 'NotSigned'){throw 'RELEASE BLOCKED — final build output was already signed before the selected signing profile ran.'}
  $tool=if($SignToolPath){$SignToolPath}elseif($env:DEVFLEET_SIGNTOOL_PATH){$env:DEVFLEET_SIGNTOOL_PATH}else{(Get-Command signtool.exe -ErrorAction SilentlyContinue).Source}
  $dlib=if($SigningDlibPath){$SigningDlibPath}else{$env:DEVFLEET_SIGNING_DLIB_PATH}
  $metadata=if($SigningMetadataPath){$SigningMetadataPath}else{$env:DEVFLEET_SIGNING_METADATA_PATH}
  $privateIdentity=$null;$timestampState='NOT TIMESTAMPED';$signtoolVerification='UNAVAILABLE — SignTool not installed'
  if($SigningProfile -eq 'PrivateSelfSigned'){
    $privateIdentity=$privateIdentityPreflight
    $thumbprint=[string]$privateIdentity.thumbprint
    if($CertificateThumbprint -and $CertificateThumbprint -cne $thumbprint){throw 'Configured certificate thumbprint does not match the persisted DevFleet private signing identity.'}
    if($tool){
      if(-not(Test-Path -LiteralPath $tool)){throw 'RELEASE BLOCKED — SIGNTOOL PATH IS INVALID.'}
      & $tool sign /v /sha1 $thumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $unsignedExe
      $timestampExit=$LASTEXITCODE
      if($timestampExit){
        $afterTimestampAttempt=Get-AuthenticodeSignature -LiteralPath $unsignedExe
        if($afterTimestampAttempt.Status -eq 'NotSigned'){
          & $tool sign /v /sha1 $thumbprint /fd SHA256 $unsignedExe
          if($LASTEXITCODE){throw "Private Authenticode signing without a timestamp failed with exit code $LASTEXITCODE."}
        }elseif($afterTimestampAttempt.Status -ne 'Valid' -or $afterTimestampAttempt.SignerCertificate.Thumbprint -cne $thumbprint){
          throw "Private Authenticode timestamp attempt failed with exit code $timestampExit and left an unusable signature; the artifact was not double-signed."
        }
        $timestampState='NOT TIMESTAMPED — RFC3161 timestamp unavailable; private SignTool signing completed without a timestamp'
      }else{$timestampState='RFC3161 TIMESTAMPED'}
    }else{
      $certificate=Get-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint"
      $setResult=Set-AuthenticodeSignature -LiteralPath $unsignedExe -Certificate $certificate -HashAlgorithm SHA256
      if($setResult.Status -ne 'Valid'){throw "Private Authenticode fallback signing failed: $($setResult.Status)"}
      $timestampState='NOT TIMESTAMPED — SignTool unavailable; Set-AuthenticodeSignature fallback used'
    }
  }else{
    $thumbprint=if($CertificateThumbprint){$CertificateThumbprint}else{$env:DEVFLEET_SIGNING_CERTIFICATE_THUMBPRINT}
    if($tool -and $dlib -and $metadata){
      if(-not (Test-Path -LiteralPath $tool) -or -not (Test-Path -LiteralPath $dlib) -or -not (Test-Path -LiteralPath $metadata)){throw 'RELEASE BLOCKED — AUTHENTICODE SIGNING INPUT PATH IS INVALID.'}
      & $tool sign /v /debug /fd SHA256 /tr $TimestampUrl /td SHA256 /dlib $dlib /dmdf $metadata $unsignedExe
    }elseif($tool -and $thumbprint){
      if(-not (Test-Path -LiteralPath $tool)){throw 'RELEASE BLOCKED — SIGNTOOL PATH IS INVALID.'}
      & $tool sign /v /sha1 $thumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $unsignedExe
    }else{throw 'RELEASE BLOCKED — AUTHENTICODE PUBLISHER IDENTITY REQUIRED'}
    if($LASTEXITCODE){throw "Authenticode signing failed with exit code $LASTEXITCODE."}
    $timestampState='RFC3161 TIMESTAMPED'
  }
  $verifyText=Join-Path $outputs 'authenticode-verification.txt'
  if($tool){
    & $tool verify /pa /v $unsignedExe 2>&1 | Set-Content -LiteralPath $verifyText
    if($LASTEXITCODE){throw 'SignTool /pa verification failed.'}
    $signtoolVerification='PASS'
  }else{
    'UNAVAILABLE — SignTool is not installed; Get-AuthenticodeSignature verification is authoritative for this private build.' | Set-Content -LiteralPath $verifyText
  }
  $signature=Get-AuthenticodeSignature -LiteralPath $unsignedExe
  if($signature.Status -ne 'Valid'){throw "Get-AuthenticodeSignature did not return Valid: $($signature.Status)"}
  if($SigningProfile -eq 'PrivateSelfSigned'){
    if($signature.SignerCertificate.Thumbprint -cne [string]$privateIdentity.thumbprint){throw 'Private Authenticode signer thumbprint does not match the expected DevFleet identity.'}
    if('1.3.6.1.5.5.7.3.3' -notin @($signature.SignerCertificate.EnhancedKeyUsageList|ForEach-Object{[string]$_.ObjectId})){throw 'Private Authenticode signer lacks the Code Signing EKU.'}
  }
  $tamperedCopy=Join-Path $outputs ".authenticode-tamper-$([guid]::NewGuid().ToString('N')).exe"
  try{
    Copy-Item -LiteralPath $unsignedExe -Destination $tamperedCopy
    $stream=[IO.File]::Open($tamperedCopy,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$stream.Position=4096;$originalByte=$stream.ReadByte();$stream.Position=4096;$stream.WriteByte(($originalByte -bxor 1))}finally{$stream.Dispose()}
    $tamperedStatus=[string](Get-AuthenticodeSignature -LiteralPath $tamperedCopy).Status
    if($tamperedStatus -eq 'Valid'){throw 'Tampered Authenticode probe unexpectedly remained valid.'}
  }finally{Remove-Item -LiteralPath $tamperedCopy -Force -ErrorAction SilentlyContinue}
  $signedTest=Join-Path $outputs 'signed-self-test.txt';$env:DEVFLEET_SELF_TEST_OUTPUT=$signedTest
  $signedProcess=Start-Process -FilePath $unsignedExe -ArgumentList '--self-test' -Wait -PassThru
  Remove-Item Env:DEVFLEET_SELF_TEST_OUTPUT -ErrorAction SilentlyContinue
  if($signedProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $signedTest) -or (Get-Content -LiteralPath $signedTest -Raw) -notmatch '(?m)^PASS(?:\r?$)'){throw 'Signed installer self-test failed.'}
  Assert-StageShippingIdentity 'post-sign'

  $artifactRows[0]=[ordered]@{name='exe';path="outputs/DevFleet-Setup-v$devfleetVersion-win-x64.exe";bytes=(Get-Item $unsignedExe).Length;sha256=(Get-FileHash $unsignedExe -Algorithm SHA256).Hash.ToLowerInvariant()}
  & $releasePython (Join-Path $buildSource 'tools\release_fingerprint.py') --source-root $buildSource --installer-root $buildInstaller --output (Join-Path $outputs 'release-fingerprint.json') --artifact "exe=$unsignedExe" --artifact "tar=$tar" --artifact "portable=$portable" --artifact "installerSource=$sourceZip"
  if($LASTEXITCODE){throw 'Signed final release fingerprint generation failed.'}
  $fingerprintObject=Get-Content (Join-Path $outputs 'release-fingerprint.json') -Raw|ConvertFrom-Json
  $signingState=if($SigningProfile -eq 'PrivateSelfSigned'){'PRIVATE SELF-SIGNED AUTHENTICODE — VALID ON EXPLICITLY TRUSTED PERSONAL/TEST SYSTEMS'}else{'AUTHENTICODE SIGNED — VALID PUBLIC SIGNING PATH'}
  $currentTooling.releaseFingerprintId=$fingerprintObject.releaseFingerprintId;$currentTooling.toolingFingerprintId=$fingerprintObject.toolingFingerprint.toolingFingerprintId;$currentTooling.artifacts=$artifactRows
  [IO.File]::WriteAllText($currentToolingPath,(($currentTooling|ConvertTo-Json -Depth 12)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
  $finalManifest.releaseFingerprintId=$fingerprintObject.releaseFingerprintId;$finalManifest.toolingFingerprintId=$fingerprintObject.toolingFingerprint.toolingFingerprintId;$finalManifest.artifacts=$artifactRows;$finalManifest.signingState=$signingState;$finalManifest.signing=$signingState;$finalManifest.preSignExe=$preSignExe;$finalManifest.publicPromotionAllowed=$false
  if($SigningProfile -eq 'PrivateSelfSigned'){$finalManifest.privateSigningProfile='PRIVATE_SELF_SIGNED';$finalManifest.privateSigningCertificateThumbprint=[string]$privateIdentity.thumbprint;$finalManifest.publicPublisherTrust=$false;$finalManifest.timestampState=$timestampState}
  $finalManifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $outputs 'final-artifact-hashes.json') -Encoding utf8
  $state.releaseFingerprintId=$fingerprintObject.releaseFingerprintId;$state.toolingFingerprintId=$fingerprintObject.toolingFingerprint.toolingFingerprintId;$state.signing_state=$signingState;$state.candidate.exe=$artifactRows[0];$state.pre_sign_exe=$preSignExe
  if($SigningProfile -eq 'PrivateSelfSigned'){$state.private_signing_profile='PRIVATE_SELF_SIGNED';$state.private_signing_certificate_thumbprint=[string]$privateIdentity.thumbprint;$state.public_publisher_trust=$false;$state.timestamp_state=$timestampState}
  $state|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $workspaceRoot 'finalization-state.json') -Encoding utf8
  $publicCertificateRecord=$null
  if($SigningProfile -eq 'PrivateSelfSigned'){
    $publicCertificateOutput=Join-Path $outputs 'DevFleet-Private-Personal-Code-Signing.cer'
    Copy-Item -LiteralPath ([string]$privateIdentity.publicCertificatePath) -Destination $publicCertificateOutput -Force
    $publicCertificateRecord=[ordered]@{path='outputs/DevFleet-Private-Personal-Code-Signing.cer';bytes=(Get-Item $publicCertificateOutput).Length;sha256=(Get-FileHash $publicCertificateOutput -Algorithm SHA256).Hash.ToLowerInvariant()}
  }
  [ordered]@{provider=if($SigningProfile -eq 'PrivateSelfSigned' -and $tool){'Windows certificate store / SignTool'}elseif($SigningProfile -eq 'PrivateSelfSigned'){'Windows certificate store / Set-AuthenticodeSignature fallback'}elseif($dlib){'Azure Artifact Signing'}else{'Windows certificate store'};signingProfile=$SigningProfile;timestampState=$timestampState;signatureStatus=$signature.Status;signerSubject=$signature.SignerCertificate.Subject;signerThumbprint=$signature.SignerCertificate.Thumbprint;codeSigningEkuVerified=$true;signtoolVerification=$signtoolVerification;tamperedCopyStatus=$tamperedStatus;preSignExe=$preSignExe;finalSignedExe=$artifactRows[0];publicCertificate=$publicCertificateRecord;publicPublisherTrust=($SigningProfile -ne 'PrivateSelfSigned');publicPromotionAllowed=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputs 'signing-provider.json')
  @("DevFleet $devfleetVersion / Installer $installerVersion","Status: signed candidate current; awaiting exact-candidate clean FullRelease","Git commit: $candidateGitCommit","Release fingerprint: $($fingerprintObject.releaseFingerprintId)","Tooling fingerprint: $($fingerprintObject.toolingFingerprint.toolingFingerprintId)","Signing state: $signingState",'Source changed since candidate: FALSE','Rebuild required: FALSE','Candidate is current: TRUE','Public promotion allowed: FALSE')|Set-Content -LiteralPath (Join-Path $workspaceRoot 'finalization-state.txt') -Encoding utf8
}else{Write-Warning 'Unsigned developer build explicitly requested; this artifact is not release eligible.'}
Write-Host "Release complete: $outputs"

```


## FILE: installer-source/CLEAN-REINSTALL.md

SHA256: 2d564d5f20f75e8314e0dba9690fc8231484a0357e8ea3ec3809d302dda98522 | Bytes: 334 | Git mode: 100644

```
# Clean Reinstall

Clean Reinstall creates a redacted recovery ZIP, preserves projects, VMs, backups, identities, and data by default, removes installer-owned control-plane integration, installs the verified current payload through the production orchestrator, and reconciles preserved state. It never silently becomes Factory Reset.

```


## FILE: installer-source/CLEAN-ROOM-INSTALL.md

SHA256: 51442b27ee7597662af6ac6898437565945da71078dcb4b256ee199f939cab3c | Bytes: 617 | Git mode: 100644

```
# Clean-room installation

Supported release profile: Windows 11 Pro x64, fully patched, Internet-connected,
administrator/UAC available, and hardware virtualization available. A clean test host
must have no DevFleet, PowerShell 7, Git, Multipass, or DevFleet VMs. MULATTOTECHBOX is
only a build/reference host and is never a clean-room target.

Run the current `DevFleet-Setup-v<DevFleet VERSION>-win-x64.exe`; record preflight, dependency resolution,
UAC, reboot/resume, role, Multipass, guest bootstrap, SSH, dashboard, and maintenance
evidence. Do not treat mocked providers or source inspection as E2E evidence.

```


## FILE: installer-source/CODE-SIGNING.md

SHA256: ac28c26aace63647228cb0d0900fe8906a653d686950be63f6455a4044e0cf94 | Bytes: 1359 | Git mode: 100644

```
# Authenticode signing

Release signing uses Microsoft Azure Artifact Signing with SignTool, SHA-256, and the
RFC 3161-compatible `http://timestamp.acs.microsoft.com` timestamp service, or a
legitimate certificate-store identity with protected private key. The normal
`Build-Release.ps1` fails closed when no identity is configured. Only
`-UnsignedDeveloperBuild` permits an unsigned inner-loop build; it is not release
eligible. Verify with `signtool verify /pa /v` and `Get-AuthenticodeSignature` and run
the signed self-test before calculating the distributed hash.

Private/personal releases may explicitly use `-SigningProfile PrivateSelfSigned`.
That profile creates or reuses one exact-subject, RSA-3072, SHA-256 Code Signing
certificate in `CurrentUser/My`, requires a non-exportable private key, persists only
public metadata under `%LOCALAPPDATA%\DevFleet\Signing\PrivateSelfSigned`, and trusts
only the exported public certificate in the signing user's Root and Trusted Publishers
stores. Windows may require the interactive owner-consent prompt for the Root import;
the release gate blocks until that exact thumbprint is present. It never creates a PFX
and never enables public promotion. This profile means
cryptographically signed and valid only on explicitly trusted personal/test systems;
it does not mean publicly trusted publisher identity.

```


## FILE: installer-source/DEPENDENCY-RESOLUTION.md

SHA256: 751d08beb7dc8bc6e9416791b8f488718959cbc6bd3b6e1c50818bba3b8e26b2 | Bytes: 580 | Git mode: 100644

```
# Dependency resolution

`dependencies.json` is the single catalog consumed by WPF and PowerShell. Detection
uses PATH, App Paths, registry, and known vendor locations, then probes version and
compatibility. Only Compatible and Compatible-Newer states are preserved automatically;
Outdated is updated, Broken is repaired/reinstalled, and Unsupported-Major is blocked.

Every downloaded executable is restricted to an official vendor source and checked for
expected file type and Authenticode signer before execution. Post-install discovery and
version verification are mandatory.

```


## FILE: installer-source/DevFleet.Setup.Tests/DevFleet.Setup.Tests.csproj

SHA256: 7d50c80ae886b551e3deeb53df04bcf0800402cfb5d87c3c56efb7fcac6febf7 | Bytes: 586 | Git mode: 100644

```
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <EnableWindowsTargeting>true</EnableWindowsTargeting>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\DevFleet.Setup\DevFleet.Setup.csproj" GlobalPropertiesToRemove="SelfContained;RuntimeIdentifier;PublishSingleFile" />
  </ItemGroup>

</Project>

```


## FILE: installer-source/DevFleet.Setup.Tests/Program.cs

SHA256: f681ebed4f6fab1cd8a13584846834f15ad16739d4a753b193b34861d91cc841 | Bytes: 46971 | Git mode: 100644

```
using DevFleet.Setup;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;

// Test mode is an explicit fixture capability, never inferred from a debugger,
// process name, or user-controlled environment variable in the Release binary.
TestEnvironment.EnableForTests();

static void Assert(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

static void AssertInheritedPipeDescendant(int expectedExitCode)
{
    var pidPath = Path.Combine(Path.GetTempPath(), "devfleet-inherited-pipe-" + Guid.NewGuid().ToString("N") + ".pid");
    var descendantPid = 0;
    try
    {
        var escapedPidPath = pidPath.Replace("'", "''", StringComparison.Ordinal);
        var parentCommand = "$childInfo=[Diagnostics.ProcessStartInfo]::new();$childInfo.FileName=(Get-Command powershell.exe).Source;$childInfo.UseShellExecute=$false;$childInfo.CreateNoWindow=$true;$childInfo.ArgumentList.Add('-NoProfile');$childInfo.ArgumentList.Add('-NonInteractive');$childInfo.ArgumentList.Add('-Command');$childInfo.ArgumentList.Add('Start-Sleep -Seconds 30');$child=[Diagnostics.Process]::Start($childInfo);[IO.File]::WriteAllText('" + escapedPidPath + "',[string]$child.Id);[Console]::Out.Write('parent-output');exit " + expectedExitCode;
        var timer = System.Diagnostics.Stopwatch.StartNew();
        var result = new ProcessRunner().Run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", parentCommand]);
        timer.Stop();
        Assert(timer.Elapsed < TimeSpan.FromSeconds(15), $"ProcessRunner exceeded its bounded post-exit drain allowance for direct exit {expectedExitCode}: {timer.Elapsed}.");
        Assert(result.ExitCode == expectedExitCode, $"ProcessRunner lost direct exit code {expectedExitCode} when a descendant retained redirected handles.");
        Assert(!result.OutputComplete, $"ProcessRunner incorrectly reported complete output for inherited-handle direct exit {expectedExitCode}.");
        Assert(File.Exists(pidPath) && int.TryParse(File.ReadAllText(pidPath), out descendantPid), "Inherited-handle fixture did not publish its descendant PID.");
        using var descendant = System.Diagnostics.Process.GetProcessById(descendantPid);
        descendant.Refresh();
        Assert(!descendant.HasExited, "ProcessRunner killed a descendant merely to manufacture redirected-output EOF.");
    }
    finally
    {
        if (descendantPid > 0)
        {
            try
            {
                using var descendant = System.Diagnostics.Process.GetProcessById(descendantPid);
                if (!descendant.HasExited) descendant.Kill(entireProcessTree: true);
                descendant.WaitForExit(5000);
            }
            catch { }
        }
        try { File.Delete(pidPath); } catch { }
    }
}

// ACL trust classification must use primitive mutation bits only.  In
// particular, read/read-execute and synchronization are not write authority,
// while composite Modify/FullControl still intersect the primitive mask.
Assert(!OwnedPathSafety.HasPrimitiveMutationRights(FileSystemRights.Read), "Users Read must not be treated as mutation authority.");
Assert(!OwnedPathSafety.HasPrimitiveMutationRights(FileSystemRights.ReadAndExecute), "Users ReadAndExecute must not be treated as mutation authority.");
foreach (var right in new[] {
    FileSystemRights.WriteData,
    FileSystemRights.AppendData,
    FileSystemRights.WriteAttributes,
    FileSystemRights.WriteExtendedAttributes,
    FileSystemRights.Delete,
    FileSystemRights.DeleteSubdirectoriesAndFiles,
    FileSystemRights.ChangePermissions,
    FileSystemRights.TakeOwnership,
    FileSystemRights.Modify,
    FileSystemRights.FullControl,
}) Assert(OwnedPathSafety.HasPrimitiveMutationRights(right), $"{right} must be treated as mutation authority.");
Assert(!OwnedPathSafety.HasPrimitiveMutationRights(FileSystemRights.ReadAttributes | FileSystemRights.ReadExtendedAttributes | FileSystemRights.ReadPermissions | FileSystemRights.ExecuteFile | FileSystemRights.Synchronize), "Read-only broad ACE rights must not be treated as mutation authority.");
Assert(OwnedPathSafety.IsBroadUntrustedPrincipal("Everyone") && OwnedPathSafety.IsBroadUntrustedPrincipal("BUILTIN\\Users") && OwnedPathSafety.IsBroadUntrustedPrincipal("NT AUTHORITY\\Authenticated Users"), "Broad-user principal classification is incomplete.");
Assert(!OwnedPathSafety.IsBroadUntrustedPrincipal("BUILTIN\\Administrators") && !OwnedPathSafety.IsBroadUntrustedPrincipal("NT AUTHORITY\\SYSTEM"), "Administrators/System must remain outside broad-user classification.");
Console.WriteLine("PASS ACL primitive mutation-rights regressions A-M");

if (OperatingSystem.IsWindows())
{
    var productionAcl = SecureStagingService.BuildDirectorySecurity(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "M-TechLabs", "DevFleet", "InstallerCache"));
    var productionSids = productionAcl.GetAccessRules(true, false, typeof(SecurityIdentifier)).Cast<FileSystemAccessRule>().Select(rule => rule.IdentityReference.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
    Assert(productionSids.SetEquals(["S-1-5-18", "S-1-5-32-544"]), "Production staging ACL must remain exactly SYSTEM and Administrators.");

    var selfTestAclRoot = Path.Combine(Path.GetTempPath(), "DevFleet-Setup-SelfTest-" + Guid.NewGuid().ToString("N"));
    var selfTestCache = Path.Combine(selfTestAclRoot, "state", "InstallerCache");
    var selfTestTransaction = Path.Combine(selfTestCache, "1.2.13", "self-test");
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
File.WriteAllText(backupManifest, System.Text.Json.JsonSerializer.Serialize(new { project_id = "project-demo