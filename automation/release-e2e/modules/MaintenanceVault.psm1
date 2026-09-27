Set-StrictMode -Version Latest

# Qualification fixture only. This does not impersonate a Laptop transaction,
# change the installed Primary role, or award proof credit. The ordinary product
# Vault cloud-init/bootstrap and client configurator remain the implementation.
function Assert-MaintenanceVaultResult {
    param($Result,$Request)
    if([string]$Result.status-cne'PASS'){throw 'Configured Primary Vault prerequisite did not pass.'}
    if([string]$Result.payloadSha256-cne[string]$Request.payloadSha256){throw 'Vault fixture payload identity differs.'}
    if([string]$Result.primaryRole-cne'primary'-or[string]$Result.primaryName-cne[string]$Request.primaryName-or[string]$Result.vaultName-cne[string]$Request.vaultName){throw 'Vault fixture Primary/instance identity differs.'}
    foreach($key in @('primaryId','vaultId','deploymentId')){$id=[guid]::Empty;if(-not[guid]::TryParse([string]$Result.$key,[ref]$id)-or$id-eq[guid]::Empty){throw "Vault fixture $key is missing or invalid."}}
    if($Result.configurationPresent-isnot[bool]-or-not$Result.configurationPresent-or$Result.authenticatedTransport-isnot[bool]-or-not$Result.authenticatedTransport){throw 'Vault fixture lacks authenticated configuration.'}
    if($Result.proofCredit-isnot[bool]-or$Result.proofCredit){throw 'Vault prerequisite cannot award proof credit.'}
}

function Get-MaintenanceVaultControlRoot {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $resolved=(Resolve-Path -LiteralPath $WorkspaceRoot).Path.ToLowerInvariant()
    $sha=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($resolved))
    $key=([Convert]::ToHexString($sha).ToLowerInvariant()).Substring(0,16)
    return Join-Path $env:LOCALAPPDATA ("DevFleet\ReleaseRunner-v9\"+$key)
}

function Protect-MaintenanceVaultPrivateFailureBytes {
    param(
        [Parameter(Mandatory)][byte[]]$Plaintext,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][guid]$VmId,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [string]$ControlRoot=''
    )
    if($Plaintext.Length-le0){throw 'Private failure evidence is empty.'}
    if(-not$ControlRoot){$ControlRoot=Get-MaintenanceVaultControlRoot -WorkspaceRoot $WorkspaceRoot}
    Add-Type -AssemblyName System.Security
    $entropy=[Text.Encoding]::UTF8.GetBytes("DevFleet exact failure evidence $RunId")
    $encrypted=[Security.Cryptography.ProtectedData]::Protect($Plaintext,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $privateDir=Join-Path $ControlRoot ("private-evidence\"+$RunId)
    [IO.Directory]::CreateDirectory($privateDir)|Out-Null
    $encryptedPath=Join-Path $privateDir 'private-product-operations.log.dpapi'
    [IO.File]::WriteAllBytes($encryptedPath,$encrypted)
    $roundTrip=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try{
        $roundTripVerified=$roundTrip.Length-eq$Plaintext.Length
        if($roundTripVerified){
            for($i=0;$i-lt$Plaintext.Length;$i++){if($roundTrip[$i]-ne$Plaintext[$i]){$roundTripVerified=$false;break}}
        }
        if(-not$roundTripVerified){throw 'Private failure DPAPI round-trip verification failed.'}
        $metadata=[ordered]@{
            schemaVersion=1;runId=$RunId;classification='ENCRYPTED_PRIVATE_FAILURE_EVIDENCE_PRESERVATION'
            sourceVmId=$VmId.ToString();sourcePath=$SourcePath;sourceBytes=$Plaintext.Length
            encryptedLocalPath=$encryptedPath;encryptedSha256=(Get-FileHash -LiteralPath $encryptedPath -Algorithm SHA256).Hash.ToLowerInvariant()
            encryption='Windows DPAPI CurrentUser';entropyDerivation='UTF8: DevFleet exact failure evidence plus space plus RunId'
            roundTripVerified=$true;plaintextWrittenToHost=$false;plaintextIncludedInAudit=$false
            sourceReadOnly=$true;runtimeRestarted=$false;observedAtUtc=[datetime]::UtcNow.ToString('o')
        }
        $metadataPath=Join-Path $RunDir 'private-failure-preservation.json'
        [IO.File]::WriteAllText($metadataPath,(($metadata|ConvertTo-Json -Depth 6)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        return [pscustomobject]$metadata
    } finally {
        if($roundTrip){[Array]::Clear($roundTrip,0,$roundTrip.Length)}
        if($encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
        if($entropy){[Array]::Clear($entropy,0,$entropy.Length)}
    }
}

function Save-MaintenanceVaultPrivateFailureEvidence {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RemoteRoot,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][guid]$VmId
    )
    $sourcePath=Join-Path $RemoteRoot 'private-product-operations.log'
    $record=Invoke-DevFleetBoundedGuestCommand -Session $Session -ScriptBlock {
        param($Path)
        if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return [pscustomobject]@{present=$false}}
        $bytes=[IO.File]::ReadAllBytes($Path)
        try{[pscustomobject]@{present=$true;length=$bytes.Length;base64=[Convert]::ToBase64String($bytes)}}finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
    } -ArgumentList @($sourcePath) -TimeoutSeconds 30
    if(-not[bool]$record.present){throw 'Private failure log was not present at the owned failure boundary.'}
    $plain=[Convert]::FromBase64String([string]$record.base64)
    $record.base64=$null
    try{
        if($plain.Length-ne[int]$record.length){throw 'Private failure log length changed during read-only preservation.'}
        return Protect-MaintenanceVaultPrivateFailureBytes -Plaintext $plain -RunId $RunId -VmId $VmId -SourcePath $sourcePath -WorkspaceRoot $WorkspaceRoot -RunDir $RunDir
    } finally {if($plain){[Array]::Clear($plain,0,$plain.Length)}}
}

function Write-MaintenanceVaultWindowsTailscaleSnapshot {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ExpectedHostname,
        [Parameter(Mandatory)][string]$RunDir
    )
    $snapshot=$null
    try{
        $snapshot=Invoke-DevFleetBoundedGuestCommand -Session $Session -ScriptBlock {
            param($Expected)
            $command=Get-Command tailscale.exe,tailscale -ErrorAction SilentlyContinue|Select-Object -First 1
            if(-not$command){return [pscustomobject][ordered]@{schemaVersion=1;status='UNAVAILABLE';commandPresent=$false;expectedHostname=$Expected}}
            $raw=& $command.Source status --json 2>$null
            if($LASTEXITCODE-ne0-or-not$raw){return [pscustomobject][ordered]@{schemaVersion=1;status='UNAVAILABLE';commandPresent=$true;expectedHostname=$Expected}}
            $status=$raw|ConvertFrom-Json
            $self=$status.Self
            $selfHostname=[string]$self.HostName
            [pscustomobject][ordered]@{
                schemaVersion=1;status='OBSERVED';commandPresent=$true;backendState=[string]$status.BackendState
                selfOnline=[bool]$self.Online;selfHostName=$selfHostname;expectedHostname=$Expected
                hostnameMatches=($selfHostname-ceq$Expected);tailscaleIpCount=@($status.TailscaleIPs).Count
                healthCount=@($status.Health).Count;observedUtc=[datetime]::UtcNow.ToString('o')
            }
        } -ArgumentList @($ExpectedHostname) -TimeoutSeconds 30
    } catch {
        $snapshot=[pscustomobject][ordered]@{schemaVersion=1;status='UNAVAILABLE';commandPresent=$null;expectedHostname=$ExpectedHostname;reason='read-only Tailscale status probe failed';observedUtc=[datetime]::UtcNow.ToString('o')}
    }
    $path=Join-Path $RunDir 'maintenance-vault-windows-tailscale-preflight.json'
    [IO.File]::WriteAllText($path,(($snapshot|ConvertTo-Json -Depth 6)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    return $snapshot
}

function Invoke-MaintenanceVaultProvisioning {
    param([Parameter(Mandatory)]$Request)
    if([string]$Request.runId-cnotmatch '\Afullrelease-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'-or[string]$Request.payloadSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'Vault fixture run/payload binding is invalid.'}
    $state=[ordered]@{}
    foreach($step in @('identity','launch','bootstrap','configure','verify')){
        if([datetime]::UtcNow-ge([datetime]$Request.ownerDeadlineUtc).ToUniversalTime()){throw 'Vault prerequisite owner deadline expired.'}
        $value=Invoke-MaintenanceVaultStep -Name $step -Request $Request -State $state
        if($step-ceq'identity'){
            if([string]$value.primaryRole-cne'primary'){throw 'Vault prerequisite requires the installed Primary role.'}
            if($value.existingVault-isnot[bool]-or$value.existingVault){throw 'Refusing to adopt or refresh an existing Vault in the prerequisite.'}
            $state.identity=$value
        } elseif($step-ceq'launch'){$state.vault=$value}
        elseif($step-ceq'verify'){Assert-MaintenanceVaultResult -Result $value -Request $Request;return $value}
    }
}

function Invoke-MaintenanceVaultStep {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)]$Request,[Parameter(Mandatory)]$State)
    # This function runs only in an exact-L1, separately bounded PS7 process.
    if($env:COMPUTERNAME-cne'DEVFLEET-E2E-01'-or$PSVersionTable.PSVersion.Major-lt7){throw 'Vault fixture is restricted to the approved disposable L1 PS7 runtime.'}
    $package=[string]$Request.packageRoot
    Import-Module (Join-Path $package 'windows/DevFleet.Common.psm1') -Scope Local -DisableNameChecking
    $config=Get-DevFleetConfig;$mp=Get-MultipassExe
    if([string]$config.Primary.InstanceName-cne[string]$Request.primaryName-or[string]$config.Vault.InstanceName-cne[string]$Request.vaultName){throw 'Installed configuration changed the approved fixture targets.'}
    $deadline=([datetime]$Request.ownerDeadlineUtc).ToUniversalTime()
    Set-DevFleetDeadlineContext -TransactionDeadlineUtc $deadline -StageName 'vault' -StageBudgetSeconds ([int]$Request.budgetSeconds)|Out-Null
    switch($Name){
        'identity' {
            $identity=Get-Content -LiteralPath (Join-Path (Get-DevFleetStateRoot) 'node-identity.json') -Raw|ConvertFrom-Json
            $primary=@(Get-VM -Name ([string]$Request.primaryName) -ErrorAction Stop)
            if($primary.Count-ne1){throw 'Primary immutable VM identity is ambiguous.'}
            $inventory=Invoke-External $mp @('list','--format','json') -Capture -TimeoutSeconds 60 -DeadlineUtc $deadline|ConvertFrom-Json
            $unexpected=@($inventory.list|Where-Object{[string]$_.name-cne[string]$Request.primaryName})
            $existing=@(Get-VM -ErrorAction Stop|Where-Object{$_.Id-ne$primary[0].Id})
            if($unexpected.Count-gt0-or$existing.Count-gt0){throw 'Refusing an existing Vault or unexpected nested instance.'}
            if(@($inventory.list|Where-Object{[string]$_.name-ceq[string]$Request.primaryName}).Count-ne1){throw 'Primary Multipass inventory is missing or ambiguous.'}
            Assert-MultipassIsolation -InstanceNames @([string]$Request.primaryName)
            return [pscustomobject]@{primaryRole=[string]$identity.node_role;primaryId=$primary[0].Id.ToString();deploymentId=[string]$identity.deployment_id;existingVault=$false}
        }
        'launch' {
            $v=$config.Vault
            $dependencyPolicy=Get-Content -LiteralPath (Join-Path $package 'linux/dependency-policy.json') -Raw|ConvertFrom-Json
            $key=[string]$dependencyPolicy.tailscale.signingKeySha256Fingerprint
            if($key-cnotmatch'^[A-F0-9]{40}$'){throw 'Candidate Vault cloud-init signing-key identity is invalid.'}
            $cloud=Join-Path ([string]$Request.workRoot) 'vault-cloud-init.yaml'
            $rendered=(Get-Content -LiteralPath (Join-Path $package 'cloud-init/vault.yaml') -Raw).Replace('__NODE_NAME__',(ConvertTo-YamlSingleQuotedScalar ([string]$Request.vaultName))).Replace('__TAILSCALE_SIGNING_FINGERPRINT__',$key)
            if($rendered-match'__[A-Z0-9_]+__'){throw 'Vault cloud-init contains unresolved placeholders.'}
            [IO.File]::WriteAllText($cloud,$rendered,[Text.UTF8Encoding]::new($false))
            Invoke-MultipassLaunchWithReadinessRecovery -InstanceName ([string]$Request.vaultName) -LaunchArguments @('launch',[string]$v.UbuntuImage,'--name',[string]$Request.vaultName,'--cpus',[string]$v.Cpus,'--memory',[string]$v.Memory,'--disk',[string]$v.Disk,'--cloud-init',$cloud) -ReadinessTimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'multipassReadiness') -LaunchTimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'multipassLaunch') -DeadlineUtc $deadline|Out-Null
            $vm=@(Get-VM -Name ([string]$Request.vaultName) -ErrorAction Stop)
            if($vm.Count-ne1){throw 'New fixture Vault identity is ambiguous.'}
            return [pscustomobject]@{vaultId=$vm[0].Id.ToString()}
        }
        'bootstrap' {
            $vault=Get-VM -Id ([guid][string]$State.vault.vaultId) -ErrorAction Stop
            if($vault.Name-cne[string]$Request.vaultName){throw 'Fixture Vault identity changed before bootstrap.'}
            & (Join-Path $package 'windows/04a-Connect-WindowsTailscale.ps1')|Out-Null
            & (Join-Path $package 'windows/04-Connect-Tailscale.ps1') -InstanceName ([string]$Request.vaultName)|Out-Null
            # The product script imports Common with -Force in its own scope.
            # Reacquire its exports after that boundary, as in native cleanup.
            Import-Module (Join-Path $package 'windows/DevFleet.Common.psm1') -Scope Local -DisableNameChecking
            $secrets=Get-OrCreateSecrets;$identity=Get-OrCreateVaultIdentity
            if([string]$identity.deployment_id-cne[string]$State.identity.deploymentId){throw 'Vault deployment differs from the installed Primary.'}
            $boundary=New-DevFleetBootstrapBoundary -Kind vault -InstanceName ([string]$Request.vaultName) -TransactionId ([string]$Request.transactionId) -PayloadSha256 ([string]$Request.payloadSha256) -BootstrapMaxSeconds (Get-DevFleetOperationMaximumSeconds 'vaultBootstrap') -PackageVersion 'vault' -NodeRole 'vault'
            $zip=Join-Path ([string]$Request.workRoot) 'vault-payload.zip'
            Compress-Archive -LiteralPath (Join-Path $package 'linux') -DestinationPath $zip -ErrorAction Stop
            $secretJson=[ordered]@{VaultPort=$config.Network.VaultPort;RestUser=$secrets.VaultRestUser;RestPassword=$secrets.VaultRestPassword;ResticPassword=$secrets.ResticPassword;ClusterName=$config.ClusterName;DeploymentId=$identity.deployment_id;NodeId=$identity.node_id;NodeName=$identity.node_name}|ConvertTo-Json -Compress
            try{
                Invoke-External $mp @('transfer',$zip,([string]$Request.vaultName+':/tmp/devfleet-vault-payload.zip')) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') -DeadlineUtc $deadline|Out-Null
                Invoke-External $mp @('exec',[string]$Request.vaultName,'--','bash','-lc',$boundary.extractionCommand) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') -DeadlineUtc $deadline|Out-Null
                Invoke-MultipassWithStandardInput -FilePath $mp -InstanceName ([string]$Request.vaultName) -CommandArgumentList @('bash','-lc',$boundary.bootstrapCommand) -TimeoutSeconds $boundary.bootstrapMaxSeconds -DeadlineUtc $deadline -StandardInputText $secretJson|Out-Null
            } finally {$secretJson=$null;$secrets=$null}
        }
        'configure' {
            & (Join-Path $package 'windows/05-Configure-LocalVaultClient.ps1') -InstanceName ([string]$Request.primaryName)|Out-Null
        }
        'verify' {
            $identity=Get-Content -LiteralPath (Join-Path (Get-DevFleetStateRoot) 'node-identity.json') -Raw|ConvertFrom-Json
            $primary=Get-VM -Id ([guid][string]$State.identity.primaryId) -ErrorAction Stop
            $vault=Get-VM -Id ([guid][string]$State.vault.vaultId) -ErrorAction Stop
            if($primary.Name-cne[string]$Request.primaryName-or$vault.Name-cne[string]$Request.vaultName-or[string]$identity.deployment_id-cne[string]$State.identity.deploymentId){throw 'Fixture changed the installed Primary or owned Vault identity.'}
            # The product configurator has already authenticated and initialized
            # the repository. Do not print secret env contents or count this
            # setup backup as the later project's data-coverage proof.
            $check='sudo -u devfleet-backup test -r /etc/devfleet/restic.env && sudo -u devfleet-backup test -w /var/lib/devfleet/backup-status/restic-cache && sudo -u devfleet-control test -r /var/lib/devfleet/backup-status/config.json'
            Invoke-External $mp @('exec',[string]$Request.primaryName,'--','bash','-lc',$check) -TimeoutSeconds 60 -DeadlineUtc $deadline|Out-Null
            return [pscustomobject][ordered]@{status='PASS';runId=[string]$Request.runId;payloadSha256=[string]$Request.payloadSha256;primaryName=$primary.Name;primaryId=$primary.Id.ToString();primaryRole=[string]$identity.node_role;vaultName=$vault.Name;vaultId=$vault.Id.ToString();deploymentId=[string]$identity.deployment_id;configurationPresent=$true;authenticatedTransport=$true;proofCredit=$false;contract='configured-primary-vault-prerequisite-v1'}
        }
    }
}

function Initialize-MaintenanceVaultFixture {
    param([Parameter(Mandatory)]$Context)
    if([string]$Context.runId-cnotmatch'\Afullrelease-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'-or([string]$Context.runId).Length-gt128){throw 'Vault fixture requires a validated FullRelease RunId.'}
    if([guid][string]$Context.vmId-ne[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'){throw 'Vault fixture is not bound to the approved immutable L1.'}
    $workspace=[string]$Context.workspaceRoot
    $session=$null;$job=$null;$stageAttempted=$false;$primaryError=$null
    foreach($module in @('GuestSession','HarnessBudget','HostSafety','MultipassDiagnostic','TailscaleE2E')){Import-Module (Join-Path $PSScriptRoot ($module+'.psm1')) -Scope Local -DisableNameChecking}
    $vm=Get-VM -Id ([guid][string]$Context.vmId) -ErrorAction Stop
    if($vm.Name-cne[string]$Context.vmName-or$vm.Name-cne'DevFleet-E2E-Win11-01'){throw 'Vault prerequisite exact L1 identity differs.'}
    $safety=Get-HostSafetySnapshot -Vm $vm
    if(-not[bool]$safety.startSafe){throw 'Vault prerequisite requires fresh native HOST-SAFETY.'}
    $policy=Get-HarnessBudgetPolicy -Config $Context.config
    # Same finite product operations, composed once. No observer timeout or
    # acceptance threshold is increased. The worker owns exact tree termination.
    $o=$policy.operationMaximumsSeconds
    $budget=[int]$o.multipassLaunch+[int]$o.multipassReadiness+2*[int]$o.payloadTransfer+[int]$o.vaultBootstrap+[int]$o.tailscale+[int]$o.vaultClient+[int]$o.verification
    $deadline=[datetime]::UtcNow.AddSeconds($budget)
    $config=Get-Content -LiteralPath (Join-Path $workspace 'source/config/devfleet.config.json') -Raw|ConvertFrom-Json
    $request=[ordered]@{runId=[string]$Context.runId;payloadSha256=[string]$Context.candidate.tar.sha256;primaryName=[string]$config.Primary.InstanceName;vaultName=[string]$config.Vault.InstanceName;transactionId=[guid]::NewGuid().ToString('N');ownerDeadlineUtc=$deadline.ToString('o');budgetSeconds=$budget;inputHashes=[ordered]@{}}
    foreach($relative in @('cloud-init/vault.yaml')+@(Get-ChildItem -LiteralPath (Join-Path $workspace 'source/windows') -File|ForEach-Object{'windows/'+$_.Name})+@(Get-ChildItem -LiteralPath (Join-Path $workspace 'source/linux') -File|ForEach-Object{'linux/'+$_.Name})){
        $request.inputHashes[$relative]=(Get-FileHash -LiteralPath (Join-Path $workspace ('source/'+$relative)) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    try{
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        if([guid]$session.Runspace.ConnectionInfo.VMGuid-ne[guid][string]$Context.vmId){throw 'Vault prerequisite session VM identity differs.'}
        $remoteRoot="C:\ProgramData\DevFleet\tmp\maintenance-vault-$($Context.runId)"
        $request.workRoot=$remoteRoot
        Invoke-DevFleetBoundedGuestCommand -Session $session -ScriptBlock {param($Path)if(Test-Path -LiteralPath $Path){throw 'Vault prerequisite work directory already exists; no unchanged replay is allowed.'};New-Item -ItemType Directory -Path $Path -ErrorAction Stop|Out-Null} -ArgumentList @($remoteRoot) -TimeoutSeconds 30|Out-Null
        $remoteModule=Join-Path $remoteRoot 'MaintenanceVault.psm1'
        Copy-DevFleetBoundedGuestFile -Session $session -LocalPath $PSCommandPath -RemotePath $remoteModule -TimeoutSeconds 30|Out-Null
        $stageAttempted=$true
        $stage=Stage-TailscaleOAuthCredential -Session $session -RunId ([string]$Context.runId) -Config $Context.config.Tailscale -ProductConfig $config
        if([string]$stage.status-cne'PASS'-or-not[bool]$stage.staged){throw 'Vault prerequisite could not stage its existing approved OAuth provider.'}
        $expectedWindowsHostname=if($stage.profile){[string]$stage.profile.hostName}else{''}
        Write-MaintenanceVaultWindowsTailscaleSnapshot -Session $session -ExpectedHostname $expectedWindowsHostname -RunDir ([string]$Context.runDir)|Out-Null
        $json=$request|ConvertTo-Json -Depth 8 -Compress
        # Keep the full exact-input inventory out of Windows' command-line
        # length limit. This request contains only public identities/hashes.
        $localRequest=Join-Path ([string]$Context.runDir) 'maintenance-vault-request.json'
        [IO.File]::WriteAllText($localRequest,$json,[Text.UTF8Encoding]::new($false))
        $remoteRequest=Join-Path $remoteRoot 'request.json'
        $requestStage=Copy-DevFleetBoundedGuestFile -Session $session -LocalPath $localRequest -RemotePath $remoteRequest -TimeoutSeconds 30
        $body=@'
$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
if((Get-FileHash -LiteralPath '__REQUEST_PATH__' -Algorithm SHA256).Hash.ToLowerInvariant()-cne'__REQUEST_HASH__'){throw 'Fixture request identity differs.'}
$request=Get-Content -LiteralPath '__REQUEST_PATH__' -Raw|ConvertFrom-Json
if($env:COMPUTERNAME-cne'DEVFLEET-E2E-01'-or$PSVersionTable.PSVersion.Major-lt7){throw 'Approved disposable L1 PS7 is required.'}
$install=Get-Content 'C:\ProgramData\M-TechLabs\DevFleet\Installer\install-state.json' -Raw|ConvertFrom-Json
if([string]$install.PackageSha256-cne[string]$request.payloadSha256){throw 'Installed payload identity differs.'}
$package=(Get-Content 'C:\ProgramData\DevFleet\package-root.txt' -Raw).Trim()
foreach($input in $request.inputHashes.PSObject.Properties){$path=Join-Path $package $input.Name;if((Get-Item -LiteralPath $path).Attributes-band[IO.FileAttributes]::ReparsePoint-or(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$input.Value){throw 'Exact candidate prerequisite input mismatch.'}}
$request|Add-Member -NotePropertyName packageRoot -NotePropertyValue $package
Import-Module (Join-Path $package 'windows/DevFleet.Common.psm1') -Force -DisableNameChecking
Protect-DevFleetStateAcl
Import-Module (Join-Path $request.workRoot 'MaintenanceVault.psm1') -Force -DisableNameChecking
$privateLog=Join-Path $request.workRoot 'private-product-operations.log'
$privateWarningLog=Join-Path $request.workRoot 'private-product-operations.warning.tmp'
$privateVerboseLog=Join-Path $request.workRoot 'private-product-operations.verbose.tmp'
$privateDebugLog=Join-Path $request.workRoot 'private-product-operations.debug.tmp'
$privateInformationLog=Join-Path $request.workRoot 'private-product-operations.information.tmp'
$privateStreamLogs=@($privateWarningLog,$privateVerboseLog,$privateDebugLog,$privateInformationLog)
function Merge-MaintenanceVaultPrivateStreams {param([string]$Destination,[string[]]$Sources)foreach($source in $Sources){if(Test-Path -LiteralPath $source -PathType Leaf){$content=[IO.File]::ReadAllText($source);if($content.Length-gt0){[IO.File]::AppendAllText($Destination,$content,[Text.UTF8Encoding]::new($false))}}}}
try{$result=Invoke-MaintenanceVaultProvisioning -Request $request 3>$privateWarningLog 4>$privateVerboseLog 5>$privateDebugLog 6>$privateInformationLog;Merge-MaintenanceVaultPrivateStreams -Destination $privateLog -Sources $privateStreamLogs;$result|ConvertTo-Json -Depth 6 -Compress}catch{$failure=$_;try{Merge-MaintenanceVaultPrivateStreams -Destination $privateLog -Sources $privateStreamLogs}catch{};try{$failure|Out-String|Add-Content -LiteralPath $privateLog}catch{};[ordered]@{status='FAIL';errorCategory=[string]$failure.CategoryInfo.Category;errorType=$failure.Exception.GetType().FullName;scriptLine=$failure.InvocationInfo.ScriptLineNumber;message='Configured Primary Vault prerequisite failed; no proof credit.'}|ConvertTo-Json -Compress;exit 1}finally{foreach($path in $privateStreamLogs){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
'@
        $body=$body.Replace('__REQUEST_PATH__',$remoteRequest.Replace("'","''")).Replace('__REQUEST_HASH__',[string]$requestStage.localSha256)
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
        $processRequest=[ordered]@{filePath='C:\Program Files\PowerShell\7\pwsh.exe';arguments=@('-NoProfile','-NonInteractive','-EncodedCommand',$encoded);deadlineUnixMilliseconds=[DateTimeOffset]::new($deadline).ToUnixTimeMilliseconds()}|ConvertTo-Json -Depth 4 -Compress
        $job=Invoke-Command -Session $session -ScriptBlock (Get-DevFleetBoundedProcessScriptBlock) -ArgumentList @($processRequest) -AsJob
        $remaining=[int][math]::Max(1,[math]::Ceiling(($deadline-[datetime]::UtcNow).TotalSeconds)+15)
        $finished=Wait-Job -Job $job -Timeout $remaining
        if(-not$finished){throw 'Vault prerequisite owner deadline expired before its terminal result.'}
        $process=@(Receive-Job -Job $job -ErrorAction Stop)|Select-Object -Last 1
        $evidencePath=Join-Path ([string]$Context.runDir) 'maintenance-vault-process.json'
        [IO.File]::WriteAllText($evidencePath,($process|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        if([string]$process.outcome-cne'PASS'-or-not[bool]$process.outputComplete){
            try{
                Save-MaintenanceVaultPrivateFailureEvidence -Session $session -RunId ([string]$Context.runId) -RemoteRoot $remoteRoot -WorkspaceRoot $workspace -RunDir ([string]$Context.runDir) -VmId ([guid][string]$Context.vmId)|Out-Null
            } catch {
                $preservationFailure=[ordered]@{schemaVersion=1;runId=[string]$Context.runId;classification='PRIVATE_FAILURE_EVIDENCE_PRESERVATION_FAILED';message='Private failure evidence could not be preserved from the owned disposable L1.';observedAtUtc=[datetime]::UtcNow.ToString('o')}
                [IO.File]::WriteAllText((Join-Path ([string]$Context.runDir) 'private-failure-preservation-error.json'),(($preservationFailure|ConvertTo-Json -Depth 4)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            }
            throw 'Configured Primary Vault bounded worker failed; see maintenance-vault-process.json.'
        }
        $result=[string]$process.stdout|ConvertFrom-Json -ErrorAction Stop
        Assert-MaintenanceVaultResult -Result $result -Request ([pscustomobject]$request)
        if([datetime]::UtcNow-gt$deadline){throw 'Vault prerequisite result arrived after its owner deadline.'}
        return $result
    } catch {$primaryError=$_;throw
    } finally {
        if($job){Stop-Job -Job $job -ErrorAction SilentlyContinue;Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
        try{if($stageAttempted-and$session){$removed=Remove-StagedTailscaleOAuthCredential -Session $session;if([string]$removed.status-cne'PASS'){throw 'Vault prerequisite OAuth cleanup failed.'}}}catch{if($primaryError){throw [InvalidOperationException]::new(($primaryError.Exception.Message+'; Vault prerequisite OAuth cleanup also failed.'),$primaryError.Exception)};throw}finally{if($session){Remove-DevFleetGuestSession -Session $session -ErrorAction SilentlyContinue}}
    }
}

Export-ModuleMember -Function Initialize-MaintenanceVaultFixture,Invoke-MaintenanceVaultProvisioning,Assert-MaintenanceVaultResult
