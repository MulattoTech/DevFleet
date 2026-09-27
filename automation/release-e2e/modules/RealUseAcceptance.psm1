Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Evidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'GuestSession.psm1') -Force

$script:RealUseAcceptanceContract = 'devfleet-real-use-acceptance-v1'
$script:RealUseAcceptancePhase = 'REAL-USE-ACCEPTANCE'
$script:RealUseAcceptanceOwnerTimeoutSeconds = 36000
$script:RealUseAcceptancePrepareTimeoutSeconds = 10800
$script:RealUseAcceptanceCleanupReserveSeconds = 900
$script:RealUsePairingCaptureContract = 'devfleet-real-use-primary-pairing-v1'
$script:RealUseClusterJoinContract = 'devfleet-real-use-cluster-join-v1'
$script:RealUseAcceptanceAssertions = [ordered]@{
    U01 = @('authenticatedDashboard','templateCreated','identityBound','assetsPresent','credentialsNotLogged')
    U02 = @('startCompleted','healthCompleted','testCompleted','smokeOutputObserved','uiBackendContainerAgree')
    U03 = @('stopCompleted','restartCompleted','serviceRestartObserved','sameProjectAndData','noDuplicateWriter','noPendingOperations','healthRecovered')
    U04 = @('immediateBackupVerified','vaultUploadVerified','backupBeforeQuarantine','quarantineReversible','foreignCollisionRejected','collisionPreserved','restoreCompleted','contentRecovered')
    U05 = @('vaultCopyCompleted','copyIdentityBound','copyContentRecovered','originalUnchanged','copyStartRejected','securityStartRejected','foreignLeaseStartRejected','originalUsable','onlyIntendedOwnerStarts')
}

function Get-RealUseAcceptanceProperty {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Name,
        [ref]$Found
    )
    $Found.Value = $false
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ([string]$key -ieq $Name) { $Found.Value = $true; return $Value[$key] }
        }
        return $null
    }
    foreach ($property in @($Value.PSObject.Properties)) {
        if ([string]$property.Name -ieq $Name) { $Found.Value = $true; return $property.Value }
    }
    return $null
}

function Get-RealUseAcceptancePropertyNames {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary]) { return @($Value.Keys | ForEach-Object { [string]$_ }) }
    return @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
}

function Assert-RealUseAcceptanceKeys {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string[]]$Allowed,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Required,
        [Parameter(Mandatory)][string]$Label
    )
    $names = @(Get-RealUseAcceptancePropertyNames $Value)
    $unknown = @($names | Where-Object { $_ -notin $Allowed })
    $missing = @($Required | Where-Object { $_ -notin $names })
    if ($unknown.Count -or $missing.Count) { throw "$Label has missing or unexpected fields." }
    return $true
}

function Assert-RealUseAcceptanceRunId {
    param([Parameter(Mandatory)][string]$RunId)
    if ($RunId.Length -gt 128 -or $RunId -cnotmatch '\A(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z') {
        throw 'REAL-USE-ACCEPTANCE RunId failed ownership validation.'
    }
    return $true
}

function Assert-RealUseAcceptanceContainedPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "$Label is outside the current FullRelease evidence directory." }
    return $fullPath
}

function Assert-RealUseAcceptanceCanonicalEvidencePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$LeafName
    )
    $actual = Assert-RealUseAcceptanceContainedPath -Root $Root -Path $Path -Label "REAL-USE-ACCEPTANCE $LeafName evidence"
    $expected = [IO.Path]::GetFullPath((Join-Path $Root $LeafName))
    if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) { throw "REAL-USE-ACCEPTANCE $LeafName evidence path is not canonical." }
    return $actual
}

function Test-RealUseAcceptanceJsonEqual {
    param([AllowNull()][object]$Left, [AllowNull()][object]$Right)
    $leftNormalized = $Left | ConvertTo-Json -Depth 32 -Compress | ConvertFrom-Json | ConvertTo-Json -Depth 32 -Compress
    $rightNormalized = $Right | ConvertTo-Json -Depth 32 -Compress | ConvertFrom-Json | ConvertTo-Json -Depth 32 -Compress
    return ($leftNormalized -ceq $rightNormalized)
}

function Assert-RealUseAcceptanceSanitizedValue {
    param(
        [AllowNull()][object]$Value,
        [string]$Path = 'report',
        [int]$Depth = 0
    )
    if ($Depth -gt 16) { throw 'REAL-USE-ACCEPTANCE report exceeds the bounded evidence depth.' }
    if ($null -eq $Value) { return $true }
    if ($Value -is [string]) {
        if ($Value.Length -gt 4096 -or $Value -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') { throw 'REAL-USE-ACCEPTANCE report contains an unsafe string.' }
        if ($Value -match '(?i)(?:authorization\s*:|bearer\s+[A-Za-z0-9._~+/=-]{8,}|basic\s+[A-Za-z0-9+/=]{8,}|tskey-[A-Za-z0-9-]+|DEVFLEET_ADMIN_(?:USER|PASSWORD)\s*=|(?:password|secret|token|cookie)\s*[:=])') {
            throw 'REAL-USE-ACCEPTANCE report contains a forbidden secret-shaped value.'
        }
        return $true
    }
    if ($Value -is [bool] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [datetime]) { return $true }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [System.Collections.IDictionary]) -and -not ($Value -is [pscustomobject])) {
        $items = @($Value)
        if ($items.Count -gt 512) { throw 'REAL-USE-ACCEPTANCE report contains an oversized collection.' }
        for ($index = 0; $index -lt $items.Count; $index++) { Assert-RealUseAcceptanceSanitizedValue -Value $items[$index] -Path "$Path[$index]" -Depth ($Depth + 1) | Out-Null }
        return $true
    }
    $names = @(Get-RealUseAcceptancePropertyNames $Value)
    if ($names.Count -gt 128) { throw 'REAL-USE-ACCEPTANCE report contains an oversized object.' }
    foreach ($name in $names) {
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9]*$' -or ($name -cne 'credentialsNotLogged' -and $name -match '(?i)(password|secret|token|cookie|authorization|credential|apiKey)')) {
            throw 'REAL-USE-ACCEPTANCE report contains a forbidden evidence field.'
        }
        $found = $false
        $child = Get-RealUseAcceptanceProperty $Value $name ([ref]$found)
        Assert-RealUseAcceptanceSanitizedValue -Value $child -Path "$Path.$name" -Depth ($Depth + 1) | Out-Null
    }
    return $true
}

function Test-RealUseAcceptanceSameValue {
    param([AllowNull()][object]$Expected, [AllowNull()][object]$Actual)
    if ($null -eq $Expected -and $null -eq $Actual) { return $true }
    if ($null -eq $Expected -or $null -eq $Actual) { return $false }
    return ([string]$Expected -ceq [string]$Actual)
}

function Test-RealUseAcceptanceSameInstant {
    param([AllowNull()][object]$Expected, [AllowNull()][object]$Actual)
    try {
        return (([datetimeoffset]$Expected).ToUniversalTime().Ticks -eq ([datetimeoffset]$Actual).ToUniversalTime().Ticks)
    } catch {
        return $false
    }
}

function Get-RealUseAcceptanceCandidateTuple {
    param([Parameter(Mandatory)][object]$Candidate)
    return [pscustomobject][ordered]@{
        repositoryHead = [string]$Candidate.repositoryHead
        candidateCommit = [string]$Candidate.gitCommit
        shippingInputIdentity = [string]$Candidate.shippingInputIdentity
        releaseFingerprintId = [string]$Candidate.releaseFingerprintId
        toolingFingerprintId = [string]$Candidate.toolingFingerprintId
        exeSha256 = [string]$Candidate.candidate.sha256
        tarSha256 = [string]$Candidate.tar.sha256
    }
}

function Get-RealUseAcceptancePrivateRoot {
    param([Parameter(Mandatory)][string]$RunId)
    Assert-RealUseAcceptanceRunId -RunId $RunId | Out-Null
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [string]::IsNullOrWhiteSpace($env:ProgramData)) { throw 'REAL-USE-ACCEPTANCE private pairing state requires Windows DPAPI.' }
    $base = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'DevFleet-E2E\Private\RealUseAcceptance')).TrimEnd('\','/')
    $path = [IO.Path]::GetFullPath((Join-Path $base $RunId))
    if (-not $path.StartsWith($base + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -cne $RunId) { throw 'REAL-USE-ACCEPTANCE private pairing root escaped its fixed L0 boundary.' }
    return $path
}

function New-RealUseAcceptancePassphrase {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    $bytes = [byte[]]::new(48)
    $secure = [Security.SecureString]::new()
    try {
        [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        foreach ($value in $bytes) { $secure.AppendChar($alphabet[[int]$value -band 63]) }
        $secure.MakeReadOnly()
        return $secure
    } catch {
        $secure.Dispose()
        throw
    } finally {
        [Array]::Clear($bytes,0,$bytes.Length)
    }
}

function Protect-RealUseAcceptancePrivateRoot {
    param([Parameter(Mandatory)][string]$Path)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $identity -or -not $identity.User) { throw 'REAL-USE-ACCEPTANCE cannot identify the DPAPI owner.' }
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in @(
        $identity.User,
        [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::LocalSystemSid,$null),
        [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,$null)
    )) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function New-RealUseAcceptancePrivateState {
    param([Parameter(Mandatory)][string]$RunId)
    $root = Get-RealUseAcceptancePrivateRoot -RunId $RunId
    if (Test-Path -LiteralPath $root) { throw 'REAL-USE-ACCEPTANCE private pairing state collided with an existing run root.' }
    $created=$false;$secure=$null
    try {
        [void][IO.Directory]::CreateDirectory($root);$created=$true
        Protect-RealUseAcceptancePrivateRoot -Path $root
        $secretPath = Join-Path $root 'pairing-passphrase.dpapi'
        $bundlePath = Join-Path $root 'primary-pairing.dfe'
        $secure = New-RealUseAcceptancePassphrase
        $protected = ConvertFrom-SecureString -SecureString $secure -ErrorAction Stop
        [IO.File]::WriteAllText($secretPath,$protected,[Text.UTF8Encoding]::new($false))
        if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf) -or (Get-Item -LiteralPath $secretPath).Length -lt 32) { throw 'REAL-USE-ACCEPTANCE DPAPI passphrase persistence failed.' }
        return [pscustomobject][ordered]@{root=$root;secretPath=$secretPath;bundlePath=$bundlePath}
    } catch {
        if($created -and (Test-Path -LiteralPath $root)){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
        throw
    } finally {
        if($secure){$secure.Dispose()}
    }
}

function Remove-RealUseAcceptancePrivateState {
    param([Parameter(Mandatory)][object]$PrivateState,[Parameter(Mandatory)][string]$RunId)
    $expected = Get-RealUseAcceptancePrivateRoot -RunId $RunId
    $actual = [IO.Path]::GetFullPath([string]$PrivateState.root)
    if (-not $actual.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) { throw 'REAL-USE-ACCEPTANCE refused to remove a noncanonical private pairing root.' }
    if (Test-Path -LiteralPath $actual) {
        $item=Get-Item -LiteralPath $actual -Force -ErrorAction Stop
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'REAL-USE-ACCEPTANCE refused to remove a replaced private pairing root.'}
        Remove-Item -LiteralPath $actual -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $actual) { throw 'REAL-USE-ACCEPTANCE private pairing state cleanup was not proven.' }
    return $true
}

function Get-RealUseAcceptanceSecurePwsh7Bridge {
    return {
        param(
            [Parameter(Mandatory)][string]$ChildScriptText,
            [Parameter(Mandatory)][string]$RequestJson,
            [Parameter(Mandatory)][Security.SecureString]$Passphrase,
            [ValidateRange(1,3600)][int]$TimeoutSeconds,
            [Parameter(Mandatory)][ValidatePattern('^REAL_USE_[A-Z0-9_]+$')][string]$FailureCode
        )
        $pwsh='C:\Program Files\PowerShell\7\pwsh.exe'
        if(-not(Test-Path -LiteralPath $pwsh -PathType Leaf)){throw $FailureCode}
        $requestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($RequestJson))
        $childBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ChildScriptText))
        $body=@'
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$WarningPreference='SilentlyContinue'
$InformationPreference='SilentlyContinue'
$secure=$null
try {
    if($PSVersionTable.PSVersion.Major-lt 7){throw 'REAL_USE_PWSH7_RUNTIME_INVALID'}
    $cipher=[Console]::In.ReadToEnd()
    if([string]::IsNullOrWhiteSpace($cipher)){throw 'REAL_USE_PWSH7_INPUT_MISSING'}
    $secure=ConvertTo-SecureString -String $cipher -ErrorAction Stop
    $requestJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__REQUEST_BASE64__'))
    $request=$requestJson|ConvertFrom-Json -ErrorAction Stop
    $childText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CHILD_BASE64__'))
    $result=& ([scriptblock]::Create($childText)) $request $secure 6>$null
    [Console]::Out.Write(($result|ConvertTo-Json -Depth 12 -Compress))
} catch {
    $match=[regex]::Match([string]$_.Exception.Message,'REAL_USE_[A-Z0-9_]+')
    [Console]::Error.Write($(if($match.Success){$match.Value}else{'__FAILURE_CODE__'}))
    exit 1
} finally {
    if($secure){$secure.Dispose()}
    $cipher=$null
}
'@
        $body=$body.Replace('__REQUEST_BASE64__',$requestBase64).Replace('__CHILD_BASE64__',$childBase64).Replace('__FAILURE_CODE__',$FailureCode)
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
        $cipher=$null;$process=$null
        try {
            # Protect the marshalled SecureString again with the guest user's
            # DPAPI key, then transmit only that ciphertext over the exact
            # same-user PowerShell 7 child's redirected stdin.  No plaintext
            # value enters argv, environment, a file, stdout, or evidence.
            $cipher=$Passphrase|ConvertFrom-SecureString -ErrorAction Stop
            $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$pwsh;$psi.Arguments="-NoProfile -NonInteractive -EncodedCommand $encoded";$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
            $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
            if(-not$process.Start()){throw $FailureCode}
            $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
            $process.StandardInput.Write($cipher);$process.StandardInput.Close();$cipher=$null
            if(-not$process.WaitForExit($TimeoutSeconds*1000)){
                try{& (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID ([string]$process.Id) /T /F 2>$null|Out-Null}catch{try{$process.Kill()}catch{}}
                try{[void]$process.WaitForExit(5000)}catch{}
                throw $FailureCode
            }
            $drained=$false
            try{$drained=[Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5))}catch{$drained=$false}
            if(-not$drained){throw $FailureCode}
            $stdout=if($stdoutTask.Status-eq[Threading.Tasks.TaskStatus]::RanToCompletion){$stdoutTask.GetAwaiter().GetResult()}else{''}
            $stderr=if($stderrTask.Status-eq[Threading.Tasks.TaskStatus]::RanToCompletion){$stderrTask.GetAwaiter().GetResult()}else{''}
            if($process.ExitCode-ne 0){$match=[regex]::Match([string]$stderr,'REAL_USE_[A-Z0-9_]+');throw $(if($match.Success){$match.Value}else{$FailureCode})}
            if([string]::IsNullOrWhiteSpace($stdout)-or$stdout.Length-gt 262144){throw $FailureCode}
            return ($stdout|ConvertFrom-Json -ErrorAction Stop)
        } catch {
            $match=[regex]::Match([string]$_.Exception.Message,'REAL_USE_[A-Z0-9_]+')
            if($match.Success){throw $match.Value}
            throw $FailureCode
        } finally {
            $cipher=$null
            if($process){
                try{if(-not$process.HasExited){& (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID ([string]$process.Id) /T /F 2>$null|Out-Null;[void]$process.WaitForExit(5000)}}catch{try{$process.Kill()}catch{}}
                $process.Dispose()
            }
        }
    }
}

function New-RealUseAcceptancePrimaryPairingCapture {
    param([Parameter(Mandatory)][object]$Context,[Parameter(Mandatory)][object]$FreshInstallEvidence)
    Assert-RealUseAcceptanceRunId -RunId ([string]$Context.runId) | Out-Null
    if ([string]$Context.phaseId -cne 'FRESH-INSTALL-WPF' -or [string]$FreshInstallEvidence.status -cne 'REAL E2E PASS' -or [string]$FreshInstallEvidence.role -cne 'Primary / Desktop' -or -not [bool]$FreshInstallEvidence.completionVerified) { throw 'REAL-USE-ACCEPTANCE pairing capture requires the completed Primary FreshInstall boundary.' }
    if ([string]$FreshInstallEvidence.transactionId -cnotmatch '^[0-9a-f]{32}$' -or [string]$FreshInstallEvidence.invocationId -cnotmatch '^[0-9a-f]{32}$' -or [string]$FreshInstallEvidence.payloadSha256 -cne [string]$Context.candidate.tar.sha256) { throw 'REAL-USE-ACCEPTANCE Primary lifecycle identity is incomplete.' }
    $candidate = Get-RealUseAcceptanceCandidateTuple -Candidate $Context.candidate
    Assert-RealUseAcceptanceCandidate -Actual $candidate -Expected $candidate | Out-Null
    $private = New-RealUseAcceptancePrivateState -RunId ([string]$Context.runId)
    $securePwsh7Bridge=(Get-RealUseAcceptanceSecurePwsh7Bridge).ToString()
    $secure = $null; $session = $null; $remoteBundle = $null; $captureResult=$null; $captureError=$null; $remoteCleanupError=$null
    try {
        $secure = ConvertTo-SecureString -String (Get-Content -LiteralPath ([string]$private.secretPath) -Raw -ErrorAction Stop) -ErrorAction Stop
        $session = Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        $capture = Invoke-Command -Session $session -ScriptBlock {
            param($runId,[Security.SecureString]$bundlePassphrase,[string]$securePwsh7Bridge)
            $ErrorActionPreference='Stop'
            if(-not$bundlePassphrase){throw 'REAL_USE_PRIMARY_CAPTURE_IDENTITY_INVALID'}
            $launcher=[scriptblock]::Create($securePwsh7Bridge)
            $child={param($request,[Security.SecureString]$bundlePassphrase)
                if($env:COMPUTERNAME -notlike 'DEVFLEET-E2E-*'-or-not$bundlePassphrase){throw 'REAL_USE_PRIMARY_CAPTURE_IDENTITY_INVALID'}
                $stateRoot='C:\ProgramData\DevFleet';$identityPath=Join-Path $stateRoot 'node-identity.json';$packageRootPath=Join-Path $stateRoot 'package-root.txt';$exports=Join-Path $stateRoot 'exports'
                if(-not(Test-Path -LiteralPath $identityPath -PathType Leaf)-or-not(Test-Path -LiteralPath $packageRootPath -PathType Leaf)){throw 'REAL_USE_PRIMARY_CAPTURE_INSTALLATION_MISSING'}
                $identity=Get-Content -LiteralPath $identityPath -Raw|ConvertFrom-Json -ErrorAction Stop
                if([string]$identity.node_role-cne'primary'-or[string]$identity.deployment_id-cnotmatch'^[0-9a-fA-F-]{36}$'-or[string]$identity.node_id-cnotmatch'^[0-9a-fA-F-]{36}$'-or[string]$identity.registration_state-cne'coordinator'){throw 'REAL_USE_PRIMARY_CAPTURE_NODE_INVALID'}
                $existing=@(Get-ChildItem -LiteralPath $exports -Filter 'devfleet-desktop-pairing-*.dfe' -File -ErrorAction SilentlyContinue)
                if($existing.Count-ne 0){throw 'REAL_USE_PRIMARY_CAPTURE_EXPORT_COLLISION'}
                $packageRoot=(Get-Content -LiteralPath $packageRootPath -Raw).Trim();$exporter=Join-Path $packageRoot 'windows\10-Export-Desktop-Pairing.ps1'
                if(-not(Test-Path -LiteralPath $exporter -PathType Leaf)){throw 'REAL_USE_PRIMARY_CAPTURE_EXPORTER_MISSING'}
                try{
                    & $exporter -NonInteractive -BundlePassphrase $bundlePassphrase | Out-Null
                    $created=@(Get-ChildItem -LiteralPath $exports -Filter 'devfleet-desktop-pairing-*.dfe' -File -ErrorAction Stop)
                    if($created.Count-ne 1){throw 'REAL_USE_PRIMARY_CAPTURE_EXPORT_COUNT_INVALID'}
                    $stream=[IO.File]::Open($created[0].FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);try{$header=[byte[]]::new(8);if($stream.Read($header,0,8)-ne 8-or[Text.Encoding]::ASCII.GetString($header)-cne'DFENV001'){throw 'REAL_USE_PRIMARY_CAPTURE_FORMAT_INVALID'}}finally{$stream.Dispose()}
                    return [pscustomobject][ordered]@{bundlePath=$created[0].FullName;bundleSha256=(Get-FileHash -LiteralPath $created[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant();bundleBytes=[int64]$created[0].Length;primary=[ordered]@{deploymentId=[string]$identity.deployment_id;nodeId=[string]$identity.node_id;nodeName=[string]$identity.node_name;nodeRole=[string]$identity.node_role;registrationState=[string]$identity.registration_state}}
                }catch{
                    $exportError=$_.Exception;$exportCleanupError=$null
                    try{foreach($created in @(Get-ChildItem -LiteralPath $exports -Filter 'devfleet-desktop-pairing-*.dfe' -File -ErrorAction Stop)){Remove-Item -LiteralPath $created.FullName -Force -ErrorAction Stop};if(@(Get-ChildItem -LiteralPath $exports -Filter 'devfleet-desktop-pairing-*.dfe' -File -ErrorAction Stop).Count){throw 'REAL_USE_PRIMARY_CAPTURE_REMOTE_CLEANUP_UNPROVEN'}}catch{$exportCleanupError=$_.Exception}
                    if($exportCleanupError){throw "$($exportError.Message); REAL_USE_PRIMARY_CAPTURE_REMOTE_CLEANUP_FAILED"}
                    throw $exportError
                }
            }.ToString()
            return & $launcher $child (@{runId=$runId}|ConvertTo-Json -Compress) $bundlePassphrase 600 'REAL_USE_PRIMARY_CAPTURE_PS7_FAILED'
        } -ArgumentList ([string]$Context.runId),$secure,$securePwsh7Bridge
        $remoteBundle = [string]$capture.bundlePath
        if ($remoteBundle -notlike 'C:\ProgramData\DevFleet\exports\devfleet-desktop-pairing-*.dfe' -or [string]$capture.bundleSha256 -cnotmatch '^[0-9a-f]{64}$' -or [int64]$capture.bundleBytes -lt 72) { throw 'REAL-USE-ACCEPTANCE Primary pairing export evidence is malformed.' }
        Copy-Item -FromSession $session -LiteralPath $remoteBundle -Destination ([string]$private.bundlePath) -ErrorAction Stop
        $bundleItem = Get-Item -LiteralPath ([string]$private.bundlePath) -ErrorAction Stop
        $bundleHash = (Get-FileHash -LiteralPath $bundleItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($bundleHash -cne [string]$capture.bundleSha256 -or [int64]$bundleItem.Length -ne [int64]$capture.bundleBytes) { throw 'REAL-USE-ACCEPTANCE Primary pairing bundle changed during L1-to-L0 transport.' }
        $evidencePath = Join-Path ([string]$Context.runDir) 'real-use-primary-pairing.json'
        $evidence = [ordered]@{schemaVersion=1;contract=$script:RealUsePairingCaptureContract;status='PASS';runId=[string]$Context.runId;phaseId='FRESH-INSTALL-WPF';candidate=$candidate;lifecycle=[ordered]@{transactionId=[string]$FreshInstallEvidence.transactionId;invocationId=[string]$FreshInstallEvidence.invocationId;payloadSha256=[string]$FreshInstallEvidence.payloadSha256;role='Primary / Desktop'};encryptedBundle=[ordered]@{sha256=$bundleHash;bytes=[int64]$bundleItem.Length;format='DFENV001'};primary=$capture.primary;sensitiveValuesPersisted=$false}
        Write-EvidenceJson -Path $evidencePath -Value $evidence
        $captureResult=[pscustomobject][ordered]@{evidence=$evidence;evidencePath=$evidencePath;evidenceSha256=(Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant();privateState=$private}
    } catch {
        $captureError=$_.Exception
    } finally {
        try {
            if($session -and $remoteBundle){Invoke-Command -Session $session -ScriptBlock{param($path)if($path-notlike'C:\ProgramData\DevFleet\exports\devfleet-desktop-pairing-*.dfe'){throw 'REAL_USE_PRIMARY_CAPTURE_CLEANUP_PATH_INVALID'};if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction Stop};if(Test-Path -LiteralPath $path){throw 'REAL_USE_PRIMARY_CAPTURE_CLEANUP_FAILED'}}-ArgumentList $remoteBundle}
        } catch {
            $remoteCleanupError=$_.Exception
        } finally {
            if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}
            if($secure){$secure.Dispose()}
        }
    }
    if($captureError -or $remoteCleanupError){
        $privateCleanupError=$null
        try { Remove-RealUseAcceptancePrivateState -PrivateState $private -RunId ([string]$Context.runId) | Out-Null } catch { $privateCleanupError=$_.Exception }
        $primaryMessage=if($captureError){[string]$captureError.Message}else{'REAL-USE-ACCEPTANCE Primary pairing remote cleanup failed.'}
        if($remoteCleanupError){$primaryMessage+='; REAL_USE_PRIMARY_CAPTURE_CLEANUP_FAILED'}
        if($privateCleanupError){$primaryMessage+='; REAL-USE-ACCEPTANCE private pairing cleanup failed'}
        throw $primaryMessage
    }
    return $captureResult
}

function Complete-RealUseAcceptanceClusterJoin {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Capture,
        [Parameter(Mandatory)][object]$PrivateState,
        [Parameter(Mandatory)][object]$SurrogateEvidence
    )
    Assert-RealUseAcceptanceRunId -RunId ([string]$Context.runId) | Out-Null
    if ([string]$Context.phaseId -cne $script:RealUseAcceptancePhase) { throw 'REAL-USE-ACCEPTANCE cluster join is outside its native FullRelease phase.' }
    $candidate = Get-RealUseAcceptanceCandidateTuple -Candidate $Context.candidate
    Assert-RealUseAcceptanceCandidate -Actual $candidate -Expected $candidate | Out-Null
    $capturePath = Assert-RealUseAcceptanceCanonicalEvidencePath -Root ([string]$Context.runDir) -Path ([string]$Capture.evidencePath) -LeafName 'real-use-primary-pairing.json'
    if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf) -or (Get-FileHash -LiteralPath $capturePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$Capture.evidenceSha256) { throw 'REAL-USE-ACCEPTANCE Primary pairing capture evidence changed before join.' }
    $durableCapture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json -ErrorAction Stop
    if (-not (Test-RealUseAcceptanceJsonEqual $durableCapture $Capture.evidence) -or [string]$durableCapture.contract -cne $script:RealUsePairingCaptureContract -or [string]$durableCapture.status -cne 'PASS' -or [string]$durableCapture.runId -cne [string]$Context.runId -or [string]$durableCapture.phaseId -cne 'FRESH-INSTALL-WPF' -or $durableCapture.sensitiveValuesPersisted -isnot [bool] -or [bool]$durableCapture.sensitiveValuesPersisted) { throw 'REAL-USE-ACCEPTANCE Primary pairing capture evidence is invalid.' }
    Assert-RealUseAcceptanceCandidate -Actual $durableCapture.candidate -Expected $candidate -Label 'REAL-USE-ACCEPTANCE Primary pairing candidate' | Out-Null
    foreach($field in @('deploymentId','nodeId')){if([string]$durableCapture.primary.$field -cnotmatch '^[0-9a-fA-F-]{36}$'){throw 'REAL-USE-ACCEPTANCE Primary pairing identity is malformed.'}}
    if([string]$durableCapture.primary.nodeRole -cne 'primary' -or [string]$durableCapture.primary.registrationState -cne 'coordinator' -or [string]::IsNullOrWhiteSpace([string]$durableCapture.primary.nodeName)){throw 'REAL-USE-ACCEPTANCE Primary pairing role is invalid.'}
    $product = $SurrogateEvidence.product
    if ([string]$SurrogateEvidence.status -cne 'REAL E2E PASS' -or [string]$SurrogateEvidence.phase -cne 'SURROGATE-DISPOSABLE' -or [string]$product.contract -cne 'product-lifecycle-completion-authority' -or [string]$product.role -cne 'Laptop / Surrogate' -or -not [bool]$product.completionVerified -or [string]$product.transactionId -cnotmatch '^[0-9a-f]{32}$' -or [string]$product.invocationId -cnotmatch '^[0-9a-f]{32}$' -or [string]$product.payloadSha256 -cne [string]$candidate.tarSha256) { throw 'REAL-USE-ACCEPTANCE cluster join lacks the immediately preceding Surrogate lifecycle authority.' }
    $expectedPrivateRoot = Get-RealUseAcceptancePrivateRoot -RunId ([string]$Context.runId)
    $expectedSecretPath=[IO.Path]::GetFullPath((Join-Path $expectedPrivateRoot 'pairing-passphrase.dpapi'));$expectedBundlePath=[IO.Path]::GetFullPath((Join-Path $expectedPrivateRoot 'primary-pairing.dfe'))
    if (-not [IO.Path]::GetFullPath([string]$PrivateState.root).Equals($expectedPrivateRoot,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFullPath([string]$PrivateState.secretPath).Equals($expectedSecretPath,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFullPath([string]$PrivateState.bundlePath).Equals($expectedBundlePath,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $expectedSecretPath -PathType Leaf) -or -not (Test-Path -LiteralPath $expectedBundlePath -PathType Leaf)) { throw 'REAL-USE-ACCEPTANCE private pairing state is unavailable or noncanonical.' }
    $bundleItem = Get-Item -LiteralPath ([string]$PrivateState.bundlePath) -ErrorAction Stop
    $bundleHash = (Get-FileHash -LiteralPath $bundleItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($bundleHash -cne [string]$durableCapture.encryptedBundle.sha256 -or [int64]$bundleItem.Length -ne [int64]$durableCapture.encryptedBundle.bytes) { throw 'REAL-USE-ACCEPTANCE encrypted Primary pairing bundle changed before join.' }

    $securePwsh7Bridge=(Get-RealUseAcceptanceSecurePwsh7Bridge).ToString()
    $secure=$null;$session=$null;$remoteRoot="C:\ProgramData\DevFleet\tmp\real-use-pairing-$($Context.runId)";$remoteBundle=Join-Path $remoteRoot 'primary-pairing.dfe';$remoteOwned=$false;$joinResult=$null;$joinError=$null;$remoteCleanupError=$null
    try {
        $secure = ConvertTo-SecureString -String (Get-Content -LiteralPath ([string]$PrivateState.secretPath) -Raw -ErrorAction Stop) -ErrorAction Stop
        $session = Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        Invoke-Command -Session $session -ScriptBlock{
            param($root,$runId)
            if($root-cne"C:\ProgramData\DevFleet\tmp\real-use-pairing-$runId"-or$runId-cnotmatch'\A(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'){throw 'REAL_USE_CLUSTER_JOIN_ROOT_INVALID'}
            if(Test-Path -LiteralPath $root){throw 'REAL_USE_CLUSTER_JOIN_ROOT_COLLISION'}
            $created=$false
            try{
                New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null;$created=$true
                $identity=[Security.Principal.WindowsIdentity]::GetCurrent();if(-not$identity-or-not$identity.User){throw 'REAL_USE_CLUSTER_JOIN_ROOT_OWNER_INVALID'}
                $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
                foreach($sid in @($identity.User,[Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::LocalSystemSid,$null),[Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,$null))){[void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))}
                Set-Acl -LiteralPath $root -AclObject $acl -ErrorAction Stop
                $verified=Get-Acl -LiteralPath $root -ErrorAction Stop;if(-not$verified.AreAccessRulesProtected-or@($verified.Access).Count-ne 3){throw 'REAL_USE_CLUSTER_JOIN_ROOT_ACL_INVALID'}
                $allowed=@([string]$identity.User.Value,'S-1-5-18','S-1-5-32-544');foreach($rule in @($verified.Access)){try{$sid=[string]$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value}catch{throw 'REAL_USE_CLUSTER_JOIN_ROOT_ACL_INVALID'};if($sid-cnotin$allowed-or$rule.AccessControlType-ne[Security.AccessControl.AccessControlType]::Allow-or($rule.FileSystemRights-band[Security.AccessControl.FileSystemRights]::FullControl)-ne[Security.AccessControl.FileSystemRights]::FullControl){throw 'REAL_USE_CLUSTER_JOIN_ROOT_ACL_INVALID'}}
            }catch{
                $createError=$_.Exception;$createCleanupError=$null
                if($created){try{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop;if(Test-Path -LiteralPath $root){throw 'REAL_USE_CLUSTER_JOIN_ROOT_CREATE_CLEANUP_UNPROVEN'}}catch{$createCleanupError=$_.Exception}}
                if($createCleanupError){throw 'REAL_USE_CLUSTER_JOIN_ROOT_CREATE_CLEANUP_FAILED'}
                throw $createError
            }
        }-ArgumentList $remoteRoot,[string]$Context.runId
        $remoteOwned=$true
        Copy-Item -ToSession $session -LiteralPath ([string]$PrivateState.bundlePath) -Destination $remoteBundle -ErrorAction Stop
        $joined = Invoke-Command -Session $session -ScriptBlock {
            param($bundle,$expectedBundleHash,$expectedPrimary,[Security.SecureString]$bundlePassphrase,[string]$securePwsh7Bridge)
            $ErrorActionPreference='Stop'
            if(-not$bundlePassphrase){throw 'REAL_USE_CLUSTER_JOIN_L1_IDENTITY_INVALID'}
            $launcher=[scriptblock]::Create($securePwsh7Bridge)
            $child={param($request,[Security.SecureString]$bundlePassphrase)
                $bundle=[string]$request.bundle;$expectedBundleHash=[string]$request.expectedBundleHash;$expectedPrimary=$request.expectedPrimary
                if($env:COMPUTERNAME -notlike 'DEVFLEET-E2E-*'-or-not$bundlePassphrase){throw 'REAL_USE_CLUSTER_JOIN_L1_IDENTITY_INVALID'}
                if((Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()-cne$expectedBundleHash){throw 'REAL_USE_CLUSTER_JOIN_BUNDLE_HASH_MISMATCH'}
                $stateRoot='C:\ProgramData\DevFleet';$packageRootPath=Join-Path $stateRoot 'package-root.txt';$hostIdentityPath=Join-Path $stateRoot 'node-identity.json';$hostVaultPath=Join-Path $stateRoot 'vault-node-identity.json';$configPath=Join-Path $stateRoot 'devfleet.config.json'
                foreach($path in @($packageRootPath,$hostIdentityPath,$hostVaultPath,$configPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'REAL_USE_CLUSTER_JOIN_INSTALLATION_MISSING'}}
                $packageRoot=(Get-Content -LiteralPath $packageRootPath -Raw).Trim();$common=Join-Path $packageRoot 'windows\DevFleet.Common.psm1';$complete=Join-Path $packageRoot 'windows\Complete-Cluster.ps1'
                if(-not(Test-Path -LiteralPath $common -PathType Leaf)-or-not(Test-Path -LiteralPath $complete -PathType Leaf)){throw 'REAL_USE_CLUSTER_JOIN_PRODUCT_SEAM_MISSING'}
                Import-Module $common -Force
                $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -ErrorAction Stop;$compute=[string]$config.Failover.InstanceName;$vault=[string]$config.Vault.InstanceName
                if($compute-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'-or$vault-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'){throw 'REAL_USE_CLUSTER_JOIN_TARGET_INVALID'}
                $mp=Get-MultipassExe
                function Read-GuestJson([string]$Name,[string]$Path,[string]$Code){try{$raw=Invoke-External $mp @('exec',$Name,'--','sudo','cat',$Path) -Capture;return ($raw|ConvertFrom-Json -ErrorAction Stop)}catch{throw $Code}}
                $hostBefore=Get-Content -LiteralPath $hostIdentityPath -Raw|ConvertFrom-Json -ErrorAction Stop;$hostVaultBefore=Get-Content -LiteralPath $hostVaultPath -Raw|ConvertFrom-Json -ErrorAction Stop;$computeBefore=Read-GuestJson $compute '/etc/devfleet/node-identity.json' 'REAL_USE_CLUSTER_JOIN_COMPUTE_IDENTITY_INVALID';$computeConfigBefore=Read-GuestJson $compute '/etc/devfleet/config.json' 'REAL_USE_CLUSTER_JOIN_COMPUTE_CONFIG_INVALID';$vaultBefore=Read-GuestJson $vault '/etc/devfleet-vault-identity.json' 'REAL_USE_CLUSTER_JOIN_VAULT_IDENTITY_INVALID'
                if([string]$hostBefore.node_role-cne'surrogate'-or[string]$hostBefore.deployment_id-ne''-or[string]$hostBefore.registration_state-cne'awaiting-primary-join'-or[string]$hostVaultBefore.deployment_id-ne''-or[string]$computeBefore.deployment_id-ne''-or[string]$computeConfigBefore.deployment_id-ne''-or[string]$vaultBefore.deployment_id-ne''){throw 'REAL_USE_CLUSTER_JOIN_PREJOIN_STATE_INVALID'}
                if([string]$computeBefore.node_id-cne[string]$hostBefore.node_id-or[string]$computeBefore.node_name-cne$compute-or[string]$computeConfigBefore.node_id-cne[string]$hostBefore.node_id-or[string]$computeConfigBefore.node_name-cne$compute-or[string]$hostVaultBefore.node_id-cne[string]$vaultBefore.node_id-or[string]$vaultBefore.node_name-cne$vault){throw 'REAL_USE_CLUSTER_JOIN_PREJOIN_IDENTITY_MISMATCH'}
                & $complete -DesktopPairingBundlePath $bundle -BundlePassphrase $bundlePassphrase | Out-Null
                $hostAfter=Get-Content -LiteralPath $hostIdentityPath -Raw|ConvertFrom-Json -ErrorAction Stop;$hostVault=Get-Content -LiteralPath $hostVaultPath -Raw|ConvertFrom-Json -ErrorAction Stop;$computeIdentity=Read-GuestJson $compute '/etc/devfleet/node-identity.json' 'REAL_USE_CLUSTER_JOIN_COMPUTE_IDENTITY_INVALID';$computeConfig=Read-GuestJson $compute '/etc/devfleet/config.json' 'REAL_USE_CLUSTER_JOIN_COMPUTE_CONFIG_INVALID';$vaultIdentity=Read-GuestJson $vault '/etc/devfleet-vault-identity.json' 'REAL_USE_CLUSTER_JOIN_VAULT_IDENTITY_INVALID'
                $deployment=[string]$expectedPrimary.deploymentId;$coordinator=[string]$expectedPrimary.nodeId
                if([string]$hostAfter.deployment_id-cne$deployment-or[string]$hostAfter.coordinator_node_id-cne$coordinator-or[string]$hostAfter.registration_state-cne'joined'-or[string]$hostAfter.node_id-cne[string]$hostBefore.node_id){throw 'REAL_USE_CLUSTER_JOIN_HOST_IDENTITY_MISMATCH'}
                if([string]$computeIdentity.deployment_id-cne$deployment-or[string]$computeIdentity.coordinator_node_id-cne$coordinator-or[string]$computeIdentity.registration_state-cne'joined'-or[string]$computeIdentity.node_id-cne[string]$hostAfter.node_id-or[string]$computeConfig.deployment_id-cne$deployment-or[string]$computeConfig.coordinator_node_id-cne$coordinator-or[string]$computeConfig.registration_state-cne'joined'-or[string]$computeConfig.node_id-cne[string]$hostAfter.node_id){throw 'REAL_USE_CLUSTER_JOIN_COMPUTE_IDENTITY_MISMATCH'}
                if([string]$hostVault.deployment_id-cne$deployment-or[string]$hostVault.node_id-cne[string]$hostVaultBefore.node_id-or[string]$vaultIdentity.deployment_id-cne$deployment-or[string]$vaultIdentity.node_id-cne[string]$hostVault.node_id){throw 'REAL_USE_CLUSTER_JOIN_VAULT_IDENTITY_MISMATCH'}
                Invoke-External $mp @('exec',$compute,'--','systemctl','is-active','--quiet','devfleet.service') | Out-Null
                foreach($path in @((Join-Path $stateRoot 'tmp\import-desktop'),(Join-Path $stateRoot 'tmp\primary-peer.json'),(Join-Path $stateRoot 'tmp\primary-node.json'),"$bundle.zip.tmp")){if(Test-Path -LiteralPath $path){if($path-like'*primary-node.json'){Remove-Item -LiteralPath $path -Force -ErrorAction Stop}else{throw 'REAL_USE_CLUSTER_JOIN_DECRYPTED_TEMP_REMAINS'}}}
                return [pscustomobject][ordered]@{primary=[ordered]@{deploymentId=$deployment;nodeId=$coordinator;nodeName=[string]$expectedPrimary.nodeName;nodeRole='primary'};laptop=[ordered]@{deploymentId=[string]$hostAfter.deployment_id;nodeId=[string]$hostAfter.node_id;nodeName=[string]$hostAfter.node_name;nodeRole=[string]$hostAfter.node_role;coordinatorNodeId=[string]$hostAfter.coordinator_node_id;registrationState=[string]$hostAfter.registration_state};compute=[ordered]@{deploymentId=[string]$computeIdentity.deployment_id;nodeId=[string]$computeIdentity.node_id;nodeName=[string]$computeIdentity.node_name;nodeRole=[string]$computeIdentity.node_role;coordinatorNodeId=[string]$computeIdentity.coordinator_node_id;registrationState=[string]$computeIdentity.registration_state};vault=[ordered]@{deploymentId=[string]$vaultIdentity.deployment_id;nodeId=[string]$vaultIdentity.node_id;nodeName=[string]$vaultIdentity.node_name;nodeRole=[string]$vaultIdentity.node_role}}
            }.ToString()
            $request=[ordered]@{bundle=$bundle;expectedBundleHash=$expectedBundleHash;expectedPrimary=$expectedPrimary}|ConvertTo-Json -Depth 6 -Compress
            return & $launcher $child $request $bundlePassphrase 1800 'REAL_USE_CLUSTER_JOIN_PS7_FAILED'
        } -ArgumentList $remoteBundle,$bundleHash,$durableCapture.primary,$secure,$securePwsh7Bridge
        $evidencePath=Join-Path ([string]$Context.runDir) 'real-use-cluster-join.json'
        $evidence=[ordered]@{schemaVersion=1;contract=$script:RealUseClusterJoinContract;status='PASS';runId=[string]$Context.runId;phaseId=$script:RealUseAcceptancePhase;candidate=$candidate;surrogateLifecycle=[ordered]@{transactionId=[string]$product.transactionId;invocationId=[string]$product.invocationId;payloadSha256=[string]$product.payloadSha256;role='Laptop / Surrogate'};primaryCapture=[ordered]@{path=$capturePath;sha256=[string]$Capture.evidenceSha256;encryptedBundleSha256=$bundleHash};primary=$joined.primary;laptop=$joined.laptop;compute=$joined.compute;vault=$joined.vault;sensitiveValuesPersisted=$false}
        Write-EvidenceJson -Path $evidencePath -Value $evidence
        $joinResult=[pscustomobject][ordered]@{evidence=$evidence;evidencePath=$evidencePath;evidenceSha256=(Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()}
    } catch {
        $joinError=$_.Exception
    } finally {
        try {
            if($session -and $remoteOwned){Invoke-Command -Session $session -ScriptBlock{param($root,$runId)if($root-cne"C:\ProgramData\DevFleet\tmp\real-use-pairing-$runId"-or$runId-cnotmatch'\A(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'){throw 'REAL_USE_CLUSTER_JOIN_ROOT_INVALID'};if(Test-Path -LiteralPath $root){$item=Get-Item -LiteralPath $root -Force -ErrorAction Stop;if(-not$item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'REAL_USE_CLUSTER_JOIN_ROOT_REPLACED'};Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop};if(Test-Path -LiteralPath $root){throw 'REAL_USE_CLUSTER_JOIN_ROOT_CLEANUP_FAILED'}}-ArgumentList $remoteRoot,[string]$Context.runId}
        } catch {
            $remoteCleanupError=$_.Exception
        } finally {
            if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}
            if($secure){$secure.Dispose()}
        }
    }
    if($joinError){if($remoteCleanupError){throw "$($joinError.Message); REAL_USE_CLUSTER_JOIN_ROOT_CLEANUP_FAILED"};throw $joinError}
    if($remoteCleanupError){throw 'REAL_USE_CLUSTER_JOIN_ROOT_CLEANUP_FAILED'}
    return $joinResult
}

function Assert-RealUseAcceptanceCandidate {
    param([Parameter(Mandatory)][object]$Actual, [Parameter(Mandatory)][object]$Expected, [string]$Label = 'REAL-USE-ACCEPTANCE candidate')
    $fields = @('repositoryHead','candidateCommit','shippingInputIdentity','releaseFingerprintId','toolingFingerprintId','exeSha256','tarSha256')
    Assert-RealUseAcceptanceKeys -Value $Actual -Allowed $fields -Required $fields -Label $Label | Out-Null
    foreach ($field in $fields) {
        $actualFound = $false; $actualValue = Get-RealUseAcceptanceProperty $Actual $field ([ref]$actualFound)
        $expectedFound = $false; $expectedValue = Get-RealUseAcceptanceProperty $Expected $field ([ref]$expectedFound)
        if (-not $actualFound -or -not $expectedFound -or -not (Test-RealUseAcceptanceSameValue $expectedValue $actualValue)) { throw "$Label binding mismatch: $field." }
    }
    foreach ($field in @('repositoryHead','candidateCommit')) {
        $found = $false; $value = [string](Get-RealUseAcceptanceProperty $Actual $field ([ref]$found))
        if ($value -cnotmatch '^[0-9a-f]{40}$') { throw "$Label has a malformed commit identity." }
    }
    foreach ($field in @('shippingInputIdentity','releaseFingerprintId','toolingFingerprintId','exeSha256','tarSha256')) {
        $found = $false; $value = [string](Get-RealUseAcceptanceProperty $Actual $field ([ref]$found))
        if ($value -cnotmatch '^[0-9a-f]{64}$') { throw "$Label has a malformed SHA-256 identity." }
    }
    return $true
}

function Assert-RealUseAcceptanceExecution {
    param([Parameter(Mandatory)][object]$Actual, [Parameter(Mandatory)][object]$Expected, [string]$Label = 'REAL-USE-ACCEPTANCE execution')
    $fields = @('role','vmName','vmId','computeInstanceName','vaultInstanceName','deploymentId','nodeId','nodeName','transactionId','invocationId','surrogateEvidenceSha256')
    Assert-RealUseAcceptanceKeys -Value $Actual -Allowed $fields -Required $fields -Label $Label | Out-Null
    foreach ($field in $fields) {
        $actualFound = $false; $actualValue = Get-RealUseAcceptanceProperty $Actual $field ([ref]$actualFound)
        $expectedFound = $false; $expectedValue = Get-RealUseAcceptanceProperty $Expected $field ([ref]$expectedFound)
        if (-not $actualFound -or -not $expectedFound -or -not (Test-RealUseAcceptanceSameValue $expectedValue $actualValue)) { throw "$Label binding mismatch: $field." }
    }
    if ([string]$Actual.role -cne 'Laptop / Surrogate' -or [string]$Actual.vmName -notlike 'DevFleet-E2E-*') { throw "$Label is not bound to the installed Laptop/Surrogate disposable." }
    if ([string]$Actual.vmId -cnotmatch '^[0-9a-fA-F-]{36}$' -or [string]$Actual.deploymentId -cnotmatch '^[0-9a-fA-F-]{36}$' -or [string]$Actual.nodeId -cnotmatch '^[0-9a-fA-F-]{36}$') { throw "$Label has a malformed VM or product identity." }
    if ([string]$Actual.computeInstanceName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$' -or [string]$Actual.vaultInstanceName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$' -or [string]$Actual.nodeName -cne [string]$Actual.computeInstanceName) { throw "$Label has a malformed or divergent installed node identity." }
    if ([string]$Actual.transactionId -cnotmatch '^[0-9a-f]{32}$' -or [string]$Actual.invocationId -cnotmatch '^[0-9a-f]{32}$' -or [string]$Actual.surrogateEvidenceSha256 -cnotmatch '^[0-9a-f]{64}$') { throw "$Label has a malformed lifecycle identity." }
    return $true
}

function Assert-RealUseAcceptanceInput {
    param([Parameter(Mandatory)][Alias('Input')][object]$AcceptanceInput, [Parameter(Mandatory)][object]$Request)
    $fields = @('schemaVersion','runId','deadlineUtc','runnerSha256','candidate','execution','paths','baseUrl')
    Assert-RealUseAcceptanceKeys -Value $AcceptanceInput -Allowed $fields -Required $fields -Label 'REAL-USE-ACCEPTANCE input' | Out-Null
    if ([int]$AcceptanceInput.schemaVersion -ne 1 -or [string]$AcceptanceInput.runId -cne [string]$Request.runId -or -not (Test-RealUseAcceptanceSameInstant $Request.deadlineUtc $AcceptanceInput.deadlineUtc) -or [string]$AcceptanceInput.runnerSha256 -cne [string]$Request.runnerSha256) { throw 'REAL-USE-ACCEPTANCE input identity is not exact.' }
    Assert-RealUseAcceptanceRunId -RunId ([string]$AcceptanceInput.runId) | Out-Null
    Assert-RealUseAcceptanceCandidate -Actual $AcceptanceInput.candidate -Expected $Request.candidate -Label 'REAL-USE-ACCEPTANCE input candidate' | Out-Null
    $expectedExecution = [ordered]@{
        role = 'Laptop / Surrogate'; vmName = [string]$Request.vmName; vmId = [string]$Request.vmId
        computeInstanceName = [string]$Request.computeInstanceName; vaultInstanceName = [string]$Request.vaultInstanceName
        deploymentId = [string]$Request.deploymentId; nodeId = [string]$Request.nodeId; nodeName = [string]$Request.computeInstanceName
        transactionId = [string]$Request.transactionId; invocationId = [string]$Request.invocationId
        surrogateEvidenceSha256 = [string]$Request.surrogateEvidenceSha256
    }
    Assert-RealUseAcceptanceExecution -Actual $AcceptanceInput.execution -Expected $expectedExecution -Label 'REAL-USE-ACCEPTANCE input execution' | Out-Null
    $pathFields = @('workspaces','quarantine','runtimeRoot')
    Assert-RealUseAcceptanceKeys -Value $AcceptanceInput.paths -Allowed $pathFields -Required $pathFields -Label 'REAL-USE-ACCEPTANCE installed paths' | Out-Null
    if ([string]$AcceptanceInput.paths.workspaces -cne '/home/devrunner/workspaces' -or [string]$AcceptanceInput.paths.quarantine -cne '/home/devrunner/.devfleet-quarantine' -or [string]$AcceptanceInput.paths.runtimeRoot -cne '/var/lib/devfleet/runtime') { throw 'REAL-USE-ACCEPTANCE installed mutable paths are outside the supported product contract.' }
    if ([string]$AcceptanceInput.baseUrl -cnotmatch '^http://127\.0\.0\.1:(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$') { throw 'REAL-USE-ACCEPTANCE input base URL is not exact loopback HTTP.' }
    Assert-RealUseAcceptanceSanitizedValue -Value $AcceptanceInput -Path 'input' | Out-Null
    return $true
}

function Assert-RealUseAcceptanceReport {
    param(
        [Parameter(Mandatory)][object]$Report,
        [Parameter(Mandatory)][Alias('Input')][object]$AcceptanceInput,
        [Parameter(Mandatory)][ValidateSet('prepare','resume','cleanup')][string]$ExpectedStage,
        [Parameter(Mandatory)][string[]]$AllowedStatus,
        [switch]$RequirePass
    )
    $topFields = @('schemaVersion','contract','status','stage','runId','phaseId','candidate','execution','runnerSha256','startedAtUtc','finishedAtUtc','deadlineUtc','journeys','operations','fixture','cleanup','failure','cleanupFailure')
    Assert-RealUseAcceptanceKeys -Value $Report -Allowed $topFields -Required $topFields -Label 'REAL-USE-ACCEPTANCE report' | Out-Null
    Assert-RealUseAcceptanceSanitizedValue -Value $Report | Out-Null
    if ([int]$Report.schemaVersion -ne 1 -or [string]$Report.contract -cne $script:RealUseAcceptanceContract -or [string]$Report.stage -cne $ExpectedStage -or [string]$Report.phaseId -cne $script:RealUseAcceptancePhase) { throw 'REAL-USE-ACCEPTANCE report contract or stage is invalid.' }
    if ([string]$Report.status -notin $AllowedStatus -or [string]$Report.runId -cne [string]$AcceptanceInput.runId -or [string]$Report.runnerSha256 -cne [string]$AcceptanceInput.runnerSha256 -or -not (Test-RealUseAcceptanceSameInstant $AcceptanceInput.deadlineUtc $Report.deadlineUtc)) { throw 'REAL-USE-ACCEPTANCE report status or immutable identity is invalid.' }
    Assert-RealUseAcceptanceCandidate -Actual $Report.candidate -Expected $AcceptanceInput.candidate -Label 'REAL-USE-ACCEPTANCE report candidate' | Out-Null
    $executionFields = @('role','vmName','vmId','computeInstanceName','vaultInstanceName','deploymentId','nodeId','nodeName','transactionId','invocationId','surrogateEvidenceSha256','uiTransport','browserJavascriptExercised')
    Assert-RealUseAcceptanceKeys -Value $Report.execution -Allowed $executionFields -Required $executionFields -Label 'REAL-USE-ACCEPTANCE report execution' | Out-Null
    $executionProjection = [ordered]@{}
    foreach ($field in @('role','vmName','vmId','computeInstanceName','vaultInstanceName','deploymentId','nodeId','nodeName','transactionId','invocationId','surrogateEvidenceSha256')) { $executionProjection[$field] = $Report.execution.$field }
    Assert-RealUseAcceptanceExecution -Actual $executionProjection -Expected $AcceptanceInput.execution -Label 'REAL-USE-ACCEPTANCE report execution' | Out-Null
    if ([string]$Report.execution.uiTransport -cne 'authenticated-http-form' -or $Report.execution.browserJavascriptExercised -isnot [bool] -or [bool]$Report.execution.browserJavascriptExercised) { throw 'REAL-USE-ACCEPTANCE report execution channel is invalid.' }
    $started = [datetime]::MinValue; $finished = [datetime]::MinValue; $deadline = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Report.startedAtUtc, [ref]$started) -or -not [datetime]::TryParse([string]$Report.finishedAtUtc, [ref]$finished) -or -not [datetime]::TryParse([string]$Report.deadlineUtc, [ref]$deadline) -or $finished.ToUniversalTime() -lt $started.ToUniversalTime() -or $finished.ToUniversalTime() -gt $deadline.ToUniversalTime()) { throw 'REAL-USE-ACCEPTANCE report timestamps are invalid or outside the owning deadline.' }
    $journeys = @($Report.journeys)
    if ($journeys.Count -ne 5 -or @($journeys.id | Select-Object -Unique).Count -ne 5 -or @('U01','U02','U03','U04','U05' | Where-Object { $_ -notin @($journeys.id) }).Count) { throw 'REAL-USE-ACCEPTANCE report does not contain exactly U01-U05.' }
    foreach ($journey in $journeys) {
        Assert-RealUseAcceptanceKeys -Value $journey -Allowed @('id','status','assertions','observations') -Required @('id','status','assertions','observations') -Label 'REAL-USE-ACCEPTANCE journey' | Out-Null
        $journeyId = [string]$journey.id
        if ($journeyId -cnotin @($script:RealUseAcceptanceAssertions.Keys)) { throw 'REAL-USE-ACCEPTANCE journey identifier is invalid.' }
        if ([string]$journey.status -notin @('PASS','IN_PROGRESS','NOT_RUN','BLOCKED')) { throw 'REAL-USE-ACCEPTANCE journey has an invalid status.' }
        if ([string]$journey.status -eq 'PASS') {
            $assertionNames = @(Get-RealUseAcceptancePropertyNames $journey.assertions)
            $expectedAssertionNames = @($script:RealUseAcceptanceAssertions[$journeyId])
            if ($assertionNames.Count -ne $expectedAssertionNames.Count -or @($assertionNames | Where-Object { $_ -cnotin $expectedAssertionNames }).Count -or @($expectedAssertionNames | Where-Object { $_ -cnotin $assertionNames }).Count) { throw 'REAL-USE-ACCEPTANCE PASS journey does not contain its exact fixed assertion set.' }
            foreach ($name in $assertionNames) { $found = $false; $value = Get-RealUseAcceptanceProperty $journey.assertions $name ([ref]$found); if (-not $found -or $value -isnot [bool] -or -not [bool]$value) { throw 'REAL-USE-ACCEPTANCE PASS journey contains an unproven assertion.' } }
        }
    }
    foreach ($operation in @($Report.operations)) {
        $operationFields = @('id','kind','project','state','expectedState','route','httpStatus','renderedState','smokeOutputObserved')
        Assert-RealUseAcceptanceKeys -Value $operation -Allowed $operationFields -Required $operationFields -Label 'REAL-USE-ACCEPTANCE operation' | Out-Null
        if ([string]$operation.id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or [int]$operation.httpStatus -lt 100 -or [int]$operation.httpStatus -gt 599 -or $operation.smokeOutputObserved -isnot [bool]) { throw 'REAL-USE-ACCEPTANCE operation evidence is malformed.' }
    }
    $fixtureFields = @('slug','projectId','sentinelSha256','originalPath','recoveredPath')
    [string[]]$requiredFixtureFields = @()
    if ($RequirePass -or [string]$Report.status -in @('PASS','PREPARED')) { $requiredFixtureFields = @('slug','projectId','sentinelSha256','originalPath','recoveredPath') }
    Assert-RealUseAcceptanceKeys -Value $Report.fixture -Allowed $fixtureFields -Required $requiredFixtureFields -Label 'REAL-USE-ACCEPTANCE fixture' | Out-Null
    $fixtureNames = @(Get-RealUseAcceptancePropertyNames $Report.fixture)
    if ('slug' -in $fixtureNames -and [string]$Report.fixture.slug -notmatch '^[a-z0-9][a-z0-9._-]{1,62}$') { throw 'REAL-USE-ACCEPTANCE fixture slug is malformed.' }
    if ('projectId' -in $fixtureNames -and [string]$Report.fixture.projectId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'REAL-USE-ACCEPTANCE fixture project identity is malformed.' }
    if ('sentinelSha256' -in $fixtureNames -and [string]$Report.fixture.sentinelSha256 -notmatch '^[0-9a-f]{64}$') { throw 'REAL-USE-ACCEPTANCE fixture sentinel identity is malformed.' }
    $cleanupFields = @('status','ownedOnly','resources','errors','vaultSnapshots')
    Assert-RealUseAcceptanceKeys -Value $Report.cleanup -Allowed $cleanupFields -Required $cleanupFields -Label 'REAL-USE-ACCEPTANCE cleanup' | Out-Null
    if ([string]$Report.cleanup.status -notin @('NOT_RUN','PASS','BLOCKED') -or $Report.cleanup.ownedOnly -isnot [bool]) { throw 'REAL-USE-ACCEPTANCE cleanup status is malformed.' }
    foreach ($resource in @($Report.cleanup.resources)) {
        Assert-RealUseAcceptanceKeys -Value $resource -Allowed @('kind','path','status') -Required @('kind','path','status') -Label 'REAL-USE-ACCEPTANCE cleanup resource' | Out-Null
        if ([string]::IsNullOrWhiteSpace([string]$resource.kind) -or [string]::IsNullOrWhiteSpace([string]$resource.path) -or [string]::IsNullOrWhiteSpace([string]$resource.status)) { throw 'REAL-USE-ACCEPTANCE cleanup resource is incomplete.' }
    }
    if ($RequirePass) {
        if ([string]$Report.status -cne 'PASS' -or $ExpectedStage -cne 'resume' -or @($journeys | Where-Object { [string]$_.status -cne 'PASS' }).Count -or [string]$Report.cleanup.status -cne 'PASS' -or -not [bool]$Report.cleanup.ownedOnly -or @($Report.cleanup.errors).Count -or [string]$Report.cleanup.vaultSnapshots -cne 'RETAINED_APPEND_ONLY_IN_DISPOSABLE_VAULT' -or $null -ne $Report.failure -or $null -ne $Report.cleanupFailure) { throw 'REAL-USE-ACCEPTANCE final report is not a complete U01-U05 plus cleanup PASS.' }
        if (@($Report.operations).Count -lt 5 -or @($Report.cleanup.resources).Count -lt 1) { throw 'REAL-USE-ACCEPTANCE final report lacks operation or cleanup evidence.' }
        foreach ($resource in @($Report.cleanup.resources)) { if ([string]$resource.status -match '(?i)BLOCK|FAIL|ERROR|REMAIN') { throw 'REAL-USE-ACCEPTANCE cleanup retained a run-owned resource.' } }
    } elseif ([string]$Report.status -ceq 'PREPARED') {
        $expected = [ordered]@{U01='PASS';U02='PASS';U03='IN_PROGRESS';U04='NOT_RUN';U05='NOT_RUN'}
        foreach ($id in $expected.Keys) { $row = @($journeys | Where-Object { [string]$_.id -ceq $id }); if ($row.Count -ne 1 -or [string]$row[0].status -cne [string]$expected[$id]) { throw 'REAL-USE-ACCEPTANCE prepare report has an invalid journey boundary.' } }
        if ([string]$Report.cleanup.status -cne 'NOT_RUN' -or $null -ne $Report.failure -or $null -ne $Report.cleanupFailure) { throw 'REAL-USE-ACCEPTANCE prepare report has an invalid cleanup boundary.' }
    }
    return $true
}

function Assert-RealUseAcceptanceBlockedEnvelope {
    param(
        [Parameter(Mandatory)][object]$Report,
        [Parameter(Mandatory)][ValidateSet('prepare','resume','cleanup')][string]$ExpectedStage
    )
    # The driver emits this exact reduced envelope only when initialization
    # fails before it can bind the request.  Do not let a malformed full
    # report fall back to this path and shed fields that failed validation.
    $fields = @('schemaVersion','contract','status','stage','phaseId','failure','cleanup')
    Assert-RealUseAcceptanceKeys -Value $Report -Allowed $fields -Required $fields -Label 'REAL-USE-ACCEPTANCE blocked envelope' | Out-Null
    Assert-RealUseAcceptanceSanitizedValue -Value $Report -Path 'blockedEnvelope' | Out-Null
    if ([int]$Report.schemaVersion -ne 1 -or [string]$Report.contract -cne $script:RealUseAcceptanceContract -or [string]$Report.status -cne 'BLOCKED' -or [string]$Report.stage -cne $ExpectedStage -or [string]$Report.phaseId -cne $script:RealUseAcceptancePhase) { throw 'REAL-USE-ACCEPTANCE blocked envelope identity is invalid.' }
    Assert-RealUseAcceptanceKeys -Value $Report.failure -Allowed @('code') -Required @('code') -Label 'REAL-USE-ACCEPTANCE blocked failure' | Out-Null
    if ([string]$Report.failure.code -cnotmatch '^[A-Z][A-Z0-9_]{1,95}$') { throw 'REAL-USE-ACCEPTANCE blocked failure code is invalid.' }
    Assert-RealUseAcceptanceKeys -Value $Report.cleanup -Allowed @('status','ownedOnly') -Required @('status','ownedOnly') -Label 'REAL-USE-ACCEPTANCE blocked cleanup' | Out-Null
    if ([string]$Report.cleanup.status -notin @('NOT_RUN','PASS','BLOCKED') -or $Report.cleanup.ownedOnly -isnot [bool]) { throw 'REAL-USE-ACCEPTANCE blocked cleanup boundary is invalid.' }
    return $true
}

function Write-RealUseAcceptanceDriverEvidence {
    param(
        [Parameter(Mandatory)][object]$Report,
        [Parameter(Mandatory)][object]$AcceptanceInput,
        [Parameter(Mandatory)][ValidateSet('prepare','resume','cleanup')][string]$ExpectedStage,
        [Parameter(Mandatory)][string[]]$AllowedStatus,
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowInitializationEnvelope
    )
    $validation = 'FULL'
    try {
        Assert-RealUseAcceptanceReport -Report $Report -Input $AcceptanceInput -ExpectedStage $ExpectedStage -AllowedStatus $AllowedStatus | Out-Null
    } catch {
        if (-not $AllowInitializationEnvelope -or [string]$Report.status -cne 'BLOCKED') { throw }
        Assert-RealUseAcceptanceBlockedEnvelope -Report $Report -ExpectedStage $ExpectedStage | Out-Null
        $validation = 'INITIALIZATION_BLOCKED_ENVELOPE'
    }
    Write-EvidenceJson -Path $Path -Value $Report
    return [pscustomobject][ordered]@{
        path = $Path
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        status = [string]$Report.status
        validation = $validation
    }
}

function Write-OptionalRealUseAcceptanceCleanupEvidence {
    param(
        [AllowNull()][object]$Report,
        [Parameter(Mandatory)][object]$AcceptanceInput,
        [Parameter(Mandatory)][string]$RunDir
    )
    if ($null -eq $Report) { return $null }
    $path = Join-Path $RunDir 'real-use-acceptance-cleanup.json'
    try {
        return Write-RealUseAcceptanceDriverEvidence -Report $Report -AcceptanceInput $AcceptanceInput -ExpectedStage cleanup -AllowedStatus @('BLOCKED') -Path $path -AllowInitializationEnvelope
    } catch {
        # Cleanup diagnostics are secondary to the already durable primary
        # prepare/resume failure.  Return a fixed classification rather than
        # replacing that primary failure with parser detail.
        return [pscustomobject][ordered]@{path=$path;sha256=$null;status='INVALID';validation='REJECTED'}
    }
}

function Assert-RealUseAcceptanceClusterJoinEvidence {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Candidate,
        [Parameter(Mandatory)][object]$SurrogateProduct
    )
    if (-not $Context.PSObject.Properties['realUseClusterJoin']) { throw 'REAL-USE-ACCEPTANCE context lacks genuine cluster-join evidence.' }
    $binding = $Context.realUseClusterJoin
    Assert-RealUseAcceptanceKeys -Value $binding -Allowed @('evidence','evidencePath','evidenceSha256') -Required @('evidence','evidencePath','evidenceSha256') -Label 'REAL-USE-ACCEPTANCE cluster-join context' | Out-Null
    $path = Assert-RealUseAcceptanceCanonicalEvidencePath -Root ([string]$Context.runDir) -Path ([string]$binding.evidencePath) -LeafName 'real-use-cluster-join.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [string]$binding.evidenceSha256 -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$binding.evidenceSha256) { throw 'REAL-USE-ACCEPTANCE cluster-join evidence is missing or changed.' }
    $join = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    if (-not (Test-RealUseAcceptanceJsonEqual $join $binding.evidence)) { throw 'REAL-USE-ACCEPTANCE cluster-join context diverges from durable evidence.' }
    $fields=@('schemaVersion','contract','status','runId','phaseId','candidate','surrogateLifecycle','primaryCapture','primary','laptop','compute','vault','sensitiveValuesPersisted')
    Assert-RealUseAcceptanceKeys -Value $join -Allowed $fields -Required $fields -Label 'REAL-USE-ACCEPTANCE cluster-join evidence' | Out-Null
    Assert-RealUseAcceptanceSanitizedValue -Value $join -Path 'clusterJoin' | Out-Null
    if ([int]$join.schemaVersion -ne 1 -or [string]$join.contract -cne $script:RealUseClusterJoinContract -or [string]$join.status -cne 'PASS' -or [string]$join.runId -cne [string]$Context.runId -or [string]$join.phaseId -cne $script:RealUseAcceptancePhase -or $join.sensitiveValuesPersisted -isnot [bool] -or [bool]$join.sensitiveValuesPersisted) { throw 'REAL-USE-ACCEPTANCE cluster-join evidence contract is invalid.' }
    Assert-RealUseAcceptanceCandidate -Actual $join.candidate -Expected $Candidate -Label 'REAL-USE-ACCEPTANCE cluster-join candidate' | Out-Null
    Assert-RealUseAcceptanceKeys -Value $join.surrogateLifecycle -Allowed @('transactionId','invocationId','payloadSha256','role') -Required @('transactionId','invocationId','payloadSha256','role') -Label 'REAL-USE-ACCEPTANCE joined Surrogate lifecycle' | Out-Null
    if ([string]$join.surrogateLifecycle.transactionId -cne [string]$SurrogateProduct.transactionId -or [string]$join.surrogateLifecycle.invocationId -cne [string]$SurrogateProduct.invocationId -or [string]$join.surrogateLifecycle.payloadSha256 -cne [string]$Candidate.tarSha256 -or [string]$join.surrogateLifecycle.role -cne 'Laptop / Surrogate') { throw 'REAL-USE-ACCEPTANCE cluster join is not bound to the preceding Surrogate lifecycle.' }
    Assert-RealUseAcceptanceKeys -Value $join.primaryCapture -Allowed @('path','sha256','encryptedBundleSha256') -Required @('path','sha256','encryptedBundleSha256') -Label 'REAL-USE-ACCEPTANCE Primary capture link' | Out-Null
    $capturePath=Assert-RealUseAcceptanceCanonicalEvidencePath -Root ([string]$Context.runDir) -Path ([string]$join.primaryCapture.path) -LeafName 'real-use-primary-pairing.json'
    if(-not(Test-Path -LiteralPath $capturePath -PathType Leaf)-or(Get-FileHash -LiteralPath $capturePath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$join.primaryCapture.sha256-or[string]$join.primaryCapture.encryptedBundleSha256-cnotmatch'^[0-9a-f]{64}$'){throw 'REAL-USE-ACCEPTANCE Primary pairing link is invalid.'}
    $capture=Get-Content -LiteralPath $capturePath -Raw|ConvertFrom-Json -ErrorAction Stop
    if([string]$capture.contract-cne$script:RealUsePairingCaptureContract-or[string]$capture.status-cne'PASS'-or[string]$capture.runId-cne[string]$Context.runId-or[string]$capture.encryptedBundle.sha256-cne[string]$join.primaryCapture.encryptedBundleSha256-or$capture.sensitiveValuesPersisted-isnot[bool]-or[bool]$capture.sensitiveValuesPersisted){throw 'REAL-USE-ACCEPTANCE durable Primary pairing capture is invalid.'}
    Assert-RealUseAcceptanceCandidate -Actual $capture.candidate -Expected $Candidate -Label 'REAL-USE-ACCEPTANCE durable Primary pairing candidate' | Out-Null
    $primaryFields=@('deploymentId','nodeId','nodeName','nodeRole');Assert-RealUseAcceptanceKeys -Value $join.primary -Allowed $primaryFields -Required $primaryFields -Label 'REAL-USE-ACCEPTANCE Primary identity'|Out-Null
    $joinedFields=@('deploymentId','nodeId','nodeName','nodeRole','coordinatorNodeId','registrationState');foreach($name in @('laptop','compute')){Assert-RealUseAcceptanceKeys -Value $join.$name -Allowed $joinedFields -Required $joinedFields -Label "REAL-USE-ACCEPTANCE $name identity"|Out-Null}
    $vaultFields=@('deploymentId','nodeId','nodeName','nodeRole');Assert-RealUseAcceptanceKeys -Value $join.vault -Allowed $vaultFields -Required $vaultFields -Label 'REAL-USE-ACCEPTANCE Vault identity'|Out-Null
    foreach($value in @($join.primary.deploymentId,$join.primary.nodeId,$join.laptop.deploymentId,$join.laptop.nodeId,$join.compute.deploymentId,$join.compute.nodeId,$join.vault.deploymentId,$join.vault.nodeId)){if([string]$value-cnotmatch'^[0-9a-fA-F-]{36}$'){throw 'REAL-USE-ACCEPTANCE joined product identity is malformed.'}}
    if([string]$join.primary.nodeRole-cne'primary'-or[string]$join.laptop.nodeRole-cne'surrogate'-or[string]$join.compute.nodeRole-cne'surrogate'-or[string]$join.vault.nodeRole-cne'vault'-or[string]$join.laptop.deploymentId-cne[string]$join.primary.deploymentId-or[string]$join.compute.deploymentId-cne[string]$join.primary.deploymentId-or[string]$join.vault.deploymentId-cne[string]$join.primary.deploymentId-or[string]$join.laptop.nodeId-cne[string]$join.compute.nodeId-or[string]$join.laptop.coordinatorNodeId-cne[string]$join.primary.nodeId-or[string]$join.compute.coordinatorNodeId-cne[string]$join.primary.nodeId-or[string]$join.laptop.registrationState-cne'joined'-or[string]$join.compute.registrationState-cne'joined'){throw 'REAL-USE-ACCEPTANCE joined identity graph is inconsistent.'}
    if([string]$capture.primary.deploymentId-cne[string]$join.primary.deploymentId-or[string]$capture.primary.nodeId-cne[string]$join.primary.nodeId-or[string]$capture.primary.nodeName-cne[string]$join.primary.nodeName){throw 'REAL-USE-ACCEPTANCE joined identities diverge from the genuine Primary invitation.'}
    return [pscustomobject][ordered]@{evidence=$join;evidencePath=$path;evidenceSha256=[string]$binding.evidenceSha256;capturePath=$capturePath;captureSha256=[string]$join.primaryCapture.sha256}
}

function Get-RealUseAcceptanceSurrogateBinding {
    param([Parameter(Mandatory)][object]$Context)
    Assert-RealUseAcceptanceRunId -RunId ([string]$Context.runId) | Out-Null
    if ([string]$Context.phaseId -cne $script:RealUseAcceptancePhase -or [string]$Context.vmName -notlike 'DevFleet-E2E-*') { throw 'REAL-USE-ACCEPTANCE context is not the owned FullRelease phase.' }
    $recordsPath = Join-Path ([string]$Context.runDir) 'fullrelease-phase-records.json'
    if (-not (Test-Path -LiteralPath $recordsPath -PathType Leaf)) { throw 'REAL-USE-ACCEPTANCE cannot bind the preceding FullRelease phase records.' }
    $records = @(Get-Content -LiteralPath $recordsPath -Raw | ConvertFrom-Json -ErrorAction Stop)
    if (-not $records.Count) { throw 'REAL-USE-ACCEPTANCE has no preceding FullRelease phase records.' }
    $surrogate = $records[$records.Count - 1]
    $surrogateErrorFound = $false
    $surrogateError = Get-RealUseAcceptanceProperty $surrogate 'error' ([ref]$surrogateErrorFound)
    if ([string]$surrogate.id -cne 'SURROGATE-DISPOSABLE' -or [string]$surrogate.status -cne 'PASS' -or ($surrogateErrorFound -and $null -ne $surrogateError)) { throw 'REAL-USE-ACCEPTANCE must immediately follow a passing SURROGATE-DISPOSABLE record.' }
    $executor = $surrogate.evidence.executor
    $product = $executor.product
    if ([string]$executor.status -cne 'REAL E2E PASS' -or [string]$executor.phase -cne 'SURROGATE-DISPOSABLE' -or [string]$product.status -cne 'REAL E2E PASS' -or [string]$product.contract -cne 'product-lifecycle-completion-authority' -or -not [bool]$product.completionVerified -or [string]$product.role -cne 'Laptop / Surrogate') { throw 'REAL-USE-ACCEPTANCE preceding Surrogate record lacks product completion authority.' }
    $transactionId = [string]$product.transactionId; $invocationId = [string]$product.invocationId
    if ($transactionId -cnotmatch '^[0-9a-f]{32}$' -or $invocationId -cnotmatch '^[0-9a-f]{32}$') { throw 'REAL-USE-ACCEPTANCE preceding Surrogate lifecycle identity is malformed.' }
    $candidate = [ordered]@{
        repositoryHead = [string]$Context.candidate.repositoryHead
        candidateCommit = [string]$Context.candidate.gitCommit
        shippingInputIdentity = [string]$Context.candidate.shippingInputIdentity
        releaseFingerprintId = [string]$Context.candidate.releaseFingerprintId
        toolingFingerprintId = [string]$Context.candidate.toolingFingerprintId
        exeSha256 = [string]$Context.candidate.candidate.sha256
        tarSha256 = [string]$Context.candidate.tar.sha256
    }
    Assert-RealUseAcceptanceCandidate -Actual $candidate -Expected $candidate | Out-Null
    $productCandidate = $product.candidate
    $candidateProjection = [ordered]@{
        repositoryHead = [string]$productCandidate.repositoryHead; candidateCommit = [string]$productCandidate.gitCommit
        shippingInputIdentity = [string]$productCandidate.shippingInputIdentity; releaseFingerprintId = [string]$productCandidate.releaseFingerprintId
        toolingFingerprintId = [string]$productCandidate.toolingFingerprintId; exeSha256 = [string]$productCandidate.candidate.sha256; tarSha256 = [string]$productCandidate.tar.sha256
    }
    Assert-RealUseAcceptanceCandidate -Actual $candidateProjection -Expected $candidate -Label 'preceding Surrogate candidate' | Out-Null
    $authorityPath = Assert-RealUseAcceptanceContainedPath -Root ([string]$Context.runDir) -Path ([string]$product.evidencePath) -Label 'Surrogate completion authority'
    if (-not (Test-Path -LiteralPath $authorityPath -PathType Leaf)) { throw 'REAL-USE-ACCEPTANCE Surrogate completion authority is missing.' }
    $authority = Get-Content -LiteralPath $authorityPath -Raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($field in @('status','contract','transactionId','invocationId','payloadSha256','role')) { if ([string]$authority.$field -cne [string]$product.$field) { throw 'REAL-USE-ACCEPTANCE durable Surrogate authority diverges from its phase record.' } }
    if (-not [bool]$authority.completionVerified -or -not [bool]$authority.authenticatedHealth -or [string]$authority.payloadSha256 -cne [string]$candidate.tarSha256) { throw 'REAL-USE-ACCEPTANCE durable Surrogate authority is incomplete.' }
    $targets = @($authority.guest.roleEvidence.requiredTargets)
    $compute = @($targets | Where-Object { [string]$_.nodeRole -ceq 'surrogate' -and [string]$_.kind -ceq 'compute' })
    $vault = @($targets | Where-Object { [string]$_.nodeRole -ceq 'vault' -and [string]$_.kind -ceq 'vault' })
    if ($targets.Count -ne 2 -or $compute.Count -ne 1 -or $vault.Count -ne 1) { throw 'REAL-USE-ACCEPTANCE Surrogate authority lacks the exact Failover and Vault target set.' }
    $joinBinding=Assert-RealUseAcceptanceClusterJoinEvidence -Context $Context -Candidate ([pscustomobject]$candidate) -SurrogateProduct $product
    if([string]$joinBinding.evidence.compute.nodeName-cne[string]$compute[0].instanceName-or[string]$joinBinding.evidence.vault.nodeName-cne[string]$vault[0].instanceName){throw 'REAL-USE-ACCEPTANCE joined nodes diverge from the Surrogate lifecycle targets.'}
    return [pscustomobject][ordered]@{
        runId = [string]$Context.runId; phaseId = $script:RealUseAcceptancePhase; vmName = [string]$Context.vmName; vmId = [string]$Context.vmId
        candidate = [pscustomobject]$candidate; transactionId = $transactionId; invocationId = $invocationId
        computeInstanceName = [string]$compute[0].instanceName; vaultInstanceName = [string]$vault[0].instanceName
        surrogateEvidencePath = $authorityPath; surrogateEvidenceSha256 = (Get-FileHash -LiteralPath $authorityPath -Algorithm SHA256).Hash.ToLowerInvariant()
        phaseRecordsPath = $recordsPath; phaseRecordsSha256 = (Get-FileHash -LiteralPath $recordsPath -Algorithm SHA256).Hash.ToLowerInvariant()
        deploymentId = [string]$joinBinding.evidence.compute.deploymentId; nodeId = [string]$joinBinding.evidence.compute.nodeId; primaryNodeId = [string]$joinBinding.evidence.primary.nodeId
        vaultNodeId = [string]$joinBinding.evidence.vault.nodeId; clusterJoinEvidencePath=$joinBinding.evidencePath; clusterJoinEvidenceSha256=$joinBinding.evidenceSha256
        primaryPairingEvidencePath=$joinBinding.capturePath; primaryPairingEvidenceSha256=$joinBinding.captureSha256
    }
}

function Invoke-RealUseAcceptanceTransport {
    param([Parameter(Mandatory)][object]$Request)
    $session = $null
    $remoteRoot = "C:\Users\Public\DevFleet-E2E\$($Request.runId)\$($Request.phaseId)"
    $remoteRunner = Join-Path $remoteRoot 'Invoke-RealUseAcceptance.py'
    $result = $null
    $outerError = $null
    $l1CleanupError = $null
    $l1RootOwned = $false
    $l1RootRemoved = $false
    try {
        $session = Connect-DevFleetGuest -VmId ([guid][string]$Request.vmId)
        Invoke-Command -Session $session -ScriptBlock {
            param($path)
            if($path -notlike 'C:\Users\Public\DevFleet-E2E\*\REAL-USE-ACCEPTANCE'){throw 'REAL_USE_L1_ROOT_INVALID'}
            if(Test-Path -LiteralPath $path){throw 'REAL_USE_L1_ROOT_COLLISION'}
            New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
        } -ArgumentList $remoteRoot
        $l1RootOwned = $true
        $l1Stage = Get-StageIntegrity -LocalPath ([string]$Request.runnerPath) -Session $session -RemotePath $remoteRunner
        if (-not [bool]$l1Stage.equal -or [string]$l1Stage.localSha256 -cne [string]$Request.runnerSha256 -or [string]$l1Stage.remoteSha256 -cne [string]$Request.runnerSha256) { throw 'REAL-USE-ACCEPTANCE runner changed while staging to the disposable L1.' }
        $result = Invoke-Command -Session $session -ScriptBlock {
            param($runner,$expectedRunnerHash,$request)
            $ErrorActionPreference = 'Stop'
            if ($env:COMPUTERNAME -notlike 'DEVFLEET-E2E-*') { throw 'REAL_USE_L1_IDENTITY_INVALID' }
            if ((Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedRunnerHash) { throw 'REAL_USE_L1_RUNNER_HASH_MISMATCH' }
            $configPath = 'C:\ProgramData\DevFleet\devfleet.config.json'; $identityPath = 'C:\ProgramData\DevFleet\node-identity.json'; $vaultIdentityPath = 'C:\ProgramData\DevFleet\vault-node-identity.json'
            if (-not (Test-Path -LiteralPath $configPath -PathType Leaf) -or -not (Test-Path -LiteralPath $identityPath -PathType Leaf) -or -not (Test-Path -LiteralPath $vaultIdentityPath -PathType Leaf)) { throw 'REAL_USE_L1_INSTALLATION_MISSING' }
            $installed = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $hostIdentity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $hostVaultIdentity = Get-Content -LiteralPath $vaultIdentityPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ([string]$installed.Failover.InstanceName -cne [string]$request.computeInstanceName -or [string]$installed.Vault.InstanceName -cne [string]$request.vaultInstanceName -or [string]$hostIdentity.node_role -cne 'surrogate' -or [string]$hostIdentity.deployment_id -cne [string]$request.deploymentId -or [string]$hostIdentity.node_id -cne [string]$request.nodeId -or [string]$hostIdentity.coordinator_node_id -cne [string]$request.primaryNodeId -or [string]$hostIdentity.registration_state -cne 'joined') { throw 'REAL_USE_LAPTOP_INSTALLATION_IDENTITY_INVALID' }
            if ([string]$hostVaultIdentity.node_name -cne [string]$request.vaultInstanceName -or [string]$hostVaultIdentity.node_role -cne 'vault' -or [string]$hostVaultIdentity.deployment_id -cne [string]$request.deploymentId -or [string]$hostVaultIdentity.node_id -cne [string]$request.vaultNodeId) { throw 'REAL_USE_LAPTOP_VAULT_IDENTITY_INVALID' }
            $expectedMultipass = Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'
            $multipass = @(Get-Command multipass.exe -All -ErrorAction Stop | Where-Object { $_.Source -ceq $expectedMultipass })
            if ($multipass.Count -ne 1) { throw 'REAL_USE_MULTIPASS_RESOLUTION_INVALID' }
            $mp = $multipass[0].Source
            function Invoke-RealUseMultipass {
                param([Parameter(Mandatory)][string[]]$Arguments,[int]$TimeoutSeconds = 120)
                $effective = [Math]::Max(1,[Math]::Min([int]$request.ownerTimeoutSeconds,$TimeoutSeconds))
                $psi = [Diagnostics.ProcessStartInfo]::new(); $psi.FileName = $mp; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
                if ($psi.PSObject.Properties.Name -contains 'ArgumentList' -and $null -ne $psi.ArgumentList) { foreach ($argument in $Arguments) { [void]$psi.ArgumentList.Add([string]$argument) } }
                else {
                    $quoted = @($Arguments | ForEach-Object { $value=[string]$_; if($value.Length -gt 0 -and $value -notmatch '[\s"]'){$value;return};$builder=[Text.StringBuilder]::new();[void]$builder.Append([char]34);$slashes=0;foreach($character in $value.ToCharArray()){if([int]$character-eq 92){$slashes++;continue};if([int]$character-eq 34){for($i=0;$i-lt($slashes*2+1);$i++){[void]$builder.Append([char]92)};[void]$builder.Append([char]34);$slashes=0;continue};for($i=0;$i-lt$slashes;$i++){[void]$builder.Append([char]92)};$slashes=0;[void]$builder.Append($character)};for($i=0;$i-lt($slashes*2);$i++){[void]$builder.Append([char]92)};[void]$builder.Append([char]34);$builder.ToString() })
                    $psi.Arguments = $quoted -join ' '
                }
                $process = [Diagnostics.Process]::new(); $process.StartInfo = $psi
                try {
                    if (-not $process.Start()) { throw 'REAL_USE_MULTIPASS_START_FAILED' }
                    $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
                    if (-not $process.WaitForExit($effective * 1000)) {
                        try { $process.Kill($true) } catch { $taskkill=Join-Path $env:SystemRoot 'System32\taskkill.exe';if(Test-Path -LiteralPath $taskkill -PathType Leaf){try{& $taskkill '/PID' ([string]$process.Id) '/T' '/F' 2>&1|Out-Null}catch{}} }
                        try { if (-not $process.WaitForExit(5000)) { try { $process.Kill() } catch {}; [void]$process.WaitForExit(5000) } } catch {}
                        throw 'REAL_USE_MULTIPASS_TIMEOUT'
                    }
                    try { [void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5))) } catch {}
                    $out=@();$err=@();if($stdout.Status-eq[Threading.Tasks.TaskStatus]::RanToCompletion){$out=@(([string]$stdout.GetAwaiter().GetResult()-split"`r?`n")|Where-Object{$_.Length-gt 0})};if($stderr.Status-eq[Threading.Tasks.TaskStatus]::RanToCompletion){$err=@(([string]$stderr.GetAwaiter().GetResult()-split"`r?`n")|Where-Object{$_.Length-gt 0})}
                    return [pscustomobject]@{exitCode=[int]$process.ExitCode;stdout=$out;stderr=$err}
                } finally { $process.Dispose() }
            }
            function Invoke-RequiredMultipass([string[]]$Arguments,[int]$Timeout,[string]$Code) { $value=Invoke-RealUseMultipass -Arguments $Arguments -TimeoutSeconds $Timeout;if($value.exitCode-ne 0){throw $Code};return $value }
            function Read-MultipassJson([string]$Name,[string]$Path,[string]$Code) { $value=Invoke-RequiredMultipass @('exec',$Name,'--','sudo','cat',$Path) 60 $Code;try{return (($value.stdout-join"`n")|ConvertFrom-Json -ErrorAction Stop)}catch{throw $Code} }
            function Read-MultipassLine([string[]]$Arguments,[string]$Code) { $value=Invoke-RequiredMultipass $Arguments 60 $Code;if(@($value.stdout).Count-ne 1){throw $Code};return [string]$value.stdout[0] }
            function Test-TailscaleReady([string]$Name) { $value=Invoke-RequiredMultipass @('exec',$Name,'--','tailscale','status','--json','--peers=false') 60 'REAL_USE_TAILSCALE_STATUS_FAILED';try{$status=($value.stdout-join"`n")|ConvertFrom-Json -ErrorAction Stop}catch{throw 'REAL_USE_TAILSCALE_STATUS_INVALID'};return ([string]$status.BackendState-ceq'Running'-and[bool]$status.Self.Online-and@($status.Self.TailscaleIPs|Where-Object{[string]$_-match'^100\.'}).Count-gt 0) }
            $inventoryResult=Invoke-RequiredMultipass @('list','--format','json') 120 'REAL_USE_MULTIPASS_INVENTORY_FAILED';try{$inventory=($inventoryResult.stdout-join"`n")|ConvertFrom-Json -ErrorAction Stop}catch{throw 'REAL_USE_MULTIPASS_INVENTORY_INVALID'}
            $computeRows=@($inventory.list|Where-Object{[string]$_.name-ceq[string]$request.computeInstanceName});$vaultRows=@($inventory.list|Where-Object{[string]$_.name-ceq[string]$request.vaultInstanceName})
            if($computeRows.Count-ne 1-or$vaultRows.Count-ne 1-or[string]$computeRows[0].state-cne'Running'-or[string]$vaultRows[0].state-cne'Running'){throw 'REAL_USE_INSTALLED_GUESTS_NOT_RUNNING'}
            foreach($name in @([string]$request.computeInstanceName,[string]$request.vaultInstanceName)){[void](Invoke-RequiredMultipass @('info',$name) 90 'REAL_USE_INSTALLED_GUEST_NOT_READY')}
            $compute=[string]$request.computeInstanceName;$vault=[string]$request.vaultInstanceName
            $computeConfig=Read-MultipassJson $compute '/etc/devfleet/config.json' 'REAL_USE_COMPUTE_CONFIG_INVALID';$computeIdentity=Read-MultipassJson $compute '/etc/devfleet/node-identity.json' 'REAL_USE_COMPUTE_IDENTITY_INVALID';$vaultIdentity=Read-MultipassJson $vault '/etc/devfleet-vault-identity.json' 'REAL_USE_VAULT_IDENTITY_INVALID'
            if([string]$computeConfig.node_name-cne$compute-or[string]$computeConfig.deployment_id-cne[string]$request.deploymentId-or[string]$computeConfig.node_id-cne[string]$request.nodeId-or[string]$computeConfig.coordinator_node_id-cne[string]$request.primaryNodeId-or[string]$computeConfig.registration_state-cne'joined'-or[string]$computeIdentity.node_name-cne$compute-or[string]$computeIdentity.node_role-cne'surrogate'-or[string]$computeIdentity.deployment_id-cne[string]$request.deploymentId-or[string]$computeIdentity.node_id-cne[string]$request.nodeId-or[string]$computeIdentity.coordinator_node_id-cne[string]$request.primaryNodeId-or[string]$computeIdentity.registration_state-cne'joined'-or[string]$vaultIdentity.node_name-cne$vault-or[string]$vaultIdentity.node_role-cne'vault'-or[string]$vaultIdentity.deployment_id-cne[string]$request.deploymentId-or[string]$vaultIdentity.node_id-cne[string]$request.vaultNodeId){throw 'REAL_USE_INSTALLED_PRODUCT_IDENTITY_MISMATCH'}
            foreach($path in @([string]$computeConfig.workspaces,[string]$computeConfig.quarantine,[string]$computeConfig.runtime_root)){if($path-notmatch'^/[A-Za-z0-9._/-]+$'){throw 'REAL_USE_INSTALLED_PATH_INVALID'}}
            if([string]$computeConfig.workspaces-cne'/home/devrunner/workspaces'-or[string]$computeConfig.quarantine-cne'/home/devrunner/.devfleet-quarantine'-or[string]$computeConfig.runtime_root-cne'/var/lib/devfleet/runtime'){throw 'REAL_USE_INSTALLED_PATH_UNSUPPORTED'}
            [void](Invoke-RequiredMultipass @('exec',$compute,'--','systemctl','is-active','--quiet','devfleet.service') 60 'REAL_USE_SERVICE_INACTIVE')
            [void](Invoke-RequiredMultipass @('exec',$compute,'--','systemctl','is-active','--quiet','devfleet-vault-broker.socket') 60 'REAL_USE_BROKER_INACTIVE')
            [void](Invoke-RequiredMultipass @('exec',$compute,'--','systemctl','is-enabled','--quiet','devfleet-vault-broker.socket') 60 'REAL_USE_BROKER_NOT_ENABLED')
            [void](Invoke-RequiredMultipass @('exec',$vault,'--','systemctl','is-active','--quiet','rest-server.service') 60 'REAL_USE_VAULT_SERVICE_INACTIVE')
            [void](Invoke-RequiredMultipass @('exec',$compute,'--','test','-x','/opt/devfleet/venv/bin/python') 60 'REAL_USE_PYTHON_MISSING')
            $secretStat=Read-MultipassLine @('exec',$compute,'--','sudo','stat','-c','%U:%G:%a:%F','/etc/devfleet/secrets.env') 'REAL_USE_SECRET_FILE_POLICY_INVALID';if($secretStat-cne'root:devfleet-control:640:regular file'){throw 'REAL_USE_SECRET_FILE_POLICY_INVALID'}
            $resticStat=Read-MultipassLine @('exec',$compute,'--','sudo','stat','-c','%U:%G:%a:%F','/etc/devfleet/restic.env') 'REAL_USE_RESTIC_FILE_POLICY_INVALID';if($resticStat-cne'root:devfleet-backup:640:regular file'){throw 'REAL_USE_RESTIC_FILE_POLICY_INVALID'}
            foreach($name in @('devfleet-backup','devfleet-control','devrunner')){[void](Invoke-RequiredMultipass @('exec',$compute,'--','id','-u',$name) 60 'REAL_USE_CREDENTIAL_PRINCIPAL_MISSING')}
            [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','-u','devfleet-backup','test','-r','/etc/devfleet/restic.env') 60 'REAL_USE_BACKUP_CANNOT_READ_RESTIC_CREDENTIAL')
            foreach($name in @('devfleet-control','devrunner')){$probe=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','-u',$name,'test','-r','/etc/devfleet/restic.env') -TimeoutSeconds 60;if($probe.exitCode-eq 0){throw 'REAL_USE_RESTIC_CREDENTIAL_BOUNDARY_INVALID'}}
            [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','test','-d','/home/devrunner/.devfleet') 60 'REAL_USE_DEVRUNNER_CONTROL_ROOT_MISSING')
            $backupRead=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','-u','devfleet-backup','test','-r','/home/devrunner/.devfleet') -TimeoutSeconds 60
            $backupList=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','-u','devfleet-backup','ls','-U','-1','--','/home/devrunner/.devfleet') -TimeoutSeconds 60
            if($backupRead.exitCode-eq 0-or$backupList.exitCode-eq 0){throw 'REAL_USE_BACKUP_CONTROL_ROOT_BOUNDARY_INVALID'}
            $socketStat=Read-MultipassLine @('exec',$compute,'--','sudo','stat','-c','%U:%G:%a:%F','/run/devfleet-vault-broker.sock') 'REAL_USE_BROKER_SOCKET_POLICY_INVALID';if($socketStat-cne'root:devfleet-control:660:socket'){throw 'REAL_USE_BROKER_SOCKET_POLICY_INVALID'}
            $brokerStat=Read-MultipassLine @('exec',$compute,'--','sudo','stat','-c','%U:%G:%a:%F','/usr/local/bin/devfleet-vault-broker') 'REAL_USE_BROKER_BINARY_POLICY_INVALID';if($brokerStat-cne'root:devfleet-backup:750:regular file'){throw 'REAL_USE_BROKER_BINARY_POLICY_INVALID'}
            $repoProbe='import json,re,sys; v=json.load(open("/var/lib/devfleet/backup-status/config.json",encoding="utf-8")); r=str(v.get("repository", "")); sys.exit(0 if re.fullmatch(r"rest:http://100\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[A-Za-z0-9._~%-]+/[A-Za-z0-9._~-]+", r) else 1)'
            [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','-u','devfleet-control','python3','-c',$repoProbe) 60 'REAL_USE_VAULT_ENDPOINT_POLICY_INVALID')
            if(-not(Test-TailscaleReady $compute)-or-not(Test-TailscaleReady $vault)){throw 'REAL_USE_TAILSCALE_PREREQUISITE_INVALID'}
            $unitBytes=[Text.Encoding]::UTF8.GetBytes(([string]$request.runId+'-'+[string]$request.runnerSha256));$unitSha=[Security.Cryptography.SHA256]::Create();try{$unitHash=($unitSha.ComputeHash($unitBytes)|ForEach-Object{$_.ToString('x2')})-join''}finally{$unitSha.Dispose()};$unitHash=$unitHash.Substring(0,12)
            $l2Root="/var/lib/devfleet/e2e-real-use/$($request.runId)";if($l2Root-cnotmatch'\A/var/lib/devfleet/e2e-real-use/(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'){throw 'REAL_USE_L2_ROOT_INVALID'}
            $incoming="/home/ubuntu/.devfleet-real-use-incoming-$unitHash";if($incoming-cnotmatch'\A/home/ubuntu/\.devfleet-real-use-incoming-[0-9a-f]{12}\z'){throw 'REAL_USE_INCOMING_ROOT_INVALID'}
            $incomingRunner="$incoming/Invoke-RealUseAcceptance.py";$l2Runner="$l2Root/Invoke-RealUseAcceptance.py";$inputPath="$l2Root/input.json";$stateDir="$l2Root/state";$statePath="$stateDir/state.json";$preparePath="$stateDir/prepare-report.json";$resumePath="$stateDir/resume-report.json";$cleanupPath="$stateDir/cleanup-report.json"
            $input=$null;$preflight=$null;$stageEvidence=$null;$prepareReport=$null;$prepareExit=$null;$resumeReport=$null;$resumeExit=$null;$restartEvidence=$null;$cleanupReport=$null;$cleanupExit=$null
            $incomingOwned=$false;$l2RootOwned=$false;$l2RootRemoved=$false;$transportResult=$null;$primaryError=$null;$cleanupError=$null;$retainL2Root=$false
            $driverUnits=[Collections.Generic.List[string]]::new()
            $driverWrapper='set -Eeuo pipefail; . /etc/devfleet/secrets.env; : "${DEVFLEET_ADMIN_USER:?}" "${DEVFLEET_ADMIN_PASSWORD:?}"; export DEVFLEET_ADMIN_USER DEVFLEET_ADMIN_PASSWORD; exec /opt/devfleet/venv/bin/python "$@"'
            function Get-DriverUnitState([string]$Unit){
                if($Unit-cnotmatch'\Adevfleet-real-use-[0-9a-f]{12}-(?:prepare|resume|cleanup)\z'){throw 'REAL_USE_DRIVER_UNIT_NAME_INVALID'}
                $probe=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','systemctl','show',$Unit,'--property=LoadState','--property=ActiveState','--property=MainPID') -TimeoutSeconds 30
                if($probe.exitCode-ne 0){throw 'REAL_USE_DRIVER_UNIT_OBSERVATION_FAILED'}
                $fields=@{};foreach($line in @($probe.stdout)){if([string]$line-cnotmatch'\A(LoadState|ActiveState|MainPID)=(.*)\z'-or$fields.ContainsKey($matches[1])){throw 'REAL_USE_DRIVER_UNIT_STATE_INVALID'};$fields[$matches[1]]=$matches[2]}
                if($fields.Count-ne 3-or-not$fields.ContainsKey('LoadState')-or-not$fields.ContainsKey('ActiveState')-or-not$fields.ContainsKey('MainPID')-or[string]$fields.MainPID-cnotmatch'\A[0-9]+\z'){throw 'REAL_USE_DRIVER_UNIT_STATE_INVALID'}
                $load=[string]$fields.LoadState;$active=[string]$fields.ActiveState;$mainPid=[int64]$fields.MainPID
                if($load-ceq'not-found'){if($active-cne'inactive'-or$mainPid-ne 0){throw 'REAL_USE_DRIVER_UNIT_STATE_INVALID'};return [pscustomobject]@{loadState=$load;activeState=$active;mainPid=$mainPid;exists=$false}}
                if($load-cne'loaded'-or$active-notin@('active','activating','reloading','deactivating','inactive','failed','dead')){throw 'REAL_USE_DRIVER_UNIT_STATE_INVALID'}
                return [pscustomobject]@{loadState=$load;activeState=$active;mainPid=$mainPid;exists=$true}
            }
            function Confirm-DriverUnitQuiescent([string]$Unit,[switch]$StopIfRunning){$observation=Get-DriverUnitState $Unit;if($observation.activeState-in@('active','activating','reloading','deactivating')-or$observation.mainPid-ne 0){if(-not$StopIfRunning){throw 'REAL_USE_DRIVER_UNIT_STILL_ACTIVE'};$stop=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','systemctl','stop',$Unit) -TimeoutSeconds 120;if($stop.exitCode-ne 0){throw 'REAL_USE_DRIVER_UNIT_STOP_FAILED'}};$deadline=[datetime]::UtcNow.AddSeconds(60);do{$observation=Get-DriverUnitState $Unit;if((-not$observation.exists-or$observation.activeState-in@('inactive','failed','dead'))-and$observation.mainPid-eq 0){return $true};Start-Sleep -Seconds 2}while([datetime]::UtcNow-lt$deadline);throw 'REAL_USE_DRIVER_UNIT_QUIESCENCE_UNPROVEN'}
            function Invoke-DriverStage([string]$Stage,[string]$Output,[int]$Timeout){$unit="devfleet-real-use-$unitHash-$Stage";$driverUnits.Add($unit)|Out-Null;$runtime=[Math]::Max(1,$Timeout-60);try{$call=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','systemd-run','--wait','--pipe','--collect','--quiet',"--unit=$unit",'-p','Type=exec','-p','User=devfleet-control','-p','Group=devfleet-control','-p','SupplementaryGroups=devrunner','-p',"RuntimeMaxSec=${runtime}s",'-p','TimeoutStopSec=30s','-p','KillMode=control-group','/usr/bin/env','-i','PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','LANG=C.UTF-8','/bin/bash','-c',$driverWrapper,'devfleet-real-use-driver',$l2Runner,'--stage',$Stage,'--input',$inputPath,'--state',$statePath,'--output',$Output) -TimeoutSeconds $Timeout;Confirm-DriverUnitQuiescent $unit|Out-Null;return $call}catch{$stageError=$_.Exception;try{Confirm-DriverUnitQuiescent $unit -StopIfRunning|Out-Null}catch{throw 'REAL_USE_DRIVER_UNIT_QUIESCENCE_FAILED'};throw $stageError}}
            function Read-Report([string]$Path,[string]$Code){$value=Invoke-RequiredMultipass @('exec',$compute,'--','sudo','cat',$Path) 60 $Code;try{return (($value.stdout-join"`n")|ConvertFrom-Json -ErrorAction Stop)}catch{throw $Code}}
            function Test-DriverCleanupProven([AllowNull()][object]$Report){
                if(-not$Report-or[int]$Report.schemaVersion-ne 1-or[string]$Report.contract-cne'devfleet-real-use-acceptance-v1'-or[string]$Report.runId-cne[string]$request.runId-or[string]$Report.phaseId-cne'REAL-USE-ACCEPTANCE'-or[string]$Report.runnerSha256-cne[string]$expectedRunnerHash){return $false}
                if([string]$Report.stage-notin@('prepare','resume','cleanup')-or[string]$Report.cleanup.status-cne'PASS'-or$Report.cleanup.ownedOnly-isnot[bool]-or-not[bool]$Report.cleanup.ownedOnly-or@($Report.cleanup.errors).Count-ne 0-or$null-ne$Report.cleanupFailure){return $false}
                if(([string]$Report.stage-ceq'resume'-and[string]$Report.status-cne'PASS')-or([string]$Report.stage-ceq'cleanup'-and[string]$Report.status-cne'BLOCKED')-or([string]$Report.stage-ceq'prepare'-and[string]$Report.status-cne'BLOCKED')){return $false}
                foreach($resource in @($Report.cleanup.resources)){if([string]::IsNullOrWhiteSpace([string]$resource.kind)-or[string]::IsNullOrWhiteSpace([string]$resource.path)-or[string]$resource.status-notin@('ABSENT','REMOVED')){return $false}}
                return $true
            }
            try{
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','install','-d','-o','root','-g','root','-m','0755','/var/lib/devfleet/e2e-real-use') 60 'REAL_USE_PARENT_ROOT_CREATE_FAILED')
                $parentStat=Read-MultipassLine @('exec',$compute,'--','sudo','stat','-c','%U:%G:%a:%F','/var/lib/devfleet/e2e-real-use') 'REAL_USE_PARENT_ROOT_POLICY_INVALID';if($parentStat-cne'root:root:755:directory'){throw 'REAL_USE_PARENT_ROOT_POLICY_INVALID'}
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','mkdir','--',$l2Root) 60 'REAL_USE_L2_ROOT_COLLISION_OR_CREATE_FAILED');$l2RootOwned=$true
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chown','root:devfleet-control','--',$l2Root) 60 'REAL_USE_OWNED_ROOT_OWNER_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chmod','0750','--',$l2Root) 60 'REAL_USE_OWNED_ROOT_MODE_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','mkdir','--',$incoming) 60 'REAL_USE_INCOMING_COLLISION_OR_CREATE_FAILED');$incomingOwned=$true
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chown','ubuntu:ubuntu','--',$incoming) 60 'REAL_USE_INCOMING_OWNER_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chmod','0700','--',$incoming) 60 'REAL_USE_INCOMING_MODE_FAILED')
                [void](Invoke-RequiredMultipass @('transfer',$runner,"$compute`:$incomingRunner") 300 'REAL_USE_RUNNER_TRANSFER_FAILED')
                $incomingHash=(Read-MultipassLine @('exec',$compute,'--','sha256sum',$incomingRunner) 'REAL_USE_INCOMING_RUNNER_HASH_MISSING').Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant();if($incomingHash-cne$expectedRunnerHash){throw 'REAL_USE_INCOMING_RUNNER_HASH_MISMATCH'}
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','chown','-R','root:root','--',$incoming) 60 'REAL_USE_INCOMING_LOCK_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','install','-T','-o','root','-g','root','-m','0555',$incomingRunner,$l2Runner) 60 'REAL_USE_RUNNER_PROMOTION_FAILED')
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','rm','-rf','--',$incoming) 60 'REAL_USE_INCOMING_CLEANUP_FAILED');$incomingOwned=$false
                $l2RunnerHash=(Read-MultipassLine @('exec',$compute,'--','sudo','sha256sum',$l2Runner) 'REAL_USE_L2_RUNNER_HASH_MISSING').Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant();if($l2RunnerHash-cne$expectedRunnerHash){throw 'REAL_USE_L2_RUNNER_HASH_MISMATCH'}
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','install','-d','-o','devfleet-control','-g','devfleet-control','-m','0700',$stateDir) 60 'REAL_USE_STATE_DIRECTORY_INVALID')
                $input=[ordered]@{schemaVersion=1;runId=[string]$request.runId;deadlineUtc=[string]$request.deadlineUtc;runnerSha256=$expectedRunnerHash;candidate=$request.candidate;execution=[ordered]@{role='Laptop / Surrogate';vmName=[string]$request.vmName;vmId=[string]$request.vmId;computeInstanceName=$compute;vaultInstanceName=$vault;deploymentId=[string]$computeIdentity.deployment_id;nodeId=[string]$computeIdentity.node_id;nodeName=[string]$computeIdentity.node_name;transactionId=[string]$request.transactionId;invocationId=[string]$request.invocationId;surrogateEvidenceSha256=[string]$request.surrogateEvidenceSha256};paths=[ordered]@{workspaces=[string]$computeConfig.workspaces;quarantine=[string]$computeConfig.quarantine;runtimeRoot=[string]$computeConfig.runtime_root};baseUrl=('http://127.0.0.1:{0}'-f[int]$computeConfig.portal_port)}
                $inputJson=$input|ConvertTo-Json -Depth 12 -Compress;$inputBytes=[Text.Encoding]::UTF8.GetBytes($inputJson);$inputBase64=[Convert]::ToBase64String($inputBytes);$sha=[Security.Cryptography.SHA256]::Create();try{$inputHash=($sha.ComputeHash($inputBytes)|ForEach-Object{$_.ToString('x2')})-join''}finally{$sha.Dispose()}
                $writeScript='set -Eeuo pipefail; umask 027; printf %s "$1" | base64 -d > "$2"; chown root:devfleet-control "$2"; chmod 0640 "$2"'
                [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','bash','-c',$writeScript,'devfleet-real-use-input',$inputBase64,$inputPath) 60 'REAL_USE_INPUT_WRITE_FAILED')
                $remoteInputHash=(Read-MultipassLine @('exec',$compute,'--','sudo','sha256sum',$inputPath) 'REAL_USE_INPUT_HASH_MISSING').Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant();if($remoteInputHash-cne$inputHash){throw 'REAL_USE_INPUT_HASH_MISMATCH'}
                $preflight=[ordered]@{laptopInstalled=$true;failoverReady=$true;vaultReady=$true;brokerReady=$true;tailscaleReady=$true;secretFilePolicy=$true;credentialBoundary=$true}
                $stageEvidence=[ordered]@{l1Sha256=$expectedRunnerHash;l2Sha256=$l2RunnerHash;inputSha256=$inputHash;onlyRunnerStaged=$true}
                $remaining=[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)-[int]$request.cleanupReserveSeconds;if($remaining-lt 1){throw 'REAL_USE_OWNER_DEADLINE_EXHAUSTED'};$prepareBudget=[Math]::Min([int]$request.prepareTimeoutSeconds,$remaining);$prepareCall=Invoke-DriverStage 'prepare' $preparePath $prepareBudget;$prepareExit=$prepareCall.exitCode;$prepareReport=Read-Report $preparePath 'REAL_USE_PREPARE_REPORT_INVALID'
                if($prepareCall.exitCode-ne 0-or[string]$prepareReport.status-cne'PREPARED'){
                    $cleanupRemaining=[Math]::Max(1,[Math]::Min([int]$request.cleanupReserveSeconds,[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)));$cleanupCall=Invoke-DriverStage 'cleanup' $cleanupPath $cleanupRemaining;$cleanupExit=$cleanupCall.exitCode;try{$cleanupReport=Read-Report $cleanupPath 'REAL_USE_CLEANUP_REPORT_INVALID'}catch{}
                    $transportResult=[pscustomobject][ordered]@{input=$input;preflight=$preflight;stage=$stageEvidence;prepareReport=$prepareReport;prepareExitCode=$prepareExit;restart=$null;resumeReport=$null;resumeExitCode=$null;cleanupReport=$cleanupReport;cleanupExitCode=$cleanupExit;ownedRootRemoved=$false}
                }else{
                    $before=Read-MultipassLine @('exec',$compute,'--','systemctl','show','devfleet.service','--property=InvocationID','--value') 'REAL_USE_SERVICE_INVOCATION_MISSING';if($before-cnotmatch'^[0-9a-f]{32}$'){throw 'REAL_USE_SERVICE_INVOCATION_INVALID'}
                    [void](Invoke-RequiredMultipass @('exec',$compute,'--','sudo','systemctl','restart','devfleet.service') 120 'REAL_USE_EXACT_SERVICE_RESTART_FAILED')
                    $restartDeadline=[datetime]::UtcNow.AddSeconds(120);$after='';do{$active=Invoke-RealUseMultipass @('exec',$compute,'--','systemctl','is-active','--quiet','devfleet.service') 30;if($active.exitCode-eq 0){try{$after=Read-MultipassLine @('exec',$compute,'--','systemctl','show','devfleet.service','--property=InvocationID','--value') 'REAL_USE_SERVICE_INVOCATION_MISSING'}catch{$after=''};if($after-match'^[0-9a-f]{32}$'-and$after-cne$before){break}};Start-Sleep -Seconds 2}while([datetime]::UtcNow-lt$restartDeadline)
                    if($after-cnotmatch'^[0-9a-f]{32}$'-or$after-ceq$before){throw 'REAL_USE_EXACT_SERVICE_RESTART_UNPROVEN'};$restartEvidence=[ordered]@{unit='devfleet.service';invocationChanged=($after-cne$before);otherUnitsRestarted=$false}
                    $remaining=[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)-[int]$request.cleanupReserveSeconds;if($remaining-lt 1){throw 'REAL_USE_OWNER_DEADLINE_EXHAUSTED'};$resumeCall=Invoke-DriverStage 'resume' $resumePath $remaining;$resumeExit=$resumeCall.exitCode;$resumeReport=Read-Report $resumePath 'REAL_USE_RESUME_REPORT_INVALID'
                    if($resumeCall.exitCode-ne 0-or[string]$resumeReport.status-cne'PASS'){$cleanupRemaining=[Math]::Max(1,[Math]::Min([int]$request.cleanupReserveSeconds,[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)));$cleanupCall=Invoke-DriverStage 'cleanup' $cleanupPath $cleanupRemaining;$cleanupExit=$cleanupCall.exitCode;try{$cleanupReport=Read-Report $cleanupPath 'REAL_USE_CLEANUP_REPORT_INVALID'}catch{}}
                    $transportResult=[pscustomobject][ordered]@{input=$input;preflight=$preflight;stage=$stageEvidence;prepareReport=$prepareReport;prepareExitCode=$prepareExit;restart=$restartEvidence;resumeReport=$resumeReport;resumeExitCode=$resumeExit;cleanupReport=$cleanupReport;cleanupExitCode=$cleanupExit;ownedRootRemoved=$false}
                }
            }catch{
                $primaryError=$_.Exception
                if($input){
                    # An interrupted prepare/resume may have created product
                    # fixtures before its terminal report.  Prove every exact
                    # transient unit quiescent, then use the driver's explicit
                    # cleanup stage against the preserved ownership journal.
                    $recoveryQuiescent=$true
                    try{foreach($unit in $driverUnits){Confirm-DriverUnitQuiescent $unit -StopIfRunning|Out-Null}}catch{$recoveryQuiescent=$false;$cleanupError=$_.Exception}
                    if($recoveryQuiescent-and-not(Test-DriverCleanupProven $prepareReport)-and-not(Test-DriverCleanupProven $resumeReport)-and-not(Test-DriverCleanupProven $cleanupReport)){
                        $cleanupRemaining=[int][Math]::Floor(([datetime]$request.deadlineUtc-[datetime]::UtcNow).TotalSeconds)
                        if($cleanupRemaining-gt 60){
                            $cleanupRemaining=[Math]::Min([int]$request.cleanupReserveSeconds,$cleanupRemaining)
                            try{$cleanupCall=Invoke-DriverStage 'cleanup' $cleanupPath $cleanupRemaining;$cleanupExit=$cleanupCall.exitCode;$cleanupReport=Read-Report $cleanupPath 'REAL_USE_CLEANUP_REPORT_INVALID'}catch{if(-not$cleanupError){$cleanupError=$_.Exception}}
                        }elseif(-not$cleanupError){$cleanupError=[Exception]::new('REAL_USE_CLEANUP_DEADLINE_EXHAUSTED')}
                    }
                    if(-not$prepareReport){try{$prepareReport=Read-Report $preparePath 'REAL_USE_PREPARE_REPORT_SALVAGE_FAILED'}catch{}}
                    if(-not$resumeReport){try{$resumeReport=Read-Report $resumePath 'REAL_USE_RESUME_REPORT_SALVAGE_FAILED'}catch{}}
                    if(-not$cleanupReport){try{$cleanupReport=Read-Report $cleanupPath 'REAL_USE_CLEANUP_REPORT_SALVAGE_FAILED'}catch{}}
                    $transportResult=[pscustomobject][ordered]@{input=$input;preflight=$preflight;stage=$stageEvidence;prepareReport=$prepareReport;prepareExitCode=$prepareExit;restart=$restartEvidence;resumeReport=$resumeReport;resumeExitCode=$resumeExit;cleanupReport=$cleanupReport;cleanupExitCode=$cleanupExit;ownedRootRemoved=$false}
                }
            }finally{
                try{
                    foreach($unit in $driverUnits){Confirm-DriverUnitQuiescent $unit -StopIfRunning|Out-Null}
                    if($incomingOwned){$removeIncoming=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','rm','-rf','--',$incoming) -TimeoutSeconds 120;if($removeIncoming.exitCode-ne 0){throw 'REAL_USE_INCOMING_FINAL_CLEANUP_FAILED'};$incomingGone=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','test','!','-e',$incoming) -TimeoutSeconds 60;if($incomingGone.exitCode-ne 0){throw 'REAL_USE_INCOMING_FINAL_CLEANUP_UNPROVEN'}}
                    $cleanupProven=(Test-DriverCleanupProven $prepareReport)-or(Test-DriverCleanupProven $resumeReport)-or(Test-DriverCleanupProven $cleanupReport)
                    if($l2RootOwned-and($driverUnits.Count-eq 0-or$cleanupProven)){$remove=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','rm','-rf','--',$l2Root) -TimeoutSeconds 120;if($remove.exitCode-ne 0){throw 'REAL_USE_OWNED_ROOT_FINAL_CLEANUP_FAILED'};$rootGone=Invoke-RealUseMultipass -Arguments @('exec',$compute,'--','sudo','test','!','-e',$l2Root) -TimeoutSeconds 60;if($rootGone.exitCode-ne 0){throw 'REAL_USE_OWNED_ROOT_FINAL_CLEANUP_UNPROVEN'};$l2RootRemoved=$true}
                    elseif($l2RootOwned){$retainL2Root=$true;if(-not$cleanupError){$cleanupError=[Exception]::new('REAL_USE_OWNED_ROOT_RETAINED_FOR_RECOVERY')}}
                }catch{if(-not$cleanupError){$cleanupError=$_.Exception};if($l2RootOwned-and-not$l2RootRemoved){$retainL2Root=$true}}
            }
            function Get-FixedTransportCode([Exception]$ErrorValue,[string]$Fallback){if(-not$ErrorValue){return''};$match=[regex]::Match([string]$ErrorValue.Message,'REAL_USE_[A-Z0-9_]+');if($match.Success){return$match.Value};return$Fallback}
            if($transportResult){
                $transportResult.ownedRootRemoved=[bool]$l2RootRemoved
                if($primaryError){$transportResult|Add-Member -NotePropertyName transportError -NotePropertyValue (Get-FixedTransportCode $primaryError 'REAL_USE_TRANSPORT_FAILED') -Force}
                if($cleanupError){$transportResult|Add-Member -NotePropertyName transportCleanupError -NotePropertyValue (Get-FixedTransportCode $cleanupError 'REAL_USE_TRANSPORT_CLEANUP_BLOCKED') -Force}
                return $transportResult
            }
            if($primaryError){throw (Get-FixedTransportCode $primaryError 'REAL_USE_TRANSPORT_FAILED')}
            if($cleanupError){throw (Get-FixedTransportCode $cleanupError 'REAL_USE_TRANSPORT_CLEANUP_BLOCKED')}
            return $transportResult
        } -ArgumentList $remoteRunner,[string]$Request.runnerSha256,$Request
        if (-not $result) { throw 'REAL_USE_TRANSPORT_RETURNED_NO_RESULT' }
    } catch {
        $outerError = $_.Exception
    } finally {
        if ($session) {
            try {
                if($l1RootOwned){
                    Invoke-Command -Session $session -ScriptBlock {
                        param($path)
                        if($path -notlike 'C:\Users\Public\DevFleet-E2E\*\REAL-USE-ACCEPTANCE'){throw 'REAL_USE_L1_ROOT_INVALID'}
                        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop}
                        if(Test-Path -LiteralPath $path){throw 'REAL_USE_L1_ROOT_CLEANUP_FAILED'}
                    } -ArgumentList $remoteRoot
                    $l1RootRemoved = $true
                }
            } catch {
                $l1CleanupError = $_.Exception
            } finally {
                Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue
            }
        }
    }
    $fixedCode = {
        param([AllowNull()][Exception]$ErrorValue,[string]$Fallback)
        if(-not$ErrorValue){return ''}
        $match=[regex]::Match([string]$ErrorValue.Message,'REAL_USE_[A-Z0-9_]+')
        if($match.Success){return $match.Value}
        return $Fallback
    }
    if($result){
        if($result.stage){
            $result.stage | Add-Member -NotePropertyName l1Path -NotePropertyValue $remoteRunner -Force
            $result.stage | Add-Member -NotePropertyName ownedRootsRemoved -NotePropertyValue ([bool]($l1RootRemoved -and [bool]$result.ownedRootRemoved)) -Force
        }
        if($outerError -and -not $result.PSObject.Properties['transportError']){$result|Add-Member -NotePropertyName transportError -NotePropertyValue (&$fixedCode $outerError 'REAL_USE_L1_TRANSPORT_FAILED') -Force}
        if($l1CleanupError){$result|Add-Member -NotePropertyName transportCleanupError -NotePropertyValue (&$fixedCode $l1CleanupError 'REAL_USE_L1_ROOT_CLEANUP_FAILED') -Force}
        return $result
    }
    if($outerError){throw (&$fixedCode $outerError 'REAL_USE_L1_TRANSPORT_FAILED')}
    if($l1CleanupError){throw (&$fixedCode $l1CleanupError 'REAL_USE_L1_ROOT_CLEANUP_FAILED')}
    throw 'REAL_USE_TRANSPORT_RETURNED_NO_RESULT'
}

function Invoke-RealUseAcceptancePhase {
    param(
        [Parameter(Mandatory)][object]$Context,
        [scriptblock]$TransportProvider
    )
    $binding = Get-RealUseAcceptanceSurrogateBinding -Context $Context
    $candidateItem = Get-Item -LiteralPath ([string]$Context.candidate.candidate.path) -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $candidateItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$binding.candidate.exeSha256 -or [int64]$candidateItem.Length -ne [int64]$Context.candidate.candidate.bytes) { throw 'REAL-USE-ACCEPTANCE exact candidate changed before execution.' }
    $runnerPath = Join-Path ([string]$Context.workspaceRoot) 'automation\release-e2e\modules\executors\Invoke-RealUseAcceptance.py'
    if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) { throw 'REAL-USE-ACCEPTANCE runner is missing.' }
    $runnerHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $timeoutSeconds = $script:RealUseAcceptanceOwnerTimeoutSeconds
    if ($Context.config -and $Context.config.PSObject.Properties['RealUseAcceptance'] -and $Context.config.RealUseAcceptance.PSObject.Properties['TimeoutSeconds']) { $timeoutSeconds = [int]$Context.config.RealUseAcceptance.TimeoutSeconds }
    if ($timeoutSeconds -lt 27000 -or $timeoutSeconds -gt $script:RealUseAcceptanceOwnerTimeoutSeconds) { throw 'REAL-USE-ACCEPTANCE timeout policy is outside the bounded supported range.' }
    $deadlineUtc = [datetime]::UtcNow.AddSeconds($timeoutSeconds).ToString('o')
    $request = [pscustomobject][ordered]@{
        runId=$binding.runId;phaseId=$script:RealUseAcceptancePhase;vmName=$binding.vmName;vmId=$binding.vmId;candidate=$binding.candidate
        transactionId=$binding.transactionId;invocationId=$binding.invocationId;computeInstanceName=$binding.computeInstanceName;vaultInstanceName=$binding.vaultInstanceName
        deploymentId=$binding.deploymentId;nodeId=$binding.nodeId;primaryNodeId=$binding.primaryNodeId;vaultNodeId=$binding.vaultNodeId
        clusterJoinEvidencePath=$binding.clusterJoinEvidencePath;clusterJoinEvidenceSha256=$binding.clusterJoinEvidenceSha256;primaryPairingEvidencePath=$binding.primaryPairingEvidencePath;primaryPairingEvidenceSha256=$binding.primaryPairingEvidenceSha256
        surrogateEvidenceSha256=$binding.surrogateEvidenceSha256;runnerPath=$runnerPath;runnerSha256=$runnerHash;deadlineUtc=$deadlineUtc
        ownerTimeoutSeconds=$timeoutSeconds;prepareTimeoutSeconds=$script:RealUseAcceptancePrepareTimeoutSeconds;cleanupReserveSeconds=$script:RealUseAcceptanceCleanupReserveSeconds
    }
    $transport = if ($TransportProvider) { & $TransportProvider $request } else { Invoke-RealUseAcceptanceTransport -Request $request }
    if (-not $transport -or -not $transport.input) { throw 'REAL-USE-ACCEPTANCE transport returned no request-bound input evidence.' }
    Assert-RealUseAcceptanceInput -Input $transport.input -Request $request | Out-Null
    $transportError = if ($transport.PSObject.Properties['transportError']) { [string]$transport.transportError } else { '' }
    $transportCleanupError = if ($transport.PSObject.Properties['transportCleanupError']) { [string]$transport.transportCleanupError } else { '' }
    foreach ($code in @($transportError,$transportCleanupError) | Where-Object { $_ }) { if ($code -cnotmatch '^REAL_USE_[A-Z0-9_]+$') { throw 'REAL-USE-ACCEPTANCE transport returned an unsafe failure classification.' } }
    $cleanupEvidence = $null
    if (-not $transport.prepareReport) {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        throw "REAL-USE-ACCEPTANCE transport returned no prepare report${cleanupSuffix}."
    }
    $preparePath = Join-Path ([string]$Context.runDir) 'real-use-acceptance-prepare.json'
    $prepareEvidence = Write-RealUseAcceptanceDriverEvidence -Report $transport.prepareReport -AcceptanceInput $transport.input -ExpectedStage prepare -AllowedStatus @('PREPARED','BLOCKED') -Path $preparePath -AllowInitializationEnvelope
    $prepareHash = [string]$prepareEvidence.sha256
    if ([int]$transport.prepareExitCode -ne 0 -or [string]$transport.prepareReport.status -cne 'PREPARED') {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        $transportSuffix = if ($transportError) { "; transport=$transportError" } else { '' }
        if ($transportCleanupError) { $transportSuffix += "; transportCleanup=$transportCleanupError" }
        throw "REAL-USE-ACCEPTANCE prepare did not reach its restart boundary; evidence=$preparePath; sha256=$prepareHash${transportSuffix}${cleanupSuffix}."
    }
    if (-not $transport.restart -or [string]$transport.restart.unit -cne 'devfleet.service' -or -not [bool]$transport.restart.invocationChanged -or [bool]$transport.restart.otherUnitsRestarted) {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        $transportSuffix = if ($transportError) { "; transport=$transportError" } else { '' }
        if ($transportCleanupError) { $transportSuffix += "; transportCleanup=$transportCleanupError" }
        throw "REAL-USE-ACCEPTANCE exact service restart was not proven; prepareEvidence=$preparePath; prepareSha256=$prepareHash${transportSuffix}${cleanupSuffix}."
    }
    if (-not $transport.resumeReport) {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        throw "REAL-USE-ACCEPTANCE resume returned no report${cleanupSuffix}."
    }
    $reportPath = Join-Path ([string]$Context.runDir) 'real-use-acceptance-report.json'
    $reportEvidence = Write-RealUseAcceptanceDriverEvidence -Report $transport.resumeReport -AcceptanceInput $transport.input -ExpectedStage resume -AllowedStatus @('PASS','BLOCKED') -Path $reportPath -AllowInitializationEnvelope
    $reportHash = [string]$reportEvidence.sha256
    if ([int]$transport.resumeExitCode -ne 0 -or [string]$transport.resumeReport.status -cne 'PASS' -or $transportError) {
        $cleanupEvidence = Write-OptionalRealUseAcceptanceCleanupEvidence -Report $transport.cleanupReport -AcceptanceInput $transport.input -RunDir ([string]$Context.runDir)
        $cleanupSuffix = if ($cleanupEvidence -and $cleanupEvidence.sha256) { "; cleanupEvidence=$($cleanupEvidence.path); cleanupSha256=$($cleanupEvidence.sha256)" } elseif ($cleanupEvidence) { '; cleanupEvidence=REJECTED' } else { '' }
        $transportSuffix = if ($transportError) { "; transport=$transportError" } else { '' }
        if ($transportCleanupError) { $transportSuffix += "; transportCleanup=$transportCleanupError" }
        throw "REAL-USE-ACCEPTANCE resume did not reach PASS; evidence=$reportPath; sha256=$reportHash${transportSuffix}${cleanupSuffix}."
    }
    Assert-RealUseAcceptanceReport -Report $transport.resumeReport -Input $transport.input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass | Out-Null
    foreach ($field in @('laptopInstalled','failoverReady','vaultReady','brokerReady','tailscaleReady','secretFilePolicy','credentialBoundary')) { if (-not [bool]$transport.preflight.$field) { throw 'REAL-USE-ACCEPTANCE installed prerequisite evidence is incomplete.' } }
    if (-not [bool]$transport.stage.onlyRunnerStaged -or [string]$transport.stage.l1Sha256 -cne $runnerHash -or [string]$transport.stage.l2Sha256 -cne $runnerHash -or [string]$transport.stage.inputSha256 -cnotmatch '^[0-9a-f]{64}$' -or -not [bool]$transport.stage.ownedRootsRemoved -or -not [bool]$transport.ownedRootRemoved) { throw 'REAL-USE-ACCEPTANCE runner transport or owned-root cleanup is incomplete.' }
    $bindingPath = Join-Path ([string]$Context.runDir) 'real-use-acceptance-binding.json'
    $bindingEvidence = [ordered]@{schemaVersion=1;contract=$script:RealUseAcceptanceContract;runId=$binding.runId;phaseId=$script:RealUseAcceptancePhase;precedingPhase='SURROGATE-DISPOSABLE';candidate=$transport.input.candidate;execution=$transport.input.execution;deadlineUtc=$deadlineUtc;runner=[ordered]@{path=$runnerPath;sha256=$runnerHash};surrogate=[ordered]@{evidencePath=$binding.surrogateEvidencePath;evidenceSha256=$binding.surrogateEvidenceSha256;phaseRecordsPath=$binding.phaseRecordsPath;phaseRecordsSha256=$binding.phaseRecordsSha256};clusterJoin=[ordered]@{evidencePath=$binding.clusterJoinEvidencePath;evidenceSha256=$binding.clusterJoinEvidenceSha256;primaryPairingEvidencePath=$binding.primaryPairingEvidencePath;primaryPairingEvidenceSha256=$binding.primaryPairingEvidenceSha256};installedPaths=$transport.input.paths;baseUrl=$transport.input.baseUrl}
    Write-EvidenceJson -Path $bindingPath -Value $bindingEvidence
    $bindingHash = (Get-FileHash -LiteralPath $bindingPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $summaryPath = Join-Path ([string]$Context.runDir) 'real-use-acceptance-evidence.json'
    $summary = [ordered]@{schemaVersion=1;contract='devfleet-real-use-acceptance-evidence-v1';status='PASS';runId=$binding.runId;phaseId=$script:RealUseAcceptancePhase;candidate=$transport.input.candidate;execution=$transport.input.execution;preflight=$transport.preflight;transport=$transport.stage;restart=$transport.restart;journeys=@($transport.resumeReport.journeys|ForEach-Object{[ordered]@{id=[string]$_.id;status=[string]$_.status}});cleanup=[ordered]@{status=[string]$transport.resumeReport.cleanup.status;ownedOnly=[bool]$transport.resumeReport.cleanup.ownedOnly;vaultSnapshots=[string]$transport.resumeReport.cleanup.vaultSnapshots};evidence=[ordered]@{binding=[ordered]@{path=$bindingPath;sha256=$bindingHash};prepare=[ordered]@{path=$preparePath;sha256=$prepareHash};report=[ordered]@{path=$reportPath;sha256=$reportHash}};credentialsStoredInEvidence=$false;internalPromotionAllowed=$false}
    Write-EvidenceJson -Path $summaryPath -Value $summary
    $summaryHash = (Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    return [ordered]@{status='REAL E2E PASS';phase=$script:RealUseAcceptancePhase;contract='devfleet-real-use-acceptance-phase-v1';candidate=$transport.input.candidate;binding=$bindingEvidence;report=$transport.resumeReport;preflight=$transport.preflight;transport=$transport.stage;restart=$transport.restart;evidence=[ordered]@{bindingPath=$bindingPath;bindingSha256=$bindingHash;preparePath=$preparePath;prepareSha256=$prepareHash;reportPath=$reportPath;reportSha256=$reportHash;summaryPath=$summaryPath;summarySha256=$summaryHash};credentialsStoredInEvidence=$false;internalPromotionAllowed=$false}
}

function Assert-RealUseAcceptancePhaseEvidence {
    param([Parameter(Mandatory)][object]$PhaseResult, [Parameter(Mandatory)][object]$Context)
    $phaseFields = @('status','phase','contract','candidate','binding','report','preflight','transport','restart','evidence','credentialsStoredInEvidence','internalPromotionAllowed')
    Assert-RealUseAcceptanceKeys -Value $PhaseResult -Allowed $phaseFields -Required $phaseFields -Label 'REAL-USE-ACCEPTANCE phase result' | Out-Null
    if ([string]$PhaseResult.status -cne 'REAL E2E PASS' -or [string]$PhaseResult.phase -cne $script:RealUseAcceptancePhase -or [string]$PhaseResult.contract -cne 'devfleet-real-use-acceptance-phase-v1' -or $PhaseResult.credentialsStoredInEvidence -isnot [bool] -or [bool]$PhaseResult.credentialsStoredInEvidence -or $PhaseResult.internalPromotionAllowed -isnot [bool] -or [bool]$PhaseResult.internalPromotionAllowed) { throw 'FullRelease rejected incomplete REAL-USE-ACCEPTANCE phase evidence.' }

    $bindingFields = @('schemaVersion','contract','runId','phaseId','precedingPhase','candidate','execution','deadlineUtc','runner','surrogate','clusterJoin','installedPaths','baseUrl')
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.binding -Allowed $bindingFields -Required $bindingFields -Label 'REAL-USE-ACCEPTANCE phase binding' | Out-Null
    if ([int]$PhaseResult.binding.schemaVersion -ne 1 -or [string]$PhaseResult.binding.contract -cne $script:RealUseAcceptanceContract -or [string]$PhaseResult.binding.runId -cne [string]$Context.runId -or [string]$PhaseResult.binding.phaseId -cne $script:RealUseAcceptancePhase -or [string]$PhaseResult.binding.precedingPhase -cne 'SURROGATE-DISPOSABLE') { throw 'FullRelease rejected unbound REAL-USE-ACCEPTANCE phase evidence.' }
    $contextCandidate = [ordered]@{
        repositoryHead=[string]$Context.candidate.repositoryHead;candidateCommit=[string]$Context.candidate.gitCommit
        shippingInputIdentity=[string]$Context.candidate.shippingInputIdentity;releaseFingerprintId=[string]$Context.candidate.releaseFingerprintId
        toolingFingerprintId=[string]$Context.candidate.toolingFingerprintId;exeSha256=[string]$Context.candidate.candidate.sha256;tarSha256=[string]$Context.candidate.tar.sha256
    }
    Assert-RealUseAcceptanceCandidate -Actual $PhaseResult.candidate -Expected $contextCandidate -Label 'REAL-USE-ACCEPTANCE phase candidate' | Out-Null
    Assert-RealUseAcceptanceCandidate -Actual $PhaseResult.binding.candidate -Expected $contextCandidate -Label 'REAL-USE-ACCEPTANCE phase binding candidate' | Out-Null
    Assert-RealUseAcceptanceExecution -Actual $PhaseResult.binding.execution -Expected $PhaseResult.binding.execution -Label 'REAL-USE-ACCEPTANCE phase binding execution' | Out-Null
    if ([string]$PhaseResult.binding.execution.vmName -cne [string]$Context.vmName -or [string]$PhaseResult.binding.execution.vmId -cne [string]$Context.vmId) { throw 'FullRelease rejected REAL-USE-ACCEPTANCE VM identity drift.' }

    Assert-RealUseAcceptanceKeys -Value $PhaseResult.binding.runner -Allowed @('path','sha256') -Required @('path','sha256') -Label 'REAL-USE-ACCEPTANCE runner binding' | Out-Null
    $expectedRunnerPath = [IO.Path]::GetFullPath((Join-Path ([string]$Context.workspaceRoot) 'automation\release-e2e\modules\executors\Invoke-RealUseAcceptance.py'))
    $boundRunnerPath = [IO.Path]::GetFullPath([string]$PhaseResult.binding.runner.path)
    if (-not $boundRunnerPath.Equals($expectedRunnerPath,[StringComparison]::OrdinalIgnoreCase) -or [string]$PhaseResult.binding.runner.sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $boundRunnerPath -PathType Leaf) -or (Get-FileHash -LiteralPath $boundRunnerPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$PhaseResult.binding.runner.sha256) { throw 'FullRelease rejected changed REAL-USE-ACCEPTANCE runner evidence.' }

    Assert-RealUseAcceptanceKeys -Value $PhaseResult.binding.surrogate -Allowed @('evidencePath','evidenceSha256','phaseRecordsPath','phaseRecordsSha256') -Required @('evidencePath','evidenceSha256','phaseRecordsPath','phaseRecordsSha256') -Label 'REAL-USE-ACCEPTANCE Surrogate binding' | Out-Null
    $surrogatePath = Assert-RealUseAcceptanceContainedPath -Root ([string]$Context.runDir) -Path ([string]$PhaseResult.binding.surrogate.evidencePath) -Label 'REAL-USE-ACCEPTANCE Surrogate authority'
    $recordsPath = Assert-RealUseAcceptanceCanonicalEvidencePath -Root ([string]$Context.runDir) -Path ([string]$PhaseResult.binding.surrogate.phaseRecordsPath) -LeafName 'fullrelease-phase-records.json'
    if (-not (Test-Path -LiteralPath $surrogatePath -PathType Leaf) -or (Get-FileHash -LiteralPath $surrogatePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$PhaseResult.binding.surrogate.evidenceSha256 -or [string]$PhaseResult.binding.surrogate.phaseRecordsSha256 -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $recordsPath -PathType Leaf)) { throw 'FullRelease rejected changed REAL-USE-ACCEPTANCE Surrogate authority.' }
    $surrogateAuthority = Get-Content -LiteralPath $surrogatePath -Raw | ConvertFrom-Json -ErrorAction Stop
    if ([string]$surrogateAuthority.status -cne 'REAL E2E PASS' -or [string]$surrogateAuthority.contract -cne 'product-lifecycle-completion-authority' -or [string]$surrogateAuthority.role -cne 'Laptop / Surrogate' -or -not [bool]$surrogateAuthority.completionVerified -or -not [bool]$surrogateAuthority.authenticatedHealth -or [string]$surrogateAuthority.transactionId -cne [string]$PhaseResult.binding.execution.transactionId -or [string]$surrogateAuthority.invocationId -cne [string]$PhaseResult.binding.execution.invocationId -or [string]$surrogateAuthority.payloadSha256 -cne [string]$contextCandidate.tarSha256) { throw 'FullRelease rejected divergent REAL-USE-ACCEPTANCE Surrogate authority.' }

    Assert-RealUseAcceptanceKeys -Value $PhaseResult.binding.clusterJoin -Allowed @('evidencePath','evidenceSha256','primaryPairingEvidencePath','primaryPairingEvidenceSha256') -Required @('evidencePath','evidenceSha256','primaryPairingEvidencePath','primaryPairingEvidenceSha256') -Label 'REAL-USE-ACCEPTANCE cluster-join binding' | Out-Null
    $joinBinding=Assert-RealUseAcceptanceClusterJoinEvidence -Context $Context -Candidate ([pscustomobject]$contextCandidate) -SurrogateProduct $surrogateAuthority
    if([string]$PhaseResult.binding.clusterJoin.evidencePath-cne[string]$joinBinding.evidencePath-or[string]$PhaseResult.binding.clusterJoin.evidenceSha256-cne[string]$joinBinding.evidenceSha256-or[string]$PhaseResult.binding.clusterJoin.primaryPairingEvidencePath-cne[string]$joinBinding.capturePath-or[string]$PhaseResult.binding.clusterJoin.primaryPairingEvidenceSha256-cne[string]$joinBinding.captureSha256-or[string]$PhaseResult.binding.execution.deploymentId-cne[string]$joinBinding.evidence.compute.deploymentId-or[string]$PhaseResult.binding.execution.nodeId-cne[string]$joinBinding.evidence.compute.nodeId){throw 'FullRelease rejected divergent REAL-USE-ACCEPTANCE cluster-join binding.'}

    $input = [pscustomobject][ordered]@{schemaVersion=1;runId=[string]$PhaseResult.binding.runId;deadlineUtc=[string]$PhaseResult.binding.deadlineUtc;runnerSha256=[string]$PhaseResult.binding.runner.sha256;candidate=$PhaseResult.binding.candidate;execution=$PhaseResult.binding.execution;paths=$PhaseResult.binding.installedPaths;baseUrl=[string]$PhaseResult.binding.baseUrl}
    $inputRequest = [pscustomobject][ordered]@{runId=[string]$Context.runId;deadlineUtc=[string]$PhaseResult.binding.deadlineUtc;runnerSha256=[string]$PhaseResult.binding.runner.sha256;candidate=$contextCandidate;vmName=[string]$Context.vmName;vmId=[string]$Context.vmId;computeInstanceName=[string]$PhaseResult.binding.execution.computeInstanceName;vaultInstanceName=[string]$PhaseResult.binding.execution.vaultInstanceName;deploymentId=[string]$joinBinding.evidence.compute.deploymentId;nodeId=[string]$joinBinding.evidence.compute.nodeId;transactionId=[string]$PhaseResult.binding.execution.transactionId;invocationId=[string]$PhaseResult.binding.execution.invocationId;surrogateEvidenceSha256=[string]$PhaseResult.binding.surrogate.evidenceSha256}
    Assert-RealUseAcceptanceInput -Input $input -Request $inputRequest | Out-Null
    Assert-RealUseAcceptanceReport -Report $PhaseResult.report -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass | Out-Null
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.preflight -Allowed @('laptopInstalled','failoverReady','vaultReady','brokerReady','tailscaleReady','secretFilePolicy','credentialBoundary') -Required @('laptopInstalled','failoverReady','vaultReady','brokerReady','tailscaleReady','secretFilePolicy','credentialBoundary') -Label 'REAL-USE-ACCEPTANCE preflight evidence' | Out-Null
    foreach ($field in @('laptopInstalled','failoverReady','vaultReady','brokerReady','tailscaleReady','secretFilePolicy','credentialBoundary')) { if ($PhaseResult.preflight.$field -isnot [bool] -or -not [bool]$PhaseResult.preflight.$field) { throw 'FullRelease rejected incomplete REAL-USE-ACCEPTANCE prerequisite evidence.' } }
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.transport -Allowed @('l1Sha256','l2Sha256','inputSha256','onlyRunnerStaged','l1Path','ownedRootsRemoved') -Required @('l1Sha256','l2Sha256','inputSha256','onlyRunnerStaged','l1Path','ownedRootsRemoved') -Label 'REAL-USE-ACCEPTANCE transport evidence' | Out-Null
    if ([string]$PhaseResult.transport.l1Sha256 -cne [string]$PhaseResult.binding.runner.sha256 -or [string]$PhaseResult.transport.l2Sha256 -cne [string]$PhaseResult.binding.runner.sha256 -or [string]$PhaseResult.transport.inputSha256 -cnotmatch '^[0-9a-f]{64}$' -or $PhaseResult.transport.onlyRunnerStaged -isnot [bool] -or -not [bool]$PhaseResult.transport.onlyRunnerStaged -or $PhaseResult.transport.ownedRootsRemoved -isnot [bool] -or -not [bool]$PhaseResult.transport.ownedRootsRemoved -or [string]$PhaseResult.transport.l1Path -notlike 'C:\Users\Public\DevFleet-E2E\*\REAL-USE-ACCEPTANCE\Invoke-RealUseAcceptance.py') { throw 'FullRelease rejected incomplete REAL-USE-ACCEPTANCE transport evidence.' }
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.restart -Allowed @('unit','invocationChanged','otherUnitsRestarted') -Required @('unit','invocationChanged','otherUnitsRestarted') -Label 'REAL-USE-ACCEPTANCE restart evidence' | Out-Null
    if ([string]$PhaseResult.restart.unit -cne 'devfleet.service' -or $PhaseResult.restart.invocationChanged -isnot [bool] -or -not [bool]$PhaseResult.restart.invocationChanged -or $PhaseResult.restart.otherUnitsRestarted -isnot [bool] -or [bool]$PhaseResult.restart.otherUnitsRestarted) { throw 'FullRelease rejected substituted REAL-USE-ACCEPTANCE restart evidence.' }

    $evidenceFields = @('bindingPath','bindingSha256','preparePath','prepareSha256','reportPath','reportSha256','summaryPath','summarySha256')
    Assert-RealUseAcceptanceKeys -Value $PhaseResult.evidence -Allowed $evidenceFields -Required $evidenceFields -Label 'REAL-USE-ACCEPTANCE evidence index' | Out-Null
    $leafNames = [ordered]@{binding='real-use-acceptance-binding.json';prepare='real-use-acceptance-prepare.json';report='real-use-acceptance-report.json';summary='real-use-acceptance-evidence.json'}
    $resolved = [ordered]@{}
    foreach ($name in $leafNames.Keys) {
        $pathName="${name}Path";$hashName="${name}Sha256";$path=Assert-RealUseAcceptanceCanonicalEvidencePath -Root ([string]$Context.runDir) -Path ([string]$PhaseResult.evidence.$pathName) -LeafName ([string]$leafNames[$name])
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$PhaseResult.evidence.$hashName) { throw "FullRelease rejected changed REAL-USE-ACCEPTANCE $name evidence." }
        $resolved[$name] = $path
    }
    $durableBinding = Get-Content -LiteralPath $resolved.binding -Raw | ConvertFrom-Json -ErrorAction Stop
    if (-not (Test-RealUseAcceptanceJsonEqual $durableBinding $PhaseResult.binding)) { throw 'FullRelease rejected divergent durable REAL-USE-ACCEPTANCE binding evidence.' }
    $durablePrepare = Get-Content -LiteralPath $resolved.prepare -Raw | ConvertFrom-Json -ErrorAction Stop
    Assert-RealUseAcceptanceReport -Report $durablePrepare -Input $input -ExpectedStage prepare -AllowedStatus @('PREPARED') | Out-Null
    $durableReport = Get-Content -LiteralPath $resolved.report -Raw | ConvertFrom-Json -ErrorAction Stop
    Assert-RealUseAcceptanceReport -Report $durableReport -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass | Out-Null
    if (-not (Test-RealUseAcceptanceJsonEqual $durableReport $PhaseResult.report)) { throw 'FullRelease rejected divergent durable REAL-USE-ACCEPTANCE report evidence.' }

    $durableSummary = Get-Content -LiteralPath $resolved.summary -Raw | ConvertFrom-Json -ErrorAction Stop
    $summaryFields = @('schemaVersion','contract','status','runId','phaseId','candidate','execution','preflight','transport','restart','journeys','cleanup','evidence','credentialsStoredInEvidence','internalPromotionAllowed')
    Assert-RealUseAcceptanceKeys -Value $durableSummary -Allowed $summaryFields -Required $summaryFields -Label 'REAL-USE-ACCEPTANCE durable summary' | Out-Null
    if ([int]$durableSummary.schemaVersion -ne 1 -or [string]$durableSummary.contract -cne 'devfleet-real-use-acceptance-evidence-v1' -or [string]$durableSummary.status -cne 'PASS' -or [string]$durableSummary.runId -cne [string]$Context.runId -or [string]$durableSummary.phaseId -cne $script:RealUseAcceptancePhase -or $durableSummary.credentialsStoredInEvidence -isnot [bool] -or [bool]$durableSummary.credentialsStoredInEvidence -or $durableSummary.internalPromotionAllowed -isnot [bool] -or [bool]$durableSummary.internalPromotionAllowed) { throw 'FullRelease rejected incomplete durable REAL-USE-ACCEPTANCE summary evidence.' }
    Assert-RealUseAcceptanceCandidate -Actual $durableSummary.candidate -Expected $contextCandidate -Label 'REAL-USE-ACCEPTANCE summary candidate' | Out-Null
    Assert-RealUseAcceptanceExecution -Actual $durableSummary.execution -Expected $PhaseResult.binding.execution -Label 'REAL-USE-ACCEPTANCE summary execution' | Out-Null
    if (-not (Test-RealUseAcceptanceJsonEqual $durableSummary.preflight $PhaseResult.preflight) -or -not (Test-RealUseAcceptanceJsonEqual $durableSummary.transport $PhaseResult.transport) -or -not (Test-RealUseAcceptanceJsonEqual $durableSummary.restart $PhaseResult.restart)) { throw 'FullRelease rejected divergent durable REAL-USE-ACCEPTANCE execution evidence.' }
    $summaryJourneys = @($durableSummary.journeys)
    if ($summaryJourneys.Count -ne 5 -or @('U01','U02','U03','U04','U05' | Where-Object { $id=$_; @($summaryJourneys | Where-Object { [string]$_.id -ceq $id -and [string]$_.status -ceq 'PASS' }).Count -ne 1 }).Count) { throw 'FullRelease rejected incomplete durable REAL-USE-ACCEPTANCE journey summary.' }
    Assert-RealUseAcceptanceKeys -Value $durableSummary.cleanup -Allowed @('status','ownedOnly','vaultSnapshots') -Required @('status','ownedOnly','vaultSnapshots') -Label 'REAL-USE-ACCEPTANCE summary cleanup' | Out-Null
    if ([string]$durableSummary.cleanup.status -cne 'PASS' -or $durableSummary.cleanup.ownedOnly -isnot [bool] -or -not [bool]$durableSummary.cleanup.ownedOnly -or [string]$durableSummary.cleanup.vaultSnapshots -cne 'RETAINED_APPEND_ONLY_IN_DISPOSABLE_VAULT') { throw 'FullRelease rejected incomplete durable REAL-USE-ACCEPTANCE cleanup summary.' }
    Assert-RealUseAcceptanceKeys -Value $durableSummary.evidence -Allowed @('binding','prepare','report') -Required @('binding','prepare','report') -Label 'REAL-USE-ACCEPTANCE summary evidence links' | Out-Null
    foreach ($name in @('binding','prepare','report')) {
        Assert-RealUseAcceptanceKeys -Value $durableSummary.evidence.$name -Allowed @('path','sha256') -Required @('path','sha256') -Label "REAL-USE-ACCEPTANCE summary $name link" | Out-Null
        $pathName="${name}Path";$hashName="${name}Sha256"
        if ([string]$durableSummary.evidence.$name.path -cne [string]$PhaseResult.evidence.$pathName -or [string]$durableSummary.evidence.$name.sha256 -cne [string]$PhaseResult.evidence.$hashName) { throw "FullRelease rejected divergent REAL-USE-ACCEPTANCE summary $name link." }
    }
    return $true
}

Export-ModuleMember -Function New-RealUseAcceptancePrimaryPairingCapture,Complete-RealUseAcceptanceClusterJoin,Remove-RealUseAcceptancePrivateState,Get-RealUseAcceptanceSurrogateBinding,Assert-RealUseAcceptanceInput,Assert-RealUseAcceptanceReport,Invoke-RealUseAcceptancePhase,Assert-RealUseAcceptancePhaseEvidence
