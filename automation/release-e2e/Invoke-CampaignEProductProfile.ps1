[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$originalData=$env:ProgramData;$resultPath='';$request=$null
$result=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PRODUCT_PROFILE';status='BLOCKED';startedAtUtc=[datetime]::UtcNow.ToString('o');productLifecycleStarted=$false;primaryError=''}
try {
    $request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))|ConvertFrom-Json -ErrorAction Stop
    $run=[string]$request.runId;$vm=[guid][string]$request.vmId;$payload=[string]$request.payloadSha256
    if($run-notmatch'^[A-Za-z0-9._-]+$'-or$vm-ne[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'-or$payload-notmatch'^[0-9a-f]{64}$'){throw 'Product profile identity is invalid.'}
    $remoteRoot=[IO.Path]::GetFullPath([string]$request.remoteRoot).TrimEnd('\')
    if($remoteRoot-cne"C:\Users\Public\DevFleet-E2E\$run\M1"){throw 'Product profile escaped the exact run staging path.'}
    $ancestor=$remoteRoot
    while($ancestor.Length-ge'C:\Users\Public\DevFleet-E2E'.Length){if((Get-Item -LiteralPath $ancestor).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Product profile staging ancestry is a reparse point.'};$ancestor=Split-Path -Parent $ancestor}
    $ownership=Get-Content (Join-Path $remoteRoot '.owner.json') -Raw|ConvertFrom-Json
    if([string]$ownership.kind-cne'DEVFLEET_CAMPAIGN_E_STAGING_OWNER'-or[string]$ownership.runId-cne$run-or[guid][string]$ownership.nonce-ne[guid][string]$request.stagingNonce){throw 'Product profile staging ownership mismatch.'}
    $resultPath=Join-Path $remoteRoot 'product-profile.json'
    $deadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.deadlineUnixMilliseconds).UtcDateTime
    if($deadline-le[datetime]::UtcNow){throw 'Product profile owner expired.'}
    $result.runId=$run;$result.vmId=$vm.ToString();$result.payloadSha256=$payload;$result.ownerDeadlineUtc=$deadline.ToString('o')
    $required=@('windows/00-Preflight.ps1','windows/DevFleet.Common.psm1','config/devfleet.config.json')
    $productLaunch=$request.PSObject.Properties['productLaunch']-and[bool]$request.productLaunch
    if($productLaunch){$required+='cloud-init/compute.yaml'}
    $inputs=@($request.inputs)
    if($inputs.Count-ne$required.Count){throw 'Product profile input count is invalid.'}
    $package=Join-Path $remoteRoot 'profile-package'
    foreach($directory in @($package,(Join-Path $package 'windows'),(Join-Path $package 'config'))){if((Get-Item -LiteralPath $directory).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Product profile package directory is a reparse point.'}}
    if($productLaunch-and((Get-Item -LiteralPath (Join-Path $package 'cloud-init')).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Product cloud-init directory is a reparse point.'}
    foreach($relative in $required){
        $entry=@($inputs|Where-Object{[string]$_.path-ceq$relative})
        if($entry.Count-ne1-or[string]$entry[0].sha256-notmatch'^[0-9a-f]{64}$'){throw 'Product profile exact input binding is missing.'}
        $path=Join-Path $package $relative
        if((Get-Item -LiteralPath $path).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Product profile input is a reparse point.'}
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$entry[0].sha256){throw 'Product profile candidate input hash mismatch.'}
    }
    $realState=Join-Path $originalData 'DevFleet'
    if((Test-Path (Join-Path $realState 'active-transaction.json'))-or@(Get-ChildItem $realState -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count){throw 'Product profile requires a transactionless marker-free diagnostic baseline.'}
    $data=Join-Path $remoteRoot 'profile-data'
    if(Test-Path $data){throw 'Product profile isolated state already exists.'}
    New-Item -ItemType Directory -Path (Join-Path $data 'DevFleet') | Out-Null
    Copy-Item -LiteralPath (Join-Path $package 'config/devfleet.config.json') -Destination (Join-Path $data 'DevFleet/devfleet.config.json')
    $configInput=@($inputs|Where-Object{$_.path-ceq'config/devfleet.config.json'})[0]
    if((Get-FileHash (Join-Path $data 'DevFleet/devfleet.config.json') -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$configInput.sha256){throw 'Product profile copied configuration hash mismatch.'}
    $system=Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop
    $result.measured=[ordered]@{totalPhysicalMemoryBytes=[int64]$system.TotalPhysicalMemory;logicalProcessors=[int]$system.NumberOfLogicalProcessors}
    # Run the actual candidate preflight. Only its config destination is isolated;
    # CPU/RAM/virtualization/disk observations are the real disposable Windows guest.
    $env:ProgramData=$data
    & (Join-Path $package 'windows/00-Preflight.ps1') -Role Desktop -InstallationMode Connected | Out-Null
    $effective=Get-Content (Join-Path $data 'DevFleet/devfleet.config.json') -Raw|ConvertFrom-Json
    $node=$effective.Primary
    if([int]$node.Cpus-lt2-or[string]$node.Memory-notmatch'^\d+G$'-or[string]$node.Disk-notmatch'^\d+G$'-or[string]$node.UbuntuImage-notmatch'^\d+\.\d+$'){throw 'Actual preflight produced an unsupported launch profile.'}
    if([datetime]::UtcNow-gt$deadline){throw 'Product profile finished after its immutable owner deadline.'}
    $result.resources=[ordered]@{cpus=[int]$node.Cpus;memory=[string]$node.Memory;disk=[string]$node.Disk}
    if($productLaunch){
        $name=[string]$request.instanceName
        if($name-cne"DevFleet-E2E-E-M1-$run"){throw 'Product cloud-init requires the exact run-owned instance name.'}
        # Same candidate template and scalar helpers as 02-Provision-ComputeNode.
        # Only the diagnostic hostname and isolated output destination differ.
        $cloud=Join-Path $remoteRoot 'product-cloud-init.yaml'
        if(Test-Path $cloud){throw 'Product cloud-init output already exists.'}
        $template=Get-Content (Join-Path $package 'cloud-init/compute.yaml') -Raw
        $template=$template.Replace('__NODE_NAME__',(ConvertTo-YamlSingleQuotedScalar $name)).Replace('__NODE_ROLE__',(ConvertTo-YamlSingleQuotedScalar 'primary')).Replace('__GIT_NAME_SHELL__',(ConvertTo-ShellSingleQuotedScalar $effective.Git.UserName)).Replace('__GIT_EMAIL_SHELL__',(ConvertTo-ShellSingleQuotedScalar $effective.Git.Email))
        Set-Content -LiteralPath $cloud -Value $template -Encoding utf8
        $result.productLaunch=[ordered]@{mode='CANDIDATE_CLOUD_INIT_AND_INVOKE_EXTERNAL';cloudInitFileName='product-cloud-init.yaml';cloudInitSha256=(Get-FileHash $cloud -Algorithm SHA256).Hash.ToLowerInvariant();instanceName=$name;nodeRole='primary';productTransactionStarted=$false;stageMarkerWritten=$false}
    }
    if([datetime]::UtcNow-gt$deadline){throw 'Product profile/render finished after its immutable owner deadline.'}
    $result.ubuntuImage=[string]$node.UbuntuImage;$result.productInstanceName=[string]$node.InstanceName
    $result.inputs=$inputs;$result.preflightConfigSha256=(Get-FileHash (Join-Path $data 'DevFleet/devfleet.config.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.childRuntime=$PSVersionTable.PSVersion.ToString();$result.status='PASS_PROFILE_ONLY'
} catch {
    $message=[regex]::Replace([string]$_.Exception.Message,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    $result.primaryError=if($message.Length-gt1024){$message.Substring($message.Length-1024)}else{$message}
} finally {
    $env:ProgramData=$originalData
    $result.producedAtUtc=[datetime]::UtcNow.ToString('o')
    if($resultPath){
        if(Test-Path -LiteralPath $resultPath){throw 'Product profile refuses to overwrite a durable result.'}
        $tmp=$resultPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try{[IO.File]::WriteAllText($tmp,($result|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false));[IO.File]::Move($tmp,$resultPath)}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
    }
    [Console]::Out.Write(($result|ConvertTo-Json -Depth 10 -Compress))
}
if([string]$result.status-cne'PASS_PROFILE_ONLY'){exit 1}
