# DevFleet source part 021

Full-source UTF-8 byte interval [930000, 976500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 6ff2479ba2fa86b074f7f3c78cec9e31513dddaa99b0f406c4c5c7962beaad03

<!-- BEGIN SOURCE SLICE -->
 throw 'REAL-USE-ACCEPTANCE cleanup status is malformed.' }
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
                    $transportResult=[pscustomobject][ordered]@{input=$input;preflight=$preflight;stage=$stageEvidence;prepareReport=$prepareReport;prepareExitCode=$prepareExit;restart=$null;resumeReport=$null;resumeExitCode=$n