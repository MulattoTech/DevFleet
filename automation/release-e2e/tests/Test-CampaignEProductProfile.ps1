[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$releaseRoot=Split-Path -Parent $PSScriptRoot;$root=Split-Path -Parent (Split-Path -Parent $releaseRoot)
Import-Module (Join-Path $releaseRoot 'modules/MultipassDiagnostic.psm1') -Force -DisableNameChecking
$worker=Join-Path $releaseRoot 'Invoke-CampaignEProductProfile.ps1';$engine=(Get-Process -Id $PID).Path
$runPrefix='astra-profile-'+[guid]::NewGuid().ToString('N');$owned=[Collections.Generic.List[string]]::new();$results=[Collections.Generic.List[object]]::new()
# Actual candidate preflight and config logic; only machine I/O/admin assertions
# are fixtures in the copied Common module and child entry, never in shipping.
$machine=@'
function Get-CimInstance {
    param($ClassName,$OperationTimeoutSec)
    switch($ClassName){
        Win32_ComputerSystem {[pscustomobject]@{TotalPhysicalMemory=16GB;NumberOfLogicalProcessors=6}}
        Win32_OperatingSystem {[pscustomobject]@{Caption='Fixture Windows 11 Pro';Version='10.0'}}
        Win32_Processor {[pscustomobject]@{Name='Fixture CPU';VirtualizationFirmwareEnabled=$true;SecondLevelAddressTranslationExtensions=$true}}
        default {throw 'Unexpected machine query.'}
    }
}
function Get-PSDrive {param($Name)[pscustomobject]@{Free=if($env:DEVFLEET_PROFILE_FIXTURE-ceq'low-disk'){1GB}else{200GB}}}
function Get-ComputerInfo {param($Property)[pscustomobject]@{WindowsProductName='Windows 11 Pro'}}
function Get-Process {param($Name) @()}
function Assert-Administrator {}
'@
try {
    foreach($case in @('success','bad-input-hash','bad-owner','active-transaction','low-disk','expired-owner','m3-success','m3-bad-template','m3-bad-name')){
        $run=$runPrefix+'-'+$case;$parent=[IO.Path]::GetFullPath("C:\Users\Public\DevFleet-E2E\$run");$remote=Join-Path $parent 'M1';$owned.Add($parent)
        New-Item -ItemType Directory -Path (Join-Path $remote 'profile-package/windows'),(Join-Path $remote 'profile-package/config'),(Join-Path $parent 'real-data/DevFleet')|Out-Null
        $nonce=[guid]::NewGuid();@{kind='DEVFLEET_CAMPAIGN_E_STAGING_OWNER';runId=$run;nonce=$nonce.ToString()}|ConvertTo-Json|Set-Content (Join-Path $remote '.owner.json')
        Copy-Item (Join-Path $root 'source/windows/00-Preflight.ps1') (Join-Path $remote 'profile-package/windows/00-Preflight.ps1')
        Copy-Item (Join-Path $root 'source/config/devfleet.config.json') (Join-Path $remote 'profile-package/config/devfleet.config.json')
        [IO.File]::WriteAllText((Join-Path $remote 'profile-package/windows/DevFleet.Common.psm1'),([IO.File]::ReadAllText((Join-Path $root 'source/windows/DevFleet.Common.psm1'))+[Environment]::NewLine+$machine+[Environment]::NewLine+'Export-ModuleMember -Function *'),[Text.UTF8Encoding]::new($false))
        $inputs=@(foreach($relative in @('windows/00-Preflight.ps1','windows/DevFleet.Common.psm1','config/devfleet.config.json')){@{path=$relative;sha256=(Get-FileHash (Join-Path $remote ('profile-package/'+$relative)) -Algorithm SHA256).Hash.ToLowerInvariant()}})
        $productLaunch=$case-like'm3-*'
        if($productLaunch){
            New-Item -ItemType Directory -Path (Join-Path $remote 'profile-package/cloud-init')|Out-Null
            Copy-Item (Join-Path $root 'source/cloud-init/compute.yaml') (Join-Path $remote 'profile-package/cloud-init/compute.yaml')
            $inputs+=@{path='cloud-init/compute.yaml';sha256=if($case-ceq'm3-bad-template'){'f'*64}else{(Get-FileHash (Join-Path $remote 'profile-package/cloud-init/compute.yaml') -Algorithm SHA256).Hash.ToLowerInvariant()}}
        }
        $deadline=[datetime]::UtcNow.AddSeconds(20);if($case-ceq'expired-owner'){$deadline=[datetime]::UtcNow.AddSeconds(-1)}
        if($case-ceq'bad-input-hash'){$inputs[0].sha256='f'*64}
        if($case-ceq'active-transaction'){'{}'|Set-Content (Join-Path $parent 'real-data/DevFleet/active-transaction.json')}
        $request=@{runId=$run;vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);remoteRoot=$remote;inputs=$inputs;stagingNonce=if($case-ceq'bad-owner'){[guid]::NewGuid().ToString()}else{$nonce.ToString()};deadlineUnixMilliseconds=[DateTimeOffset]::new($deadline).ToUnixTimeMilliseconds()}
        if($productLaunch){$request.productLaunch=$true;$request.instanceName=if($case-ceq'm3-bad-name'){'devfleet-primary'}else{"DevFleet-E2E-E-M1-$run"}}
        $entry=Join-Path $parent 'entry.ps1';$entryBody=@'
param($Worker,$Request,$Data,$Case)
$env:ProgramData=$Data;$env:DEVFLEET_PROFILE_FIXTURE=$Case
'@
        [IO.File]::WriteAllText($entry,($entryBody+[Environment]::NewLine+$machine+[Environment]::NewLine+'& $Worker -RequestBase64 $Request; exit $LASTEXITCODE'),[Text.UTF8Encoding]::new($false))
        $base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Depth 5 -Compress)))
        $probe=Invoke-DevFleetBoundedNativeProbe -Operation "profile-$case" -FilePath $engine -ArgumentList @('-NoProfile','-File',$entry,'-Worker',$worker,'-Request',$base64,'-Data',(Join-Path $parent 'real-data'),'-Case',$case) -TimeoutSeconds 15 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(20)) -ForceLegacyArgumentString -MaxStdoutCharacters 32768
        $path=Join-Path $remote 'product-profile.json';$profile=if(Test-Path $path){Get-Content $path -Raw|ConvertFrom-Json}else{$probe.stdout|ConvertFrom-Json}
        $pass=$true
        if($case-cin@('success','m3-success')){
            $pass=$probe.exitCode-eq0-and$profile.status-ceq'PASS_PROFILE_ONLY'-and[int]$profile.resources.cpus-eq4-and$profile.resources.memory-ceq'9G'-and$profile.resources.disk-ceq'220G'-and$profile.ubuntuImage-ceq'24.04'
            Assert-DevFleetCampaignEProductProfile -Profile $profile -ExpectedRunId $run -ExpectedVmId ([guid]$request.vmId) -ExpectedPayloadSha256 $request.payloadSha256 -ExpectedInputs $inputs -DeadlineUtc $deadline -ExpectedProductLaunch:$productLaunch|Out-Null
            if($productLaunch){
                $cloud=Join-Path $remote 'product-cloud-init.yaml';$rendered=Get-Content $cloud -Raw
                $pass=$pass-and(Get-FileHash $cloud -Algorithm SHA256).Hash.ToLowerInvariant()-ceq$profile.productLaunch.cloudInitSha256-and$rendered-match([regex]::Escape($request.instanceName))-and$rendered-notmatch'__(NODE|GIT)_'-and$rendered-match'package_update: true'
                $plainRejected=$false;try{Assert-DevFleetCampaignEProductProfile -Profile $profile -ExpectedRunId $run -ExpectedVmId ([guid]$request.vmId) -ExpectedPayloadSha256 $request.payloadSha256 -ExpectedInputs $inputs -DeadlineUtc $deadline|Out-Null}catch{$plainRejected=$true};$pass=$pass-and$plainRejected
            }
        }else{$pass=$probe.exitCode-eq1-and$profile.status-ceq'BLOCKED'-and-not[string]::IsNullOrWhiteSpace([string]$profile.primaryError)}
        $pass=$pass-and-not(Test-Path (Join-Path $parent 'real-data/DevFleet/devfleet.config.json'))-and-not[bool]$profile.productLifecycleStarted
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;exitCode=$probe.exitCode;error=$profile.primaryError})
    }
}finally{
    foreach($path in $owned){if(-not$path.StartsWith('C:\Users\Public\DevFleet-E2E\'+$runPrefix,[StringComparison]::Ordinal)){throw 'Profile fixture cleanup escaped ownership.'};if(Test-Path $path){Remove-Item -LiteralPath $path -Recurse -Force}}
}
$results|ConvertTo-Json -Depth 3
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual candidate preflight profile regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) actual candidate preflight profile checks"
