# DevFleet source part 019

Full-source UTF-8 byte interval [837000, 883500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: daa696ad79875c305e3a4f4000d8f3b92c3ab4945db21165cdf00260ffae20f4

<!-- BEGIN SOURCE SLICE -->
n.operation-ceq'winget-version'-and[string]$raw.stdout-notmatch'(?<!\d)\d+\.\d+(?:\.\d+){0,2}'){throw 'Campaign E PowerShell acquisition could not parse the bounded WinGet version response.'}
        if([bool]$specification.requirePackageId-and[string]$raw.stdout-notmatch[regex]::Escape([string]$Dependency.wingetPackageId)){throw 'Campaign E PowerShell acquisition search did not identify the exact manifest-approved package.'}
        [void]$observations.Add([pscustomobject][ordered]@{operation=[string]$raw.operation;outcome=[string]$raw.outcome;exitCode=$raw.exitCode;startedAtUtc=[string]$raw.startedAtUtc;finishedAtUtc=[string]$raw.finishedAtUtc;deadlineUtc=[string]$raw.deadlineUtc;outputComplete=[bool]$raw.outputComplete;packageIdentityObserved=if([bool]$specification.requirePackageId){$true}else{$null}})
        $lastFinished=$rawFinished
    }
    $final=&$PowerShellCompatibilityProvider $Dependency $owner
    if(-not(&$validateCompatibility $final)){throw 'Campaign E PowerShell acquisition completed without a candidate-compatible PowerShell executable.'}
    $finished=&$now
    if($finished-gt$owner){throw 'Campaign E PowerShell acquisition completed after its immutable owner deadline.'}
    return [pscustomobject][ordered]@{
        schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='WINGET_MANIFEST_APPROVED_DIAGNOSTIC'
        packageId=[string]$Dependency.wingetPackageId;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');ownerDeadlineUtc=$owner.ToString('o')
        wingetPathSha256=$wingetHash;operations=@($observations);powershell=[pscustomobject]@{status='Compatible';version=[string]$final.version;pathSha256=[string]$final.pathSha256}
        productLifecycleStarted=$false;stageMarkerWritten=$false
    }
}

function Test-DevFleetCampaignEExactSignerSubject {
    param([Parameter(Mandatory)][string]$Actual,[Parameter(Mandatory)][string[]]$Expected)
    $normalize={param([string]$Value)try{(([Security.Cryptography.X509Certificates.X500DistinguishedName]::new($Value)).Format($false)-replace'\s','').ToUpperInvariant()}catch{($Value-replace'\s','').ToUpperInvariant()}}
    $actualNormalized=&$normalize $Actual
    return @($Expected|Where-Object{(&$normalize ([string]$_))-ceq$actualNormalized}).Count-eq1
}

function Save-DevFleetCampaignEAllowlistedHttpsDownload {
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][string[]]$AllowedHosts,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [ValidateRange(60,1200)][int]$MaximumSeconds=900
    )
    $started=[datetime]::UtcNow;$owner=$OwnerDeadlineUtc.ToUniversalTime();$deadline=$started.AddSeconds($MaximumSeconds);if($deadline-gt$owner){$deadline=$owner}
    if($deadline-le$started){throw 'Campaign E official download owner deadline expired before transfer.'}
    if(Test-Path -LiteralPath $Path){throw 'Campaign E official download destination already exists.'}
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp";$current=$Uri;$redirectHosts=[Collections.Generic.List[string]]::new()
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false;$client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[Threading.Timeout]::InfiniteTimeSpan
    try {
        for($hop=0;$hop-le5;$hop++){
            if($current.Scheme-cne'https'-or$current.UserInfo-or@($AllowedHosts)-cnotcontains$current.Host){throw 'Campaign E official download left the allowlisted HTTPS boundary.'}
            [void]$redirectHosts.Add($current.Host)
            $remaining=($deadline-[datetime]::UtcNow)
            if($remaining.TotalMilliseconds-le0){throw 'Campaign E official download exceeded its inherited finite deadline.'}
            $cts=[Threading.CancellationTokenSource]::new($remaining);$response=$null;$input=$null;$output=$null
            try {
                $response=$client.GetAsync($current,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cts.Token).GetAwaiter().GetResult()
                if([int]$response.StatusCode-ge300-and[int]$response.StatusCode-le399){$location=$response.Headers.Location;if(-not$location){throw 'Campaign E official download redirect omitted Location.'};$current=[uri]::new($current,$location);continue}
                if(-not$response.IsSuccessStatusCode){throw "Campaign E official download failed with HTTP $([int]$response.StatusCode)."}
                $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult();$output=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                [void]$input.CopyToAsync($output,81920,$cts.Token).GetAwaiter().GetResult();$output.Flush($true);$output.Dispose();$output=$null
                [IO.File]::Move($temporary,$Path)
                $finished=[datetime]::UtcNow
                return [pscustomobject][ordered]@{outcome='PASS';startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$deadline.ToString('o');finalHost=$current.Host;redirectHosts=@($redirectHosts);bytes=(Get-Item -LiteralPath $Path).Length;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
            } finally {if($output){$output.Dispose()};if($input){$input.Dispose()};if($response){$response.Dispose()};$cts.Dispose()}
        }
        throw 'Campaign E official download exceeded the redirect limit.'
    } finally {$client.Dispose();$handler.Dispose();Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}

function Get-DevFleetCampaignEOfficialPowerShellPayload {
    param(
        [Parameter(Mandatory)][psobject]$Dependency,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [scriptblock]$MetadataProvider,
        [scriptblock]$DownloadProvider,
        [scriptblock]$AuthenticityProvider,
        [scriptblock]$ClockProvider
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}};$started=&$now;$owner=$OwnerDeadlineUtc.ToUniversalTime()
    if($owner-le$started){throw 'Campaign E official PowerShell acquisition owner deadline expired before metadata.'}
    if([string]$Dependency.id-cne'powershell7'-or[string]$Dependency.wingetPackageId-cne'Microsoft.PowerShell'-or[string]$Dependency.directOfficialVendorResolver.type-cne'github-release'){throw 'Campaign E official PowerShell dependency identity/resolver is unsupported.'}
    $resolver=$Dependency.directOfficialVendorResolver;$metadataUri=[uri][string]$resolver.metadataUri
    if($metadataUri.Scheme-cne'https'-or$metadataUri.UserInfo-or$metadataUri.AbsolutePath-cne'/repos/PowerShell/PowerShell/releases/latest'-or@($resolver.allowedHosts)-cnotcontains$metadataUri.Host){throw 'Campaign E official PowerShell metadata identity is invalid.'}
    $remaining=[int][math]::Floor(($owner-(&$now)).TotalSeconds);if($remaining-le0){throw 'Campaign E official PowerShell acquisition owner deadline expired before metadata request.'}
    $metadata=if($MetadataProvider){&$MetadataProvider $metadataUri ([math]::Min(60,$remaining)) $owner}else{Invoke-RestMethod -UseBasicParsing -TimeoutSec ([math]::Min(60,$remaining)) -Uri $metadataUri -Headers @{'User-Agent'='DevFleet-Campaign-E/1.2.13'}}
    $metadataFinished=&$now
    if($metadataFinished-gt$owner){throw 'Campaign E official PowerShell metadata arrived after the immutable owner deadline.'}
    if(-not$metadata-or[bool]$metadata.prerelease-or[bool]$metadata.draft-or[string]$metadata.tag_name-notmatch'^v7\.\d+\.\d+$'){throw 'Campaign E official PowerShell release metadata is unusable.'}
    $releasePage=[uri][string]$metadata.html_url
    if($releasePage.Scheme-cne'https'-or$releasePage.Host-cne'github.com'-or-not$releasePage.AbsolutePath.StartsWith('/PowerShell/PowerShell/releases/tag/',[StringComparison]::Ordinal)){throw 'Campaign E official PowerShell release repository identity mismatch.'}
    $assets=@($metadata.assets|Where-Object{[string]$_.name-match[string]$resolver.assetRegex})
    if($assets.Count-ne1){throw 'Campaign E official PowerShell release did not contain one canonical x64 MSI.'}
    $asset=$assets[0];$assetName=[string]$asset.name;$assetUri=[uri][string]$asset.browser_download_url
    $expectedPathPrefix="/PowerShell/PowerShell/releases/download/$([string]$metadata.tag_name)/"
    if($assetUri.Scheme-cne'https'-or$assetUri.UserInfo-or@($resolver.allowedHosts)-cnotcontains$assetUri.Host-or-not$assetUri.AbsolutePath.StartsWith($expectedPathPrefix,[StringComparison]::Ordinal)-or[IO.Path]::GetFileName($assetUri.AbsolutePath)-cne$assetName-or[IO.Path]::GetExtension($assetName)-cne'.msi'){throw 'Campaign E official PowerShell asset identity is invalid.'}
    $destinationRoot=[IO.Path]::GetFullPath($DestinationDirectory).TrimEnd('\');if(-not(Test-Path -LiteralPath $destinationRoot -PathType Container)){throw 'Campaign E official PowerShell destination root is absent.'}
    $DestinationPath=Join-Path $destinationRoot $assetName
    if(Test-Path -LiteralPath $DestinationPath){throw 'Campaign E official PowerShell destination already exists and will not be overwritten.'}
    $download=if($DownloadProvider){&$DownloadProvider $assetUri @($resolver.allowedHosts) $DestinationPath $owner}else{Save-DevFleetCampaignEAllowlistedHttpsDownload -Uri $assetUri -AllowedHosts @($resolver.allowedHosts) -Path $DestinationPath -OwnerDeadlineUtc $owner}
    if($null-eq$download-or[string]$download.outcome-cne'PASS'-or-not(Test-Path -LiteralPath $DestinationPath -PathType Leaf)-or[int64]$download.bytes-lt1-or[string]$download.sha256-notmatch'^[0-9a-f]{64}$'-or(Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$download.sha256){throw 'Campaign E official PowerShell download evidence is invalid.'}
    $downloadStarted=([datetime]$download.startedAtUtc).ToUniversalTime();$downloadFinished=([datetime]$download.finishedAtUtc).ToUniversalTime();$downloadDeadline=([datetime]$download.deadlineUtc).ToUniversalTime();$redirectHosts=@($download.redirectHosts)
    if($downloadStarted-lt$metadataFinished-or$downloadFinished-lt$downloadStarted-or$downloadFinished-gt$owner-or$downloadDeadline-gt$owner-or$redirectHosts.Count-lt1-or@($redirectHosts|Where-Object{@($resolver.allowedHosts)-cnotcontains[string]$_}).Count){throw 'Campaign E official PowerShell download deadline/redirect evidence is invalid.'}
    $authenticity=if($AuthenticityProvider){&$AuthenticityProvider $DestinationPath $Dependency.installerAuthenticityPolicy}else{$signature=Get-AuthenticodeSignature -LiteralPath $DestinationPath;[pscustomobject]@{status=$signature.Status.ToString();signerSubject=if($signature.SignerCertificate){$signature.SignerCertificate.Subject}else{''}}}
    if([string]$authenticity.status-cne'Valid'-or-not(Test-DevFleetCampaignEExactSignerSubject -Actual ([string]$authenticity.signerSubject) -Expected @($Dependency.installerAuthenticityPolicy.allowedSignerSubjectsExact))){throw 'Campaign E official PowerShell payload signer identity is invalid.'}
    $finished=&$now;if($finished-lt$downloadFinished-or$finished-gt$owner){throw 'Campaign E official PowerShell authenticity observation completed outside the immutable owner timeline.'}
    [pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_OFFICIAL_POWERSHELL_PAYLOAD';status='PASS';method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId='Microsoft.PowerShell';releaseTag=[string]$metadata.tag_name;assetName=$assetName;metadataHost=$metadataUri.Host;assetHost=$assetUri.Host;redirectHosts=$redirectHosts;sha256=[string]$download.sha256;bytes=[int64]$download.bytes;signerSubject=[string]$authenticity.signerSubject;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');ownerDeadlineUtc=$owner.ToString('o');localPath=$DestinationPath;productLifecycleStarted=$false;stageMarkerWritten=$false}
}

function Invoke-DevFleetCampaignEStagedPowerShellAcquisition {
    param(
        [Parameter(Mandatory)][psobject]$Dependency,
        [Parameter(Mandatory)][psobject]$PayloadEvidence,
        [Parameter(Mandatory)][string]$PayloadPath,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [Parameter(Mandatory)][scriptblock]$AuthenticityProvider,
        [Parameter(Mandatory)][scriptblock]$InstallerProvider,
        [Parameter(Mandatory)][scriptblock]$PowerShellCompatibilityProvider,
        [scriptblock]$ClockProvider
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}};$started=&$now;$owner=$OwnerDeadlineUtc.ToUniversalTime()
    if($owner-le$started){throw 'Campaign E staged PowerShell acquisition owner deadline expired before compatibility inspection.'}
    if([string]$Dependency.id-cne'powershell7'-or[string]$Dependency.wingetPackageId-cne'Microsoft.PowerShell'){throw 'Campaign E staged PowerShell package identity is unsupported.'}
    $initial=&$PowerShellCompatibilityProvider $Dependency $owner
    if([string]$initial.status-ceq'Compatible'){
        $finished=&$now;if($finished-gt$owner){throw 'Campaign E staged PowerShell compatibility observation completed after cutoff.'}
        if([Version][string]$initial.version-lt[Version][string]$Dependency.minimumSupportedVersion-or([Version][string]$initial.version).Major-gt[int]$Dependency.maximumMajor-or[string]$initial.pathSha256-notmatch'^[0-9a-f]{64}$'){throw 'Campaign E staged PowerShell preserved state violates the candidate compatibility policy.'}
        return [pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='PRESERVED_CANDIDATE_COMPATIBLE';packageId='Microsoft.PowerShell';startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');ownerDeadlineUtc=$owner.ToString('o');wingetPathSha256='';operations=@();powershell=[pscustomobject]@{status='Compatible';version=[string]$initial.version;pathSha256=[string]$initial.pathSha256};productLifecycleStarted=$false;stageMarkerWritten=$false}
    }
    if([string]$PayloadEvidence.kind-cne'DEVFLEET_CAMPAIGN_E_OFFICIAL_POWERSHELL_PAYLOAD'-or[string]$PayloadEvidence.status-cne'PASS'-or[string]$PayloadEvidence.method-cne'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'-or[string]$PayloadEvidence.packageId-cne'Microsoft.PowerShell'-or[string]$PayloadEvidence.releaseTag-notmatch'^v7\.\d+\.\d+$'-or[string]$PayloadEvidence.assetName-notmatch'^PowerShell-7\.[0-9.]+-win-x64\.msi$'-or[string]$PayloadEvidence.sha256-notmatch'^[0-9a-f]{64}$'-or[int64]$PayloadEvidence.bytes-lt1-or[bool]$PayloadEvidence.productLifecycleStarted-or[bool]$PayloadEvidence.stageMarkerWritten){throw 'Campaign E staged official payload evidence is invalid.'}
    $payloadStarted=([datetime]$PayloadEvidence.startedAtUtc).ToUniversalTime();$payloadFinished=([datetime]$PayloadEvidence.finishedAtUtc).ToUniversalTime();$payloadOwner=([datetime]$PayloadEvidence.ownerDeadlineUtc).ToUniversalTime()
    if($payloadFinished-lt$payloadStarted-or$payloadFinished-gt$owner-or$payloadOwner-lt$payloadFinished-or-not(Test-DevFleetCampaignEExactSignerSubject -Actual ([string]$PayloadEvidence.signerSubject) -Expected @($Dependency.installerAuthenticityPolicy.allowedSignerSubjectsExact))){throw 'Campaign E staged official payload timeline/signer evidence is invalid.'}
    if(-not(Test-Path -LiteralPath $PayloadPath -PathType Leaf)-or[IO.Path]::GetFileName($PayloadPath)-cne[string]$PayloadEvidence.assetName-or(Get-FileHash -LiteralPath $PayloadPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$PayloadEvidence.sha256){throw 'Campaign E staged official payload file identity mismatch.'}
    $authenticity=&$AuthenticityProvider $PayloadPath $Dependency.installerAuthenticityPolicy
    if([string]$authenticity.status-cne'Valid'-or-not(Test-DevFleetCampaignEExactSignerSubject -Actual ([string]$authenticity.signerSubject) -Expected @($Dependency.installerAuthenticityPolicy.allowedSignerSubjectsExact))){throw 'Campaign E staged official payload failed candidate signer validation.'}
    $remaining=[int][math]::Floor(($owner-(&$now)).TotalSeconds);if($remaining-le0){throw 'Campaign E staged PowerShell acquisition owner deadline expired before install.'}
    $arguments=@('/i',$PayloadPath)+@($Dependency.silentInstallArguments)
    $install=&$InstallerProvider $PayloadPath $arguments ([math]::Min(600,$remaining)) $owner
    $installStarted=([datetime]$install.startedAtUtc).ToUniversalTime();$installFinished=([datetime]$install.finishedAtUtc).ToUniversalTime();$installDeadline=([datetime]$install.deadlineUtc).ToUniversalTime()
    $accepted=[string]$install.outcome-ceq'PASS';if([string]$install.outcome-ceq'NONZERO'-and[int]$install.exitCode-eq3010){$accepted=$true}
    if(-not$accepted-or-not[bool]$install.outputComplete-or$installStarted-lt$started-or$installFinished-lt$installStarted-or$installFinished-gt$owner-or$installDeadline-gt$owner){throw 'Campaign E staged PowerShell installer failed or violated its immutable deadline.'}
    $final=&$PowerShellCompatibilityProvider $Dependency $owner;$finished=&$now
    if([string]$final.status-cne'Compatible'-or[Version][string]$final.version-lt[Version][string]$Dependency.minimumSupportedVersion-or([Version][string]$final.version).Major-gt[int]$Dependency.maximumMajor-or[string]$final.pathSha256-notmatch'^[0-9a-f]{64}$'-or$finished-gt$owner){throw 'Campaign E staged PowerShell installer did not reach candidate-compatible state.'}
    [pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId='Microsoft.PowerShell';startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');ownerDeadlineUtc=$owner.ToString('o');wingetPathSha256='';officialPayload=[ordered]@{releaseTag=[string]$PayloadEvidence.releaseTag;assetName=[string]$PayloadEvidence.assetName;sha256=[string]$PayloadEvidence.sha256;bytes=[int64]$PayloadEvidence.bytes;signerSubject=[string]$authenticity.signerSubject};operations=@([pscustomobject][ordered]@{operation='official-powershell-msi-install';outcome=[string]$install.outcome;exitCode=$install.exitCode;startedAtUtc=[string]$install.startedAtUtc;finishedAtUtc=[string]$install.finishedAtUtc;deadlineUtc=[string]$install.deadlineUtc;outputComplete=[bool]$install.outputComplete;packageIdentityObserved=$true});powershell=[pscustomobject]@{status='Compatible';version=[string]$final.version;pathSha256=[string]$final.pathSha256};productLifecycleStarted=$false;stageMarkerWritten=$false}
}

function Get-DevFleetCampaignEBootstrapStubContent {
    @'
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role,
  [ValidateSet('Offline','Connected')][string]$InstallationMode='Connected',
  [string]$PackageRoot,
  [string]$BootstrapBundlePath,
  [switch]$NonInteractive,
  [switch]$SkipWindowsUpdates,
  [switch]$DeferNetworkPairing,
  [switch]$AcknowledgeRootfulDocker,
  [string]$TransactionDeadlineUtc,
  [string]$TransactionId,
  [string]$TransactionPayloadSha256,
  [string]$TransactionAction,
  [string]$TransactionRole,
  [string]$TransactionPreparedUtc,
  [string]$DeadlinePolicyVersion='1.0.0'
)
$ErrorActionPreference='Stop'
$ack=$env:DEVFLEET_E_BOOTSTRAP_ACK
$run=$env:DEVFLEET_E_RUN_ID
if($ack-notlike'C:\Users\Public\DevFleet-E2E\*\Prerequisite\bootstrap-ack.json'-or$run-notmatch'^[A-Za-z0-9._-]+$'){throw 'Campaign E bootstrap acknowledgement boundary is invalid.'}
if($TransactionId-or$TransactionPayloadSha256-or$TransactionAction-or$TransactionRole-or$TransactionPreparedUtc){throw 'Campaign E prerequisite bootstrap must remain transactionless.'}
$record=[ordered]@{schemaVersion=1;kind='CAMPAIGN_E_POWERSHELL_BOOTSTRAP_ONLY';runId=$run;role=$Role;installationMode=$InstallationMode;packageRoot=$PackageRoot;pwshVersion=$PSVersionTable.PSVersion.ToString();producedAtUtc=[datetime]::UtcNow.ToString('o');productLifecycleStarted=$false;stageMarkerWritten=$false}
$tmp="$ack.$([guid]::NewGuid().ToString('N')).tmp";$record|ConvertTo-Json -Compress|Set-Content -LiteralPath $tmp -Encoding UTF8;[IO.File]::Move($tmp,$ack)
'@
}

function Get-DevFleetSystemExecutionPolicyProjection {
    param([scriptblock]$PolicyProvider)
    $read={param($Scope)if($PolicyProvider){[string](& $PolicyProvider $Scope)}else{[string](Get-ExecutionPolicy -Scope $Scope)}}
    [pscustomobject][ordered]@{
        MachinePolicy=&$read 'MachinePolicy'
        UserPolicy=&$read 'UserPolicy'
        LocalMachine=&$read 'LocalMachine'
        CurrentUser=&$read 'CurrentUser'
    }
}

function Assert-DevFleetCampaignEPrerequisiteFailure {
    param(
        [Parameter(Mandatory)][psobject]$Failure,
        [Parameter(Mandatory)][string]$ExpectedRunId,
        [Parameter(Mandatory)][guid]$ExpectedVmId,
        [Parameter(Mandatory)][string]$ExpectedPayloadSha256
    )
    if([int]$Failure.schemaVersion-ne1-or[string]$Failure.kind-cne'DEVFLEET_CAMPAIGN_E_PREREQUISITE_FAILURE'-or[string]$Failure.status-cne'BLOCKED'){throw 'Campaign E prerequisite failure schema is invalid.'}
    if([string]$Failure.runId-cne$ExpectedRunId-or[guid][string]$Failure.vmId-ne$ExpectedVmId-or[string]$Failure.payloadSha256-cne$ExpectedPayloadSha256){throw 'Campaign E prerequisite failure identity mismatch.'}
    $produced=([datetime]$Failure.producedAtUtc).ToUniversalTime();$deadline=([datetime]$Failure.ownerDeadlineUtc).ToUniversalTime()
    if($produced-gt$deadline-or[string]::IsNullOrWhiteSpace([string]$Failure.primaryError)-or([string]$Failure.primaryError).Length-gt1024){throw 'Campaign E prerequisite failure deadline/error evidence is invalid.'}
    $acquisition=$Failure.powershellAcquisition
    if($null-eq$acquisition-or[string]$acquisition.status-cne'BLOCKED'-or[bool]$acquisition.productLifecycleStarted-or[bool]$acquisition.stageMarkerWritten){throw 'Campaign E prerequisite failure fabricated product progress.'}
    $operations=@($acquisition.operations);$identity=$acquisition.identity
    $method=if($null-ne$identity){[string]$identity.method}else{''}
    if($method-ceq'WINGET_MANIFEST_APPROVED_DIAGNOSTIC'){$expectedOperations=@('winget-version','winget-source-list','winget-source-update','winget-powershell-search','winget-powershell-install');$maximumOperations=5}
    elseif($method-ceq'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'){$expectedOperations=@('official-powershell-msi-install');$maximumOperations=1}
    elseif($method-or$operations.Count-gt0){throw 'Campaign E prerequisite failure acquisition identity is missing or unsupported.'}
    else{$expectedOperations=@();$maximumOperations=0}
    if($operations.Count-gt$maximumOperations){throw 'Campaign E prerequisite failure contains too many acquisition operations.'}
    $previous=[datetime]::MinValue
    for($index=0;$index-lt$operations.Count;$index++){
        $operation=$operations[$index];$started=([datetime]$operation.startedAtUtc).ToUniversalTime();$finished=([datetime]$operation.finishedAtUtc).ToUniversalTime();$operationDeadline=([datetime]$operation.deadlineUtc).ToUniversalTime()
        if([string]$operation.operation-cne$expectedOperations[$index]-or$started-lt$previous-or$finished-lt$started-or$finished-gt$deadline-or$operationDeadline-gt$deadline){throw 'Campaign E prerequisite failure operation sequence/deadline is invalid.'}
        $previous=$finished
    }
    if($null-ne$identity){
        if([string]$identity.packageId-cne'Microsoft.PowerShell'-or([datetime]$identity.ownerDeadlineUtc).ToUniversalTime()-ne$deadline){throw 'Campaign E prerequisite failure acquisition identity is invalid.'}
        if($method-ceq'WINGET_MANIFEST_APPROVED_DIAGNOSTIC'-and[string]$identity.wingetPathSha256-notmatch'^[0-9a-f]{64}$'){throw 'Campaign E prerequisite failure WinGet identity is invalid.'}
        if($method-ceq'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'-and([string]$identity.payloadSha256-notmatch'^[0-9a-f]{64}$'-or[string]$identity.assetName-notmatch'^PowerShell-7\.[0-9.]+-win-x64\.msi$')){throw 'Campaign E prerequisite failure staged payload identity is invalid.'}
    }
    $serialized=$Failure|ConvertTo-Json -Depth 12 -Compress
    if($serialized-match'(?i)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*(?!<redacted>|\\u003credacted\\u003e)[^,}"]+'){throw 'Campaign E prerequisite failure contains unredacted secret-shaped evidence.'}
    return $true
}

function Assert-DevFleetCampaignEStagingOwnership {
    param(
        [Parameter(Mandatory)][psobject]$Record,
        [Parameter(Mandatory)][string]$ExpectedRunId,
        [Parameter(Mandatory)][guid]$ExpectedNonce
    )
    if([int]$Record.schemaVersion-ne1-or[string]$Record.kind-cne'DEVFLEET_CAMPAIGN_E_STAGING_OWNER'){throw 'Campaign E staging ownership schema is invalid.'}
    if([string]$Record.runId-cne$ExpectedRunId-or[guid][string]$Record.nonce-ne$ExpectedNonce){throw 'Campaign E staging ownership identity mismatch.'}
    return $true
}

function Resolve-DevFleetCampaignEWorkerResult {
    param(
        [AllowEmptyString()][string]$ProcessStdout,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DurableRaw
    )
    try {$durable=$DurableRaw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Campaign E durable worker result is malformed.'}
    if([string]$durable.kind-cnotin@('DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY','DEVFLEET_CAMPAIGN_E_PREREQUISITE_FAILURE','DEVFLEET_CAMPAIGN_E_M1_RESULT')){throw 'Campaign E durable worker result kind is unsupported.'}
    $stdoutStatus='EMPTY';$processValue=$null
    if(-not[string]::IsNullOrWhiteSpace($ProcessStdout)){
        try{$processValue=$ProcessStdout|ConvertFrom-Json -ErrorAction Stop;$stdoutStatus='VALID'}catch{$stdoutStatus='MALFORMED'}
    }
    if($processValue){
        if([string]$processValue.kind-cne[string]$durable.kind-or[string]$processValue.runId-cne[string]$durable.runId-or[string]$processValue.vmId-cne[string]$durable.vmId-or[string]$processValue.payloadSha256-cne[string]$durable.payloadSha256-or(($processValue|ConvertTo-Json -Depth 24 -Compress)-cne($durable|ConvertTo-Json -Depth 24 -Compress))){throw 'Campaign E process and durable worker results disagree.'}
    }
    [pscustomobject][ordered]@{value=$durable;source=if($stdoutStatus-ceq'VALID'){'DURABLE_AND_PROCESS_MATCH'}else{'DURABLE'};processStdoutStatus=$stdoutStatus}
}

function Assert-DevFleetCampaignEProductProfile {
    param([Parameter(Mandatory)]$Profile,[Parameter(Mandatory)][string]$ExpectedRunId,[Parameter(Mandatory)][guid]$ExpectedVmId,[Parameter(Mandatory)][string]$ExpectedPayloadSha256,[Parameter(Mandatory)][object[]]$ExpectedInputs,[Parameter(Mandatory)][datetime]$DeadlineUtc,[switch]$ExpectedProductLaunch)
    if([int]$Profile.schemaVersion-ne1-or[string]$Profile.kind-cne'DEVFLEET_CAMPAIGN_E_PRODUCT_PROFILE'-or[string]$Profile.status-cne'PASS_PROFILE_ONLY'-or[bool]$Profile.productLifecycleStarted){throw 'Candidate preflight profile did not pass.'}
    if([string]$Profile.runId-cne$ExpectedRunId-or[guid][string]$Profile.vmId-ne$ExpectedVmId-or[string]$Profile.payloadSha256-cne$ExpectedPayloadSha256){throw 'Candidate preflight profile identity mismatch.'}
    $start=([datetime]$Profile.startedAtUtc).ToUniversalTime();$end=([datetime]$Profile.producedAtUtc).ToUniversalTime();$owner=([datetime]$Profile.ownerDeadlineUtc).ToUniversalTime()
    if($end-lt$start-or$end-gt$owner-or$owner-gt$DeadlineUtc.ToUniversalTime()-or[version][string]$Profile.childRuntime-lt[version]'7.0'-or[string]$Profile.preflightConfigSha256-notmatch'^[0-9a-f]{64}$'){throw 'Candidate preflight profile runtime/deadline evidence is invalid.'}
    $inputCount=if($ExpectedProductLaunch){4}else{3}
    if(@($Profile.inputs).Count-ne$inputCount-or$ExpectedInputs.Count-ne$inputCount){throw 'Candidate preflight profile input count mismatch.'}
    foreach($expectedInput in $ExpectedInputs){$match=@($Profile.inputs|Where-Object{[string]$_.path-ceq[string]$expectedInput.path-and[string]$_.sha256-ceq[string]$expectedInput.sha256});if($match.Count-ne1){throw 'Candidate preflight profile input binding mismatch.'}}
    if([int]$Profile.resources.cpus-lt2-or[int]$Profile.resources.cpus-gt12-or[string]$Profile.resources.memory-notmatch'^(?:[89]|[12][0-9]|3[0-2])G$'-or[string]$Profile.resources.disk-notmatch'^[1-9][0-9]{1,2}G$'-or[string]$Profile.ubuntuImage-notmatch'^\d+\.\d+$'){throw 'Candidate preflight profile capacity is invalid.'}
    if($ExpectedProductLaunch){
        if(-not$Profile.PSObject.Properties['productLaunch']-or[string]$Profile.productLaunch.mode-cne'CANDIDATE_CLOUD_INIT_AND_INVOKE_EXTERNAL'-or[string]$Profile.productLaunch.cloudInitFileName-cne'product-cloud-init.yaml'-or[string]$Profile.productLaunch.cloudInitSha256-notmatch'^[0-9a-f]{64}$'-or[string]$Profile.productLaunch.instanceName-cne"DevFleet-E2E-E-M1-$ExpectedRunId"-or[string]$Profile.productLaunch.nodeRole-cne'primary'-or[bool]$Profile.productLaunch.productTransactionStarted-or[bool]$Profile.productLaunch.stageMarkerWritten){throw 'Candidate product cloud-init binding is invalid.'}
    }elseif($Profile.PSObject.Properties['productLaunch']){throw 'Plain M2 profile unexpectedly enabled product cloud-init.'}
    return $true
}

function Invoke-DevFleetCampaignECandidateNativeLaunch {
    param(
        [Parameter(Mandatory)][Management.Automation.PSModuleInfo]$CandidateCommonModule,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [ValidateRange(1,900)][int]$MaximumSeconds=900
    )
    if($PSVersionTable.PSVersion.Major-lt7){throw 'Candidate native launch requires PowerShell7.'}
    $started=[datetime]::UtcNow;$deadline=$started.AddSeconds($MaximumSeconds)
    if($OwnerDeadlineUtc.ToUniversalTime()-lt$deadline){$deadline=$OwnerDeadlineUtc.ToUniversalTime()}
    $outcome='COMMAND_FAILED';$exitCode=$null;$stdout='';$stderr='';$complete=$false
    try{
        # Module-qualified execution keeps the real hash-verified candidate body
        # and its helpers. Capture is a stricter diagnostic completeness check.
        $stdout=[string](& $CandidateCommonModule {
            param($NativePath,[string[]]$NativeArguments,$Seconds,[datetime]$Deadline)
            Invoke-External -FilePath $NativePath -ArgumentList $NativeArguments -TimeoutSeconds $Seconds -DeadlineUtc $Deadline -Capture
        } $FilePath $ArgumentList $MaximumSeconds $deadline)
        $outcome='PASS';$exitCode=0;$complete=$true
    }catch{
        $stderr=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 4096
        if($stderr-match'(?i)timed out|deadline expired'){$outcome='TIMEOUT'}
        elseif($stderr-match'failed with exit code (-?\d+)'){$exitCode=[int]$Matches[1];$complete=$true}
    }
    [pscustomobject][ordered]@{operation='launch';adapter='CANDIDATE_COMMON_INVOKE_EXTERNAL';outcome=$outcome;exitCode=$exitCode;pid=$null;pidEvidence='Candidate function does not expose child PID';startedAtUtc=$started.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');deadlineUtc=$deadline.ToString('o');nativeMaximumSeconds=$MaximumSeconds;stdout=ConvertTo-DevFleetDiagnosticSafeText $stdout 32768;stderr=$stderr;outputComplete=$complete;stdoutTruncated=($stdout.Length-gt32768);stderrTruncated=$false;captureMode=$true}
}

function Get-DevFleetCampaignEBackendSnapshot {
    param(
        [Parameter(Mandatory)][ValidatePattern('^(?:DevFleet-E2E-E-M1-[A-Za-z0-9._-]+|devfleet-primary)$')][string]$InstanceName,
        [Parameter(Mandatory)][datetime]$SinceUtc,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [ValidateRange(1,60)][int]$TimeoutSeconds=45,
        [switch]$ProductContext,
        [string]$ExpectedPayloadSha256=''
    )
    if($ProductContext-and($InstanceName-cne'devfleet-primary'-or$ExpectedPayloadSha256-notmatch'^[0-9a-f]{64}$')){throw 'Product observation requires the explicit candidate payload and Primary identity.'}
    if($InstanceName-ceq'devfleet-primary'-and-not$ProductContext){throw 'Product backend observation requires an explicit product context.'}
    $started=[datetime]::UtcNow;$remaining=[int][math]::Floor(($OwnerDeadlineUtc.ToUniversalTime()-$started).TotalSeconds)
    if($remaining-le0){return [pscustomobject]@{status='OWNER_EXPIRED';startedAtUtc=$started.ToString('o');records=$null}}
    $job=$null
    try {
        # This observer never invokes Multipass or guest commands. One bounded
        # child reads independent service, process, Hyper-V and event evidence.
        $job=Start-Job -ArgumentList @($InstanceName,$SinceUtc.ToUniversalTime(),[bool]$ProductContext,$ExpectedPayloadSha256) -ScriptBlock {
            param($Name,$Since,$ObserveProduct,$Payload)
            $ErrorActionPreference='Stop';$errors=[Collections.Generic.List[string]]::new()
            $data=[ordered]@{services=@();processes=@();backend=[ordered]@{status='UNVERIFIED';owned=@();foreignCount=-1};events=@();eventLogs=@()}
            try{
                $data.services=@(Get-CimInstance Win32_Service -OperationTimeoutSec 10|Where-Object{$_.Name-match'^(?i:multipassd?|vmms|vmcompute)$'}|ForEach-Object{[ordered]@{name=[string]$_.Name;state=[string]$_.State;pid=[int]$_.ProcessId;exitCode=[int]$_.ExitCode;startMode=[string]$_.StartMode;account=[string]$_.StartName}})
                $processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 10)
                $bound=@($processes|Where-Object{$_.Name-match'^(?i:multipassd?\.exe)$'})
                for($depth=0;$depth-lt3;$depth++){$ids=@($bound|ForEach-Object{[int]$_.ProcessId});$bound=@($bound)+@($processes|Where-Object{$ids-contains[int]$_.ParentProcessId-and$ids-notcontains[int]$_.ProcessId})}
                $data.processes=@($bound|Sort-Object ProcessId -Unique|ForEach-Object{[ordered]@{name=[string]$_.Name;pid=[int]$_.ProcessId;parentPid=[int]$_.ParentProcessId;createdAtUtc=([datetime]$_.CreationDate).ToUniversalTime().ToString('o')}})
                if($ObserveProduct){
                    $data.launches=@(foreach($process in @($processes|Where-Object{$_.Name-ieq'multipass.exe'})){
                        # Accept only the exact non-secret candidate launch grammar.
                        # No arbitrary native command line or environment is emitted.
                        $pattern='^\s*(?:"(?<exe>[^"]*multipass\.exe)"|(?<exe>\S*multipass\.exe))\s+launch\s+(?<image>[0-9]+\.[0-9]+)\s+--name\s+(?<instance>[A-Za-z0-9._-]+)\s+--cpus\s+(?<cpus>[0-9]+)\s+--memory\s+(?<memory>[0-9]+G)\s+--disk\s+(?<disk>[0-9]+G)\s+--cloud-init\s+(?:"(?<cloud>[^"]+)"|(?<cloud>\S+))\s*$'
                        $match=[regex]::Match([string]$process.CommandLine,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
                        if(-not$match.Success-or$match.Groups['instance'].Value-cne$Name){continue}
                        $vendor=Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe';$cloud=Join-Path $env:ProgramData ('DevFleet\tmp\cloud-'+$Name+'.yaml')
                        if($match.Groups['exe'].Value-ine$vendor-or$match.Groups['cloud'].Value-ine$cloud){continue}
                        $accountHash='';$accountStatus='UNAVAILABLE'
                        try{$account=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop;if($account.ReturnValue-eq0-and[string]$account.Sid-match'^S-1-[0-9-]+$'){$hasher=[Security.Cryptography.SHA256]::Create();try{$accountHash=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$account.Sid)))).Replace('-','').ToLowerInvariant();$accountStatus='OBSERVED'}finally{$hasher.Dispose()}}}catch{}
                        [ordered]@{pid=[int]$process.ProcessId;parentPid=[int]$process.ParentProcessId;createdAtUtc=([datetime]$process.CreationDate).ToUniversalTime().ToString('o');sessionId=[int]$process.SessionId;principalSidSha256=$accountHash;principalStatus=$accountStatus;executablePath=$vendor;image=$match.Groups['image'].Value;instanceName=$Name;cpus=[int]$match.Groups['cpus'].Value;memory=$match.Groups['memory'].Value;disk=$match.Groups['disk'].Value;cloudInitPath=$cloud;argumentGrammar='EXACT_CANDIDATE_COMPUTE_LAUNCH';rawCommandLineCaptured=$false}
                    })
                }
            }catch{$errors.Add('services/processes: '+$_.Exception.Message)}
            try{
                $vms=@(Get-VM -ErrorAction Stop);$owned=@($vms|Where-Object{$_.Name-ceq$Name})
                $data.backend=[ordered]@{status='PASS';foreignCount=@($vms|Where-Object{$_.Name-cne$Name}).Count;owned=@($owned|ForEach-Object{
                    $vm=$_;$disks=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop|ForEach-Object{$disk=Get-VHD -Path $_.Path -ErrorAction Stop;[ordered]@{virtualBytes=[int64]$disk.Size;fileBytes=[int64]$disk.FileSize;type=[string]$disk.VhdType;attached=[bool]$disk.Attached}})
                    $entry=[ordered]@{name=[string]$vm.Name;id=$vm.Id.ToString();state=[string]$vm.State;status=[string]$vm.Status;generation=[int]$vm.Generation;cpus=[int]$vm.ProcessorCount;startupMemoryBytes=[int64]$vm.MemoryStartup;assignedMemoryBytes=[int64]$vm.MemoryAssigned;uptimeSeconds=[double]$vm.Uptime.TotalSeconds;disks=$disks}
                    if($ObserveProduct){$entry.networkAdapters=@(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop|ForEach-Object{[ordered]@{switchName=[string]$_.SwitchName;status=@($_.Status|ForEach-Object{[string]$_});ipAddresses=@($_.IPAddresses|Where-Object{[string]$_-match'^[0-9a-fA-F:.]+$'})}})}
                    $entry
                })}
            }catch{$errors.Add('Hyper-V: '+$_.Exception.Message);$data.backend.status='UNVERIFIED'}
            $eventSources=@(@{log='Microsoft-Windows-Hyper-V-VMMS-Admin';provider=''},@{log='Microsoft-Windows-Hyper-V-Worker-Admin';provider=''})
            if($ObserveProduct){$eventSources+=@{log='Application';provider='Multipass'}}
            foreach($eventSource in $eventSources){$log=$eventSource.log
                try{
                    $available=Get-WinEvent -ListLog $log -ErrorAction Stop
                    if(-not$available.IsEnabled){$data.eventLogs+=@{name=$log;status='DISABLED'};continue}
                    # Get-WinEvent treats StartTime as local wall time, including
                    # when the caller supplies a UTC DateTime. Convert the same
                    # instant explicitly so non-UTC guests do not miss events.
                    $filter=@{LogName=$log;StartTime=$Since.ToLocalTime()};if($eventSource.provider){$filter.ProviderName=$eventSource.provider}
                    $queryErrors=@();$events=@(Get-WinEvent -FilterHashtable $filter -MaxEvents 32 -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
                    if(@($queryErrors|Where-Object{$_.FullyQualifiedErrorId-notlike'NoMatchingEventsFound*'}).Count){throw 'Event query failed.'}
                    $data.eventLogs+=@{name=$log;provider=$eventSource.provider;status='PASS';queryStartUtc=$Since.ToUniversalTime().ToString('o');queryStartLocal=$filter.StartTime.ToString('o');count=$events.Count;limit=32;mayBeTruncated=($events.Count-eq32)}
                    $data.events+=@($events|ForEach-Object{[ordered]@{log=$log;provider=[string]$_.ProviderName;eventId=[int]$_.Id;recordId=[long]$_.RecordId;timestampUtc=$_.TimeCreated.ToUniversalTime().ToString('o');message=[string]$_.Message}})
                }catch{$data.eventLogs+=@{name=$log;status='UNVERIFIED'};$errors.Add('events: '+$_.Exception.Message)}
            }
            if($ObserveProduct){
                $data.product=[ordered]@{status='NOT_STARTED';collectorPowerShellVersion=$PSVersionTable.PSVersion.ToString();effectivePrimary=$null;activeTransaction=$null;cloudInit=$null;failureRecords=@()}
                try{
                    $state=Join-Path $env:ProgramData 'DevFleet';$configPath=Join-Path $state 'devfleet.config.json';$activePath=Join-Path $state 'active-transaction.json'
                    if(Test-Path -LiteralPath $configPath -PathType Leaf){$config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json;$node=$config.Primary;if([string]$node.InstanceName-cne$Name-or[int]$node.Cpus-lt2-or[int]$node.Cpus-gt12-or[string]$node.Memory-notmatch'^[0-9]+G$'-or[string]$node.Disk-notmatch'^[0-9]+G$'-or[string]$node.UbuntuImage-notmatch'^[0-9]+\.[0-9]+$'){throw 'Observed config does not match the exact Primary target/profile grammar.'};$data.product.effectivePrimary=[ordered]@{instanceName=[string]$node.InstanceName;cpus=[int]$node.Cpus;memory=[string]$node.Memory;disk=[string]$node.Disk;ubuntuImage=[string]$node.UbuntuImage};$data.product.status='CONFIG_OBSERVED'}
                    if(Test-Path -LiteralPath $activePath -PathType Leaf){$tx=Get-Content -LiteralPath $activePath -Raw|ConvertFrom-Json;if([string]$tx.payloadSha256-cne$Payload-or[string]$tx.transactionId-notmatch'^[0-9a-fA-F]{32}$'){throw 'Observed active transaction identity does not match candidate.'};$data.product.activeTransaction=[ordered]@{transactionId=[string]$tx.transactionId;payloadSha256=[string]$tx.payloadSha256};$data.product.status='TRANSACTION_OBSERVED'}
                    $cloud=Join-Path $state ('tmp\cloud-'+$Name+'.yaml');if(Test-Path -LiteralPath $cloud -PathType Leaf){$data.product.cloudInit=[ordered]@{path=$cloud;sha256=(Get-FileHash -LiteralPath $cloud -Algorithm SHA256).Hash.ToLowerInvariant();lastWriteUtc=(Get-Item -LiteralPath $cloud).LastWriteTimeUtc.ToString('o');contentCaptured=$false}}
                    $logRoot=Join-Path $env:ProgramData 'M-TechLabs\DevFleet\Logs'
                    $logs=@(Get-ChildItem -LiteralPath $logRoot -Filter 'setup-*.log' -File -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTimeUtc-ge$Since}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 2)
                    $data.product.setupLogStatus=if($logs.Count){'OBSERVED'}else{'NO_RECENT_LOG'}
                    $data.product.failureRecords=@(foreach($log in $logs){if($log.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Setup log is a reparse point.'};[ordered]@{name=$log.Name;lastWriteUtc=$log.LastWriteTimeUtc.ToString('o');tail=(@(Get-Content -LiteralPath $log.FullName -Tail 80)-join"`n");lineLimit=80;tailOnly=$true}})
                }catch{$data.product.status='UNVERIFIED';$errors.Add('product context: '+$_.Exception.Message)}
            }
            [pscustomobject]@{data=$data;errors=@($errors)}
        }
        if(-not(Wait-Job -Job $job -Timeout ([math]::Min($TimeoutSeconds,$remaining)))){throw 'Independent backend observation timed out.'}
        $values=@(Receive-Job -Job $job -ErrorAction Stop);if($values.Count-ne1){throw 'Independent backend observation omitted its result.'}
        $value=$values[0]
        foreach($event in $value.data.events){$event.message=ConvertTo-DevFleetDiagnosticSafeText $event.message 4096}
        if($ProductContext-and$value.data.product){foreach($record in $value.data.product.failureRecords){$record.tail=ConvertTo-DevFleetDiagnosticSafeText $record.tail 16384}}
        [pscustomobject][ordered]@{status=if(@($value.errors).Count){'PARTIAL'}else{'COMPLETE'};instanceName=$InstanceName;startedAtUtc=$started.ToString('o');producedAtUtc=[datetime]::UtcNow.ToString('o');data=$value.data;errors=@($value.errors|ForEach-Object{ConvertTo-DevFleetDiagnosticSafeText $_ 512})}
    }catch{[pscustomobject][ordered]@{status='UNVERIFIED';instanceName=$InstanceName;startedAtUtc=$started.ToString('o');producedAtUtc=[datetime]::UtcNow.ToString('o');error=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 512}}
    finally{if($job){Stop-Job -Job $job -ErrorAction SilentlyContinue;Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}}
}

function Invoke-DevFleetCampaignEMultipassM1Sequence {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
        [Parameter(Mandatory)][ValidatePattern('^DevFleet-E2E-E-M1-[A-Za-z0-9._-]+$')][string]$InstanceName,
        [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+$')][string]$UbuntuImage,
        [Parameter(Mandatory)][string]$MultipassPath,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [Parameter(Mandatory)][scriptblock]$NativeProbeProvider,
        [scriptblock]$ClockProvider,
        [hashtable]$Resources=@{cpus=2;memory='2G';disk='10G'},
        [string]$CloudInitPath=''
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}};$started=&$now;$owner=$OwnerDeadlineUtc.ToUniversalTime()
    if($owner-le$started){throw 'Campaign E M1 owner deadline expired before launch.'}
    if($Resources.Count-ne3-or[int]$Resources.cpus-lt2-or[int]$Resources.cpus-gt12-or[string]$Resources.memory-notmatch'^(?:[2-9]|[12][0-9]|3[0-2])G$'-or[string]$Resources.disk-notmatch'^[1-9][0-9]{1,2}G$'){throw 'Campaign E launch resources are invalid.'}
    $observations=[Collections.Generic.List[object]]::new();$state=[pscustomobject]@{previous=$started;primaryError=''};$progress=[ordered]@{launchAccepted=$false;instanceRunning=$false;ipObserved=$false;sshReady=$false;cloudInitDone=$false}
    $invoke={
        param([string]$Operation,[string[]]$Arguments,[int]$MaximumSeconds)
        $remaining=[int][math]::Floor(($owner-(&$now)).TotalSeconds);if($remaining-le0){$state.primaryError="Owner deadline expired before $Operation.";return $null}
        $raw=&$NativeProbeProvider $Operation $MultipassPath $Arguments ([math]::Min($MaximumSeconds,$remaining)) $owner
        $rawStarted=([datetime]$raw.startedAtUtc).ToUniversalTime();$rawFinished=([datetime]$raw.finishedAtUtc).ToUniversalTime();$rawDeadline=([datetime]$raw.deadlineUtc).ToUniversalTime()
        $summary=[pscustomobject][ordered]@{operation=$Operation;outcome=[string]$raw.outcome;exitCode=$raw.exitCode;pid=if($raw.PSObject.Properties['pid']){$raw.pid}else{$null};startedAtUtc=$rawStarted.ToString('o');finishedAtUtc=$rawFinished.ToString('o');deadlineUtc=$rawDeadline.ToString('o');outputComplete=[bool]$raw.outputComplete;error=ConvertTo-DevFleetDiagnosticSafeText $raw.stderr 512}
        [void]$observations.Add($summary)
        if($rawStarted-lt$state.previous-or$rawFinished-lt$rawStarted-or$rawFinished-gt$owner-or$rawDeadline-gt$owner){$state.primaryError="M1 $Operation violated its immutable owner timeline.";return $null}
        $state.previous=$rawFinished
        if([string]$raw.outcome-cne'