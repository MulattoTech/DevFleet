# DevFleet source part 111

Full-source UTF-8 byte interval [5115000, 5161500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: febd32d445feb9181dd87bed89f2ae1c735bdcc0c4cd4e9a74abdcabb4bf0fa9

<!-- BEGIN SOURCE SLICE -->
TaskStatus]::RanToCompletion){$stdoutTask.GetAwaiter().GetResult()}else{''}
        $stderr=if($stderrTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderrTask.GetAwaiter().GetResult()}else{''}
        $combined=($stdout+"`n"+$stderr).Trim()
        if($logWriter){$logWriter.Write($combined);if(-not $outputComplete){$logWriter.Write("`n[DEVFLEET_OUTPUT_INCOMPLETE_AFTER_PROCESS_EXIT]")};$logWriter.Flush()}
        $diagnostic=if($combined.Length -gt $MaxDiagnosticChars){$combined.Substring($combined.Length-$MaxDiagnosticChars)}else{$combined}
        if(-not $outputComplete){
            $message="External command exited with code $exitCode, but redirected output was incomplete after the bounded post-exit drain: $FilePath $($safeArguments -join ' ')"
            if($Capture){throw $message}
            if($exitCode -notin $AllowedExitCodes -and -not $IgnoreExitCode){throw "$message`n$diagnostic"}
            Write-Warning $message
            return
        }
        if($exitCode -notin $AllowedExitCodes -and -not $IgnoreExitCode){throw "$FilePath failed with exit code $exitCode`n$diagnostic"}
        if($inputError){throw "External command input delivery failed: $FilePath $($safeArguments -join ' ')`n$inputError"}
        if($Capture){return $combined}
    } finally {if($logWriter){$logWriter.Dispose()};$process.Dispose()}
}

function Invoke-MultipassWithStandardInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$InstanceName,
        [Parameter(Mandatory)][string[]]$CommandArgumentList,
        [Parameter(Mandatory)][AllowEmptyString()][string]$StandardInputText,
        [int]$TimeoutSeconds=900,
        [datetime]$DeadlineUtc=[datetime]::MinValue,
        [switch]$Capture,
        [string]$ExpectedCompletionMarkerPattern=''
    )
    if($InstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or -not $CommandArgumentList.Count){throw 'Multipass input command identity is malformed.'}
    if([string]::IsNullOrEmpty($StandardInputText)){throw 'Multipass input delivery requires a nonempty byte stream.'}
    $remoteCommand=(@($CommandArgumentList|ForEach-Object{ConvertTo-ShellSingleQuotedScalar $_}) -join ' ')
    $ownerDeadline=[datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    if($DeadlineUtc -gt [datetime]::MinValue -and $DeadlineUtc.ToUniversalTime() -lt $ownerDeadline){$ownerDeadline=$DeadlineUtc.ToUniversalTime()}
    $context=Get-DevFleetDeadlineContext
    if($context -and ([datetime]$context.StageDeadlineUtc).ToUniversalTime() -lt $ownerDeadline){$ownerDeadline=([datetime]$context.StageDeadlineUtc).ToUniversalTime()}
    # Reserve cleanup inside the existing owner; no command receives a fresh
    # full timeout after staging or a slow transfer.
    $workDeadline=$ownerDeadline.AddSeconds(-15)
    $cleanupDeadline=$ownerDeadline.AddSeconds(-5)
    if($workDeadline -le [datetime]::UtcNow){throw 'Insufficient owning deadline for Multipass input delivery and cleanup.'}
    $directory='/run/devfleet-input-'+[guid]::NewGuid().ToString('N')
    $inputPath="$directory/input"
    $quotedDirectory=ConvertTo-ShellSingleQuotedScalar $directory
    $quotedInput=ConvertTo-ShellSingleQuotedScalar $inputPath
    # Windows Multipass exec reads console events, not redirected stdin.
    # SFTP transfer '-' supports a byte stream. Create its destination first
    # in a fresh private tmpfs directory, so no host plaintext file or secret
    # argument is needed and SFTP cannot create a publicly reachable file.
    $prepare=@'
set -Eeuo pipefail; d=__DIRECTORY__; f=__INPUT__; created=0; trap 'rc=$?; if (( created )); then sudo rm -f -- "$f" || true; sudo rmdir -- "$d" || true; fi; exit "$rc"' EXIT; sudo mkdir -m 0700 -- "$d"; created=1; sudo chown "$(id -u):$(id -g)" -- "$d"; umask 077; : > "$f"; chmod 0600 -- "$f"; test ! -L "$d"; test "$(stat -c '%a:%u' -- "$d")" = "700:$(id -u)"; test ! -L "$f"; test "$(stat -c '%a:%u' -- "$f")" = "600:$(id -u)"; trap - EXIT
'@
    $consume=@'
set -Eeuo pipefail; d=__DIRECTORY__; f=__INPUT__; test ! -L "$d"; test -d "$d"; test "$(stat -c '%a:%u' -- "$d")" = "700:$(id -u)"; test ! -L "$f"; test -f "$f"; test -s "$f"; test "$(stat -c '%a:%u' -- "$f")" = "600:$(id -u)"; exec 3< "$f"; rm -f -- "$f"; sudo rmdir -- "$d"; exec 0<&3; exec 3<&-; exec __COMMAND__
'@
    $cleanup=@'
set -Eeuo pipefail; d=__DIRECTORY__; f=__INPUT__; if test -e "$d" || test -L "$d"; then test ! -L "$d"; test -d "$d"; test "$(stat -c '%a:%u' -- "$d")" = "700:$(id -u)"; if test -e "$f" || test -L "$f"; then test ! -L "$f"; test -f "$f"; test "$(stat -c '%u' -- "$f")" = "$(id -u)"; rm -f -- "$f"; fi; sudo rmdir -- "$d"; fi
'@
    $prepare=$prepare.Replace('__DIRECTORY__',$quotedDirectory).Replace('__INPUT__',$quotedInput)
    $consume=$consume.Replace('__DIRECTORY__',$quotedDirectory).Replace('__INPUT__',$quotedInput).Replace('__COMMAND__',$remoteCommand)
    $cleanup=$cleanup.Replace('__DIRECTORY__',$quotedDirectory).Replace('__INPUT__',$quotedInput)
    $acquired=$false;$primaryError=$null;$cleanupError=$null;$output=$null
    try {
        Invoke-External $FilePath @('exec',$InstanceName,'--','bash','-lc',$prepare) -TimeoutSeconds 60 -DeadlineUtc $workDeadline
        $acquired=$true
        Invoke-External $FilePath @('transfer','-',"${InstanceName}:$inputPath") -TimeoutSeconds 60 -DeadlineUtc $workDeadline -StandardInputText $StandardInputText
        if($ExpectedCompletionMarkerPattern){
            if(-not $Capture){throw 'Expected Multipass completion-marker handling requires captured output.'}
            # A guest command that changes its own network can finish the
            # authenticated operation and emit its sentinel while the outer
            # Multipass transport reports a nonzero status as its connection
            # is torn down. Accept that status only for this explicit marker
            # contract; preparation, transfer, cleanup, and all generic
            # callers remain strict about external exit codes.
            $output=Invoke-External $FilePath @('exec',$InstanceName,'--','bash','-lc',$consume) -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $workDeadline -Capture -IgnoreExitCode
            if(-not [regex]::IsMatch([string]$output,$ExpectedCompletionMarkerPattern,[Text.RegularExpressions.RegexOptions]::Multiline)){
                throw 'Multipass input command returned without its expected completion marker.'
            }
        }else{
            $output=Invoke-External $FilePath @('exec',$InstanceName,'--','bash','-lc',$consume) -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $workDeadline -Capture:$Capture
        }
    } catch {$primaryError=$_}
    finally {
        # No secret is sent until preparation acknowledges a fresh private
        # directory. Once acknowledged, cleanup is exact and non-recursive.
        if($acquired){
            try {Invoke-External $FilePath @('exec',$InstanceName,'--','bash','-lc',$cleanup) -TimeoutSeconds 10 -DeadlineUtc $cleanupDeadline}
            catch {$cleanupError=$_}
        }
        $StandardInputText=$null
    }
    if($primaryError){
        if($cleanupError){throw "Multipass input command failed: $($primaryError.Exception.Message)`nGuest input cleanup failed: $($cleanupError.Exception.Message)"}
        $PSCmdlet.ThrowTerminatingError($primaryError)
    }
    if($cleanupError){$PSCmdlet.ThrowTerminatingError($cleanupError)}
    if($Capture){return $output}
}

function New-DevFleetBootstrapBoundary {
    param(
        [Parameter(Mandatory)][ValidateSet('compute','vault')][string]$Kind,
        [Parameter(Mandatory)][string]$InstanceName,
        [Parameter(Mandatory)][string]$TransactionId,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][int]$BootstrapMaxSeconds,
        [Parameter(Mandatory)][string]$PackageVersion,
        [Parameter(Mandatory)][string]$NodeRole
    )
    if($InstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){throw 'Bootstrap instance identity is malformed.'}
    if($TransactionId -notmatch '^[0-9a-fA-F]{32}$' -or $PayloadSha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Bootstrap transaction or payload identity is malformed.'}
    if($BootstrapMaxSeconds -le 0){throw 'Bootstrap maximum must be a positive finite duration.'}
    if($Kind -eq 'compute'){
        if($PackageVersion -notmatch '^\d+\.\d+\.\d+$' -or $NodeRole -notin @('primary','surrogate')){throw 'Compute bootstrap version or role identity is malformed.'}
        $extraction="set -Eeuo pipefail; sudo rm -rf /tmp/devfleet-payload; mkdir /tmp/devfleet-payload; if ! unzip -q /tmp/devfleet-payload.zip -d /tmp/devfleet-payload; then sudo rm -rf /tmp/devfleet-payload /tmp/devfleet-payload.zip; exit 70; fi; test -f /tmp/devfleet-payload/linux/bootstrap-compute.sh"
        $bootstrap="set -Eeuo pipefail; trap 'sudo rm -rf /tmp/devfleet-payload /tmp/devfleet-payload.zip' EXIT; sudo bash /tmp/devfleet-payload/linux/bootstrap-compute.sh /tmp/devfleet-payload --secrets-stdin --transaction-id '$TransactionId' --payload-sha256 '$PayloadSha256' --bootstrap-max-seconds '$BootstrapMaxSeconds' --package-version '$PackageVersion' --node-role '$NodeRole'"
        $prefix="compute-$InstanceName"
    }else{
        if($PackageVersion -cne 'vault' -or $NodeRole -cne 'vault'){throw 'Vault bootstrap version or role identity is malformed.'}
        $extraction="set -Eeuo pipefail; sudo rm -rf /tmp/devfleet-vault-payload; mkdir /tmp/devfleet-vault-payload; if ! unzip -q /tmp/devfleet-vault-payload.zip -d /tmp/devfleet-vault-payload; then sudo rm -rf /tmp/devfleet-vault-payload /tmp/devfleet-vault-payload.zip; exit 70; fi; test -f /tmp/devfleet-vault-payload/linux/bootstrap-vault.sh"
        $bootstrap="set -Eeuo pipefail; trap 'sudo rm -rf /tmp/devfleet-vault-payload /tmp/devfleet-vault-payload.zip' EXIT; sudo bash /tmp/devfleet-vault-payload/linux/bootstrap-vault.sh /tmp/devfleet-vault-payload --secrets-stdin --transaction-id '$TransactionId' --payload-sha256 '$PayloadSha256' --bootstrap-max-seconds '$BootstrapMaxSeconds' --package-version 'vault' --node-role 'vault'"
        $prefix='vault'
    }
    [pscustomobject]@{
        kind=$Kind
        instanceName=$InstanceName
        multipassResolvedStageName="$prefix-multipass-resolved"
        isolationVerifiedStageName="$prefix-isolation-verified"
        instancePresentStageName="$prefix-instance-present"
        instanceAbsentStageName="$prefix-instance-absent"
        instanceStartedStageName="$prefix-instance-started"
        instanceLaunchedStageName="$prefix-instance-launched"
        instanceReadyStageName="$prefix-instance-ready"
        payloadTransferredStageName="$prefix-payload-transferred"
        payloadExtractedStageName="$prefix-payload-extracted"
        completionStageName=$prefix
        extractionCommand=$extraction
        bootstrapCommand=$bootstrap
        remoteCommand="$extraction; $bootstrap"
        bootstrapMaxSeconds=$BootstrapMaxSeconds
    }
}

function Test-CommandExists { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Get-DevFleetPowerShell {
    foreach($candidate in @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
    )) { if($candidate -and (Test-TrustedExecutableCandidate $candidate)){return $candidate} }
    throw 'No trusted machine PowerShell executable was found.'
}

function Get-CanonicalDependencyManifest {
    param([Parameter(Mandatory)][string]$PackageRoot)
    $path = Join-Path $PackageRoot 'dependencies.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Canonical dependency manifest is missing: $path" }
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.manifestVersion -ne (Get-Content (Join-Path $PackageRoot 'VERSION') -Raw).Trim()) { throw 'Canonical dependency manifest schema/version mismatch.' }
    if (-not $manifest.dependencies -or @($manifest.dependencies).Count -lt 1) { throw 'Canonical dependency manifest contains no dependency records.' }
    return $manifest
}

function Expand-DependencyLocation {
    param([Parameter(Mandatory)][string]$Path)
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Resolve-DependencyExecutable {
    param([Parameter(Mandatory)]$Dependency)
    foreach ($candidate in (Get-TrustedDependencyCandidates $Dependency)) { return $candidate }
    return $null
}

function Test-PrimitiveMutationRights {
    param([Parameter(Mandatory)][Security.AccessControl.FileSystemRights]$Rights)
    # Keep this mask primitive-only.  Modify and FullControl are composites;
    # their primitive mutation bits still intersect the mask naturally.
    $mutationMask = [Security.AccessControl.FileSystemRights]::WriteData -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    return (($Rights -band $mutationMask) -ne 0)
}

function Test-BroadUntrustedPrincipal {
    param([Parameter(Mandatory)][string]$Identity)
    return $Identity.Equals('Everyone',[StringComparison]::OrdinalIgnoreCase) -or
        $Identity.EndsWith('\Users',[StringComparison]::OrdinalIgnoreCase) -or
        $Identity.Equals('NT AUTHORITY\Authenticated Users',[StringComparison]::OrdinalIgnoreCase)
}

function Get-TrustedSystemRootForExecutable {
    param([Parameter(Mandatory)][string]$FullPath)
    try {
        $candidate = [IO.Path]::GetFullPath($FullPath).TrimEnd('\')
        $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:WINDIR) |
            Where-Object { $_ } |
            ForEach-Object { [IO.Path]::GetFullPath([string]$_).TrimEnd('\') } |
            Select-Object -Unique |
            Where-Object { $candidate.StartsWith($_ + '\',[StringComparison]::OrdinalIgnoreCase) }
        if (@($roots).Count -ne 1) { return $null }
        return [string]@($roots)[0]
    } catch { return $null }
}

function Get-TrustedWingetPackageCandidates {
    $result = [Collections.Generic.List[object]]::new()
    try {
        $windowsApps = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps')).TrimEnd('\')
        $windowsAppsInfo = Get-Item -LiteralPath $windowsApps -Force -ErrorAction Stop
        if (($windowsAppsInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return @() }
        foreach ($package in @(Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop)) {
            $installLocation = [string]$package.InstallLocation
            if ([string]::IsNullOrWhiteSpace($installLocation)) { continue }
            $root = [IO.Path]::GetFullPath($installLocation).TrimEnd('\')
            $rootInfo = Get-Item -LiteralPath $root -Force -ErrorAction Stop
            $basename = [IO.Path]::GetFileName($root)
            if (-not $package.Name.Equals('Microsoft.DesktopAppInstaller',[StringComparison]::OrdinalIgnoreCase) -or
                -not ([string]$package.PublisherId).Equals('8wekyb3d8bbwe',[StringComparison]::OrdinalIgnoreCase) -or
                -not ([IO.Path]::GetDirectoryName($root)).Equals($windowsApps,[StringComparison]::OrdinalIgnoreCase) -or
                -not $basename.StartsWith('Microsoft.DesktopAppInstaller_',[StringComparison]::OrdinalIgnoreCase) -or
                -not $basename.EndsWith('_x64__8wekyb3d8bbwe',[StringComparison]::OrdinalIgnoreCase) -or
                ($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $version = $basename.Substring('Microsoft.DesktopAppInstaller_'.Length, $basename.Length - 'Microsoft.DesktopAppInstaller_'.Length - '_x64__8wekyb3d8bbwe'.Length)
            if ([string]::IsNullOrWhiteSpace($version) -or @($version.Split('.') | Where-Object { $_ -notmatch '^\d+$' }).Count -gt 0) { continue }
            $candidate = Join-Path $root 'winget.exe'
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
            $candidateInfo = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
            if (($candidateInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $result.Add([pscustomobject]@{ Path = [IO.Path]::GetFullPath($candidate); Root = $root })
        }
        return @($result | Sort-Object Path -Unique)
    } catch { return @() }
}

function Test-TrustedExecutableCandidate {
    param([Parameter(Mandatory)][string]$Path,[Parameter()][object]$Dependency)
    try {
        if ([string]$Path -match '(?i)(^|[\\/])\.\.?([\\/]|$)') { return $false }
        $full = [IO.Path]::GetFullPath($Path)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
        if ([IO.Path]::GetExtension($full).ToLowerInvariant() -in @('.cmd','.bat') -and $Dependency) { return $false }
        $trustedRoot = $null
        if ([IO.Path]::GetFileName($full).Equals('winget.exe',[StringComparison]::OrdinalIgnoreCase)) {
            $wingetCandidates = @(Get-TrustedWingetPackageCandidates | Where-Object { $_.Path.Equals($full,[StringComparison]::OrdinalIgnoreCase) })
            if ($wingetCandidates.Count -ne 1) { return $false }
            $trustedRoot = [string]$wingetCandidates[0].Root
        } else { $trustedRoot = Get-TrustedSystemRootForExecutable $full }
        if ([string]::IsNullOrWhiteSpace($trustedRoot)) { return $false }
        $rootInfo = Get-Item -LiteralPath $trustedRoot -Force -ErrorAction Stop
        if (($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $fileInfo = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if (($fileInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        foreach($entry in @((Get-Acl -LiteralPath $full -ErrorAction Stop).Access)) {
            if($entry.AccessControlType -eq 'Allow' -and (Test-BroadUntrustedPrincipal ([string]$entry.IdentityReference.Value)) -and (Test-PrimitiveMutationRights ([Security.AccessControl.FileSystemRights]$entry.FileSystemRights))){return $false}
        }
        $cursor = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($full))
        $reachedRoot = $false
        while($cursor){
            if(($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
            foreach($entry in @((Get-Acl -LiteralPath $cursor.FullName -ErrorAction Stop).Access)) {
                if($entry.AccessControlType -eq 'Allow' -and (Test-BroadUntrustedPrincipal ([string]$entry.IdentityReference.Value)) -and (Test-PrimitiveMutationRights ([Security.AccessControl.FileSystemRights]$entry.FileSystemRights))){return $false}
            }
            if($cursor.FullName.TrimEnd('\').Equals($trustedRoot.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)){ $reachedRoot = $true; break }
            $cursor=$cursor.Parent
        }
        if (-not $reachedRoot) { return $false }
        $policy=if($null -ne $Dependency){$Dependency.installerAuthenticityPolicy}else{$null}
        $exact=@(if($null -ne $policy){$policy.allowedSignerSubjectsExact})
        $signature=Get-AuthenticodeSignature -LiteralPath $full
        $installedTrust = if($null -ne $policy -and $null -ne $policy.PSObject.Properties['installedExecutableTrust']){[string]$policy.installedExecutableTrust}else{''}
        $allowUnsignedInstalled = $installedTrust -eq 'signed-installer-locked-path' -and $signature.Status -eq 'NotSigned'
        if($signature.Status -ne 'Valid' -and -not $allowUnsignedInstalled){return $false}
        if($signature.Status -eq 'Valid' -and @($exact).Count -gt 0 -and -not (Test-ExactSignerIdentity ([string]$signature.SignerCertificate.Subject) $exact)){return $false}
        if(@($exact).Count -eq 0 -and $null -ne $policy -and @($policy.allowedSignerPatterns).Count -gt 0){return $false}
        return $true
    } catch { return $false }
}

function Normalize-SignerIdentity {
    param([Parameter(Mandatory)][string]$Subject)
    try { return (([Security.Cryptography.X509Certificates.X500DistinguishedName]::new($Subject)).Format($false) -replace '\s','').ToUpperInvariant() }
    catch { return ($Subject -replace '\s','').ToUpperInvariant() }
}
function Test-ExactSignerIdentity {
    param([Parameter(Mandatory)][string]$Subject,[Parameter(Mandatory)][string[]]$Expected)
    $actual=Normalize-SignerIdentity $Subject
    return @($Expected | Where-Object { (Normalize-SignerIdentity ([string]$_)) -ceq $actual }).Count -gt 0
}

function Get-TrustedDependencyCandidates {
    param([Parameter(Mandatory)]$Dependency)
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($probe in @($Dependency.executableProbes)) {
        $pathEntries = ([Environment]::GetEnvironmentVariable('PATH') -split [IO.Path]::PathSeparator) | Where-Object { $_ }
        foreach ($entry in $pathEntries) {
            $candidate = Join-Path $entry.Trim('"') $probe
            if ((Test-Path -LiteralPath $candidate) -and (Test-TrustedExecutableCandidate $candidate -Dependency $Dependency)) { $paths.Add([IO.Path]::GetFullPath($candidate)) }
        }
        foreach ($hive in @('HKLM:')) {
            foreach ($subkey in @("SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$probe", "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$probe")) {
                $key = Get-Item -LiteralPath (Join-Path $hive $subkey) -ErrorAction SilentlyContinue
                $value = if ($key) { $key.GetValue('') } else { $null }
                $candidate = if ($value) { ([string]$value).Trim('"') } else { $null }
                if ($candidate -and (Test-TrustedExecutableCandidate $candidate -Dependency $Dependency)) { $paths.Add([IO.Path]::GetFullPath($candidate)) }
            }
        }
    }
    foreach ($location in @($Dependency.knownVendorInstallLocations)) {
        $expanded = Expand-DependencyLocation $location
        if ((Test-Path -LiteralPath $expanded) -and (Test-TrustedExecutableCandidate $expanded -Dependency $Dependency)) { $paths.Add([IO.Path]::GetFullPath($expanded)) }
    }
    return $paths | Select-Object -Unique
}

function Get-DependencyStatus {
    param(
        [Parameter(Mandatory)]$Dependency,
        [int]$ProbeTimeoutSeconds = (Get-DevFleetOperationMaximumSeconds 'dependencyProbe'),
        [datetime]$DeadlineUtc = [datetime]::MinValue
    )
    if($ProbeTimeoutSeconds -le 0){throw 'Dependency probe timeout must be positive.'}
    $probeDeadline=[datetime]::UtcNow.AddSeconds($ProbeTimeoutSeconds)
    if($DeadlineUtc -gt [datetime]::MinValue -and $DeadlineUtc.ToUniversalTime() -lt $probeDeadline){$probeDeadline=$DeadlineUtc.ToUniversalTime()}
    $deadlineContext=Get-DevFleetDeadlineContext
    if($deadlineContext -and ([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime() -lt $probeDeadline){$probeDeadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
    $args = @($Dependency.versionProbe.arguments)
    $first = $null
    foreach ($path in (Get-TrustedDependencyCandidates $Dependency)) {
        $remaining=[int][math]::Floor(($probeDeadline-[datetime]::UtcNow).TotalSeconds)
        if($remaining -le 0){
            if($null -eq $first){$first=[pscustomobject]@{Status='Broken';Path=$path;Version=$null;Detail='Trusted executable was found but its bounded version probe deadline expired.'}}
            break
        }
        try {
            $output=Invoke-External -FilePath $path -ArgumentList $args -Capture -TimeoutSeconds ([math]::Min($ProbeTimeoutSeconds,$remaining)) -DeadlineUtc $probeDeadline
            $exit=0
        } catch {
            if($null -eq $first){$first=[pscustomobject]@{Status='Broken';Path=$path;Version=$null;Detail='Trusted executable was found but its bounded version probe failed.'}}
            continue
        }
        $match = if ($Dependency.versionProbe.regex) { [regex]::Match($output, [string]$Dependency.versionProbe.regex) } else { $null }
        if ($exit -ne 0 -or -not $match -or -not $match.Success) {
            if ($null -eq $first) { $first = [pscustomobject]@{ Status='Broken'; Path=$path; Version=$null; Detail='Trusted executable was found but version probe failed.' } }
            continue
        }
        $version = [Version]$match.Groups[1].Value
        $minimum = [Version]$Dependency.minimumSupportedVersion
        $status = if ($version -lt $minimum) { 'Outdated' } elseif ($null -ne $Dependency.maximumMajor -and $version.Major -gt [int]$Dependency.maximumMajor) { 'Unsupported-Major' } else { 'Compatible' }
        $result = [pscustomobject]@{ Status=$status; Path=$path; Version=$version; Detail="Resolved trusted executable $path; version $version" }
        if ($status -eq 'Compatible') { return $result }
        if ($null -eq $first) { $first = $result }
    }
    if ($null -ne $first) { return $first }
    return [pscustomobject]@{ Status='Missing'; Path=''; Version=$null; Detail='No trusted machine executable, HKLM App Path, or vendor location matched.' }
}

function Wait-DevFleetDependencyStatus {
    param(
        [Parameter(Mandatory)]$Dependency,
        [datetime]$DeadlineUtc = [datetime]::MinValue,
        [ValidateRange(1,10)][int]$MaximumAttempts = 3,
        [scriptblock]$StatusProvider,
        [scriptblock]$ClockProvider,
        [scriptblock]$SleepProvider
    )
    $now={if($ClockProvider){[datetime](& $ClockProvider)}else{[datetime]::UtcNow}}
    $sleep={param([double]$Seconds)if($SleepProvider){& $SleepProvider $Seconds}else{Start-Sleep -Milliseconds ([int][math]::Ceiling($Seconds*1000))}}
    $start=(& $now).ToUniversalTime()
    $deadline=if($DeadlineUtc -gt [datetime]::MinValue){$DeadlineUtc.ToUniversalTime()}else{$start.AddSeconds((Get-DevFleetOperationMaximumSeconds 'dependencyProbe'))}
    $deadlineContext=Get-DevFleetDeadlineContext
    if($deadlineContext -and ([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime() -lt $deadline){$deadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
    $last=$null
    for($attempt=1;$attempt -le $MaximumAttempts;$attempt++){
        $remainingSeconds=[int][math]::Floor(($deadline-(& $now).ToUniversalTime()).TotalSeconds)
        if($remainingSeconds -le 0){break}
        $attemptsRemaining=$MaximumAttempts-$attempt+1
        $probeTimeout=[math]::Max(1,[math]::Min(20,[int][math]::Floor($remainingSeconds/$attemptsRemaining)))
        try {
            $last=if($StatusProvider){& $StatusProvider $Dependency $deadline $probeTimeout}else{Get-DependencyStatus -Dependency $Dependency -ProbeTimeoutSeconds $probeTimeout -DeadlineUtc $deadline}
        } catch {
            $last=[pscustomobject]@{Status='Broken';Path='';Version=$null;Detail='Bounded dependency status provider failed.'}
        }
        if($last -and [string]$last.Status -cne 'Broken'){return $last}
        if($attempt -ge $MaximumAttempts){break}
        $remainingAfter=[math]::Floor(($deadline-(& $now).ToUniversalTime()).TotalSeconds)
        if($remainingAfter -le 0){break}
        & $sleep ([math]::Min(1,$remainingAfter))
    }
    if($last){return $last}
    return [pscustomobject]@{Status='Broken';Path='';Version=$null;Detail='Dependency status deadline expired before a bounded probe completed.'}
}

function Get-DevFleetDependencyProbeAttemptLimit {
    param([Parameter(Mandatory)]$Dependency)
    # Multipass may still be bringing its daemon/backend online immediately
    # after a restored Windows checkpoint. Give only that proven transient gate
    # five additional bounded probes; the existing dependencyProbe deadline,
    # trusted-path checks, version policy, and fail-closed result handling stay
    # unchanged.
    if ([string]$Dependency.id -ceq 'multipass') { return 8 }
    return 3
}


function Get-TailscaleExe {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe')
    )) { if ($candidate -and (Test-TrustedExecutableCandidate $candidate)) { return $candidate } }
    throw 'Tailscale is not installed in a trusted machine location.'
}

function Get-VsCodeCli {
    param([switch]$AllowPerUser)
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\bin\code.cmd')
    )) { if ($candidate -and (Test-TrustedExecutableCandidate $candidate)) { return $candidate } }
    if ($AllowPerUser) {
        $user = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
        if ($user -and (Test-Path -LiteralPath $user -PathType Leaf) -and -not ((Get-Item -LiteralPath $user -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $user }
    }
    return $null
}

function Get-MultipassExe {
    # Multipass is intentionally allowed to be unsigned after installation only
    # when the canonical dependency policy binds it to a signed installer and a
    # locked machine path.  Resolve through that same policy as Ensure-Dependency
    # so runtime helpers cannot reject a legitimate install (or invent a weaker
    # trust rule of their own).
    $packageRoot = Get-DevFleetPackageRoot
    $manifest = Get-CanonicalDependencyManifest -PackageRoot $packageRoot
    $dependency = @($manifest.dependencies | Where-Object id -eq 'multipass' | Select-Object -First 1)
    if (-not $dependency) { throw 'Canonical Multipass dependency policy is missing.' }
    $cachedVariable=Get-Variable -Scope Script -Name DevFleetMultipassResolution -ErrorAction SilentlyContinue
    if($cachedVariable -and $cachedVariable.Value){
        $cached=$cachedVariable.Value
        try {
            if((Test-TrustedExecutableCandidate ([string]$cached.Path) -Dependency $dependency) -and (Get-FileHash -LiteralPath ([string]$cached.Path) -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$cached.Sha256){return [string]$cached.Path}
        } catch {}
        $script:DevFleetMultipassResolution=$null
    }
    $deadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'dependencyProbe'))
    $deadlineContext=Get-DevFleetDeadlineContext
    if($deadlineContext -and ([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime() -lt $deadline){$deadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
    $status = Wait-DevFleetDependencyStatus -Dependency $dependency -DeadlineUtc $deadline -MaximumAttempts (Get-DevFleetDependencyProbeAttemptLimit -Dependency $dependency)
    if ($status.Status -eq 'Compatible' -and $status.Path) {
        $script:DevFleetMultipassResolution=[pscustomobject]@{Path=[string]$status.Path;Sha256=(Get-FileHash -LiteralPath ([string]$status.Path) -Algorithm SHA256).Hash.ToLowerInvariant();Version=[string]$status.Version}
        return [string]$status.Path
    }
    throw "Multipass is not installed in a trusted machine location or compatible state: $($status.Status)."
}


function Assert-MultipassIsolation {
    param([string[]]$InstanceNames = @())
    $mp = Get-MultipassExe
    $setting = Invoke-External $mp @('get','local.privileged-mounts') -Capture
    if ($setting.Trim().ToLowerInvariant() -ne 'false') {
        throw 'Multipass host mounts are not disabled. Run: multipass set local.privileged-mounts=false'
    }
    foreach ($name in $InstanceNames) {
        if (-not $name -or -not (Test-MultipassInstance $name)) { continue }
        $raw = Invoke-External $mp @('info',$name,'--format','json') -Capture
        $data = $raw | ConvertFrom-Json
        $prop = $data.info.PSObject.Properties[$name]
        if (-not $prop) { throw "Multipass info did not contain instance $name." }
        $info = $prop.Value
        if ($info.PSObject.Properties.Name -contains 'mounts' -and $null -ne $info.mounts) {
            $mountCount = 0
            if ($info.mounts -is [System.Array]) {
                $mountCount = @($info.mounts).Count
            } elseif ($info.mounts -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace([string]$info.mounts)) { $mountCount = 1 }
            } else {
                $mountCount = @($info.mounts.PSObject.Properties).Count
            }
            if ($mountCount -gt 0) { throw "$name has one or more host mounts. Remove them before using DevFleet." }
        }
    }
}

function Get-MultipassInstances {
    $mp = Get-MultipassExe
    $raw = Invoke-External $mp @('list','--format','json') -Capture
    if (-not $raw) { return @() }
    $data = $raw | ConvertFrom-Json
    @($data.list)
}

function Test-MultipassInstance { param([string]$Name) [bool](Get-MultipassInstances | Where-Object name -eq $Name) }

function Wait-MultipassReady {
    param([string]$Name,[int]$TimeoutSeconds=600,[datetime]$DeadlineUtc=[datetime]::MinValue)
    $mp = Get-MultipassExe
    if($TimeoutSeconds -le 0){throw 'Multipass readiness timeout must be positive.'}
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $context = Get-DevFleetDeadlineContext
    if($DeadlineUtc -gt [datetime]::MinValue -and $DeadlineUtc.ToUniversalTime() -lt $deadline){$deadline=$DeadlineUtc.ToUniversalTime()}
    elseif($context -and [datetime]$context.StageDeadlineUtc -lt $deadline){$deadline=[datetime]$context.StageDeadlineUtc.ToUniversalTime()}
    $attempt=0
    while([DateTime]::UtcNow -lt $deadline) {
        $attempt++
        $out = $null
        try {
            # Probe without --wait so the outer deadline remains authoritative. Newer
            # cloud-init versions expose JSON; older versions use the normalized text
            # fallback below. Exit code 2 is not itself a readiness result.
            $remaining=[int][math]::Floor(($deadline-[DateTime]::UtcNow).TotalSeconds)
            if($remaining -le 0){break}
            $out = Invoke-External $mp @('exec',$Name,'--','bash','-lc','cloud-init status --format=json 2>&1 || cloud-init status 2>&1') -Capture -IgnoreExitCode -TimeoutSeconds ([math]::Min(900,$remaining)) -DeadlineUtc $deadline
        } catch {
            $remaining=[math]::Max(0,($deadline-[DateTime]::UtcNow).TotalSeconds)
            Write-Verbose "Multipass readiness probe $attempt failed for $Name; retrying with $([math]::Round($remaining,1)) seconds remaining."
            if($remaining -le 0){break}
            Start-Sleep -Milliseconds ([int][math]::Min(5000,[math]::Max(100,$remaining*1000)))
            continue
        }
        $normalized=[regex]::Replace([string]$out,'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\a]*(?:\a|\x1B\\))','')
        $normalized=$normalized -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',''
        $state=$null
        try {
            $structured=$normalized.Trim() | ConvertFrom-Json
            if($structured -and $structured.PSObject.Properties.Name -contains 'status'){$state=[string]$structured.status}
            if($structured -and $structured.PSObject.Properties.Name -contains 'extended_status' -and [string]$structured.extended_status -match '(?i)error|degraded|fail'){$state='error'}
        } catch { }
        if(-not $state){
            if($normalized -match '(?im)^\s*status:\s*done\s*$'){$state='done'}
            elseif($normalized -match '(?im)^\s*status:\s*(error|degraded|failed)\s*$'){$state='error'}
            elseif($normalized -match '(?im)^\s*status:\s*(running|pending|not\s+started)\s*$'){$state='running'}
        }
        if($state -eq 'done'){return}
        if($state -eq 'error'){throw "cloud-init failed in $Name`n$normalized"}
        $remaining=[math]::Max(0,($deadline-[DateTime]::UtcNow).TotalSeconds)
        $summary=($normalized -replace '\s+',' ')
        if($summary.Length -gt 240){$summary=$summary.Substring([math]::Max(0,$summary.Length-240))}
        Write-Verbose "Multipass readiness probe $attempt for $Name returned: $summary; $([math]::Round($remaining,1)) seconds remaining."
        if($remaining -le 0){break}
        Start-Sleep -Milliseconds ([int][math]::Min(5000,[math]::Max(100,$remaining*1000)))
    }
    throw "Instance $Name did not become ready within $TimeoutSeconds seconds."
}

function Invoke-MultipassInventoryWithBoundedRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$InventoryScript,
        [datetime]$DeadlineUtc = [datetime]::MinValue,
        [ValidateRange(1,5)][int]$MaximumAttempts = 3
    )
    $deadline = if ($DeadlineUtc -gt [datetime]::MinValue) { $DeadlineUtc.ToUniversalTime() } else { [datetime]::UtcNow.AddSeconds(60) }
    $lastError = $null
    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        $remaining = [int][math]::Floor(($deadline - [datetime]::UtcNow).TotalSeconds)
        if ($remaining -le 0) { break }
        $attemptsRemaining = $MaximumAttempts - $attempt + 1
        $probeTimeout = [math]::Max(1, [math]::Min(60, [int][math]::Floor($remaining / $attemptsRemaining)))
        try {
            return @(& $InventoryScript $probeTimeout)
        } catch {
            $lastError = $_.Exception
        }
        $remainingAfter = [math]::Floor(($deadline - [datetime]::UtcNow).TotalSeconds)
        if ($attempt -lt $MaximumAttempts -and $remainingAfter -gt 0) {
            Start-Sleep -Seconds ([int][math]::Min(1, $remainingAfter))
        }
    }
    if ($lastError) { throw "Multipass inventory retry exhausted: $($lastError.Message)" }
    throw 'Multipass inventory retry exhausted before a bounded probe completed.'
}

function Invoke-DevFleetMultipassControlPlaneRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$MultipassPath,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [scriptblock]$ServiceLookupProvider = { Get-CimInstance Win32_Service -Filter "Name='Multipass'" -ErrorAction Stop },
        [scriptblock]$ServiceControlProvider = { param($Action) $sc=Join-Path $env:SystemRoot 'System32\sc.exe'; if(-not(Test-Path -LiteralPath $sc -PathType Leaf)){throw 'Trusted Windows service controller is missing.'}; & $sc $Action Multipass 2>&1 | Out-Null },
        [scriptblock]$DaemonLookupProvider = { param($Id) Get-Process -Id $Id -ErrorAction Stop },
        [scriptblock]$DaemonStopProvider = { param($Id) Stop-Process -Id $Id -Force -ErrorAction Stop },
        [scriptblock]$ClockProvider = { [datetime]::UtcNow },
        [scriptblock]$SleepProvider = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    )
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Multipass control-plane recovery requires a failure reason.' }
    $deadline = $OwnerDeadlineUtc.ToUniversalTime()
    if ([datetime](& $ClockProvider) -ge $deadline) { throw 'Multipass control-plane recovery owner deadline is already exhausted.' }
    $expectedDaemon = Join-Path (Split-Path -Parent $MultipassPath) 'multipassd.exe'
    $services = @(& $ServiceLookupProvider)
    if ($services.Count -ne 1) { throw "Expected exactly one Multipass service; found $($services.Count)." }
    $service = $services[0]
    if ([string]$service.Name -cne 'Multipass') { throw 'Multipass service lookup returned the wrong service identity.' }
    $serviceCommand = [Environment]::ExpandEnvironmentVariables([string]$service.PathName)
    if ($serviceCommand -notmatch [regex]::Escape($expectedDaemon)) { throw 'Multipass service executable does not match the trusted installation.' }
    if ([string]$service.StartName -notin @('LocalSystem','NT AUTHORITY\SYSTEM')) { throw 'Multipass service identity is not LocalSystem.' }

    $stateBefore = [string]$service.State
    $initialDaemonPid = [int]$service.ProcessId
    $forced = $false
    if ($stateBefore -ne 'Stopped') { & $ServiceControlProvider 'stop' }
    $stopDeadline = ([datetime](& $ClockProvider)).AddSeconds(20)
    if ($deadline -lt $stopDeadline) { $stopDeadline = $deadline }
    do {
        $services = @(& $ServiceLookupProvider)
        if ($services.Count -ne 1) { throw "Expected exactly one Multipass service during stop; found $($services.Count)." }
        $service = $services[0]
        if ([string]$service.State -eq 'Stopped') { break }
        & $SleepProvider 250
    } while ([datetime](& $ClockProvider) -lt $stopDeadline)

    if ([string]$service.State -ne 'Stopped') {
        $daemonPid = [int]$service.ProcessId
        if ($daemonPid -le 0) { $daemonPid = $initialDaemonPid }
        if ($daemonPid -le 0) { throw "Multipass service remained $([string]$service.State) without an exact daemon PID." }
        $daemon = & $DaemonLookupProvider $daemonPid
        if ([string]$daemon.ProcessName -cne 'multipassd') { throw 'Multipass service PID did not identify the exact multipassd process.' }
        $daemonPath = ''
        try { $daemonPath = [string]$daemon.Path } catch { }
        if (-not [string]::IsNullOrWhiteSpace($daemonPath) -and [IO.Path]::GetFullPath($daemonPath) -cne [IO.Path]::GetFullPath($expectedDaemon)) {
            throw 'Multipass daemon PID resolved outside the trusted installation.'
        }
        & $DaemonStopProvider $daemonPid
        $forced = $true
        $forcedDeadline = ([datetime](& $ClockProvider)).AddSeconds(10)
        if ($deadline -lt $forcedDeadline) { $forcedDeadline = $deadline }
        do {
            & $SleepProvider 250
            $services = @(& $ServiceLookupProvider)
            if ($services.Count -ne 1) { throw "Expected exactly one Multipass service after daemon termination; found $($services.Count)." }
            $service = $services[0]
        } while ([string]$service.State -ne 'Stopped' -and [datetime](& $ClockProvider) -lt $forcedDeadline)
        if ([string]$service.State -ne 'Stopped') { throw "Multipass service did not reach Stopped after exact daemon termination; state=$([string]$service.State)." }
    }

    if ([datetime](& $ClockProvider) -ge $deadline) { throw 'Multipass control-plane recovery exhausted its owner deadline before restart.' }
    & $ServiceControlProvider 'start'
    $startDeadline = ([datetime](& $ClockProvider)).AddSeconds(45)
    if ($deadline -lt $startDeadline) { $startDeadline = $deadline }
    do {
        $services = @(& $ServiceLookupProvider)
        if ($services.Count -ne 1) { throw "Expected exactly one Multipass service during start; found $($services.Count)." }
        $service = $services[0]
        if ([string]$service.State -eq 'Running') { break }
        & $SleepProvider 250
    } while ([datetime](& $ClockProvider) -lt $startDeadline)
    if ([string]$service.State -ne 'Running') { throw "Multipass service did not return to Running before its owner deadline; state=$([string]$service.State)." }

    return [pscustomobject]@{
        status = 'PASS'
        service = 'Multipass'
        reason = $Reason
        stateBefore = $stateBefore
        stateAfter = [string]$service.State
        forcedDaemonTermination = $forced
        trustedDaemonPath = $expectedDaemon
        ownerDeadlineUtc = $deadline.ToString('o')
    }
}

function Invoke-MultipassLaunchWithReadinessRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstanceName,
        [Parameter(Mandatory)][string[]]$LaunchArguments,
        [Parameter(Mandatory)][int]$ReadinessTimeoutSeconds,
        [int]$LaunchTimeoutSeconds = 900,
        [datetime]$DeadlineUtc = [datetime]::MinValue,
        [scriptblock]$OnInstanceEstablished,
        [scriptblock]$ControlPlaneRecoveryProvider
    )
    if ($InstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'Multipass launch recovery instance identity is malformed.' }
    $launchArgs = @($LaunchArguments | ForEach-Object { [string]$_ })
    if ($launchArgs.Count -lt 2 -or $launchArgs[0] -cne 'launch') { throw 'Multipass launch recovery requires a launch argument vector.' }
    $nameIndex = [Array]::IndexOf([string[]]$launchArgs, '--name')
    if ($nameIndex -lt 0 -or $nameIndex + 1 -ge $launchArgs.Count -or [string]$launchArgs[$nameIndex + 1] -cne $InstanceName) {
        throw 'Multipass launch recovery refused an argument vector that is not bound to the exact instance name.'
    }
    if ($ReadinessTimeoutSeconds -le 0 -or $LaunchTimeoutSeconds -le 0) { throw 'Multipass launch and readiness deadlines must be positive.' }

    $mp = Get-MultipassExe
    $inventory = {
        param([int]$TimeoutSeconds)
        $raw = Invoke-External -FilePath $mp -ArgumentList @('list','--format','json') -Capture -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $DeadlineUtc
        try {
            $parsed = $raw | ConvertFrom-Json
            return @($parsed.list)
        } catch {
            throw 'Multipass inventory returned malformed JSON during fresh-instance recovery.'
        }
    }
    # This helper is only for the fresh-launch branch. Existing DevFleet
    # instances use their separate backup-preserving refresh path below; a
    # second inventory check prevents a recovery command from being aimed at a
    # pre-existing instance if the caller's earlier snapshot was stale.
    # Reserve a finite recovery slice inside the existing compute/vault stage
    # budget. The normal 900-second operation maximum therefore leaves 600
    # seconds for the initial launch and 300 seconds for one exact recovery.
    $recoveryBudgetSeconds = 300
    $supervisorGraceSeconds = 30
    $minimumOperationSeconds = 60
    if (@($launchArgs | Where-Object { $_ -ieq '--timeout' -or $_ -imatch '^--timeout=' }).Count -gt 0) {
        throw 'Multipass launch recovery rejects caller-supplied --timeout so the inner operation and supervisor deadlines remain separated.'
    }
    $before = @(Invoke-MultipassInventoryWithBoundedRetry -InventoryScript $inventory -DeadlineUtc $DeadlineUtc -MaximumAttempts 3 | Where-Object { [string]$_.name -ceq $InstanceName })
    if ($before.Count -ne 0) { throw "Fresh Multipass launch recovery refused existing instance $InstanceName." }
    $launchBudgetRemaining = $LaunchTimeoutSeconds
    if ($DeadlineUtc -gt [datetime]::MinValue) {
        $launchBudgetRemaining = [math]::Min($launchBudgetRemaining, [int][math]::Floor(($DeadlineUtc.ToUniversalTim