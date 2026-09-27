Set-StrictMode -Version Latest

function ConvertTo-DevFleetDiagnosticSafeText {
    param([AllowNull()][object]$Value,[int]$MaximumCharacters=512)
    $text=[string]$Value
    if([string]::IsNullOrEmpty($text)){return ''}
    $text=[regex]::Replace($text,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    $text=[regex]::Replace($text,'(?i)\bBearer\s+\S+','Bearer <redacted>')
    $text=$text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',''
    if($MaximumCharacters -gt 0 -and $text.Length -gt $MaximumCharacters){$text=$text.Substring($text.Length-$MaximumCharacters)}
    return $text.Trim()
}

function ConvertTo-DevFleetWindowsProcessArgument {
    param([AllowEmptyString()][string]$Value)
    if($Value.Length-gt0-and$Value-notmatch'[\s"]'){return $Value}
    $builder=[Text.StringBuilder]::new()
    [void]$builder.Append([char]34)
    $slashes=0
    foreach($character in $Value.ToCharArray()){
        if([int]$character-eq92){$slashes++;continue}
        if([int]$character-eq34){for($i=0;$i-lt($slashes*2+1);$i++){[void]$builder.Append([char]92)};[void]$builder.Append([char]34);$slashes=0;continue}
        for($i=0;$i-lt$slashes;$i++){[void]$builder.Append([char]92)}
        $slashes=0;[void]$builder.Append($character)
    }
    for($i=0;$i-lt($slashes*2);$i++){[void]$builder.Append([char]92)}
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Get-DevFleetExistingFilePathSet {
    param([string[]]$CandidatePaths,[scriptblock]$PathExistsProvider)
    $found=[Collections.Generic.List[string]]::new()
    foreach($candidate in @($CandidatePaths)){
        if([string]::IsNullOrWhiteSpace([string]$candidate)){continue}
        $exists=if($PathExistsProvider){[bool](& $PathExistsProvider ([string]$candidate))}else{Test-Path -LiteralPath $candidate -PathType Leaf}
        if($exists){[void]$found.Add([IO.Path]::GetFullPath([string]$candidate))}
    }
    return @($found|Select-Object -Unique)
}

function Invoke-DevFleetBoundedNativeProbe {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList=@(),
        [ValidateRange(1,1800)][int]$TimeoutSeconds=30,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [int[]]$RedactArgumentIndexes=@(),
        [ValidateRange(512,1048576)][int]$MaxStdoutCharacters=4096,
        [ValidateRange(512,65536)][int]$MaxStderrCharacters=2048,
        [switch]$ForceLegacyArgumentString,
        [scriptblock]$ClockProvider
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}}
    $started=&$now
    $ownerDeadline=$OwnerDeadlineUtc.ToUniversalTime()
    $remaining=[int][math]::Floor(($ownerDeadline-$started).TotalSeconds)
    if($remaining -le 0){
        return [pscustomobject]@{operation=$Operation;outcome='OWNER_EXPIRED';exitCode=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=$started.ToString('o');deadlineUtc=$ownerDeadline.ToString('o');stdout='';stderr='Owning diagnostic deadline expired before probe start.';pid=$null;outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}
    }
    $operationDeadline=$started.AddSeconds([math]::Min($TimeoutSeconds,$remaining))
    $arguments=@($ArgumentList)
    $safeArguments=for($i=0;$i -lt $arguments.Count;$i++){if($RedactArgumentIndexes -contains $i){'<redacted>'}else{[string]$arguments[$i]}}
    $process=$null
    try {
        $psi=[Diagnostics.ProcessStartInfo]::new()
        $psi.FileName=$FilePath
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        if(-not$ForceLegacyArgumentString-and$psi.PSObject.Properties.Name-contains'ArgumentList'){
            foreach($argument in $arguments){[void]$psi.ArgumentList.Add([string]$argument)}
        } else {$psi.Arguments=(@($arguments|ForEach-Object{ConvertTo-DevFleetWindowsProcessArgument ([string]$_)})-join' ')}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
        if(-not $process.Start()){throw 'Native process start returned false.'}
        $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
        $waitMilliseconds=[int][math]::Max(1,[math]::Min([int]::MaxValue,[math]::Ceiling(($operationDeadline-(&$now)).TotalMilliseconds)))
        if(-not $process.WaitForExit($waitMilliseconds)){
            try{$process.Kill($true)}catch{try{& (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID ([string]$process.Id) /T /F 2>$null|Out-Null}catch{try{$process.Kill()}catch{}}}
            try{[void]$process.WaitForExit(5000)}catch{}
            try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
            $finished=&$now
            return [pscustomobject]@{operation=$Operation;outcome='TIMEOUT';exitCode=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$operationDeadline.ToString('o');stdout='';stderr="Native probe exceeded its inherited finite deadline: $FilePath $($safeArguments -join ' ')";pid=$process.Id;outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}
        }
        $exitCode=$process.ExitCode
        $drained=$false
        try{$drained=[Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5))}catch{$drained=$false}
        $stdout=if($drained -and $stdoutTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdoutTask.GetAwaiter().GetResult()}else{''}
        $stderr=if($drained -and $stderrTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderrTask.GetAwaiter().GetResult()}else{'Redirected output did not drain within the bounded post-exit margin.'}
        $finished=&$now
        return [pscustomobject]@{operation=$Operation;outcome=if(-not$drained){'DRAIN_INCOMPLETE'}elseif($exitCode -eq 0){'PASS'}else{'NONZERO'};exitCode=$exitCode;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$operationDeadline.ToString('o');stdout=(ConvertTo-DevFleetDiagnosticSafeText $stdout $MaxStdoutCharacters);stderr=(ConvertTo-DevFleetDiagnosticSafeText $stderr $MaxStderrCharacters);pid=$process.Id;outputComplete=$drained;stdoutTruncated=([string]$stdout).Length-gt$MaxStdoutCharacters;stderrTruncated=([string]$stderr).Length-gt$MaxStderrCharacters}
    } catch {
        $finished=&$now
        return [pscustomobject]@{operation=$Operation;outcome='START_FAILED';exitCode=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$operationDeadline.ToString('o');stdout='';stderr=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message);pid=if($process-and-not$process.HasExited){$process.Id}else{$null};outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}
    } finally {
        if($process){$process.Dispose()}
    }
}

function Assert-DevFleetCampaignEArchiveEntries {
    param(
        [Parameter(Mandatory)][string[]]$Entries,
        [string[]]$RequiredEntries=@('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json','windows/DevFleet.Common.psm1')
    )
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($raw in @($Entries)){
        $entry=([string]$raw).Trim().Replace('\','/')
        if([string]::IsNullOrWhiteSpace($entry)){continue}
        if($entry.StartsWith('/')-or$entry-match'^[A-Za-z]:'-or$entry.Contains([char]0)){throw "Candidate archive entry escapes the package root: $entry"}
        $segments=@($entry.Split('/')|Where-Object{$_-ne''})
        if($segments.Count-eq0-or@($segments|Where-Object{$_-eq'..'-or$_-eq'.'}).Count){throw "Candidate archive entry is not a canonical relative path: $entry"}
        $canonical=$segments-join'/'
        if(-not$seen.Add($canonical)){throw "Candidate archive contains a duplicate path: $canonical"}
    }
    foreach($required in @($RequiredEntries)){
        if(-not$seen.Contains($required)){throw "Candidate archive is missing required prerequisite input: $required"}
    }
    return $true
}

function Get-DevFleetCampaignEPrerequisitePlan {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [ValidateSet('Desktop','Laptop')][string]$Role='Desktop'
    )
    $root=(Resolve-Path -LiteralPath $PackageRoot).Path
    $versionPath=Join-Path $root 'VERSION'
    $manifestPath=Join-Path $root 'dependencies.json'
    $configPath=Join-Path $root 'config\devfleet.config.json'
    foreach($path in @($versionPath,$manifestPath,$configPath,(Join-Path $root 'Bootstrap-Install.ps1'),(Join-Path $root 'Install-DevFleet.ps1'),(Join-Path $root 'windows\DevFleet.Common.psm1'))){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Candidate prerequisite input is missing: $path"}}
    $version=(Get-Content -LiteralPath $versionPath -Raw).Trim()
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -ErrorAction Stop
    $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -ErrorAction Stop
    if([int]$manifest.schemaVersion-ne1-or[string]$manifest.manifestVersion-cne$version){throw 'Candidate dependency manifest schema/version mismatch.'}
    if([int]$config.SchemaVersion-ne2-or[string]$config.PackageVersion-cne$version){throw 'Candidate configuration schema/version mismatch.'}
    $selected=[ordered]@{}
    foreach($id in @('powershell7','multipass')){
        $matches=@($manifest.dependencies|Where-Object{[string]$_.id-ceq$id})
        if($matches.Count-ne1){throw "Candidate dependency identity must be unique: $id"}
        $dependency=$matches[0]
        if(-not[bool]$dependency.required-or@($dependency.roles|ForEach-Object{[string]$_})-cnotcontains$Role){throw "Candidate dependency is not required for role ${Role}: $id"}
        if([string]$dependency.minimumSupportedVersion-notmatch'^\d+\.\d+\.\d+$'-or[Version]$dependency.minimumSupportedVersion-le[Version]'0.0.0'){throw "Candidate dependency minimum version is invalid: $id"}
        $selected[$id]=[ordered]@{id=$id;minimumSupportedVersion=[string]$dependency.minimumSupportedVersion;maximumMajor=$dependency.maximumMajor;wingetPackageId=[string]$dependency.wingetPackageId;resolverType=[string]$dependency.directOfficialVendorResolver.type;allowedSignerSubjectsExact=@($dependency.installerAuthenticityPolicy.allowedSignerSubjectsExact|ForEach-Object{[string]$_})}
    }
    if([string]$selected.powershell7.wingetPackageId-cne'Microsoft.PowerShell'-or[string]$selected.multipass.wingetPackageId-cne'Canonical.Multipass'){throw 'Candidate prerequisite package mapping is unsupported.'}
    $names=@([string]$config.Primary.InstanceName,[string]$config.Failover.InstanceName,[string]$config.Vault.InstanceName)
    if($names.Count-ne3-or@($names|Where-Object{$_-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'}).Count-or@($names|Select-Object -Unique).Count-ne3){throw 'Candidate product instance identities are invalid.'}
    [pscustomobject][ordered]@{
        schemaVersion=1;role=$Role;packageVersion=$version;dependencyIds=@('powershell7','multipass');expectedBackend='hyperv';privilegedMounts=$false
        ubuntuImage=[string]$config.Primary.UbuntuImage;candidateInstanceNames=$names
        inputHashes=[ordered]@{
            version=(Get-FileHash -LiteralPath $versionPath -Algorithm SHA256).Hash.ToLowerInvariant()
            dependencies=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
            config=(Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
            bootstrap=(Get-FileHash -LiteralPath (Join-Path $root 'Bootstrap-Install.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
            install=(Get-FileHash -LiteralPath (Join-Path $root 'Install-DevFleet.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
            common=(Get-FileHash -LiteralPath (Join-Path $root 'windows\DevFleet.Common.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        dependencies=$selected
    }
}

function Invoke-DevFleetCampaignEPowerShellAcquisition {
    param(
        [Parameter(Mandatory)][psobject]$Dependency,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [Parameter(Mandatory)][scriptblock]$TrustedWingetCandidateProvider,
        [Parameter(Mandatory)][scriptblock]$NativeProbeProvider,
        [Parameter(Mandatory)][scriptblock]$PowerShellCompatibilityProvider,
        [scriptblock]$ClockProvider
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}}
    $owner=$OwnerDeadlineUtc.ToUniversalTime()
    $started=&$now
    if($owner-le$started){throw 'Campaign E PowerShell acquisition owner deadline expired before compatibility inspection.'}
    if([string]$Dependency.id-cne'powershell7'-or[string]$Dependency.wingetPackageId-cne'Microsoft.PowerShell'){throw 'Campaign E PowerShell acquisition package identity is unsupported.'}
    if([string]$Dependency.minimumSupportedVersion-notmatch'^\d+\.\d+\.\d+$'-or[Version][string]$Dependency.minimumSupportedVersion-le[Version]'0.0.0'){throw 'Campaign E PowerShell acquisition minimum version is invalid.'}
    if($null-eq$Dependency.maximumMajor-or[int]$Dependency.maximumMajor-ne7){throw 'Campaign E PowerShell acquisition maximum-major policy is invalid.'}

    $validateCompatibility={
        param($Status)
        if($null-eq$Status){throw 'Campaign E PowerShell compatibility provider returned no observation.'}
        if([string]$Status.status-cne'Compatible'){return $false}
        $version=[Version][string]$Status.version
        if($version-lt[Version][string]$Dependency.minimumSupportedVersion-or$version.Major-gt[int]$Dependency.maximumMajor){throw 'Campaign E PowerShell compatibility result violates the candidate version policy.'}
        if([string]$Status.pathSha256-notmatch'^[0-9a-f]{64}$'){throw 'Campaign E PowerShell compatibility result lacks an exact executable hash.'}
        return $true
    }
    $initial=&$PowerShellCompatibilityProvider $Dependency $owner
    if(&$validateCompatibility $initial){
        $preservedFinished=&$now
        if($preservedFinished-gt$owner){throw 'Campaign E PowerShell compatibility observation completed after its immutable owner deadline.'}
        return [pscustomobject][ordered]@{
            schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='PRESERVED_CANDIDATE_COMPATIBLE'
            packageId=[string]$Dependency.wingetPackageId;startedAtUtc=$started.ToString('o');finishedAtUtc=$preservedFinished.ToString('o');ownerDeadlineUtc=$owner.ToString('o')
            wingetPathSha256='';operations=@();powershell=[pscustomobject]@{status='Compatible';version=[string]$initial.version;pathSha256=[string]$initial.pathSha256}
            productLifecycleStarted=$false;stageMarkerWritten=$false
        }
    }

    $candidates=@(&$TrustedWingetCandidateProvider $Dependency)
    if($candidates.Count-ne1){throw 'Campaign E PowerShell acquisition requires exactly one candidate-trusted physical WinGet executable.'}
    $candidate=$candidates[0]
    if(-not[bool]$candidate.trustValidated){throw 'Campaign E PowerShell acquisition rejected an unvalidated WinGet candidate.'}
    $wingetPath=[IO.Path]::GetFullPath([string]$candidate.path)
    $wingetRoot=[IO.Path]::GetFullPath([string]$candidate.root).TrimEnd('\')
    if(-not[IO.Path]::GetFileName($wingetPath).Equals('winget.exe',[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetDirectoryName($wingetPath).TrimEnd('\').Equals($wingetRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Campaign E PowerShell acquisition WinGet path/root identity is invalid.'}
    if(-not(Test-Path -LiteralPath $wingetPath -PathType Leaf)){throw 'Campaign E PowerShell acquisition WinGet executable is absent.'}
    $wingetHash=(Get-FileHash -LiteralPath $wingetPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $specifications=@(
        [pscustomobject]@{operation='winget-version';arguments=@('--version');seconds=60;allowAlreadySatisfied=$false;requirePackageId=$false},
        [pscustomobject]@{operation='winget-source-list';arguments=@('source','list','--disable-interactivity');seconds=60;allowAlreadySatisfied=$false;requirePackageId=$false},
        [pscustomobject]@{operation='winget-source-update';arguments=@('source','update','--name','winget','--disable-interactivity');seconds=300;allowAlreadySatisfied=$false;requirePackageId=$false},
        [pscustomobject]@{operation='winget-powershell-search';arguments=@('search','--id',[string]$Dependency.wingetPackageId,'--exact','--source','winget','--disable-interactivity');seconds=90;allowAlreadySatisfied=$false;requirePackageId=$true},
        [pscustomobject]@{operation='winget-powershell-install';arguments=@('install','--id',[string]$Dependency.wingetPackageId,'--exact','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity');seconds=900;allowAlreadySatisfied=$true;requirePackageId=$false}
    )
    $observations=[Collections.Generic.List[object]]::new()
    $lastFinished=$started
    foreach($specification in $specifications){
        $observed=&$now
        $remaining=[int][math]::Floor(($owner-$observed).TotalSeconds)
        if($remaining-le0){throw "Campaign E PowerShell acquisition owner deadline expired before $([string]$specification.operation)."}
        $raw=&$NativeProbeProvider ([string]$specification.operation) $wingetPath ([string[]]$specification.arguments) ([math]::Min([int]$specification.seconds,$remaining)) $owner
        if($null-eq$raw-or[string]$raw.operation-cne[string]$specification.operation){throw "Campaign E PowerShell acquisition received a mismatched native observation for $([string]$specification.operation)."}
        $rawStarted=([datetime]$raw.startedAtUtc).ToUniversalTime();$rawFinished=([datetime]$raw.finishedAtUtc).ToUniversalTime();$rawDeadline=([datetime]$raw.deadlineUtc).ToUniversalTime()
        if($rawStarted-lt$observed-or$rawStarted-lt$lastFinished-or$rawFinished-lt$rawStarted-or$rawFinished-gt$owner-or$rawDeadline-gt$owner){throw "Campaign E PowerShell acquisition received an out-of-deadline or nonmonotonic native observation for $([string]$specification.operation)."}
        $accepted=[string]$raw.outcome-ceq'PASS'
        if([bool]$specification.allowAlreadySatisfied-and[string]$raw.outcome-ceq'NONZERO'-and[int]$raw.exitCode-eq-1978335189){$accepted=$true}
        if(-not$accepted-or-not[bool]$raw.outputComplete){throw "Campaign E PowerShell acquisition operation failed: $([string]$specification.operation) / $([string]$raw.outcome) / $([string]$raw.exitCode)."}
        if([string]$specification.operation-ceq'winget-version'-and[string]$raw.stdout-notmatch'(?<!\d)\d+\.\d+(?:\.\d+){0,2}'){throw 'Campaign E PowerShell acquisition could not parse the bounded WinGet version response.'}
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
        if([string]$raw.outcome-cne'PASS'){$state.primaryError="M1 $Operation returned $([string]$raw.outcome).";return $null}
        if(-not[bool]$raw.outputComplete){$state.primaryError="M1 $Operation returned incomplete output.";return $null}
        return $raw
    }.GetNewClosure()
    $launchArguments=@('launch',$UbuntuImage,'--name',$InstanceName,'--cpus',[string]$Resources.cpus,'--memory',[string]$Resources.memory,'--disk',[string]$Resources.disk)
    if($CloudInitPath){$launchArguments+=@('--cloud-init',$CloudInitPath)}
    $launch=&$invoke 'launch' $launchArguments 900
    if($launch){$progress.launchAccepted=$true}
    $info=$null
    if($launch){$info=&$invoke 'info-running' @('info',$InstanceName,'--format','json') 60}
    if($info){
        try{$parsed=[string]$info.stdout|ConvertFrom-Json -ErrorAction Stop;$properties=@($parsed.info.PSObject.Properties|Where-Object{[string]$_.Name-ceq$InstanceName});if($properties.Count-ne1){throw 'exact instance key missing'};$row=$properties[0].Value;if([string]$row.state-cne'Running'){throw 'instance not Running'};$addresses=@($row.ipv4|Where-Object{[string]$_-match'^\d{1,3}(?:\.\d{1,3}){3}$'});if($addresses.Count-lt1){throw 'IPv4 absent'};$progress.instanceRunning=$true;$progress.ipObserved=$true}catch{$state.primaryError="M1 info-running response was malformed: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)"}
    }
    $ssh=$null;if($progress.instanceRunning){$ssh=&$invoke 'ssh-ready' @('exec',$InstanceName,'--','true') 120;if($ssh){$progress.sshReady=$true}}
    $cloud=$null;if($progress.sshReady){$cloud=&$invoke 'cloud-init' @('exec',$InstanceName,'--','cloud-init','status','--wait') 300;if($cloud){if([string]$cloud.stdout-notmatch'(?im)^status:\s*done\s*$'){$state.primaryError='M1 cloud-init did not report done.'}else{$progress.cloudInitDone=$true}}}
    $finalInfo=$null;if($progress.cloudInitDone){$finalInfo=&$invoke 'info-final' @('info',$InstanceName,'--format','json') 60;if($finalInfo){try{$parsed=[string]$finalInfo.stdout|ConvertFrom-Json -ErrorAction Stop;$properties=@($parsed.info.PSObject.Properties|Where-Object{[string]$_.Name-ceq$InstanceName});if($properties.Count-ne1-or[string]$properties[0].Value.state-cne'Running'){throw 'final exact Running state missing'}}catch{$state.primaryError="M1 final info response was malformed: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)"}}}
    $finished=&$now
    [pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_M1_SEQUENCE';status=if($progress.launchAccepted-and$progress.instanceRunning-and$progress.ipObserved-and$progress.sshReady-and$progress.cloudInitDone-and$finalInfo-and-not$state.primaryError){'PASS'}else{'BLOCKED'};runId=$RunId;instanceName=$InstanceName;ubuntuImage=$UbuntuImage;resources=[ordered]@{cpus=[int]$Resources.cpus;memory=[string]$Resources.memory;disk=[string]$Resources.disk;diagnosticDeviation=$true};startedAtUtc=$started.ToString('o');producedAtUtc=$finished.ToString('o');ownerDeadlineUtc=$owner.ToString('o');progress=$progress;observations=@($observations);primaryError=[string]$state.primaryError;productLifecycleStarted=$false;productProgressClaimed=$false}
}

function New-DevFleetCampaignEM1CleanupState {
    param([Parameter(Mandatory)][ValidatePattern('^DevFleet-E2E-E-M1-[A-Za-z0-9._-]+$')][string]$InstanceName)
    [ordered]@{status='UNVERIFIED';instanceName=$InstanceName;delete=$null;inventory=$null;finalInventoryCount=-1}
}

function Assert-DevFleetCampaignEM1Result {
    param([Parameter(Mandatory)][psobject]$Result,[Parameter(Mandatory)][string]$ExpectedRunId,[Parameter(Mandatory)][guid]$ExpectedVmId,[Parameter(Mandatory)][string]$ExpectedInstanceName,[Parameter(Mandatory)][string]$ExpectedPayloadSha256,[hashtable]$ExpectedResources=@{cpus=2;memory='2G';disk='10G'})
    if([int]$Result.schemaVersion-ne1-or[string]$Result.kind-cne'DEVFLEET_CAMPAIGN_E_M1_RESULT'-or[string]$Result.status-cnotin@('PASS_DIAGNOSTIC','BLOCKED')){throw 'Campaign E M1 result schema/status is invalid.'}
    if([string]$Result.runId-cne$ExpectedRunId-or[guid][string]$Result.vmId-ne$ExpectedVmId-or[string]$Result.instanceName-cne$ExpectedInstanceName-or[string]$Result.payloadSha256-cne$ExpectedPayloadSha256){throw 'Campaign E M1 result identity mismatch.'}
    $deadline=([datetime]$Result.ownerDeadlineUtc).ToUniversalTime();$produced=([datetime]$Result.producedAtUtc).ToUniversalTime();if($produced-gt$deadline){throw 'Campaign E M1 result was produced after cutoff.'}
    if([string]$Result.multipassSha256-notmatch'^[0-9a-f]{64}$'-or[bool]$Result.productLifecycleStarted-or[bool]$Result.productProgressClaimed-or[bool]$Result.boundaryBefore.activeTransactionPresent-or[int]$Result.boundaryBefore.stageMarkerCount-ne0-or[bool]$Result.boundaryAfter.activeTransactionPresent-or[int]$Result.boundaryAfter.stageMarkerCount-ne0){throw 'Campaign E M1 fabricated or crossed the product boundary.'}
    if([string]$Result.cleanup.status-cne'ABSENT_VERIFIED'-or[string]$Result.cleanup.instanceName-cne$ExpectedInstanceName-or[int]$Result.cleanup.finalInventoryCount-ne0){throw 'Campaign E M1 cleanup did not prove exact empty inventory.'}
    if([string]$Result.status-ceq'PASS_DIAGNOSTIC'){
        $sequence=$Result.sequence;$sequenceDeadline=([datetime]$sequence.ownerDeadlineUtc).ToUniversalTime();$sequenceStarted=([datetime]$sequence.startedAtUtc).ToUniversalTime();$sequenceProduced=([datetime]$sequence.producedAtUtc).ToUniversalTime()
        if([string]$sequence.status-cne'PASS'-or[string]$sequence.runId-cne$ExpectedRunId-or[string]$sequence.instanceName-cne$ExpectedInstanceName-or$sequenceStarted-gt$sequenceDeadline-or$sequenceProduced-lt$sequenceStarted-or$sequenceProduced-gt$sequenceDeadline-or$sequenceDeadline-gt$deadline-or[bool]$sequence.productLifecycleStarted-or[bool]$sequence.productProgressClaimed-or-not[bool]$sequence.resources.diagnosticDeviation-or[int]$sequence.resources.cpus-ne[int]$ExpectedResources.cpus-or[string]$sequence.resources.memory-cne[string]$ExpectedResources.memory-or[string]$sequence.resources.disk-cne[string]$ExpectedResources.disk-or-not[bool]$sequence.progress.launchAccepted-or-not[bool]$sequence.progress.instanceRunning-or-not[bool]$sequence.progress.ipObserved-or-not[bool]$sequence.progress.sshReady-or-not[bool]$sequence.progress.cloudInitDone){throw 'Campaign E M1 PASS lacks required identity/deadline/readiness evidence.'}
        $expected=@('launch','info-running','ssh-ready','cloud-init','info-final');$ops=@($sequence.observations);if($ops.Count-ne$expected.Count){throw 'Campaign E M1 PASS operation count is invalid.'};$previous=$sequenceStarted;for($i=0;$i-lt$expected.Count;$i++){$opStarted=([datetime]$ops[$i].startedAtUtc).ToUniversalTime();$opFinished=([datetime]$ops[$i].finishedAtUtc).ToUniversalTime();$opDeadline=([datetime]$ops[$i].deadlineUtc).ToUniversalTime();if([string]$ops[$i].operation-cne$expected[$i]-or[string]$ops[$i].outcome-cne'PASS'-or-not[bool]$ops[$i].outputComplete-or$opStarted-lt$previous-or$opFinished-lt$opStarted-or$opFinished-gt$sequenceProduced-or$opDeadline-gt$sequenceDeadline){throw 'Campaign E M1 PASS operation evidence is invalid.'};$previous=$opFinished}
    }
    $serialized=$Result|ConvertTo-Json -Depth 24 -Compress;if($serialized-match'(?i)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*(?!<redacted>|\\u003credacted\\u003e)[^,}\"]+'){throw 'Campaign E M1 result contains unredacted secret-shaped evidence.'}
    return $true
}

function Get-DevFleetCampaignEDeadlinePartition {
    param(
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [ValidateRange(60,900)][int]$ReservedTerminalizationSeconds=300,
        [scriptblock]$ClockProvider
    )
    $now=if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}
    $owner=$OwnerDeadlineUtc.ToUniversalTime()
    $child=$owner.AddSeconds(-$ReservedTerminalizationSeconds)
    if($child-le$now){throw 'Campaign E owner deadline cannot provide the required terminalization reserve.'}
    [pscustomobject][ordered]@{observedAtUtc=$now.ToString('o');childDeadlineUtc=$child.ToString('o');ownerDeadlineUtc=$owner.ToString('o');terminalizationDeadlineUtc=$owner.AddSeconds($ReservedTerminalizationSeconds).ToString('o');reservedTerminalizationSeconds=$ReservedTerminalizationSeconds;childRemainingSeconds=[int][math]::Floor(($child-$now).TotalSeconds);ownerRemainingSeconds=[int][math]::Floor(($owner-$now).TotalSeconds)}
}

function Assert-DevFleetCampaignEPrerequisiteResult {
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [Parameter(Mandatory)][string]$ExpectedRunId,
        [Parameter(Mandatory)][guid]$ExpectedVmId,
        [Parameter(Mandatory)][string]$ExpectedPayloadSha256,
        [Parameter(Mandatory)][psobject]$ExpectedPlan
    )
    if([int]$Result.schemaVersion-ne1-or[string]$Result.kind-cne'DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY'){throw 'Prerequisite result schema identity is invalid.'}
    if([string]$Result.runId-cne$ExpectedRunId-or[guid][string]$Result.vmId-ne$ExpectedVmId){throw 'Prerequisite result run/VM identity mismatch.'}
    if([string]$Result.payloadSha256-cne$ExpectedPayloadSha256){throw 'Prerequisite result payload identity mismatch.'}
    if([string]$Result.status-cne'PASS'){throw "Prerequisite result is not PASS: $([string]$Result.status)"}
    $deadline=([datetime]$Result.ownerDeadlineUtc).ToUniversalTime();$started=([datetime]$Result.startedAtUtc).ToUniversalTime();$produced=([datetime]$Result.producedAtUtc).ToUniversalTime()
    if($started-gt$deadline-or$produced-gt$deadline-or$produced-lt$started){throw 'Prerequisite result violates its immutable owner deadline.'}
    if([string]$Result.role-cne[string]$ExpectedPlan.role-or[string]$Result.packageVersion-cne[string]$ExpectedPlan.packageVersion){throw 'Prerequisite result candidate role/version mismatch.'}
    foreach($name in @('version','dependencies','config','bootstrap','install','common')){if([string]$Result.inputHashes.$name-cne[string]$ExpectedPlan.inputHashes.$name){throw "Prerequisite result candidate input hash mismatch: $name"}}
    if([bool]$Result.systemPolicyChanged-or[bool]$Result.productLifecycleStarted-or[bool]$Result.activeTransactionPresent-or[int]$Result.stageMarkerCount-ne0-or[int]$Result.activeInstallProcessCount-ne0){throw 'Prerequisite result crossed a forbidden product/security boundary.'}
    if([bool]$Result.pendingReboot){throw 'Prerequisite state requires a reboot and is not checkpoint-ready.'}
    $powerShellVersion=[Version][string]$Result.powershell.version
    if([string]$Result.powershell.status-cne'Compatible'-or$powerShellVersion-lt[Version][string]$ExpectedPlan.dependencies.powershell7.minimumSupportedVersion-or$powerShellVersion.Major-gt[int]$ExpectedPlan.dependencies.powershell7.maximumMajor-or[string]$Result.powershell.pathSha256-notmatch'^[0-9a-f]{64}$'){throw 'PowerShell did not reach the candidate compatibility policy.'}
    $acquisition=$Result.powershellAcquisition
    if($null-eq$acquisition-or[int]$acquisition.schemaVersion-ne1-or[string]$acquisition.kind-cne'DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION'-or[string]$acquisition.status-cne'PASS'){throw 'PowerShell acquisition evidence is missing or malformed.'}
    if([string]$acquisition.packageId-cne[string]$ExpectedPlan.dependencies.powershell7.wingetPackageId-or[bool]$acquisition.productLifecycleStarted-or[bool]$acquisition.stageMarkerWritten){throw 'PowerShell acquisition evidence violates the candidate/product boundary.'}
    $acquisitionStarted=([datetime]$acquisition.startedAtUtc).ToUniversalTime();$acquisitionFinished=([datetime]$acquisition.finishedAtUtc).ToUniversalTime();$acquisitionDeadline=([datetime]$acquisition.ownerDeadlineUtc).ToUniversalTime()
    if($acquisitionStarted-lt$started-or$acquisitionFinished-lt$acquisitionStarted-or$acquisitionFinished-gt$produced-or$acquisitionDeadline-ne$deadline){throw 'PowerShell acquisition evidence violates the prerequisite owner timeline.'}
    if([string]$acquisition.powershell.status-cne'Compatible'-or[string]$acquisition.powershell.version-cne[string]$Result.powershell.version-or[string]$acquisition.powershell.pathSha256-cne[string]$Result.powershell.pathSha256){throw 'PowerShell acquisition and final candidate compatibility evidence disagree.'}
    $acquisitionOperations=@($acquisition.operations)
    if([string]$acquisition.method-ceq'PRESERVED_CANDIDATE_COMPATIBLE'){
        if($acquisitionOperations.Count-ne0-or-not[string]::IsNullOrEmpty([string]$acquisition.wingetPathSha256)){throw 'Preserved PowerShell acquisition contains unexpected WinGet evidence.'}
    } elseif([string]$acquisition.method-ceq'WINGET_MANIFEST_APPROVED_DIAGNOSTIC'){
        if([string]$acquisition.wingetPathSha256-notmatch'^[0-9a-f]{64}$'-or$acquisitionOperations.Count-ne5){throw 'WinGet PowerShell acquisition identity/operation evidence is incomplete.'}
        $expectedOperations=@('winget-version','winget-source-list','winget-source-update','winget-powershell-search','winget-powershell-install');$previous=$acquisitionStarted
        for($index=0;$index-lt$expectedOperations.Count;$index++){
            $operation=$acquisitionOperations[$index];$operationStarted=([datetime]$operation.startedAtUtc).ToUniversalTime();$operationFinished=([datetime]$operation.finishedAtUtc).ToUniversalTime();$operationDeadline=([datetime]$operation.deadlineUtc).ToUniversalTime()
            if([string]$operation.operation-cne$expectedOperations[$index]-or$operationStarted-lt$previous-or$operationFinished-lt$operationStarted-or$operationFinished-gt$acquisitionFinished-or$operationDeadline-gt$deadline-or-not[bool]$operation.outputComplete){throw 'WinGet PowerShell acquisition operation sequence/deadline evidence is invalid.'}
            $accepted=[string]$operation.outcome-ceq'PASS'
            if($index-eq4-and[string]$operation.outcome-ceq'NONZERO'-and[int]$operation.exitCode-eq-1978335189){$accepted=$true}
            if(-not$accepted){throw 'WinGet PowerShell acquisition operation did not pass.'}
            $previous=$operationFinished
        }
        if(-not[bool]$acquisitionOperations[3].packageIdentityObserved){throw 'WinGet search did not record the exact candidate package identity.'}
    } elseif([string]$acquisition.method-ceq'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'){
        if(-not[string]::IsNullOrEmpty([string]$acquisition.wingetPathSha256)-or$acquisitionOperations.Count-ne1){throw 'Staged official PowerShell acquisition contains invalid operation evidence.'}
        $official=$acquisition.officialPayload
        if($null-eq$official-or[string]$official.releaseTag-notmatch'^v7\.\d+\.\d+$'-or[string]$official.assetName-notmatch'^PowerShell-7\.[0-9.]+-win-x64\.msi$'-or[string]$official.sha256-notmatch'^[0-9a-f]{64}$'-or[int64]$official.bytes-lt1-or-not(Test-DevFleetCampaignEExactSignerSubject -Actual ([string]$official.signerSubject) -Expected @($ExpectedPlan.dependencies.powershell7.allowedSignerSubjectsExact))){throw 'Staged official PowerShell payload evidence is incomplete.'}
        $operation=$acquisitionOperations[0];$operationStarted=([datetime]$operation.startedAtUtc).ToUniversalTime();$operationFinished=([datetime]$operation.finishedAtUtc).ToUniversalTime();$operationDeadline=([datetime]$operation.deadlineUtc).ToUniversalTime()
        $accepted=[string]$operation.outcome-ceq'PASS';if([string]$operation.outcome-ceq'NONZERO'-and[int]$operation.exitCode-eq3010){$accepted=$true}
        if([string]$operation.operation-cne'official-powershell-msi-install'-or-not$accepted-or-not[bool]$operation.outputComplete-or-not[bool]$operation.packageIdentityObserved-or$operationStarted-lt$acquisitionStarted-or$operationFinished-lt$operationStarted-or$operationFinished-gt$acquisitionFinished-or$operationDeadline-gt$deadline){throw 'Staged official PowerShell installation evidence is invalid.'}
    } else {throw 'PowerShell acquisition method is unsupported.'}
    if([string]$Result.multipass.status-cne'Compatible'-or[Version][string]$Result.multipass.version-lt[Version][string]$ExpectedPlan.dependencies.multipass.minimumSupportedVersion){throw 'Multipass did not reach the candidate compatibility policy.'}
    if([string]$Result.backend.driver-cne[string]$ExpectedPlan.expectedBackend-or[bool]$Result.backend.privilegedMounts-or[int]$Result.backend.inventoryCount-ne0){throw 'Prerequisite backend is not the required empty Hyper-V/no-mount baseline.'}
    if([string]$Result.l2Status-cne'ABSENT'){throw 'Prerequisite result does not positively establish L2 absence.'}
    $serialized=$Result|ConvertTo-Json -Depth 20 -Compress
    if($serialized-match'(?i)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*(?!<redacted>|\\u003credacted\\u003e)[^,}\"]+'){throw 'Prerequisite result contains unredacted secret-shaped evidence.'}
    return $true
}

function ConvertTo-DevFleetMultipassProbeObservation {
    param(
        [Parameter(Mandatory)][psobject]$Probe,
        [Parameter(Mandatory)][string]$UbuntuImage,
        [Parameter(Mandatory)][string[]]$CandidateInstanceNames,
        [Parameter(Mandatory)][string]$RunOwnedPrefix
    )
    $allowedOperations=@('version','driver','privileged-mounts','inventory','image')
    $operation=[string]$Probe.operation
    if($operation -notin $allowedOperations){throw "Diagnostic probe operation is not allowlisted: $operation"}
    $outcome=[string]$Probe.outcome
    $observation=[ordered]@{operation=$operation;outcome=$outcome;exitCode=$Probe.exitCode;pid=if($Probe.PSObject.Properties['pid']){$Probe.pid}else{$null};startedAtUtc=[string]$Probe.startedAtUtc;finishedAtUtc=[string]$Probe.finishedAtUtc;deadlineUtc=if($Probe.PSObject.Properties['deadlineUtc']){[string]$Probe.deadlineUtc}else{''};outputComplete=if($Probe.PSObject.Properties['outputComplete']){[bool]$Probe.outputComplete}else{$true};stdoutTruncated=if($Probe.PSObject.Properties['stdoutTruncated']){[bool]$Probe.stdoutTruncated}else{$false};stderrTruncated=if($Probe.PSObject.Properties['stderrTruncated']){[bool]$Probe.stderrTruncated}else{$false};data=$null;error=''}
    if($outcome -ne 'PASS'){$observation.error=ConvertTo-DevFleetDiagnosticSafeText $Probe.stderr;return [pscustomobject]$observation}
    $stdout=[string]$Probe.stdout
    try {
        switch($operation){
            'version' {
                $match=[regex]::Match($stdout,'(?i)\bmultipass\s+(?:version\s+)?v?(\d+\.\d+(?:\.\d+)?)')
                if(-not$match.Success){throw 'Multipass version output was malformed.'}
                $observation.data=[ordered]@{version=$match.Groups[1].Value}
            }
            'driver' {
                $value=$stdout.Trim().ToLowerInvariant()
                if($value -notin @('hyperv','virtualbox')){throw 'Multipass driver output was malformed or unsupported.'}
                $observation.data=[ordered]@{driver=$value}
            }
            'privileged-mounts' {
                $value=$stdout.Trim().ToLowerInvariant()
                if($value -notin @('true','false')){throw 'Multipass privileged-mount output was malformed.'}
                $observation.data=[ordered]@{enabled=($value -eq 'true')}
            }
            'inventory' {
                $parsed=$stdout|ConvertFrom-Json -ErrorAction Stop
                $instances=@(if($parsed.PSObject.Properties.Name -contains 'list'){$parsed.list}elseif($parsed -is [array]){$parsed}else{throw 'Multipass inventory omitted its list.'})
                $owned=@();$candidate=@();$foreign=0
                foreach($row in $instances){
                    $name=[string]$row.name
                    if($name -and $name.StartsWith($RunOwnedPrefix,[StringComparison]::Ordinal)){$owned+=$name}
                    elseif($CandidateInstanceNames -ccontains $name){$candidate+=$name}
                    else{$foreign++}
                }
                $observation.data=[ordered]@{count=$instances.Count;runOwnedNames=@($owned|Sort-Object -Unique);candidateNames=@($candidate|Sort-Object -Unique);foreignCount=$foreign}
            }
            'image' {
                if($stdout -notmatch [regex]::Escape($UbuntuImage)){throw 'Multipass image query did not identify the candidate-bound image.'}
                $observation.data=[ordered]@{image=$UbuntuImage;available=$true}
            }
        }
    } catch {
        $observation.outcome='MALFORMED'
        $observation.error=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message
        $observation.data=$null
    }
    return [pscustomobject]$observation
}

function Get-DevFleetMultipassM0Snapshot {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
        [Parameter(Mandatory)][string]$ExpectedVmName,
        [Parameter(Mandatory)][guid]$ExpectedVmId,
        [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+$')][string]$UbuntuImage,
        [Parameter(Mandatory)][string[]]$CandidateInstanceNames,
        [Parameter(Mandatory)][ValidatePattern('^DevFleet-E2E-E-[A-Za-z0-9._-]+$')][string]$RunOwnedPrefix,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [scriptblock]$EnvironmentProvider,
        [scriptblock]$NativeProbeProvider,
        [scriptblock]$EventProvider,
        [scriptblock]$ClockProvider,
        [AllowNull()][string]$PrimaryError
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}}
    $started=&$now;$ownerDeadline=$OwnerDeadlineUtc.ToUniversalTime()
    if($ownerDeadline -le $started){throw 'Campaign E M0 owner deadline is already expired.'}
    $errors=[Collections.Generic.List[string]]::new()
    $safePrimary=ConvertTo-DevFleetDiagnosticSafeText $PrimaryError
    $environment=$null
    try {
        if($EnvironmentProvider){$environment=&$EnvironmentProvider $ExpectedVmName $ExpectedVmId $CandidateInstanceNames $RunOwnedPrefix}
        else {
            $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=[Security.Principal.WindowsPrincipal]::new($identity)
            $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $systemDrive=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
            $processor=Get-CimInstance Win32_Processor -ErrorAction Stop|Select-Object -First 1
            $feature=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction Stop
            $paths=@(Get-DevFleetExistingFilePathSet -CandidatePaths @((Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe')))
            if($paths.Count -eq 0){$command=Get-Command multipass.exe -ErrorAction SilentlyContinue;if(-not$command){$command=Get-Command multipass -ErrorAction SilentlyContinue};if($command){$paths=@([string]$command.Source)}}
            $paths=@($paths|Select-Object -Unique)
            $multipass=[ordered]@{executableStatus=if($paths.Count-eq 0){'ABSENT'}elseif($paths.Count-eq 1){'PRESENT'}else{'AMBIGUOUS'};executablePresent=($paths.Count-eq 1);executablePath=if($paths.Count-eq 1){$paths[0]}else{''};sha256=if($paths.Count-eq 1){(Get-FileHash -LiteralPath $paths[0] -Algorithm SHA256).Hash.ToLowerInvariant()}else{''};fileVersion=if($paths.Count-eq 1){[string](Get-Item -LiteralPath $paths[0]).VersionInfo.FileVersion}else{''}}
            $services=@(Get-CimInstance Win32_Service -ErrorAction Stop|Where-Object{[string]$_.Name -match '^(?i:multipass(?:d)?(?:\..*)?)$'}|ForEach-Object{[ordered]@{name=[string]$_.Name;state=[string]$_.State;startMode=[string]$_.StartMode;processId=[int]$_.ProcessId;accountKind=switch -Regex ([string]$_.StartName){'^(?i:LocalSystem|NT AUTHORITY\\SYSTEM)$'{'SYSTEM';break}'^(?i:NT AUTHORITY\\NetworkService)$'{'NETWORK_SERVICE';break}'^(?i:NT AUTHORITY\\LocalService)$'{'LOCAL_SERVICE';break}default{'OTHER'}}}})
            $hyperVNames=@();$hyperVForeign=0
            if([string]$feature.State -eq 'Enabled'){
                foreach($row in @(Get-CimInstance -Namespace 'root\virtualization\v2' -ClassName Msvm_ComputerSystem -ErrorAction Stop|Where-Object{[string]$_.Caption -eq 'Virtual Machine'})){
                    $name=[string]$row.ElementName
                    if($CandidateInstanceNames -ccontains $name -or $name.StartsWith($RunOwnedPrefix,[StringComparison]::Ordinal)){$hyperVNames+=$name}else{$hyperVForeign++}
                }
            }
            $activeTransaction=Test-Path -LiteralPath (Join-Path $env:ProgramData 'DevFleet\active-transaction.json') -PathType Leaf
            $activeInstallProcesses=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{[string]$_.Name -in @('DevFleet.Setup.exe','pwsh.exe','powershell.exe') -and [string]$_.CommandLine -match '(?i)Install-DevFleet|Bootstrap-Install|DevFleet.Setup'}).Count
            $dnsStatus='UNAVAILABLE';$dnsAddressCount=0
            try{$dnsTask=[Net.Dns]::GetHostAddressesAsync('cloud-images.ubuntu.com');if($dnsTask.Wait([TimeSpan]::FromSeconds(10))){$dnsStatus='PASS';$dnsAddressCount=@($dnsTask.GetAwaiter().GetResult()).Count}else{$dnsStatus='TIMEOUT'}}catch{$dnsStatus='ERROR'}
            $vboxExe=@((Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Oracle\VirtualBox\VBoxManage.exe'))|Where-Object{$_-and(Test-Path -LiteralPath $_ -PathType Leaf)}|Select-Object -First 1
            $vboxServices=@(Get-CimInstance Win32_Service -ErrorAction Stop|Where-Object{[string]$_.Name -match '^(?i:VBox)'}).Count
            $environment=[ordered]@{
                computerName=$env:COMPUTERNAME
                principal=[ordered]@{kind=if($identity.IsSystem){'SYSTEM'}elseif($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){'ADMINISTRATOR'}else{'STANDARD_USER'};isAdministrator=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
                capacity=[ordered]@{logicalProcessors=[Environment]::ProcessorCount;totalMemoryBytes=[int64]$os.TotalVisibleMemorySize*1KB;freeMemoryBytes=[int64]$os.FreePhysicalMemory*1KB;systemDriveFreeBytes=[int64]$systemDrive.FreeSpace}
                nestedVirtualization=[ordered]@{hyperVFeatureState=[string]$feature.State;vmMonitorModeExtensions=[bool]$processor.VMMonitorModeExtensions;secondLevelAddressTranslation=[bool]$processor.SecondLevelAddressTranslationExtensions;virtualizationFirmwareEnabled=[bool]$processor.VirtualizationFirmwareEnabled}
                multipass=$multipass
                services=$services
                backendInventory=[ordered]@{hyperV=[ordered]@{status=if([string]$feature.State-eq'Enabled'){'PASS'}else{'UNAVAILABLE'};boundNames=@($hyperVNames|Sort-Object -Unique);foreignCount=$hyperVForeign};virtualBox=[ordered]@{executablePresent=[bool]$vboxExe;serviceCount=[int]$vboxServices;registryPresent=((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox')-or(Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox'))}}
                network=[ordered]@{host='cloud-images.ubuntu.com';status=$dnsStatus;addressCount=[int]$dnsAddressCount}
                activeProduct=[ordered]@{activeTransactionPresent=[bool]$activeTransaction;activeInstallProcessCount=[int]$activeInstallProcesses}
            }
        }
    } catch {[void]$errors.Add("environment: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)")}
    $probes=[Collections.Generic.List[object]]::new()
    $multipassPath=if($environment-and$environment.multipass-and[bool]$environment.multipass.executablePresent){[string]$environment.multipass.executablePath}else{''}
    $definitions=@(
        [ordered]@{operation='version';arguments=@('version');seconds=20},
        [ordered]@{operation='driver';arguments=@('get','local.driver');seconds=20},
        [ordered]@{operation='privileged-mounts';arguments=@('get','local.privileged-mounts');seconds=20},
        [ordered]@{operation='inventory';arguments=@('list','--format','json');seconds=30},
        [ordered]@{operation='image';arguments=@('find',$UbuntuImage);seconds=60}
    )
    foreach($definition in $definitions){
        if(-not$multipassPath){
            [void]$probes.Add([pscustomobject]@{operation=$definition.operation;outcome='SKIPPED_NO_EXECUTABLE';exitCode=$null;pid=$null;startedAtUtc=(&$now).ToString('o');finishedAtUtc=(&$now).ToString('o');deadlineUtc=$ownerDeadline.ToString('o');outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false;data=$null;error=''})
            continue
        }
        $remaining=[int][math]::Floor(($ownerDeadline-(&$now)).TotalSeconds)
        if($remaining -le 0){[void]$probes.Add([pscustomobject]@{operation=$definition.operation;outcome='OWNER_EXPIRED';exitCode=$null;pid=$null;startedAtUtc=(&$now).ToString('o');finishedAtUtc=(&$now).ToString('o');deadlineUtc=$ownerDeadline.ToString('o');outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false;data=$null;error='Owning diagnostic deadline expired.'});continue}
        $raw=if($NativeProbeProvider){&$NativeProbeProvider $definition.operation $multipassPath @($definition.arguments) ([math]::Min([int]$definition.seconds,$remaining)) $ownerDeadline}else{Invoke-DevFleetBoundedNativeProbe -Operation $definition.operation -FilePath $multipassPath -ArgumentList @($definition.arguments) -TimeoutSeconds ([math]::Min([int]$definition.seconds,$remaining)) -OwnerDeadlineUtc $ownerDeadline}
        [void]$probes.Add((ConvertTo-DevFleetMultipassProbeObservation -Probe $raw -UbuntuImage $UbuntuImage -CandidateInstanceNames $CandidateInstanceNames -RunOwnedPrefix $RunOwnedPrefix))
    }
    $events=$null
    try {
        if($EventProvider){$events=&$EventProvider $ownerDeadline}
        else {
            $eventJob=Start-Job -ScriptBlock {
                $start=(Get-Date).AddHours(-4)
                @(Get-WinEvent -FilterHashtable @{LogName=@('System','Application');StartTime=$start} -MaxEvents 400 -ErrorAction SilentlyContinue|Where-Object{[string]$_.ProviderName -match '(?i)Multipass|Hyper-V|vmcompute|Host-Network-Service'}|Select-Object -First 80|ForEach-Object{
                    $message=[string]$_.Message
                    $category=if($message-match'(?i)timeout|timed out'){'TIMEOUT'}elseif($message-match'(?i)permission|denied|unauthor'){'PERMISSION'}elseif($message-match'(?i)memory|disk|space|resource'){'CAPACITY'}elseif($message-match'(?i)network|dns|connect'){'NETWORK'}elseif($message-match'(?i)image|download'){'IMAGE'}elseif($message-match'(?i)daemon|service'){'SERVICE'}else{'OTHER'}
                    [ordered]@{provider=[string]$_.ProviderName;eventId=[int]$_.Id;level=[string]$_.LevelDisplayName;timestampUtc=$_.TimeCreated.ToUniversalTime().ToString('o');category=$category}
                })
            }
            try {
                $remaining=[int][math]::Max(1,[math]::Min(15,[math]::Floor(($ownerDeadline-(&$now)).TotalSeconds)))
                if(-not(Wait-Job -Job $eventJob -Timeout $remaining)){$events=[ordered]@{status='TIMEOUT';records=@()}}
                else{$events=[ordered]@{status='PASS';records=@(Receive-Job -Job $eventJob -ErrorAction SilentlyContinue)}}
            } finally {if($eventJob){Stop-Job -Job $eventJob -ErrorAction SilentlyContinue;Remove-Job -Job $eventJob -Force -ErrorAction SilentlyContinue}}
        }
    } catch {[void]$errors.Add("events: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)");$events=[ordered]@{status='ERROR';records=@()}}
    $finished=&$now
    $status=if($null-eq$environment){'ERROR'}elseif($errors.Count -gt 0 -or @($probes|Where-Object{$_.outcome -in @('OWNER_EXPIRED','DRAIN_INCOMPLETE','START_FAILED')}).Count -gt 0){'PARTIAL'}else{'COMPLETE'}
    return [pscustomobject][ordered]@{
        schemaVersion=1;collector='DevFleet-Campaign-E-Multipass-M0';status=$status;runId=$RunId;expectedVmName=$ExpectedVmName;expectedVmId=$ExpectedVmId.ToString();runOwnedPrefix=$RunOwnedPrefix;ubuntuImage=$UbuntuImage;candidateInstanceNames=@($CandidateInstanceNames);ownerDeadlineUtc=$ownerDeadline.ToString('o');startedAtUtc=$started.ToString('o');producedAtUtc=$finished.ToString('o');primaryError=$safePrimary;environment=$environment;probes=@($probes);events=$events;errors=@($errors)
    }
}

function Assert-DevFleetMultipassM0Snapshot {
    param(
        [Parameter(Mandatory)][psobject]$Snapshot,
        [Parameter(Mandatory)][string]$ExpectedRunId,
        [Parameter(Mandatory)][string]$ExpectedVmName,
        [Parameter(Mandatory)][guid]$ExpectedVmId
    )
    if([int]$Snapshot.schemaVersion-ne1-or[string]$Snapshot.collector-cne'DevFleet-Campaign-E-Multipass-M0'){throw 'M0 collector schema identity is invalid.'}
    if([string]$Snapshot.runId-cne$ExpectedRunId){throw 'M0 collector run identity mismatch.'}
    if([string]$Snapshot.expectedVmName-cne$ExpectedVmName-or[guid][string]$Snapshot.expectedVmId-ne$ExpectedVmId){throw 'M0 collector VM identity mismatch.'}
    if([string]$Snapshot.status-notin@('COMPLETE','PARTIAL','ERROR')){throw 'M0 collector status is invalid.'}
    $deadline=([datetime]$Snapshot.ownerDeadlineUtc).ToUniversalTime();$started=([datetime]$Snapshot.startedAtUtc).ToUniversalTime();$produced=([datetime]$Snapshot.producedAtUtc).ToUniversalTime()
    if($started-gt$deadline-or$produced-gt$deadline){throw 'M0 collector was first produced after its immutable owner deadline.'}
    $expected=@('version','driver','privileged-mounts','inventory','image')
    foreach($operation in $expected){if(@($Snapshot.probes|Where-Object{[string]$_.operation-ceq$operation}).Count-ne1){throw "M0 collector did not contain exactly one '$operation' probe."}}
    $previousFinish=$null
    foreach($probe in @($Snapshot.probes)){
        if(([datetime]$probe.startedAtUtc).ToUniversalTime()-gt$deadline-or([datetime]$probe.finishedAtUtc).ToUniversalTime()-gt$deadline){throw "M0 '$([string]$probe.operation)' probe exceeded the immutable owner deadline."}
        if([string]::IsNullOrWhiteSpace([string]$probe.deadlineUtc)-or([datetime]$probe.deadlineUtc).ToUniversalTime()-gt$deadline){throw "M0 '$([string]$probe.operation)' probe did not inherit the immutable owner deadline."}
        $probeStart=([datetime]$probe.startedAtUtc).ToUniversalTime();$probeFinish=([datetime]$probe.finishedAtUtc).ToUniversalTime()
        if($probeFinish-lt$probeStart){throw "M0 '$([string]$probe.operation)' probe time ordering is malformed."}
        if($previousFinish-and$probeStart-lt$previousFinish){throw 'M0 Multipass probes overlapped; the required serialized CLI stream was not preserved.'}
        $previousFinish=$probeFinish
    }
    $serialized=$Snapshot|ConvertTo-Json -Depth 24 -Compress
    if($serialized-match'(?i)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*(?!<redacted>|\\u003credacted\\u003e)[^,}\"]+'){throw 'M0 collector contains unredacted secret-shaped evidence.'}
    return $true
}

function Invoke-DevFleetBoundedGuestCommand {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList=@(),
        [ValidateRange(1,3600)][int]$TimeoutSeconds=300
    )
    $pipeline=[powershell]::Create()
    try {
        $null=$pipeline.AddCommand('Invoke-Command').AddParameter('Session',$Session).AddParameter('ScriptBlock',$ScriptBlock).AddParameter('ArgumentList',@($ArgumentList)).AddParameter('ErrorAction','Stop')
        $async=$pipeline.BeginInvoke()
        if(-not$async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))){
            try{$pipeline.Stop()}catch{}
            throw "Bounded guest diagnostic command exceeded $TimeoutSeconds seconds."
        }
        $output=@($pipeline.EndInvoke($async))
        if($pipeline.HadErrors){throw ((@($pipeline.Streams.Error|ForEach-Object{ConvertTo-DevFleetDiagnosticSafeText $_})-join '; '))}
        return $output
    } finally {$pipeline.Dispose()}
}

function Get-DevFleetBoundedProcessScriptBlock {
    return {
        param([string]$RequestJson)
        $request=$RequestJson|ConvertFrom-Json -ErrorAction Stop
        $FilePath=[string]$request.filePath
        $Arguments=@($request.arguments|ForEach-Object{[string]$_})
        $deadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.deadlineUnixMilliseconds).UtcDateTime
        $started=[datetime]::UtcNow
        if($deadline-le$started){return [pscustomobject]@{outcome='OWNER_EXPIRED';exitCode=$null;pid=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=$started.ToString('o');stdout='';stderr='Owning deadline expired before worker start.';outputComplete=$true}}
        if(-not(Test-Path -LiteralPath $FilePath -PathType Leaf)){return [pscustomobject]@{outcome='START_FAILED';exitCode=$null;pid=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');stdout='';stderr='Exact worker executable is missing.';outputComplete=$true}}
        if(@($Arguments|Where-Object{[string]$_-match'[\s"]'}).Count){return [pscustomobject]@{outcome='START_FAILED';exitCode=$null;pid=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');stdout='';stderr='Worker arguments must use the validated whitespace-free diagnostic envelope.';outputComplete=$true}}
        $process=$null
        # Read incrementally: ReadToEndAsync cannot expose a flushed prefix while
        # a descendant still holds the pipe. Keep each captured stream bounded.
        function Receive-WorkerOutput($Streams) {
            $progress=$false
            foreach($stream in $Streams){
                if($stream.eof -or $stream.error -or -not $stream.task.IsCompleted){continue}
                $progress=$true
                try {
                    $read=$stream.task.GetAwaiter().GetResult()
                    if($read -eq 0){$stream.eof=$true;continue}
                    $take=[math]::Min($read,[math]::Max(0,65536-$stream.text.Length))
                    if($take -gt 0){[void]$stream.text.Append($stream.buffer,0,$take)}
                    if($take -lt $read){$stream.truncated=$true}
                    $stream.task=$stream.reader.ReadAsync($stream.buffer,0,$stream.buffer.Length)
                } catch {$stream.error=$true}
            }
            return $progress
        }
        try {
            $psi=[Diagnostics.ProcessStartInfo]::new()
            $psi.FileName=$FilePath
            $psi.Arguments=(@($Arguments|ForEach-Object{[string]$_})-join' ')
            $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
            $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
            if(-not$process.Start()){throw 'Diagnostic worker process start returned false.'}
            $streams=@(foreach($reader in @($process.StandardOutput,$process.StandardError)){
                [char[]]$buffer=New-Object char[] 4096
                [pscustomobject]@{reader=$reader;buffer=$buffer;task=$reader.ReadAsync($buffer,0,$buffer.Length);text=[Text.StringBuilder]::new();eof=$false;error=$false;truncated=$false}
            })
            while(-not$process.HasExited-and[datetime]::UtcNow-lt$deadline){
                if(-not(Receive-WorkerOutput $streams)){Start-Sleep -Milliseconds 20}
            }
            $timedOut=-not $process.HasExited
            $treeKillExitCode=$null
            if(-not$process.HasExited){
                $killer=$null
                try {
                    $killInfo=[Diagnostics.ProcessStartInfo]::new()
                    $killInfo.FileName=Join-Path $env:SystemRoot 'System32\taskkill.exe'
                    $killInfo.Arguments='/PID '+[string]$process.Id+' /T /F'
                    $killInfo.UseShellExecute=$false;$killInfo.CreateNoWindow=$true
                    $killInfo.RedirectStandardOutput=$true;$killInfo.RedirectStandardError=$true
                    $killer=[Diagnostics.Process]::Start($killInfo)
                    $killer.BeginOutputReadLine();$killer.BeginErrorReadLine()
                    if($killer.WaitForExit(2000)){$treeKillExitCode=$killer.ExitCode}else{$killer.Kill()}
                } catch {} finally {if($killer){$killer.Dispose()}}
                try{if(-not $process.HasExited){$process.Kill()};[void]$process.WaitForExit(1000)}catch{}
            }
            $drainDeadline=[datetime]::UtcNow.AddSeconds(5)
            while([datetime]::UtcNow -lt $drainDeadline){
                $progress=Receive-WorkerOutput $streams
                if(@($streams|Where-Object{-not $_.eof -and -not $_.error}).Count -eq 0){break}
                if(-not $progress){Start-Sleep -Milliseconds 20}
            }
            $drained=@($streams|Where-Object{-not $_.eof -or $_.error}).Count -eq 0
            $truncated=$streams[0].truncated -or $streams[1].truncated
            $terminated=$process.HasExited
            $supervisorError=if($timedOut){'Diagnostic worker exceeded its inherited finite deadline.'}elseif(-not $drained){'Diagnostic worker output did not drain inside the terminal margin.'}elseif($truncated){'Diagnostic worker output exceeded the bounded capture limit.'}else{''}
            return [pscustomobject]@{outcome=if($timedOut){'TIMEOUT'}elseif(-not$drained){'DRAIN_INCOMPLETE'}elseif($truncated){'OUTPUT_TRUNCATED'}elseif($process.ExitCode-eq0){'PASS'}else{'NONZERO'};exitCode=if($timedOut){$null}else{$process.ExitCode};pid=$process.Id;startedAtUtc=$started.ToString('o');deadlineUtc=$deadline.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');stdout=$streams[0].text.ToString();stderr=$streams[1].text.ToString();outputComplete=($drained-and-not$truncated);drainComplete=$drained;stdoutTruncated=$streams[0].truncated;stderrTruncated=$streams[1].truncated;supervisorError=$supervisorError;terminationVerified=$terminated;treeKillExitCode=$treeKillExitCode}
        } catch {
            return [pscustomobject]@{outcome='START_FAILED';exitCode=$null;pid=if($process-and-not$process.HasExited){$process.Id}else{$null};startedAtUtc=$started.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');stdout='';stderr=[string]$_.Exception.Message;outputComplete=$true}
        } finally {if($process){$process.Dispose()}}
    }
}

function Invoke-DevFleetBoundedGuestProcess {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc
    )
    $remaining=[int][math]::Floor(($OwnerDeadlineUtc.ToUniversalTime()-[datetime]::UtcNow).TotalSeconds)
    if($remaining-le0){throw 'Guest diagnostic worker owner deadline expired before launch.'}
    $scriptBlock=Get-DevFleetBoundedProcessScriptBlock
    $deadlineUnixMilliseconds=[DateTimeOffset]::new($OwnerDeadlineUtc.ToUniversalTime()).ToUnixTimeMilliseconds()
    $requestJson=[ordered]@{filePath=$FilePath;arguments=@($ArgumentList);deadlineUnixMilliseconds=$deadlineUnixMilliseconds}|ConvertTo-Json -Depth 4 -Compress
    $output=@(Invoke-DevFleetBoundedGuestCommand -Session $Session -ScriptBlock $scriptBlock -ArgumentList @($requestJson) -TimeoutSeconds ([math]::Min(3600,$remaining+10)))
    if($output.Count-eq0){throw 'Guest diagnostic worker returned no process result.'}
    return $output[-1]
}

function Copy-DevFleetBoundedGuestFile {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$RemotePath,
        [ValidateRange(1,300)][int]$TimeoutSeconds=60
    )
    $pipeline=[powershell]::Create()
    try {
        $null=$pipeline.AddCommand('Copy-Item').AddParameter('LiteralPath',$LocalPath).AddParameter('Destination',$RemotePath).AddParameter('ToSession',$Session).AddParameter('Force',$true).AddParameter('ErrorAction','Stop')
        $async=$pipeline.BeginInvoke()
        if(-not$async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))){try{$pipeline.Stop()}catch{};throw "Bounded guest file staging exceeded $TimeoutSeconds seconds."}
        $null=@($pipeline.EndInvoke($async))
        if($pipeline.HadErrors){throw ((@($pipeline.Streams.Error|ForEach-Object{ConvertTo-DevFleetDiagnosticSafeText $_})-join '; '))}
    } finally {$pipeline.Dispose()}
    $localHash=(Get-FileHash -LiteralPath $LocalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $remoteHash=@(Invoke-DevFleetBoundedGuestCommand -Session $Session -TimeoutSeconds $TimeoutSeconds -ScriptBlock {param($Path)if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Staged diagnostic file is missing.'};(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()} -ArgumentList @($RemotePath))|Select-Object -Last 1
    if([string]$remoteHash-cne$localHash){throw 'Staged diagnostic file hash diverged.'}
    return [pscustomobject]@{localPath=$LocalPath;remotePath=$RemotePath;localSha256=$localHash;remoteSha256=[string]$remoteHash;equal=$true}
}

Export-ModuleMember -Function Invoke-DevFleetCampaignECandidateNativeLaunch,Get-DevFleetCampaignEBackendSnapshot,Assert-DevFleetCampaignEProductProfile,ConvertTo-DevFleetDiagnosticSafeText,ConvertTo-DevFleetWindowsProcessArgument,Get-DevFleetExistingFilePathSet,Invoke-DevFleetBoundedNativeProbe,ConvertTo-DevFleetMultipassProbeObservation,Get-DevFleetMultipassM0Snapshot,Assert-DevFleetMultipassM0Snapshot,Invoke-DevFleetBoundedGuestCommand,Get-DevFleetBoundedProcessScriptBlock,Invoke-DevFleetBoundedGuestProcess,Copy-DevFleetBoundedGuestFile,Assert-DevFleetCampaignEArchiveEntries,Get-DevFleetCampaignEPrerequisitePlan,Invoke-DevFleetCampaignEPowerShellAcquisition,Get-DevFleetCampaignEOfficialPowerShellPayload,Invoke-DevFleetCampaignEStagedPowerShellAcquisition,Get-DevFleetCampaignEBootstrapStubContent,Get-DevFleetSystemExecutionPolicyProjection,Assert-DevFleetCampaignEPrerequisiteFailure,Assert-DevFleetCampaignEStagingOwnership,Resolve-DevFleetCampaignEWorkerResult,Invoke-DevFleetCampaignEMultipassM1Sequence,New-DevFleetCampaignEM1CleanupState,Assert-DevFleetCampaignEM1Result,Get-DevFleetCampaignEDeadlinePartition,Assert-DevFleetCampaignEPrerequisiteResult
