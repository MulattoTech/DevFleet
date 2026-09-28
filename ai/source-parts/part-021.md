# DevFleet source part 021

Full-source UTF-8 byte interval [930000, 976500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 0d276e97a9ac6aa69c0b2a0ecd911088dbe972e6c02926fc1604150d5cf6efc2

<!-- BEGIN SOURCE SLICE -->
ew-RealUseAcceptancePassphrase
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
        Assert-RealUseAcceptanceKeys -Value $resource -Allowed @('kind','path','status') -Required @('kind',