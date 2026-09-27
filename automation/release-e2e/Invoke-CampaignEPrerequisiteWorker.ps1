[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Get-PendingRebootProjection {
    $cbs=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $wu=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $value=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    $raw=@();if($null-ne$value){$raw=@($value.PendingFileRenameOperations)}
    $pairs=[Collections.Generic.List[string]]::new()
    for($index=0;$index-lt$raw.Count;$index+=2){$source=[string]$raw[$index];$destination=if($index+1-lt$raw.Count){[string]$raw[$index+1]}else{''};if($source-or$destination){[void]$pairs.Add("$source`n$destination")}}
    [ordered]@{CbsPending=[bool]$cbs;WindowsUpdatePending=[bool]$wu;PendingPairs=[string[]]$pairs}
}

function Get-ProductBoundary {
    $root=Join-Path $env:ProgramData 'DevFleet'
    [ordered]@{
        activeTransactionPresent=Test-Path -LiteralPath (Join-Path $root 'active-transaction.json') -PathType Leaf
        stageMarkerCount=@(Get-ChildItem -LiteralPath $root -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count
        activeInstallProcessCount=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{[string]$_.Name-in@('DevFleet.Setup.exe','pwsh.exe','powershell.exe')-and[uint32]$_.ProcessId-ne[uint32]$PID-and[string]$_.CommandLine-match'(?i)Install-DevFleet|Bootstrap-Install|DevFleet.Setup'}).Count
    }
}

function Write-FreshAtomicJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    if(Test-Path -LiteralPath $Path){throw 'Campaign E final worker result path already exists.'}
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try{[IO.File]::WriteAllBytes($temporary,[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 24 -Compress)));[IO.File]::Move($temporary,$Path)}finally{Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}

$request=$null
$ownerDeadline=[datetime]::MinValue
$validatedRemoteRoot=''
$campaignEAcquisitionState=[pscustomobject]@{pwshPath='';nativeTrace=[Collections.Generic.List[object]]::new();identity=$null}
try {
    $requestJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))
    $request=$requestJson|ConvertFrom-Json -ErrorAction Stop
    if([string]$request.runId-notmatch'^[A-Za-z0-9._-]+$'){throw 'Campaign E prerequisite run identity is invalid.'}
    $remoteRoot=[IO.Path]::GetFullPath([string]$request.remoteRoot).TrimEnd('\')
    if($remoteRoot-notlike'C:\Users\Public\DevFleet-E2E\*\Prerequisite'){throw 'Campaign E prerequisite root is outside the run-owned boundary.'}
    $validatedRemoteRoot=$remoteRoot
    foreach($property in @('candidateTarPath','diagnosticModulePath','innerWorkerPath','powerShellPayloadPath')){
        $resolved=[IO.Path]::GetFullPath([string]$request.$property)
        if(-not$resolved.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Campaign E prerequisite input escaped the run-owned root: $property"}
    }
    $ownerDeadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.ownerDeadlineUnixMilliseconds).UtcDateTime
    $started=[datetime]::UtcNow
    if($ownerDeadline-le$started){throw 'Campaign E prerequisite owner deadline expired before worker start.'}
    Import-Module ([string]$request.diagnosticModulePath) -Force -ErrorAction Stop
    $policyBefore=Get-DevFleetSystemExecutionPolicyProjection
    $boundaryBefore=Get-ProductBoundary
    if([bool]$boundaryBefore.activeTransactionPresent-or[int]$boundaryBefore.stageMarkerCount-ne0-or[int]$boundaryBefore.activeInstallProcessCount-ne0){throw 'Campaign E prerequisite preparation requires a transactionless, marker-free, quiescent product boundary.'}
    $tarPath=[string]$request.candidateTarPath
    if(-not(Test-Path -LiteralPath $tarPath -PathType Leaf)-or(Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$request.payloadSha256){throw 'Staged candidate TAR payload identity mismatch.'}
    $tarExe=Join-Path $env:SystemRoot 'System32\tar.exe'
    if(-not(Test-Path -LiteralPath $tarExe -PathType Leaf)){throw 'In-box tar.exe is unavailable.'}
    $listProbe=Invoke-DevFleetBoundedNativeProbe -Operation 'candidate-archive-list' -FilePath $tarExe -ArgumentList @('-tf',$tarPath) -TimeoutSeconds 120 -OwnerDeadlineUtc $ownerDeadline -ForceLegacyArgumentString -MaxStdoutCharacters 262144
    if([string]$listProbe.outcome-cne'PASS'-or[bool]$listProbe.stdoutTruncated){throw "Candidate archive listing failed: $(ConvertTo-DevFleetDiagnosticSafeText $listProbe.stderr)"}
    $entries=@([string]$listProbe.stdout-split"`r?`n"|Where-Object{$_})
    Assert-DevFleetCampaignEArchiveEntries -Entries $entries|Out-Null
    $packageRoot=Join-Path $remoteRoot 'candidate-package'
    if(Test-Path -LiteralPath $packageRoot){throw 'Campaign E candidate extraction path already exists.'}
    New-Item -ItemType Directory -Path $packageRoot|Out-Null
    $extractProbe=Invoke-DevFleetBoundedNativeProbe -Operation 'candidate-archive-extract' -FilePath $tarExe -ArgumentList @('-xf',$tarPath,'-C',$packageRoot) -TimeoutSeconds 180 -OwnerDeadlineUtc $ownerDeadline -ForceLegacyArgumentString
    if([string]$extractProbe.outcome-cne'PASS'){throw "Candidate archive extraction failed: $(ConvertTo-DevFleetDiagnosticSafeText $extractProbe.stderr)"}
    $plan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot $packageRoot -Role ([string]$request.role)
    foreach($name in @('version','dependencies','config','bootstrap','install','common')){if([string]$plan.inputHashes.$name-cne[string]$request.inputHashes.$name){throw "Extracted candidate prerequisite hash mismatch: $name"}}
    $pendingBaseline=Get-PendingRebootProjection
    $candidateCommon=Join-Path $packageRoot 'windows\DevFleet.Common.psm1'
    Import-Module $candidateCommon -Force -Global -ErrorAction Stop
    $manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'dependencies.json') -Raw|ConvertFrom-Json -ErrorAction Stop
    $powerShellDependencies=@($manifest.dependencies|Where-Object{[string]$_.id-ceq'powershell7'})
    if($powerShellDependencies.Count-ne1){throw 'Candidate PowerShell dependency identity is not unique.'}
    $powerShellDependency=$powerShellDependencies[0]
    $powerShellPayload=$request.powerShellPayload
    $powerShellPayloadPath=[IO.Path]::GetFullPath([string]$request.powerShellPayloadPath)
    if($null-eq$powerShellPayload-or[string]$powerShellPayload.kind-cne'DEVFLEET_CAMPAIGN_E_OFFICIAL_POWERSHELL_PAYLOAD'-or[string]$powerShellPayload.status-cne'PASS'-or[string]$powerShellPayload.method-cne'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'-or[string]$powerShellPayload.packageId-cne'Microsoft.PowerShell'-or[bool]$powerShellPayload.productLifecycleStarted-or[bool]$powerShellPayload.stageMarkerWritten){throw 'Staged official PowerShell payload evidence is missing or malformed.'}
    if(-not(Test-Path -LiteralPath $powerShellPayloadPath -PathType Leaf)-or[IO.Path]::GetFileName($powerShellPayloadPath)-cne[string]$powerShellPayload.assetName-or(Get-FileHash -LiteralPath $powerShellPayloadPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$powerShellPayload.sha256){throw 'Staged official PowerShell payload identity mismatch.'}
    $script:campaignEPwshPath=''
    $compatibilityProvider={
        param($dependency,$deadline)
        $first=$null
        foreach($path in @(Get-TrustedDependencyCandidates $dependency)){
            $remaining=[int][math]::Floor((([datetime]$deadline).ToUniversalTime()-[datetime]::UtcNow).TotalSeconds)
            if($remaining-le0){return [pscustomobject]@{status='Broken';version='';pathSha256='';detail='Owner deadline expired before PowerShell compatibility probe.'}}
            $probe=Invoke-DevFleetBoundedNativeProbe -Operation 'powershell-version' -FilePath ([string]$path) -ArgumentList @($dependency.versionProbe.arguments) -TimeoutSeconds ([math]::Min(60,$remaining)) -OwnerDeadlineUtc ([datetime]$deadline) -ForceLegacyArgumentString
            if([string]$probe.outcome-cne'PASS'){$first=[pscustomobject]@{status='Broken';version='';pathSha256='';detail='Trusted PowerShell version probe failed.'};continue}
            $match=[regex]::Match([string]$probe.stdout,[string]$dependency.versionProbe.regex)
            if(-not$match.Success){$first=[pscustomobject]@{status='Broken';version='';pathSha256='';detail='Trusted PowerShell version response was malformed.'};continue}
            $version=[Version]$match.Groups[1].Value
            $status=if($version-lt[Version][string]$dependency.minimumSupportedVersion){'Outdated'}elseif($null-ne$dependency.maximumMajor-and$version.Major-gt[int]$dependency.maximumMajor){'Unsupported-Major'}else{'Compatible'}
            $value=[pscustomobject]@{status=$status;version=$version.ToString();pathSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();detail='Candidate-trusted executable and bounded version probe.'}
            if($status-ceq'Compatible'){$campaignEAcquisitionState.pwshPath=[string]$path;return $value}
            if($null-eq$first){$first=$value}
        }
        if($null-ne$first){return $first}
        return [pscustomobject]@{status='Missing';version='';pathSha256='';detail='No candidate-trusted PowerShell executable was found.'}
    }.GetNewClosure()
    $authenticityProvider={
        param($payloadPath,$policy)
        Test-OfficialSigner -Path $payloadPath -Policy $policy
        $signature=Get-AuthenticodeSignature -LiteralPath $payloadPath
        [pscustomobject]@{status=$signature.Status.ToString();signerSubject=if($signature.SignerCertificate){[string]$signature.SignerCertificate.Subject}else{''}}
    }.GetNewClosure()
    $installerProvider={
        param($payloadPath,$arguments,$timeoutSeconds,$deadline)
        $msiexec=Join-Path $env:SystemRoot 'System32\msiexec.exe'
        if(-not(Test-TrustedExecutableCandidate -Path $msiexec)){throw 'Candidate-trusted system msiexec.exe is unavailable.'}
        if($null-eq$campaignEAcquisitionState.identity){$campaignEAcquisitionState.identity=[pscustomobject]@{method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId=[string]$powerShellDependency.wingetPackageId;payloadSha256=[string]$powerShellPayload.sha256;assetName=[string]$powerShellPayload.assetName;ownerDeadlineUtc=([datetime]$deadline).ToUniversalTime().ToString('o')}}
        $observation=Invoke-DevFleetBoundedNativeProbe -Operation 'official-powershell-msi-install' -FilePath $msiexec -ArgumentList @($arguments) -TimeoutSeconds $timeoutSeconds -OwnerDeadlineUtc $deadline -ForceLegacyArgumentString -MaxStdoutCharacters 32768 -MaxStderrCharacters 8192
        [void]$campaignEAcquisitionState.nativeTrace.Add([pscustomobject][ordered]@{operation=[string]$observation.operation;outcome=[string]$observation.outcome;exitCode=$observation.exitCode;pid=$observation.pid;startedAtUtc=[string]$observation.startedAtUtc;finishedAtUtc=[string]$observation.finishedAtUtc;deadlineUtc=[string]$observation.deadlineUtc;outputComplete=[bool]$observation.outputComplete})
        return $observation
    }.GetNewClosure()
    $campaignEAcquisitionState.identity=[pscustomobject]@{method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId=[string]$powerShellDependency.wingetPackageId;payloadSha256=[string]$powerShellPayload.sha256;assetName=[string]$powerShellPayload.assetName;ownerDeadlineUtc=$ownerDeadline.ToString('o')}
    $acquisition=Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powerShellDependency -PayloadEvidence $powerShellPayload -PayloadPath $powerShellPayloadPath -OwnerDeadlineUtc $ownerDeadline -AuthenticityProvider $authenticityProvider -InstallerProvider $installerProvider -PowerShellCompatibilityProvider $compatibilityProvider
    if([string]$acquisition.status-cne'PASS'-or[bool]$acquisition.productLifecycleStarted-or[bool]$acquisition.stageMarkerWritten){throw 'Campaign E PowerShell acquisition failed or crossed the product boundary.'}
    if([string]::IsNullOrWhiteSpace([string]$campaignEAcquisitionState.pwshPath)-or-not(Test-Path -LiteralPath ([string]$campaignEAcquisitionState.pwshPath) -PathType Leaf)){throw 'Campaign E PowerShell acquisition did not leave one candidate-compatible trusted pwsh.exe path.'}
    $innerResultPath=Join-Path $remoteRoot 'prerequisite-result.json'
    $innerRequest=[ordered]@{runId=[string]$request.runId;vmId=[string]$request.vmId;remoteRoot=$remoteRoot;packageRoot=$packageRoot;diagnosticModulePath=[string]$request.diagnosticModulePath;resultPath=$innerResultPath;role=[string]$request.role;payloadSha256=[string]$request.payloadSha256;inputHashes=$plan.inputHashes;ownerDeadlineUnixMilliseconds=[DateTimeOffset]::new($ownerDeadline).ToUnixTimeMilliseconds();pendingRebootBaseline=$pendingBaseline}|ConvertTo-Json -Depth 8 -Compress
    $innerBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($innerRequest))
    $innerArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',[string]$request.innerWorkerPath,'-RequestBase64',$innerBase64)
    $innerSeconds=[int][math]::Min(1200,[math]::Max(1,[math]::Floor(($ownerDeadline-[datetime]::UtcNow).TotalSeconds)))
    $innerProbe=Invoke-DevFleetBoundedNativeProbe -Operation 'candidate-multipass-prerequisite' -FilePath ([string]$campaignEAcquisitionState.pwshPath) -ArgumentList $innerArgs -TimeoutSeconds $innerSeconds -OwnerDeadlineUtc $ownerDeadline -ForceLegacyArgumentString -MaxStdoutCharacters 32768 -MaxStderrCharacters 8192
    if(-not(Test-Path -LiteralPath $innerResultPath -PathType Leaf)){throw "Candidate Multipass prerequisite worker did not publish a result: $(ConvertTo-DevFleetDiagnosticSafeText $innerProbe.stderr 1024)"}
    $result=Get-Content -LiteralPath $innerResultPath -Raw|ConvertFrom-Json -ErrorAction Stop
    $policyAfter=Get-DevFleetSystemExecutionPolicyProjection
    $systemChanged=($policyBefore|ConvertTo-Json -Compress)-cne($policyAfter|ConvertTo-Json -Compress)
    $result.systemPolicyChanged=[bool]$systemChanged
    $result|Add-Member -NotePropertyName powershellAcquisition -NotePropertyValue $acquisition -Force
    $result|Add-Member -NotePropertyName worker -NotePropertyValue ([pscustomobject][ordered]@{outcome=[string]$innerProbe.outcome;pid=$innerProbe.pid;startedAtUtc=[string]$innerProbe.startedAtUtc;finishedAtUtc=[string]$innerProbe.finishedAtUtc;outputComplete=[bool]$innerProbe.outputComplete}) -Force
    $result.startedAtUtc=$started.ToString('o')
    $result.producedAtUtc=[datetime]::UtcNow.ToString('o')
    if(([datetime]$result.producedAtUtc).ToUniversalTime()-gt$ownerDeadline){throw 'Campaign E prerequisite result publication crossed the immutable owner deadline.'}
    Write-FreshAtomicJson -Path (Join-Path $remoteRoot 'prerequisite-worker-result.json') -Value $result
    if([datetime]::UtcNow-gt$ownerDeadline){throw 'Campaign E durable prerequisite result completed after the immutable owner deadline.'}
    [Console]::Out.Write(($result|ConvertTo-Json -Depth 20 -Compress))
    if([string]$innerProbe.outcome-cne'PASS'-or$systemChanged){exit 1}
} catch {
    $message=[regex]::Replace([string]$_.Exception.Message,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    if($null-ne$request-and$validatedRemoteRoot-and(Test-Path -LiteralPath $validatedRemoteRoot -PathType Container)){
        $primaryError=if($message.Length-gt1024){$message.Substring($message.Length-1024)}else{$message}
        $failure=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_FAILURE';status='BLOCKED';runId=[string]$request.runId;vmId=[string]$request.vmId;payloadSha256=[string]$request.payloadSha256;producedAtUtc=[datetime]::UtcNow.ToString('o');ownerDeadlineUtc=if($ownerDeadline-gt[datetime]::MinValue){$ownerDeadline.ToUniversalTime().ToString('o')}else{''};primaryError=$primaryError;powershellAcquisition=[ordered]@{status='BLOCKED';identity=$campaignEAcquisitionState.identity;operations=@($campaignEAcquisitionState.nativeTrace);productLifecycleStarted=$false;stageMarkerWritten=$false}}
        $failurePath=Join-Path $validatedRemoteRoot 'prerequisite-failure.json';$failureTmp="$failurePath.$([guid]::NewGuid().ToString('N')).tmp"
        try{$failure|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $failureTmp -Encoding UTF8;[IO.File]::Move($failureTmp,$failurePath)}catch{Remove-Item -LiteralPath $failureTmp -Force -ErrorAction SilentlyContinue}
        [Console]::Out.Write(($failure|ConvertTo-Json -Depth 12 -Compress))
    }
    [Console]::Error.Write($message)
    exit 1
}
