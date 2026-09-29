# DevFleet source part 031

Full-source UTF-8 byte interval [1395000, 1441500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8e4de45c965f453c6241fa58e93848403a0bbd9df37bb6621e5367e2d15d96af

<!-- BEGIN SOURCE SLICE -->
stname -RunId ([string]$Context.runId) -Role 'windows') -Force
            }
            $tailscaleWaitSeconds=if($tailscaleConfig.PSObject.Properties['PollTimeoutSeconds'] -and [int]$tailscaleConfig.PollTimeoutSeconds -gt 0){[int]$tailscaleConfig.PollTimeoutSeconds}else{120}
            $tailscaleOwnerDeadline=[datetime]::UtcNow.AddSeconds($tailscaleWaitSeconds+30)
            $auth=Invoke-TailscaleAuthentication -Session $session -Config $tailscaleConfig -OwnerDeadlineUtc $tailscaleOwnerDeadline
            if(-not [bool]$auth.authenticationAttempted -and [bool]$auth.userActionRequired) { Write-TailscaleOAuthActionRequired; throw "USER ACTION REQUIRED - TAILSCALE-AUTH: $([string]$auth.reason)." }
            Assert-TailscaleAuthenticationResult -Result $auth | Out-Null
            $productConfigPath=Join-Path ((Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path) 'source\config\devfleet.config.json'
            if(-not(Test-Path -LiteralPath $productConfigPath -PathType Leaf)){throw 'TAILSCALE_CONTROL_PLANE_OFFLINE: product configuration is unavailable for readiness endpoint discovery.'}
            $productConfig=Get-Content -LiteralPath $productConfigPath -Raw|ConvertFrom-Json -ErrorAction Stop
            $expectedPeer=Get-TailscaleE2EHostname -RunId ([string]$Context.runId) -Role 'primary'
            $servicePort=[int]$productConfig.Network.PortalPort
            $servicePath='/healthz'
            $expectedNode=if($provider-in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){Get-TailscaleE2EHostname -RunId ([string]$Context.runId) -Role 'windows'}else{[string]$Context.config.Tailscale.ExpectedGuestNodePattern}
            $expectedTag=if($authConfig.PSObject.Properties['Tag']){[string]$authConfig.Tag}else{''}
            $readiness=Get-TailscaleReadiness -Session $session -ExpectedNodePattern $expectedNode -ExpectedTag $expectedTag -ExpectedPeer $expectedPeer -ServicePort $servicePort -ServicePath $servicePath -OwnerDeadlineUtc $tailscaleOwnerDeadline
            if(-not [bool]$readiness.ready){throw "$([string]$readiness.failureClass): TAILSCALE-AUTH structured readiness did not pass."}
            return [ordered]@{status='REAL E2E PASS';phase=[string]$Context.phaseId;contract=if($provider-in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){'oauth-client-secret-provider-with-layered-readiness'}else{'auth-key-fallback-provider-with-layered-readiness'};configuredMode=$configuredMode;candidate=$candidate;guest=$readiness.layer2;readiness=$readiness;authenticationAttempted=[bool]$auth.authenticationAttempted;authenticationSucceeded=[bool]$auth.authenticationSucceeded;authProvider=$provider;expectedPeer=$expectedPeer;servicePort=$servicePort;servicePath=$servicePath;credentialsStoredInEvidence=$false;userActionRequired=$false}
        }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
    }
    if($configuredMode -ne 'Deferred'){throw 'USER ACTION REQUIRED - configured Tailscale policy requires the official interactive authentication boundary.'}
    $session=$null
    try{
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        $status=Get-TailscaleGuestStatus -Session $session -ExpectedNodePattern ([string]$Context.config.Tailscale.ExpectedGuestNodePattern)
        if([bool]$status.online -or -not[bool]$status.needsLogin){throw 'Deferred Tailscale policy expected an installed but unauthenticated guest.'}
        if([string]::IsNullOrWhiteSpace([string]$status.version) -or [string]$status.version -match 'not recognized|not found'){throw 'Deferred Tailscale policy could not verify the installed Tailscale client.'}
        return [ordered]@{status='REAL E2E PASS';phase=[string]$Context.phaseId;contract=if([string]$Context.phaseId -eq 'TAILSCALE-DEFERRED'){'installed-client-deferred-no-auth'}else{'authentication-explicitly-not-run-by-supported-deferred-policy'};configuredMode=$configuredMode;candidate=$candidate;guest=$status;authenticationAttempted=$false;credentialsStoredInEvidence=$false;userActionRequired=$false}
    }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
}

function ConvertTo-LfShellText([string]$Text) {
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Invoke-LinuxBootstrapPhase {
    param([Parameter(Mandatory)][string]$ContextJson)
    $context = Read-PhaseContext $ContextJson
    $candidate = Assert-ExactCandidate $context
    $tarPath = [string]$context.candidate.tar.path
    if (-not (Test-Path -LiteralPath $tarPath -PathType Leaf)) { throw "Linux phase TAR is missing: $tarPath" }
    $tarHash = (Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($tarHash -ne [string]$context.candidate.tar.sha256) { throw 'Linux phase TAR hash differs from the exact candidate tuple.' }
    $aiBundle = $null
    $aiBundleFound=$false;$aiBundleValue=Get-LifecycleProperty $context 'aiAuditZip' ([ref]$aiBundleFound);if ($aiBundleFound -and $aiBundleValue) {
        $aiPathFound=$false;$aiPathValue=Get-LifecycleProperty $aiBundleValue 'path' ([ref]$aiPathFound);$aiHashFound=$false;$aiHashValue=Get-LifecycleProperty $aiBundleValue 'sha256' ([ref]$aiHashFound);$aiBundlePath = [string]$aiPathValue
        $expectedAiBundleHash = ([string]$aiHashValue).ToLowerInvariant()
        if (-not (Test-Path -LiteralPath $aiBundlePath -PathType Leaf)) { throw "Focused Linux AI audit bundle is missing: $aiBundlePath" }
        if ($expectedAiBundleHash -notmatch '^[0-9a-f]{64}$') { throw 'Focused Linux AI audit bundle is missing an exact SHA-256 identity.' }
        $actualAiBundleHash = (Get-FileHash -LiteralPath $aiBundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualAiBundleHash -ne $expectedAiBundleHash) { throw 'Focused Linux AI audit bundle hash differs from the supplied exact identity.' }
        $aiBundle = [ordered]@{path=(Resolve-Path -LiteralPath $aiBundlePath).Path;sha256=$actualAiBundleHash;bytes=(Get-Item -LiteralPath $aiBundlePath).Length}
    }
    if ([string]$context.vmName -notlike 'DevFleet-E2E-*') { throw 'LINUX phase requires an ownership-scoped disposable L1.' }
    if ($env:COMPUTERNAME -notmatch '^MULATTOTechBOX$|^MULATTOTECHBOX$' -or $env:COMPUTERNAME -match 'SURFACE') { throw 'LINUX phase is not running on the approved MULATTOTECHBOX host.' }
    $l1 = Get-VM -Id ([guid][string]$context.vmId) -ErrorAction Stop
    if ($l1.Name -cne [string]$context.vmName) { throw 'LINUX phase disposable L1 identity/name mismatch.' }
    $vmProcessor = Get-VMProcessor -VM $l1 -ErrorAction Stop
    if (-not [bool]$vmProcessor.ExposeVirtualizationExtensions) { throw 'Disposable L1 does not expose nested virtualization.' }
    $nested = $context.config.NestedLinux
    if (-not $nested) { throw 'E2E config is missing the NestedLinux resource policy.' }
    $l2Name = [string]$nested.Name
    $l2Image = [string]$nested.UbuntuImage
    $l2Cpus = [int]$nested.Cpus
    $l2Memory = [string]$nested.Memory
    $l2Disk = [string]$nested.Disk
    $budgetPolicy = Get-HarnessBudgetPolicy -Config $context.config
    $l2BootstrapTimeout = [int]$budgetPolicy.operationMaximumsSeconds.guestBootstrap
    if ($l2Name -notlike 'DevFleet-E2E-*' -or $l2Name -eq ([string]$context.vmName)) { throw 'Nested Linux identity is outside the disposable E2E namespace.' }
    if ($l2Cpus -lt 1 -or $l2BootstrapTimeout -lt 1) { throw 'Nested Linux resource policy contains an invalid positive integer.' }
    # Each FullRelease phase restores its declared checkpoint independently.
    # The clean checkpoint intentionally has no product prerequisites, so the
    # Linux phase must exercise the candidate's real install path in this same
    # phase before asking the installed L1 to provide Multipass.
    $productInstall = Invoke-SupportedFreshInstallLifecycle -Context $context -Role 'Primary / Desktop' -CompleteLifecycle
    if ([string]$productInstall.status -ne 'REAL E2E PASS' -or -not [bool]$productInstall.guest.completionVerified) {
        throw "LINUX requires a genuine supported FreshInstall lifecycle PASS before Multipass; observed $($productInstall.status)."
    }
    $bootstrapTransactionId = [string]$productInstall.transactionId
    $bootstrapPayloadSha256 = [string]$context.candidate.tar.sha256
    $bootstrapPackageVersion = [string]$context.candidate.releaseVersion
    $bootstrapNodeRole = 'surrogate'
    if ($bootstrapTransactionId -notmatch '^[0-9a-fA-F]{32}$' -or
        $bootstrapPayloadSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $bootstrapPackageVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw 'LINUX product lifecycle did not return an exact bootstrap transaction, payload, or package identity.'
    }
    # The supported Desktop lifecycle leaves its exact product Multipass child
    # running after completion. A fixed 16 GiB nested L1 cannot safely allocate
    # that product child and the independent 4 GiB Linux L2 at the same time.
    # Quiesce only the candidate-bound product identity after its completion
    # authority has passed; never infer ownership from the harness L2 name.
    $productComputeName = Get-DevFleetProductComputeInstanceName -Context $context -Role 'Primary / Desktop'
    if ($productComputeName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$' -or $productComputeName -eq $l2Name -or $productComputeName -like 'DevFleet-E2E-*') {
        throw 'LINUX product compute identity is malformed or overlaps the disposable L2 namespace.'
    }
    $session = $null
    try {
        $session = Connect-DevFleetGuest -VmId ([guid][string]$context.vmId)
        $remoteRoot = "C:\Users\Public\DevFleet-E2E\$($context.runId)\$($context.phaseId)"
        $remoteTar = Join-Path $remoteRoot (Split-Path -Leaf $tarPath)
        Invoke-Command -Session $session -ScriptBlock { param($root) New-Item -ItemType Directory -Force -Path $root | Out-Null } -ArgumentList $remoteRoot
        $stage = Get-StageIntegrity -LocalPath $tarPath -Session $session -RemotePath $remoteTar
        if (-not $stage.equal) { throw 'Exact candidate TAR did not survive host-to-L1 staging.' }
        $remoteAiBundle = $null
        $aiBundleStage = $null
        if ($aiBundle) {
            $remoteAiBundle = Join-Path $remoteRoot (Split-Path -Leaf ([string]$aiBundle.path))
            $aiBundleStage = Get-StageIntegrity -LocalPath ([string]$aiBundle.path) -Session $session -RemotePath $remoteAiBundle
            if (-not $aiBundleStage.equal -or ([string]$aiBundleStage.remoteSha256).ToLowerInvariant() -ne [string]$aiBundle.sha256) { throw 'Exact AI audit ZIP did not survive host-to-L1 staging.' }
        }
        $secretJson = [ordered]@{
            NodeName=$l2Name; NodeRole='surrogate'; FriendlyName='DevFleet E2E Linux'; PortalPort=8787
            DeploymentId=("e2e-$($context.runId)"); NodeId=([guid]::NewGuid().ToString()); CoordinatorNodeId=''
            ProtocolVersion=1; AdminUser='e2e-admin'; AdminPassword=('E2E-' + [guid]::NewGuid().ToString('N')); ApiToken=('e2e-token-' + [guid]::NewGuid().ToString('N'))
            GitName='DevFleet E2E'; GitEmail='e2e@example.invalid'; OllamaBaseUrl=''; OllamaModel='e2e-disabled'; OllamaProfile='stable-interactive'
            DevelopmentProfile='strict'; DockerMode='rootless'; EnableSharedCaches=$false; EnableAnalyzerCache=$true; AutoStartCodexPro=$false
            AllowTailnetPorts=$false; BackupBeforeRebuild=$false; BackupBeforeQuarantine=$true; BackupIntervalMinutes=15; PackageVersion=$context.candidate.releaseVersion
        } | ConvertTo-Json -Compress
        $linuxResult = Invoke-Command -Session $session -ScriptBlock {
            param($remoteTarPath,$expectedTarHash,$runId,$phaseId,$l2,$productCompute,$image,$cpus,$memory,$disk,$secret,$timeoutSeconds,$remoteAiBundlePath,$expectedAiBundleHash,$bootstrapTransactionId,$bootstrapPayloadSha256,$bootstrapPackageVersion,$bootstrapNodeRole)
            $ErrorActionPreference='Stop'
            function ConvertTo-LfShellText([string]$Text) {
                if ($null -eq $Text) { return '' }
                return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
            }
            # Resolve the same trusted machine locations used by the shipping
            # product. PATH/App Execution Alias discovery is not sufficient for
            # a freshly-installed guest and can race the vendor service setup.
            $mpCandidates=@(
                (Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe')
            ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
            $mp=$mpCandidates | Select-Object -First 1
            if (-not $mp) {
                $mpCommand=Get-Command multipass.exe -ErrorAction SilentlyContinue
                if (-not $mpCommand) { $mpCommand=Get-Command multipass -ErrorAction SilentlyContinue }
                if ($mpCommand) { $mp=$mpCommand.Source }
            }
            if (-not $mp) { throw 'The real Desktop candidate path did not provide Multipass inside disposable L1.' }
            $started=$false; $marker="/etc/devfleet-e2e-run-$runId"; $lastOperation='initialization'; $lastMpResult=$null; $cloudInitPath=$null; $nestedDeadline=[DateTime]::UtcNow.AddSeconds($timeoutSeconds)
            $result=[ordered]@{status='FAIL';runId=$runId;phase=$phaseId;l1TarSha256=$null;l2TarSha256=$null;l2Name=$l2;productComputeInstanceName=$productCompute;productQuiescence=[ordered]@{status='PENDING';instanceName=$productCompute;initialState=$null;finalState=$null;stopInvoked=$false};ubuntu=$null;multipassVersion=$null;cloudInitSource='exact-candidate-tar:cloud-init/compute.yaml';cloudInitRenderedSha256=$null;cloudInitStatus=$null;devrunnerIdentityPreBootstrap=$false;bootstrapExitCode=$null;bootstrapLogExcerpt=@();postconditions=@{};aiAuditBundle=if($remoteAiBundlePath){[ordered]@{status='PENDING';expectedSha256=$expectedAiBundleHash}}else{[ordered]@{status='NOT REQUESTED'}};failureOperation=$null;lastMultipassCommand=$null;cleanup=$null}
            function Invoke-Mp([string[]]$Arguments,[switch]$DoNotRecord) {
                $remaining=[int][math]::Floor(($nestedDeadline-[DateTime]::UtcNow).TotalSeconds)
                if($remaining -le 0){throw 'Nested Multipass owning deadline expired before starting the next operation.'}
                $effective=[math]::Min(900,$remaining)
                $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$mp;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
                if($psi.PSObject.Properties.Name -contains 'ArgumentList' -and $null -ne $psi.ArgumentList){
                    foreach($argument in $Arguments){[void]$psi.ArgumentList.Add([string]$argument)}
                } else {
                    $quotedArguments=@($Arguments|ForEach-Object{
                        $value=[string]$_
                        if($value.Length -gt 0 -and $value -notmatch '[\s"]'){ $value; return }
                        $builder=[Text.StringBuilder]::new();[void]$builder.Append([char]34);$slashes=0
                        foreach($character in $value.ToCharArray()){
                            if([int]$character -eq 92){$slashes++;continue}
                            if([int]$character -eq 34){for($i=0;$i -lt ($slashes*2+1);$i++){[void]$builder.Append([char]92)};[void]$builder.Append([char]34);$slashes=0;continue}
                            for($i=0;$i -lt $slashes;$i++){[void]$builder.Append([char]92)}
                            $slashes=0;[void]$builder.Append($character)
                        }
                        for($i=0;$i -lt ($slashes*2);$i++){[void]$builder.Append([char]92)}
                        [void]$builder.Append([char]34);$builder.ToString()
                    })
                    $psi.Arguments=$quotedArguments -join ' '
                }
                $process=[Diagnostics.Process]::new();$process.StartInfo=$psi;$out=@();$code=-1
                try{
                    if(-not $process.Start()){throw 'Unable to start Multipass operation.'}
                    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
                    if(-not $process.WaitForExit($effective*1000)){try{$process.Kill($true)}catch{};try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5)))}catch{};throw "Multipass operation timed out after $effective seconds."}
                    try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
                    $out=@($(if($stdout.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdout.GetAwaiter().GetResult()})+$(if($stderr.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderr.GetAwaiter().GetResult()}) -split "`r?`n" | ForEach-Object {[string]$_})
                    $code=[int]$process.ExitCode
                } finally {$process.Dispose()}
                $record=[pscustomobject]@{arguments=@($Arguments);output=@($out);exitCode=$code}
                if(-not $DoNotRecord){Set-Variable -Scope 1 -Name lastMpResult -Value $record}
                return $record
            }
            try {
                $l1Hash=(Get-FileHash -LiteralPath $remoteTarPath -Algorithm SHA256).Hash.ToLowerInvariant(); $result.l1TarSha256=$l1Hash
                if ($l1Hash -ne $expectedTarHash) { throw 'L1 TAR hash differs from exact candidate TAR.' }
                $lastOperation='product-quiescence-inventory';$productInventory=Invoke-Mp @('list','--format','json');if($productInventory.exitCode -ne 0){throw "Product Multipass inventory failed: $($productInventory.output -join ' ')"};try{$productInventoryJson=($productInventory.output -join "`n")|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Product Multipass inventory was not valid JSON.'};$productRows=@($productInventoryJson.list|Where-Object{[string]$_.name-ceq$productCompute});if($productRows.Count-ne1){throw "Candidate-bound product compute instance '$productCompute' was not uniquely present after lifecycle completion."};$productInitialState=[string]$productRows[0].state;$stopInvoked=$false;if($productInitialState-ceq'Running'){$lastOperation='product-quiescence-stop';$stopProduct=Invoke-Mp @('stop',$productCompute);if($stopProduct.exitCode-ne0){throw "Candidate-bound product compute stop failed: $($stopProduct.output -join ' ')"};$stopInvoked=$true}elseif($productInitialState-cne'Stopped'){throw "Candidate-bound product compute instance '$productCompute' was in unsupported state '$productInitialState'."};$lastOperation='product-quiescence-verify';$productAfter=Invoke-Mp @('list','--format','json');if($productAfter.exitCode-ne0){throw "Product Multipass post-quiescence inventory failed: $($productAfter.output -join ' ')"};try{$productAfterJson=($productAfter.output -join "`n")|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Product Multipass post-quiescence inventory was not valid JSON.'};$productAfterRows=@($productAfterJson.list|Where-Object{[string]$_.name-ceq$productCompute});if($productAfterRows.Count-ne1){throw "Candidate-bound product compute instance '$productCompute' disappeared during quiescence verification."};$productFinalState=[string]$productAfterRows[0].state;if($productFinalState-cne'Stopped'){throw "Candidate-bound product compute instance '$productCompute' did not reach Stopped state; observed '$productFinalState'."};$result.productQuiescence=[ordered]@{status='PASS';instanceName=$productCompute;initialState=$productInitialState;finalState=$productFinalState;stopInvoked=$stopInvoked};$lastOperation='inventory';$existing=$productAfter.output -join "`n"
                if ($existing -match ('"name"\s*:\s*"' + [regex]::Escape($l2) + '"')) { throw "Nested VM identity already exists; refusing to adopt or mutate $l2." }
                $version=$null
                for($attempt=1;$attempt -le 30;$attempt++) {
                    $lastOperation='version-probe'
                    $version=Invoke-Mp @('version')
                    if($version.exitCode -eq 0){break}
                    if($attempt -lt 30){Start-Sleep -Seconds 2}
                }
                if($null -eq $version -or $version.exitCode -ne 0){throw "Multipass version probe failed after bounded retry: $($version.output -join ' ')"}
                $result.multipassVersion=($version.output -join ' ')
                # The shipping product creates the restricted devrunner account
                # through the exact candidate cloud-init template before invoking
                # bootstrap-compute.sh.  Exercise that same prerequisite here;
                # running the bootstrap against a raw Ubuntu image is not the
                # production provisioning contract.
                $lastOperation='cloud-init-template'
                $tarCommand=Get-Command tar.exe -ErrorAction SilentlyContinue
                if(-not $tarCommand){$tarCommand=Get-Command tar -ErrorAction SilentlyContinue}
                if(-not $tarCommand){throw 'Windows tar is unavailable for exact candidate cloud-init extraction.'}
                $previousErrorActionPreference=$ErrorActionPreference
                try{
                    $ErrorActionPreference='Continue'
                    $cloudTemplateOutput=@(& $tarCommand.Source -xOf $remoteTarPath 'cloud-init/compute.yaml' 2>&1|ForEach-Object{[string]$_})
                    $cloudTemplateExit=[int]$LASTEXITCODE
                }finally{$ErrorActionPreference=$previousErrorActionPreference}
                if($cloudTemplateExit -ne 0){throw "Exact candidate cloud-init extraction failed: $($cloudTemplateOutput -join ' ')"}
                $cloudTemplate=$cloudTemplateOutput -join "`n"
                if([string]::IsNullOrWhiteSpace($cloudTemplate)){throw 'Exact candidate cloud-init template is empty.'}
                $yamlNode="'"+$l2.Replace("'","''")+"'"
                $renderedCloudInit=$cloudTemplate.Replace('__NODE_NAME__',$yamlNode).Replace('__NODE_ROLE__',"'surrogate'").Replace('__GIT_NAME_SHELL__',"'DevFleet E2E'").Replace('__GIT_EMAIL_SHELL__',"'e2e@example.invalid'")
                if($renderedCloudInit -match '__[A-Z0-9_]+__'){throw 'Exact candidate cloud-init has unresolved placeholders.'}
                $cloudInitPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-cloud-init.yaml"
                [IO.File]::WriteAllText($cloudInitPath,$renderedCloudInit,[Text.UTF8Encoding]::new($false))
                $result.cloudInitRenderedSha256=(Get-FileHash -LiteralPath $cloudInitPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $lastOperation='launch'
                $launch=(Invoke-Mp @('launch',$image,'--name',$l2,'--cpus',[string]$cpus,'--memory',[string]$memory,'--disk',[string]$disk,'--cloud-init',$cloudInitPath)); if($launch.exitCode -ne 0){throw "Multipass launch failed: $($launch.output -join ' ')"}; $started=$true
                $lastOperation='run-marker'
                $mark=(Invoke-Mp @('exec',$l2,'--','bash','-lc',"echo '$runId' | sudo tee '$marker' >/dev/null")); if($mark.exitCode -ne 0){throw 'Unable to bind nested L2 to this E2E run.'}
                $lastOperation='cloud-init-ready'
                $cloudInitDeadline=(Get-Date).AddSeconds([math]::Min($timeoutSeconds,1200))
                $cloudInitDone=$false
                do{
                    $cloudProbe=Invoke-Mp @('exec',$l2,'--','bash','-lc','cloud-init status --format=json 2>&1 || cloud-init status 2>&1')
                    $cloudText=($cloudProbe.output -join "`n")
                    if($cloudProbe.exitCode -eq 0 -and $cloudText -match '(?im)("status"\s*:\s*"done"|^\s*status:\s*done\s*$)'){$cloudInitDone=$true;break}
                    if($cloudText -match '(?im)("status"\s*:\s*"(error|degraded|failed)"|^\s*status:\s*(error|degraded|failed)\s*$)'){throw "Exact candidate cloud-init failed: $cloudText"}
                    if((Get-Date)-lt $cloudInitDeadline){Start-Sleep -Seconds 5}
                }while((Get-Date)-lt $cloudInitDeadline)
                if(-not $cloudInitDone){throw "Exact candidate cloud-init did not finish before the bounded deadline: $cloudText"}
                $result.cloudInitStatus='done'
                $lastOperation='cloud-init-identity-contract'
                $identityProbe=Invoke-Mp @('exec',$l2,'--','bash','-lc','id -u devrunner >/dev/null && getent group devrunner >/dev/null')
                if($identityProbe.exitCode -ne 0){throw "Exact candidate cloud-init did not create the restricted devrunner identity: $($identityProbe.output -join ' ')"}
                $result.devrunnerIdentityPreBootstrap=$true
                $lastOperation='tar-transfer'
                $transfer=(Invoke-Mp @('transfer',$remoteTarPath,"${l2}:/tmp/devfleet-e2e-candidate.tar.gz")); if($transfer.exitCode -ne 0){throw "L1-to-L2 TAR transfer failed: $($transfer.output -join ' ')"}
                $lastOperation='tar-hash'
                $l2HashProbe=(Invoke-Mp @('exec',$l2,'--','sha256sum','/tmp/devfleet-e2e-candidate.tar.gz')); if($l2HashProbe.exitCode -ne 0){throw 'L2 TAR hash probe failed.'}; $l2Hash=((($l2HashProbe.output -join '').Trim() -split '\s+')[0]).ToLowerInvariant(); $result.l2TarSha256=$l2Hash
                if($l2Hash -ne $expectedTarHash){throw 'L2 TAR hash differs from exact candidate TAR.'}
                $lastOperation='payload-reset'
                $removePayload=(Invoke-Mp @('exec',$l2,'--','rm','-rf','/tmp/devfleet-e2e-payload')); if($removePayload.exitCode -ne 0){throw 'Unable to reset the exact candidate extraction directory in L2.'}
                $makePayload=(Invoke-Mp @('exec',$l2,'--','mkdir','-m','0755','/tmp/devfleet-e2e-payload')); if($makePayload.exitCode -ne 0){throw 'Unable to create the exact candidate extraction directory in L2.'}
                $lastOperation='payload-extraction'
                $extractArchive=(Invoke-Mp @('exec',$l2,'--','tar','-xzf','/tmp/devfleet-e2e-candidate.tar.gz','-C','/tmp/devfleet-e2e-payload')); if($extractArchive.exitCode -ne 0){throw 'Exact candidate extraction failed in L2.'}
                $lastOperation='entrypoint-probe'
                $entrypointProbe=(Invoke-Mp @('exec',$l2,'--','test','-f','/tmp/devfleet-e2e-payload/linux/bootstrap-compute.sh')); if($entrypointProbe.exitCode -ne 0){throw 'Exact candidate bootstrap entrypoint check failed in L2.'}
                $secretPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-secrets.json"; [IO.File]::WriteAllText($secretPath,$secret,[Text.UTF8Encoding]::new($false))
                try {
                    $lastOperation='secret-transfer'
                    $secretTransfer=(Invoke-Mp @('transfer',$secretPath,"${l2}:/tmp/devfleet-e2e-secrets.json")); if($secretTransfer.exitCode -ne 0){throw 'Ephemeral synthetic secret transfer failed.'}
                    $bootstrapScriptPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-bootstrap.sh"
                    $bootstrapScript=@'
#!/usr/bin/env bash
set +e
sudo chmod 600 /tmp/devfleet-e2e-secrets.json
timeout __TIMEOUT__ sudo bash /tmp/devfleet-e2e-payload/linux/bootstrap-compute.sh /tmp/devfleet-e2e-payload --secrets-stdin --transaction-id '__TRANSACTION_ID__' --payload-sha256 '__PAYLOAD_SHA256__' --bootstrap-max-seconds '__BOOTSTRAP_MAX_SECONDS__' --package-version '__PACKAGE_VERSION__' --node-role '__NODE_ROLE__' < /tmp/devfleet-e2e-secrets.json
code=$?
sudo rm -f /tmp/devfleet-e2e-secrets.json
exit "$code"
'@
                    $bootstrapScript=$bootstrapScript.Replace('__TIMEOUT__',[string]$timeoutSeconds).Replace('__TRANSACTION_ID__',[string]$bootstrapTransactionId).Replace('__PAYLOAD_SHA256__',[string]$bootstrapPayloadSha256).Replace('__BOOTSTRAP_MAX_SECONDS__',[string]$timeoutSeconds).Replace('__PACKAGE_VERSION__',[string]$bootstrapPackageVersion).Replace('__NODE_ROLE__',[string]$bootstrapNodeRole)
                    [IO.File]::WriteAllText($bootstrapScriptPath,(ConvertTo-LfShellText $bootstrapScript),[Text.UTF8Encoding]::new($false))
                    $lastOperation='bootstrap-wrapper-transfer'
                    $bootstrapTransfer=(Invoke-Mp @('transfer',$bootstrapScriptPath,"${l2}:/tmp/devfleet-e2e-bootstrap.sh")); if($bootstrapTransfer.exitCode -ne 0){throw 'Ephemeral Linux bootstrap wrapper transfer failed.'}
                    $lastOperation='bootstrap'
                    $boot=Invoke-Mp @('exec',$l2,'--','bash','/tmp/devfleet-e2e-bootstrap.sh');$bootOutput=@($boot.output);$result.bootstrapExitCode=[int]$boot.exitCode; $result.bootstrapLogExcerpt=@($bootOutput | ForEach-Object {[string]$_} | Select-Object -Last 120 | ForEach-Object { if($_.Length -gt 400){$_.Substring(0,400)}else{$_} })
                    if($result.bootstrapExitCode -ne 0){throw 'Real Linux bootstrap returned a non-zero exit code.'}
                } finally { Remove-Item -LiteralPath $secretPath -Force -ErrorAction SilentlyContinue; if($bootstrapScriptPath){Remove-Item -LiteralPath $bootstrapScriptPath -Force -ErrorAction SilentlyContinue}; [void](Invoke-Mp -Arguments @('exec',$l2,'--','rm','-f','/tmp/devfleet-e2e-bootstrap.sh','/tmp/devfleet-e2e-secrets.json') -DoNotRecord) }
                $checkScriptPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-postconditions.sh"
                $checkScript=@'
#!/usr/bin/env bash
set +e
overall=0
if (. /etc/os-release && test "$VERSION_ID" = "24.04"); then echo 'ubuntu=PASS'; else echo 'ubuntu=FAIL'; overall=1; fi
if test "$(ps -p 1 -o comm=)" = systemd; then echo 'systemd=PASS'; else echo 'systemd=FAIL'; overall=1; fi
if systemctl is-active --quiet devfleet.service; then echo 'service=PASS'; else echo 'service=FAIL'; overall=1; fi
if sudo -n -u devfleet-control -- test -s /etc/devfleet/config.json && sudo -n -u devfleet-control -- jq -e . /etc/devfleet/config.json >/dev/null; then echo 'config=PASS'; else echo 'config=FAIL'; overall=1; fi
uid=$(id -u devrunner)
if sudo -n -u devrunner test -S /run/user/$uid/docker.sock && sudo -n -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid DOCKER_HOST=unix:///run/user/$uid/docker.sock docker info --format '{{json .SecurityOptions}}' | grep -q rootless; then echo 'rootless=PASS'; else echo 'rootless=FAIL'; overall=1; fi
if sudo -n -u devfleet-control env DOCKER_HOST=unix:///run/user/$uid/docker.sock docker info >/dev/null; then echo 'controlSocket=PASS'; else echo 'controlSocket=FAIL'; overall=1; fi
if sudo -n -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid DOCKER_HOST=unix:///run/user/$uid/docker.sock docker run --rm hello-world >/dev/null; then echo 'container=PASS'; else echo 'container=FAIL'; overall=1; fi
if curl --fail --silent --show-error --connect-timeout 5 http://127.0.0.1:8787/healthz >/dev/null; then echo 'health=PASS'; else echo 'health=FAIL'; overall=1; fi
if test "$(sudo -n -u devfleet-control -- stat -c %U:%G:%a /etc/devfleet/config.json)" = root:devfleet-control:640 && test "$(sudo -n -u devfleet-control -- stat -c %U:%G:%a /etc/devfleet/secrets.env)" = root:devfleet-control:640; then echo 'ownership=PASS'; else echo 'ownership=FAIL'; overall=1; fi
if ! journalctl -k -b --no-pager 2>/dev/null | grep -Eiq 'out of memory|oom-killer|killed process'; then echo 'oom=PASS'; else echo 'oom=FAIL'; overall=1; fi
exit "$overall"
'@
                [IO.File]::WriteAllText($checkScriptPath,(ConvertTo-LfShellText $checkScript),[Text.UTF8Encoding]::new($false))
                try {
                    $lastOperation='postcondition-transfer'
                    $checkTransfer=(Invoke-Mp @('transfer',$checkScriptPath,"${l2}:/tmp/devfleet-e2e-postconditions.sh")); if($checkTransfer.exitCode -ne 0){throw 'Linux postcondition script transfer failed.'}
                    $lastOperation='postconditions'
                    $check=Invoke-Mp @('exec',$l2,'--','bash','/tmp/devfleet-e2e-postconditions.sh');$checkOutput=@($check.output);$checkExit=[int]$check.exitCode
                    foreach($name in @('ubuntu','systemd','service','config','rootless','controlSocket','container','health','ownership','oom')) { $line=@($checkOutput | ForEach-Object {[string]$_} | Where-Object {$_ -match ('^'+[regex]::Escape($name)+'=(PASS|FAIL)$')} | Select-Object -Last 1); $pass=($line.Count -eq 1 -and [string]$line[0] -eq ($name+'=PASS')); $result.postconditions[$name]=[ordered]@{pass=[bool]$pass;output=$line}; if(-not $pass){throw "Linux postcondition failed: $name"} }
                    if($checkExit -ne 0){throw 'One or more Linux postconditions failed.'}
                } finally { Remove-Item -LiteralPath $checkScriptPath -Force -ErrorAction SilentlyContinue; [void](Invoke-Mp -Arguments @('exec',$l2,'--','rm','-f','/tmp/devfleet-e2e-postconditions.sh') -DoNotRecord) }
                if($remoteAiBundlePath){
                    $lastOperation='ai-bundle-transfer'
                    $aiTransfer=Invoke-Mp @('transfer',$remoteAiBundlePath,"${l2}:/tmp/devfleet-e2e-ai-audit.zip")
                    if($aiTransfer.exitCode -ne 0){throw "L1-to-L2 AI audit ZIP transfer failed: $($aiTransfer.output -join ' ')"}
                    $aiValidationScriptPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-ai-bundle.sh"
                    $aiValidationScript=@'
#!/usr/bin/env bash
set -euo pipefail
expected_hash="$1"
archive=/tmp/devfleet-e2e-ai-audit.zip
extract_root="/tmp/devfleet e2e ai audit"
actual_hash="$(sha256sum "$archive" | awk '{print $1}')"
test "$actual_hash" = "$expected_hash"
rm -rf "$extract_root"
mkdir -m 0755 "$extract_root"
unzip -q "$archive" -d "$extract_root"
python3 - "$extract_root" <<'PY'
import json
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
records = json.loads((root / "SOURCE-MODES.json").read_text(encoding="utf-8"))
failures = []
executable = 0
for record in records:
    path = root / record["path"]
    expected = int(record["posixMode"])
    if not path.is_file():
        failures.append(f"missing:{record['path']}")
        continue
    actual = stat.S_IMODE(path.stat().st_mode)
    if actual != expected:
        failures.append(f"mode:{record['path']}:{actual:04o}!={expected:04o}")
    executable += int(bool(record["executable"]))
if failures:
    raise SystemExit(";".join(failures[:20]))
print(json.dumps({"status":"PASS","modeRecords":len(records),"executableRecords":executable}, sort_keys=True))
PY
python3 "$extract_root/source/tools/validate_audit_coherence.py" --root "$extract_root"
python3 -m compileall -q "$extract_root/source" "$extract_root/automation"
while IFS= read -r -d '' script; do bash -n "$script"; done < <(find "$extract_root/source" "$extract_root/automation" -type f -name '*.sh' -print0)
printf 'aiBundle=PASS\n'
'@
                    [IO.File]::WriteAllText($aiValidationScriptPath,(ConvertTo-LfShellText $aiValidationScript),[Text.UTF8Encoding]::new($false))
                    try{
                        $lastOperation='ai-bundle-validator-transfer'
                        $aiValidatorTransfer=Invoke-Mp @('transfer',$aiValidationScriptPath,"${l2}:/tmp/devfleet-e2e-ai-bundle.sh")
                        if($aiValidatorTransfer.exitCode -ne 0){throw 'AI audit Linux validator transfer failed.'}
                        $lastOperation='ai-bundle-linux-roundtrip'
                        $aiCheck=Invoke-Mp @('exec',$l2,'--','bash','/tmp/devfleet-e2e-ai-bundle.sh',$expectedAiBundleHash)
                        $aiOutput=@($aiCheck.output|ForEach-Object{[string]$_})
                        if($aiCheck.exitCode -ne 0 -or $aiOutput -notcontains 'aiBundle=PASS'){throw "AI audit Linux unzip/mode validation failed: $($aiOutput -join ' ')"}
                        $modeJson=@($aiOutput|Where-Object{$_ -match '^\{"executableRecords"'}|Select-Object -Last 1)
                        $coherenceJson=@($aiOutput|Where-Object{$_ -match '^\{"currentReleaseFingerprintId"'}|Select-Object -Last 1)
                        $result.aiAuditBundle=[ordered]@{status='PASS';sha256=$expectedAiBundleHash;standardUnzip=$true;pathWithSpaces=$true;modeInventory=if($modeJson){$modeJson|ConvertFrom-Json}else{$null};coherence=if($coherenceJson){$coherenceJson|ConvertFrom-Json}else{$null};pythonCompile=$true;bashSyntax=$true;output=@($aiOutput|Select-Object -Last 40)}
                    }finally{
                        Remove-Item -LiteralPath $aiValidationScriptPath -Force -ErrorAction SilentlyContinue
                        [void](Invoke-Mp -Arguments @('exec',$l2,'--','rm','-f','/tmp/devfleet-e2e-ai-bundle.sh','/tmp/devfleet-e2e-ai-audit.zip') -DoNotRecord)
                    }
                }
                $result.status='REAL E2E PASS'
            } catch {
                $errorMessage=[string]$_.Exception.Message
                $errorRecord=([string]($_ | Out-String)).Trim()
                if([string]::IsNullOrWhiteSpace($errorMessage)){$errorMessage=$errorRecord}
                if([string]::IsNullOrWhiteSpace($errorMessage) -and $lastMpResult){$errorMessage=(@($lastMpResult.output)-join ' ').Trim()}
                if([string]::IsNullOrWhiteSpace($errorMessage)){$errorMessage='Unknown nested Linux harness failure.'}
                $result.failureOperation=$lastOperation
                if($lastMpResult){$result.lastMultipassCommand=[ordered]@{arguments=@($lastMpResult.arguments);exitCode=[int]$lastMpResult.exitCode;output=@($lastMpResult.output|Select-Object -Last 40)}}
                $result.error="${lastOperation}: $errorMessage"
            }
            finally {
                if($cloudInitPath){Remove-Item -LiteralPath $cloudInitPath -Force -ErrorAction SilentlyContinue}
                if($started){
                    $boundFile=(Invoke-Mp @('exec',$l2,'--','test','-f',$marker))
                    $boundValue=(Invoke-Mp @('exec',$l2,'--','cat',$marker))
                    $bound=($boundFile.exitCode -eq 0 -and $boundValue.exitCode -eq 0 -and (($boundValue.output -join '').Trim() -eq $runId))
                    if($bound){ $deleted=(Invoke-Mp @('delete','--purge',$l2)); $gone=(Invoke-Mp @('list','--format','json')).output -join "`n"; $result.cleanup=[ordered]@{boundToRun=$true;deleteExitCode=$deleted.exitCode;absent=($gone -notmatch ('"name"\s*:\s*"' + [regex]::Escape($l2) + '"'));deleteOutput=(($deleted.output -join ' ') | Select-Object -Last 20)} }
                    else { $result.cleanup=[ordered]@{boundToRun=$false;absent=$false;error='L2 run marker was not positively verified; resource retained for manual cleanup.'} }
                } else { $result.cleanup=[ordered]@{boundToRun=$false;absent=$true;notCreated=$true} }
            }
            $result
        } -ArgumentList $remoteTar,$tarHash,$context.runId,$context.phaseId,$l2Name,$productComputeName,$l2Image,$l2Cpus,$l2Memory,$l2Disk,$secretJson,$l2BootstrapTimeout,$remoteAiBundle,$(if($aiBundle){[string]$aiBundle.sha256}else{$null}),$bootstrapTransactionId,$bootstrapPayloadSha256,$bootstrapPackageVersion,$bootstrapNodeRole
        $evidencePath = Join-Path ([string]$context.runDir) 'linux-l2-evidence.json'
        ($linuxResult | ConvertTo-Json -Depth 32) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        if ([string]$linuxResult.status -ne 'REAL E2E PASS') { throw "Real nested Linux E2E failed: $([string]$linuxResult.error); evidence=$evidencePath" }
        if (-not [bool]$linuxResult.cleanup.absent) { throw "Nested Linux cleanup was not positively verified; evidence=$evidencePath" }
        return [ordered]@{status='REAL E2E PASS';phase='LINUX';contract='nested-multipass-ubuntu-bootstrap-after-real-wpf-install';candidate=$candidate;productInstall=$productInstall;productComputeInstanceName=$productComputeName;productQuiescence=$linuxResult.productQuiescence;hostToL1=$stage;aiBundleHostToL1=$aiBundleStage;l1=$linuxResult.l1TarSha256;l2=$linuxResult;linuxEvidencePath=$evidencePath}
    } finally { if ($session) { Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue } }
}

function Invoke-DependencyMatrix {
    param([Parameter(Mandatory)][psobject]$Context)
    $scenarios = @('Healthy-WinGet','Outdated-Prerequisites','WinGet-Missing','WinGet-Broken','WinGet-Source-Broken','Official-Direct-Fallback','Valid-Nonstandard-Path')
    $records = [System.Collections.Generic.List[object]]::new()
    $healthy = Invoke-SupportedFreshInstallLifecycle -Context $Context -Role 'Primary / Desktop' -CompleteLifecycle
    # A failed product lifecycle returns terminal evidence rather than a
    # completion-shaped candidate/guest object. Read every field through the
    # representation-neutral helper so a dependency-matrix wrapper cannot
    # replace the earliest product failure with a StrictMode property error.
    $healthyStatusFound=$false;$healthyStatusValue=Get-LifecycleProperty -Value $healthy -Name 'status' -Found ([ref]$healthyStatusFound)
    $healthyStatus=if($healthyStatusFound){[string]$healthyStatusValue}else{'UNAVAILABLE'}
    $healthyCandidateFound=$false;$healthyCandidate=Get-LifecycleProperty -Value $healthy -Name 'candidate' -Found ([ref]$healthyCandidateFound)
    $healthyGuestFound=$false;$healthyGuest=Get-LifecycleProperty -Value $healthy -Name 'guest' -Found ([ref]$healthyGuestFound)
    $healthyCompletionFound=$false;$healthyCompletion=Get-LifecycleProperty -Value $healthyGuest -Name 'completionVerified' -Found ([ref]$healthyCompletionFound)
    $healthyErrorFound=$false;$healthyErrorValue=Get-LifecycleProperty -Value $healthy -Name 'error' -Found ([ref]$healthyErrorFound)
    $healthyEvidenceFound=$false;$healthyEvidenceValue=Get-LifecycleProperty -Value $healthy -Name 'evidencePath' -Found ([ref]$healthyEvidenceFound)
    $healthyCompleted=($healthyGuestFound -and $healthyCompletionFound -and [bool]$healthyCompletion)
    [void]$records.Add([ordered]@{scenario='Healthy-WinGet';evidenceClass='REAL_DISPOSABLE_L1';status=$healthyStatus;candidate=$healthyCandidate;guest=$healthyGuest;condition='current trusted WinGet/dependency inventory';actualConditionProven=$healthyCompleted;error=if($healthyErrorFound){[string]$healthyErrorValue}else{''};evidencePath=if($healthyEvidenceFound){[string]$healthyEvidenceValue}else{''}})
    if($healthyStatus -ne 'REAL E2E PASS' -or -not $healthyCompleted){
        $detail=if($healthyErrorFound -and -not [string]::IsNullOrWhiteSpace([string]$healthyErrorValue)){[string]$healthyErrorValue}else{'lifecycle completionVerified was not proven'}
        $evidence=if($healthyEvidenceFound -and -not [string]::IsNullOrWhiteSpace([string]$healthyEvidenceValue)){"; evidence=$([string]$healthyEvidenceValue)"}else{''}
        throw "Healthy-WinGet did not complete the supported exact-candidate lifecycle: status=$healthyStatus; $detail$evidence"
    }
    $workspace = if($Context.workspaceRoot){[string]$Context.workspaceRoot}else{(Resolve-Path (Join-Path $Context.runDir '..\..\..\..')).Path}
    $dotnet = Join-Path $workspace '.dotnet\dotnet.exe'
    if(-not(Test-Path -LiteralPath $dotnet -PathType Leaf)){throw "Explicit repository-local .NET SDK is missing: $dotnet"}
    $sdkVersion = (& $dotnet --version 2>&1 | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $sdkVersion -ne '8.0.424'){throw "Dependency runner requires repository-local .NET SDK 8.0.424; observed '$sdkVersion'."}
    $sdkHash=(Get-FileHash -LiteralPath $dotnet -Algorithm SHA256).Hash.ToLowerInvariant()
    $sdkEvidence=[ordered]@{schemaVersion=1;contract='explicit-repository-local-dotnet-sdk';path=(Resolve-Path -LiteralPath $dotnet).Path;version=$sdkVersion;sha256=$sdkHash;source='repository-local .dotnet SDK';globalPathMutated=$false;capturedUtc=(Get-Date).ToUniversalTime().ToString('o')}
    Write-EvidenceJson -Path (Join-Path ([string]$Context.runDir) 'dotnet-sdk-evidence.json') -Value $sdkEvidence
    $runnerProject=Join-Path $workspace 'automation\release-e2e\tests\DependencyPolicyRunner\DependencyPolicyRunner.csproj'
    if(-not(Test-Path -LiteralPath $runnerProject -PathType Leaf)){throw 'Tooling-only dependency policy runner is missing.'}
    $steps=[ordered]@{}
    function Invoke-SdkStep([string]$Name,[string[]]$Arguments,[string]$Cwd) {
        $lines=@(& $dotnet @Arguments 2>&1 | ForEach-Object {[string]$_});$exit=[int]$LASTEXITCODE
        $steps[$Name]=[ordered]@{command=@($dotnet)+$Arguments;workingDirectory=$Cwd;exitCode=$exit;stdoutStderr=$lines}
        if($exit -ne 0){
            # Persist the failed step before throwing so a bounded tooling
            # blocker retains stdout/stderr and the exact command contract.
            Write-EvidenceJson -Path (Join-Path ([string]$Context.runDir) 'dependency-policy-runner.json') -Value ([ordered]@{schemaVersion=1;contract='restore-build-run-explicit-local-sdk';status='FAIL';failedStep=$Name;sdk=$sdkEvidence;project=$runnerProject;steps=$steps})
            throw "Dependency policy runner $Name failed with exit code $exit."
        }
        return $lines
    }
    $projectDir=Split-Path -Parent $runnerProject
    [void](Invoke-SdkStep 'restore' @('restore',$runnerProject,'--nologo') $workspace)
    [void](Invoke-SdkStep 'build' @('build',$runnerProject,'--configuration','Release','--nologo','-v:minimal') $workspace)
    $json=Invoke-SdkStep 'run' @('run','--project',$runnerProject,'--configuration','Release','--nologo') $workspace
    Write-EvidenceJson -Path (Join-Path ([string]$Context.runDir) 'dependency-policy-runner.json') -Value ([ordered]@{schemaVersion=1;contract='restore-build-run-explicit-local-sdk';sdk=$sdkEvidence;project=$runnerProject;steps=$steps})
    try{$adversarial=@(($json -join "`n")|ConvertFrom-Json)}catch{throw "Dependency policy runner returned invalid JSON: $($_.Exception.Message)"}
    $scenarioIds=@('WinGet-Missing','WinGet-Broken','WinGet-Source-Broken','Official-Direct-Fallback','Valid-Nonstandard-Path','Outdated-Prerequisites')
    if(@($adversarial.scenario|Sort-Object -Unique).Count -ne $scenarioIds.Count -or @($adversarial).Count -ne $scenarioIds.Count -or (@($adversarial.scenario|Sort-Object -Unique) -join '|') -ne (@($scenarioIds|Sort-Object) -join '|')){throw 'Dependency policy runner returned duplicate, missing, or unexpected scenario IDs.'}
    foreach($row in $adversarial){
        if([string]$row.status -ne 'PASS' -or [string]$row.evidenceClass -ne 'ADVERSARIAL_PRODUCT_POLICY' -or -not [bool]$row.actualConditionProven){thro