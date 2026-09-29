# DevFleet source part 013

Full-source UTF-8 byte interval [558000, 604500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2ae0d1513412cd540e960d5b7864d9ff32159bea0ccac1251290e8b4f285490c

<!-- BEGIN SOURCE SLICE -->
ullName
        installerSource = Get-FileHashRecord -Path $sourceZip
        signingState = if($candidateManifest.PSObject.Properties['signingState']){[string]$candidateManifest.signingState}else{''}
        privateSigningProfile = $privateSigningProfile
        privateSigningCertificateThumbprint = $privateSigningThumbprint
        publicPublisherTrust = $manifestPublicPublisherTrust
        publicPromotionAllowed = $manifestPublicPromotionAllowed
        publicCertificate = $publicCertificate
        authenticode = $authenticode
    }
}

function Invoke-CandidateSelfTest {
    param(
        [Parameter(Mandatory)][psobject]$Fingerprint,
        [string]$ReportPath
    )
    $callerSuppliedReportPath = -not [string]::IsNullOrWhiteSpace($ReportPath)
    if (-not $callerSuppliedReportPath) {
        $selfTestName=if([string]$Fingerprint.privateSigningProfile -eq 'PRIVATE_SELF_SIGNED'){'signed-self-test.txt'}else{'unsigned-self-test.txt'}
        $ReportPath = Join-Path (Split-Path -Parent $Fingerprint.candidate.path) $selfTestName
    }
    $reportPath = [IO.Path]::GetFullPath($ReportPath)
    if (Test-Path -LiteralPath $reportPath) {
        if ($callerSuppliedReportPath) { throw "Self-test report path already exists; a unique path is required: $reportPath" }
        Remove-Item -LiteralPath $reportPath -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportPath) | Out-Null
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Fingerprint.candidate.path
    $psi.Arguments = '--self-test'
    $psi.WorkingDirectory = Split-Path -Parent $Fingerprint.candidate.path
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.Environment['DEVFLEET_SELF_TEST_OUTPUT'] = $reportPath
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw 'Unable to start candidate self-test.' }
    if (-not $process.WaitForExit(120000)) { try { $process.Kill() } catch {}; throw 'Candidate self-test timed out.' }
    $report = if (Test-Path -LiteralPath $reportPath) { Get-Content -LiteralPath $reportPath -Raw } else { '' }
    $token = Get-WindowsTokenEvidence
    [pscustomobject]@{
        exitCode = $process.ExitCode
        reportPath = $reportPath
        result = if ($process.ExitCode -eq 0 -and $report -match '(?m)^PASS\s*$') { 'PASS' } else { 'FAIL' }
        reportSha256 = if (Test-Path -LiteralPath $reportPath) { (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        reportContent = $report
        token = $token
        requiredChecks = [ordered]@{
            devfleet = $report -match [regex]::Escape("devfleet_version=$($Fingerprint.releaseVersion)")
            installer = $report -match [regex]::Escape("installer_version=$($Fingerprint.installerVersion)")
            embeddedTarCount = $report -match '(?m)^embedded_tar_count=1\s*$'
            payloadSha = $report -match [regex]::Escape("payload=$($Fingerprint.tar.sha256)")
            extraction = $report -match '(?m)^payload_extraction=PASS\s*$'
            bootstrap = $report -match '(?m)^bootstrap_entrypoint=PASS\s*$'
            parameterContract = $report -match '(?m)^bootstrap_parameter_contract=PASS\s*$'
            factoryResetBackupGate = $report -match '(?m)^factory_reset_backup_gate=PASS\s*$'
            planSafety = $report -match '(?m)^plan_safety=PASS\s*$'
        }
    }
}

function Test-CandidateFingerprint {
    param([Parameter(Mandatory)][psobject]$Expected,[Parameter(Mandatory)][psobject]$Actual)
    foreach ($name in @('candidate','tar','portable','installerSource')) {
        if ($Expected.$name.sha256 -ne $Actual.$name.sha256 -or $Expected.$name.bytes -ne $Actual.$name.bytes) { return $false }
    }
    foreach($name in @('releaseFingerprintId','toolingFingerprintId','gitCommit')){if([string]$Expected.$name -ne [string]$Actual.$name){return $false}}
    return $true
}

Export-ModuleMember -Function Get-FileHashRecord,Get-WindowsTokenEvidence,Test-PrivateAuthenticodeSignature,Get-CandidateFingerprint,Invoke-CandidateSelfTest,Test-CandidateFingerprint

```


## FILE: automation/release-e2e/modules/Cleanup.psm1

SHA256: c80888b620328f95bc63f55523c8a06ef10939106836dfe17a945d18729944e5 | Bytes: 19207 | Git mode: 100644

```
Set-StrictMode -Version Latest

function New-CleanupManifest {
    param([Parameter(Mandatory)][psobject]$Vm,[Parameter(Mandatory)][string]$RunId)
    if ($Vm.Name -notlike 'DevFleet-E2E-*') { throw 'Cleanup manifest refused a non-disposable VM.' }
    [pscustomobject]@{
        schemaVersion=1; runId=$RunId; createdAt=(Get-Date).ToUniversalTime().ToString('o');
        resources=@([pscustomobject]@{ kind='Hyper-V VM'; name=$Vm.Name; id=$Vm.Id.ToString(); ownership='exact recorded disposable identity'; destructiveAllowed=$true });
        deniedNames=@('devfleet-primary','devfleet-project-m-techlabs-job-finder','MulattoTechSurface','MULATTOTECHBOX');
        productionTouched=$false
    }
}

function Test-CleanupManifest {
    param([Parameter(Mandatory)][psobject]$Manifest)
    foreach($r in @($Manifest.resources)) {
        if ($r.name -notlike 'DevFleet-E2E-*' -or -not $r.id -or $r.destructiveAllowed -ne $true) { return $false }
    }
    if ($Manifest.productionTouched -ne $false) { return $false }
    $true
}

function Get-OwnedManifestVm {
    param([Parameter(Mandatory)][psobject]$Resource)
    if ($Resource.name -notlike 'DevFleet-E2E-*' -or -not $Resource.id -or $Resource.destructiveAllowed -ne $true) {
        throw 'Cleanup resource failed exact disposable identity validation.'
    }
    try { $expectedId = [guid][string]$Resource.id }
    catch { throw "Cleanup resource has an invalid VM ID for $($Resource.name)." }
    $vm = Get-VM -Id $expectedId -ErrorAction Stop
    if ($vm.Id -ne $expectedId -or $vm.Name -cne [string]$Resource.name) {
        throw "Cleanup identity mismatch for $($Resource.name)."
    }
    return $vm
}

function Get-DevFleetHostNameExclusion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name)
    try {
        $rows=@(Get-VM -Name $Name -ErrorAction Stop)
        return [pscustomobject]@{
            status=if($rows.Count){'PRESENT'}else{'ABSENT'}
            present=($rows.Count -gt 0)
            name=$Name
            inventoryScope='host Hyper-V exact-name exclusion only'
            verification='Get-VM -Name exact returned host inventory rows'
            resources=@($rows|ForEach-Object{[ordered]@{name=[string]$_.Name;id=[string]$_.Id;state=[string]$_.State}})
        }
    } catch {
        $expectedMessage='Hyper-V was unable to find a virtual machine with name "'+$Name+'".'
        $isExactNotFound=([string]$_.FullyQualifiedErrorId -ceq 'InvalidParameter,Microsoft.HyperV.PowerShell.Commands.GetVM' -and $_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::InvalidArgument -and [string]$_.TargetObject -ceq $Name -and [string]$_.Exception.Message -ceq $expectedMessage)
        if(-not $isExactNotFound){throw}
        return [pscustomobject]@{
            status='ABSENT'
            present=$false
            name=$Name
            inventoryScope='host Hyper-V exact-name exclusion only'
            verification='Get-VM exact Hyper-V missing-name signature; not nested L2 evidence'
            resources=@()
        }
    }
}

function Stop-ManifestVm {
    param([Parameter(Mandatory)][psobject]$Manifest)
    if (-not (Test-CleanupManifest $Manifest)) { throw 'Cleanup manifest failed validation.' }
    foreach($r in @($Manifest.resources)) {
        $vm = Get-OwnedManifestVm -Resource $r
        if ($vm.State -ne 'Off') { Stop-VM -VM $vm -Force -Confirm:$false }
    }
}

function Write-TerminalVmEvidence {
    param(
        [Parameter(Mandatory)][psobject]$Vm,
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$L2Name,
        [string]$RunId,
        [AllowNull()][psobject]$NestedL2Observation,
        [AllowNull()][psobject]$Candidate,
        [string]$EvidenceClass='run-owned safety cleanup'
    )
    if($Vm.Name -notlike 'DevFleet-E2E-*' -or -not $Vm.Id){throw 'Terminal evidence requires an exact disposable L1 identity.'}
    if([string]::IsNullOrWhiteSpace($L2Name) -or $L2Name -notlike 'DevFleet-E2E-*' -or $L2Name -eq 'DevFleet-H10-Linux') { throw 'Terminal L2 evidence requires the configured exact disposable L2 name and explicitly protects DevFleet-H10-Linux.' }
    $actual=Get-VM -Id ([guid][string]$Vm.Id) -ErrorAction Stop
    if($actual.Name -cne [string]$Vm.Name -or $actual.Id.ToString() -cne $Vm.Id.ToString()){throw 'Terminal L1 identity changed while collecting evidence.'}
    $timestamp=(Get-Date).ToUniversalTime().ToString('o')
    $l1=[ordered]@{schemaVersion=1;name=$actual.Name;id=$actual.Id.ToString();state=[string]$actual.State;timestamp=$timestamp;timestampUtc=$timestamp;ownershipScope='exact disposable DevFleet-E2E VM identity';ownershipMethod='Get-VM -Id plus exact case-sensitive name';runId=(Split-Path -Leaf $RunDir)}
    $runDirId=Split-Path -Leaf $RunDir
    if([string]::IsNullOrWhiteSpace($RunId)){$RunId=$runDirId}
    if([string]$RunId -cne [string]$runDirId){throw 'Terminal evidence RunId does not match its exact run directory.'}
    $l2=[ordered]@{schemaVersion=2;expectedName=$L2Name;status='UNVERIFIED';present=$null;verificationMethod='No validated nested L1 inventory was supplied';ownershipScope='exact expected nested L2 name inside exact disposable L1';runId=$runId;evidenceClass=$EvidenceClass;certifiedReleaseCleanup=$false}
    if($NestedL2Observation){
        $observedText=[string]$NestedL2Observation.observedUtc
        $observedInstant=[datetimeoffset]::MinValue
        $parsed=[datetimeoffset]::TryParse($observedText,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$observedInstant)
        $candidateTuple=$null
        if($Candidate){
            $candidateTuple=[ordered]@{
                repositoryHead=[string]$Candidate.repositoryHead
                candidateCommit=[string]$Candidate.gitCommit
                shippingInputIdentity=[string]$Candidate.shippingInputIdentity
                releaseFingerprintId=[string]$Candidate.releaseFingerprintId
                toolingFingerprintId=[string]$Candidate.toolingFingerprintId
            }
        }
        $tupleValid=$candidateTuple -and @($candidateTuple.Values|Where-Object{[string]::IsNullOrWhiteSpace([string]$_)}).Count -eq 0
        $status=[string]$NestedL2Observation.status
        $exactCountProperty=$NestedL2Observation.PSObject.Properties['exactMatchCount']
        $exactCount=if($exactCountProperty){$exactCountProperty.Value}else{$null}
        $countValid=($exactCountProperty -and ($exactCount -is [int] -or $exactCount -is [long]))
        $observationValid=([string]$NestedL2Observation.expectedName -ceq $L2Name -and $status -in @('ABSENT','PRESENT') -and $NestedL2Observation.present -is [bool] -and (($status -ceq 'ABSENT' -and $NestedL2Observation.present -eq $false) -or ($status -ceq 'PRESENT' -and $NestedL2Observation.present -eq $true)) -and $parsed -and $observedInstant.Offset -eq [timespan]::Zero -and $countValid)
        if($observationValid -and $status -ceq 'ABSENT' -and [long]$exactCount -ne 0){$observationValid=$false}
        if($observationValid -and $status -ceq 'PRESENT' -and [long]$exactCount -lt 1){$observationValid=$false}
        if(-not $observationValid){throw 'Terminal nested L2 observation is malformed, wrong-scope, or not UTC.'}
        if([string]$NestedL2Observation.verification -ceq 'Bounded Multipass JSON inventory inside exact L1'){
            if(($NestedL2Observation.inventoryCount -isnot [int] -and $NestedL2Observation.inventoryCount -isnot [long]) -or [long]$NestedL2Observation.inventoryCount -lt 0 -or [long]$exactCount -gt [long]$NestedL2Observation.inventoryCount){throw 'Terminal Multipass nested inventory is incomplete or inconsistent.'}
        }elseif([string]$NestedL2Observation.verification -ceq 'Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend'){
            $backendRows=@($NestedL2Observation.backendInventories)
            if($backendRows.Count -ne 2){throw 'Terminal nested evidence is missing a supported in-L1 backend inventory.'}
            $backendExactCount=0
            foreach($provider in @('Hyper-V','VirtualBox')){
                $rows=@($backendRows|Where-Object{[string]$_.provider -ceq $provider})
                if($rows.Count -ne 1 -or [string]$rows[0].status -cne 'PASS' -or $rows[0].names -isnot [array] -or [string]::IsNullOrWhiteSpace([string]$rows[0].verification)){throw "Terminal nested $provider inventory is missing or ambiguous."}
                foreach($name in $rows[0].names){if($name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$name)){throw "Terminal nested $provider inventory contains an invalid name."};if([string]$name -ceq $L2Name){$backendExactCount++}}
            }
            if($backendExactCount -ne [long]$exactCount){throw 'Terminal nested backend inventories disagree with the exact L2 match count.'}
        }else{throw 'Terminal nested evidence uses an unsupported or incomplete inventory method.'}
        $observation=[ordered]@{
            schemaVersion=1;runId=$runId;status=[string]$NestedL2Observation.status;expectedName=$L2Name;present=[bool]$NestedL2Observation.present
            observedUtc=$observedInstant.UtcDateTime.ToString('o');verification=[string]$NestedL2Observation.verification
            exactMatchCount=if($NestedL2Observation.PSObject.Properties['exactMatchCount']){[int]$NestedL2Observation.exactMatchCount}else{$null}
            inventoryCount=if($NestedL2Observation.PSObject.Properties['inventoryCount']){[int]$NestedL2Observation.inventoryCount}else{$null}
            backendInventories=@($NestedL2Observation.backendInventories);candidate=$candidateTuple
            l1=[ordered]@{name=[string]$Vm.Name;id=([guid][string]$Vm.Id).ToString()}
            nestedScope='inside the exact L1 guest session';observer='Get-DevFleetNestedL2State';evidenceClass=$EvidenceClass
        }
        if(-not $tupleValid -or [string]::IsNullOrWhiteSpace([string]$observation.verification)){throw 'Terminal nested L2 observation lacks exact candidate or observer provenance.'}
        if([string]$EvidenceClass -ceq 'FullRelease run-bound nested observation' -and [string]$NestedL2Observation.status -ceq 'ABSENT'){
            $l1Instant=[datetimeoffset]::MinValue
            if([string]$actual.State -cne 'Off' -or -not [datetimeoffset]::TryParse($timestamp,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$l1Instant) -or $observedInstant -gt $l1Instant){throw 'FullRelease nested L2 observation is not followed by exact L1 OFF continuity.'}
        }
        $sourcePath=Join-Path $RunDir 'nested-l2-terminal-observation.json'
        Write-EvidenceJson -Path $sourcePath -Value $observation
        $sourceHash=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $l2=[ordered]@{
            schemaVersion=2;expectedName=$L2Name;status=[string]$NestedL2Observation.status;present=[bool]$NestedL2Observation.present
            timestamp=$observation.observedUtc;timestampUtc=$observation.observedUtc;verificationMethod=[string]$NestedL2Observation.verification
            ownershipScope='exact expected nested L2 name inside exact disposable L1';nestedScope=$observation.nestedScope
            backendInventories=@($NestedL2Observation.backendInventories);runId=$runId;sourceRunId=$runId
            sourceEvidence='nested-l2-terminal-observation.json';sourceEvidenceSha256=$sourceHash
            l1Name=[string]$Vm.Name;l1Id=([guid][string]$Vm.Id).ToString();candidate=$candidateTuple
            evidenceClass=$EvidenceClass;certifiedReleaseCleanup=$false
        }
    }
    Write-EvidenceJson -Path (Join-Path $RunDir 'l1-terminal-state.json') -Value $l1
    Write-EvidenceJson -Path (Join-Path $RunDir 'l2-terminal-state.json') -Value $l2
    [pscustomobject]@{l1=$l1;l2=$l2}
}

function Publish-DevFleetTerminalCleanupSummary {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$CleanupEvidencePath
    )
    $root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $sourceInput=Get-Item -LiteralPath $CleanupEvidencePath -Force -ErrorAction Stop
    if($sourceInput.PSIsContainer -or ($sourceInput.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Terminal cleanup summary source is not a regular non-reparse file.'}
    $source=(Resolve-Path -LiteralPath $CleanupEvidencePath).Path
    foreach($relative in @('audit','audit\automation-harness','audit\automation-harness\runs')){
        $directory=Get-Item -LiteralPath (Join-Path $root $relative) -Force -ErrorAction Stop
        if(-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Terminal cleanup summary path contains a disallowed reparse directory.'}
    }
    $rootPrefix=$root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not $source.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Terminal cleanup summary source is outside the workspace.'}
    $relative=$source.Substring($rootPrefix.Length).Replace('\','/')
    if($relative -notmatch '^audit/automation-harness/runs/([^/]+)/cleanup-state\.json$'){throw 'Terminal cleanup summary source is not an exact proof run cleanup record.'}
    $sourceRunId=$Matches[1]
    $runDirectory=Get-Item -LiteralPath (Join-Path $root (Join-Path 'audit\automation-harness\runs' $sourceRunId)) -Force -ErrorAction Stop
    if(-not $runDirectory.PSIsContainer -or ($runDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Terminal cleanup summary run directory is missing or a disallowed reparse point.'}
    $sourceStream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
    $sourceMemory=[IO.MemoryStream]::new()
    try{$sourceStream.CopyTo($sourceMemory);$sourceBytes=$sourceMemory.ToArray()}finally{$sourceMemory.Dispose()}
    try{$cleanup=([Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes))|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Terminal cleanup summary source is unreadable.'}
    if([string]$cleanup.runId -cne $sourceRunId){throw 'Terminal cleanup summary RunId does not match its exact run directory.'}
    if([string]$cleanup.status -cne 'PASS' -or -not [bool]$cleanup.runOwnedOnly -or [string]$cleanup.cleanupOwner -cne 'run-exact-candidate-proof.ps1'){throw 'Terminal cleanup summary requires a PASS, run-owned exact-proof cleanup record.'}
    if([string]$cleanup.l1.status -cne 'OFF' -or [string]$cleanup.l1.name -cne 'DevFleet-E2E-Win11-01' -or [string]$cleanup.l1.id -cne '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'){throw 'Terminal cleanup summary L1 identity or state is invalid.'}
    if([string]$cleanup.l2.status -cne 'ABSENT' -or $cleanup.l2.present -isnot [bool] -or $cleanup.l2.present -ne $false -or [string]$cleanup.l2.expectedName -cne 'DevFleet-E2E-Linux-01' -or ($cleanup.l2.exactMatchCount -isnot [int] -and $cleanup.l2.exactMatchCount -isnot [long]) -or [long]$cleanup.l2.exactMatchCount -ne 0 -or [string]$cleanup.l2.verification -cnotin @('complete read-only inventories from every supported in-L1 virtualization backend','Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend')){throw 'Terminal cleanup summary L2 identity or state is invalid.'}
    $backendInventories=@($cleanup.l2.backendInventories)
    if($backendInventories.Count -ne 2){throw 'Terminal cleanup summary requires exactly one complete inventory from each supported in-L1 backend.'}
    foreach($provider in @('Hyper-V','VirtualBox')){
        $rows=@($backendInventories|Where-Object{[string]$_.provider -ceq $provider})
        if($rows.Count -ne 1 -or [string]$rows[0].status -cne 'PASS' -or $rows[0].names -isnot [array] -or [string]::IsNullOrWhiteSpace([string]$rows[0].verification)){throw "Terminal cleanup summary has a missing, duplicate, or incomplete $provider inventory."}
        foreach($name in $rows[0].names){if($name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$name)){throw "Terminal cleanup summary $provider inventory contains an invalid name."};if([string]$name -ceq 'DevFleet-E2E-Linux-01'){throw "Terminal cleanup summary $provider inventory still contains the exact nested L2 target."}}
    }
    $asUtcText={param($value)if($value -is [datetime]){return $value.ToUniversalTime().ToString('o')}if($value -is [datetimeoffset]){return $value.UtcDateTime.ToString('o')}return [string]$value}
    $l1Utc=&$asUtcText $cleanup.l1.observedUtc;$l2Utc=&$asUtcText $cleanup.l2.observedUtc
    $l1Instant=[datetimeoffset]::MinValue;$l2Instant=[datetimeoffset]::MinValue
    $roundtrip=[Globalization.DateTimeStyles]::RoundtripKind;$invariant=[Globalization.CultureInfo]::InvariantCulture
    if(-not [datetimeoffset]::TryParse($l1Utc,$invariant,$roundtrip,[ref]$l1Instant) -or $l1Instant.Offset -ne [timespan]::Zero){throw 'Terminal cleanup summary L1 observation UTC is invalid.'}
    if(-not [datetimeoffset]::TryParse($l2Utc,$invariant,$roundtrip,[ref]$l2Instant) -or $l2Instant.Offset -ne [timespan]::Zero){throw 'Terminal cleanup summary L2 observation UTC is invalid.'}
    if($l2Instant -gt $l1Instant){throw 'Terminal cleanup summary nested observation must precede exact L1 shutdown observation.'}
    $sourceHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($sourceBytes)).ToLowerInvariant()
    $l1=[ordered]@{
        schemaVersion=1;name=[string]$cleanup.l1.name;id=[string]$cleanup.l1.id;state='Off';timestamp=$l1Utc;timestampUtc=$l1Utc
        ownershipScope='exact disposable DevFleet-E2E VM identity';ownershipMethod='Live Get-VM -Id after exact canonical CLEAN restore and complete in-L1 nested inventory'
        sourceRunId=$sourceRunId;sourceEvidence=$relative;sourceEvidenceSha256=$sourceHash;cleanupEvidenceClass='run-owned safety cleanup';certifiedReleaseCleanup=$false
    }
    $l2=[ordered]@{
        schemaVersion=1;expectedName=[string]$cleanup.l2.expectedName;present=$false;timestamp=$l2Utc;timestampUtc=$l2Utc
        verificationMethod=[string]$cleanup.l2.verification;backendInventories=$backendInventories;ownershipScope='exact expected nested L2 name inside exact disposable L1'
        sourceRunId=$sourceRunId;sourceEvidence=$relative;sourceEvidenceSha256=$sourceHash;cleanupEvidenceClass='run-owned safety cleanup';certifiedReleaseCleanup=$false
    }
    $evidenceDir=Join-Path $root 'evidence';if(-not(Test-Path -LiteralPath $evidenceDir -PathType Container)){throw 'Workspace evidence directory is missing.'}
    Write-EvidenceJson -Path (Join-Path $evidenceDir 'l1-terminal-state.json') -Value $l1
    Write-EvidenceJson -Path (Join-Path $evidenceDir 'l2-terminal-state.json') -Value $l2
    [pscustomobject]@{sourceRunId=$sourceRunId;sourceEvidence=$relative;sourceEvidenceSha256=$sourceHash;l1=$l1;l2=$l2}
    } finally {$sourceStream.Dispose()}
}

Export-ModuleMember -Function New-CleanupManifest,Test-CleanupManifest,Get-OwnedManifestVm,Stop-ManifestVm,Get-DevFleetHostNameExclusion,Write-TerminalVmEvidence,Publish-DevFleetTerminalCleanupSummary

```


## FILE: automation/release-e2e/modules/Evidence.psm1

SHA256: c2642b8bcb0018aae5f1c8136aa855daf68c85b71bc5d8a8b4d7c73f20f2ac41 | Bytes: 2377 | Git mode: 100644

```
Set-StrictMode -Version Latest

function New-RunEvidenceDirectory {
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunId)
    if($RunId.Length -gt 128 -or $RunId -cnotmatch '\A[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'){
        throw 'RunId must contain only non-empty ASCII alphanumeric segments separated by single hyphens.'
    }
    $runsRoot=[IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'audit\automation-harness\runs')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $path=[IO.Path]::GetFullPath((Join-Path $runsRoot $RunId))
    $ownedPrefix=$runsRoot+[IO.Path]::DirectorySeparatorChar
    if(-not $path.StartsWith($ownedPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -cne $RunId){
        throw 'Run evidence path escaped the canonical runs root.'
    }
    [void][IO.Directory]::CreateDirectory($path)
    $path
}

function Write-EvidenceJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Value)
    $json=$Value | ConvertTo-Json -Depth 32
    for($attempt=1;$attempt -le 4;$attempt++) {
        try {
            $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
            [IO.File]::WriteAllText($tmp,$json,(New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $tmp -Destination $Path -Force
            return
        } catch {
            if($attempt -eq 4){throw}
            Start-Sleep -Milliseconds (100*$attempt)
        } finally {
            if($tmp -and (Test-Path -LiteralPath $tmp)){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
        }
    }
}
function Write-EvidenceText { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string[]]$Lines); $Lines | Set-Content -LiteralPath $Path -Encoding utf8 }

function New-GateRecord {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][ValidateSet('PASS','IMPLEMENTED','UNIT/INTEGRATION TESTED','REAL E2E PASS','FAIL','BLOCKED','USER ACTION REQUIRED','SKIPPED','SKIP — platform prerequisite','NOT RUN','NOT APPLICABLE')][string]$Status,[string]$Details)
    [pscustomobject]@{ name=$Name; status=$Status; details=$Details; timestamp=(Get-Date).ToUniversalTime().ToString('o') }
}

Export-ModuleMember -Function New-RunEvidenceDirectory,Write-EvidenceJson,Write-EvidenceText,New-GateRecord

```


## FILE: automation/release-e2e/modules/FullRelease.psm1

SHA256: c23e6779204b4b3679ae9c1969c5123a4459018e203be34fcbc8d3928c5acd69 | Bytes: 87106 | Git mode: 100644

```
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Evidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'InteractiveLogon.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'HarnessBudget.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'GuestSession.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'MultipassDiagnostic.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'RealUseAcceptance.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'BaselineLineage.psm1') -Force
$script:ActiveBaselineWorkspaceRoot=$null
$script:ActiveBaselineFingerprint=$null

$script:FullReleasePhases = @(
    [pscustomobject]@{ id='HOST-SAFETY'; label='HOST SAFETY'; checkpoint=$null; destructive=$false },
    [pscustomobject]@{ id='CANDIDATE-VERIFY'; label='CANDIDATE/FINGERPRINT VERIFY'; checkpoint=$null; destructive=$false },
    [pscustomobject]@{ id='RESTORE-CLEAN'; label='RESTORE CLEAN DISPOSABLE BASELINE'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$true },
    [pscustomobject]@{ id='ESTABLISH-SESSION'; label='ESTABLISH INTERACTIVE E2E SESSION'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$false },
    [pscustomobject]@{ id='DEPENDENCY-MATRIX'; label='DEPENDENCY MATRIX 7/7'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$true },
    [pscustomobject]@{ id='SECURITY-POISON'; label='SECURITY-POISON SCENARIOS'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$true },
    [pscustomobject]@{ id='FRESH-INSTALL-WPF'; label='FRESH INSTALL THROUGH REAL WPF'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$true },
    [pscustomobject]@{ id='PRIMARY'; label='PRIMARY ROLE'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$true },
    [pscustomobject]@{ id='LINUX'; label='LINUX GUEST BOOTSTRAP'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$true },
    [pscustomobject]@{ id='HTTP-HOSTILE'; label='EXACT-CANDIDATE HOSTILE HTTP REGRESSION'; checkpoint=$null; destructive=$false },
    [pscustomobject]@{ id='MAINTENANCE-READY'; label='CHECKPOINT MAINTENANCE-READY'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='WINDOWS-SENTINELS'; label='WINDOWS FOREIGN SENTINELS'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='REPAIR'; label='REPAIR'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='CLEAN-REINSTALL'; label='CLEAN REINSTALL'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='UNINSTALL'; label='UNINSTALL'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='FACTORY-RESET'; label='FACTORY RESET'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    # This phase must begin from the prerequisite-free product baseline so the
    # supported FreshInstall path can create and consume a real reboot
    # checkpoint. MAINTENANCE-READY is a post-completion installed snapshot;
    # rerunning FreshInstall from it is legitimately idempotent and cannot
    # satisfy the reboot/resume receipt contract.
    [pscustomobject]@{ id='REBOOT-RESUME'; label='REBOOT/RESUME'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$true },
    [pscustomobject]@{ id='PERMANENT-DELETE'; label='PERMANENT DELETE'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='DELETE-RESTORE'; label='DELETE THEN RESTORE'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='STOPPED-PROJECT'; label='STOPPED PROJECT'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='HOST-CONCURRENCY'; label='HOST AGENT CONCURRENCY'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$false },
    [pscustomobject]@{ id='OPERATION-RECOVERY'; label='OPERATION RESTART RECOVERY'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$false },
    [pscustomobject]@{ id='OWNERSHIP'; label='OWNERSHIP ISOLATION'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='VAULT'; label='VAULT TRANSPORT/FIREWALL'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='SURROGATE-DISPOSABLE'; label='DISPOSABLE LAPTOP/SURROGATE VALIDATION'; checkpoint='DevFleet-E2E-CLEAN'; destructive=$true },
    # Consume the installed Laptop/Failover/Vault state before either later
    # Tailscale phase restores the Primary MAINTENANCE-READY checkpoint.
    [pscustomobject]@{ id='REAL-USE-ACCEPTANCE'; label='REAL USE ACCEPTANCE U01-U05'; checkpoint=$null; destructive=$true },
    [pscustomobject]@{ id='TAILSCALE-DEFERRED'; label='TAILSCALE DEFERRED'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$false },
    [pscustomobject]@{ id='TAILSCALE-AUTH'; label='TAILSCALE FULL AUTH LAST'; checkpoint='DevFleet-E2E-MAINTENANCE-READY'; destructive=$true },
    [pscustomobject]@{ id='AI-BUNDLE'; label='AI CODEBASE BUNDLE ROUND-TRIP'; checkpoint=$null; destructive=$false },
    [pscustomobject]@{ id='RECONCILE'; label='FINAL RECONCILIATION'; checkpoint=$null; destructive=$false },
    [pscustomobject]@{ id='CLEANUP'; label='CLEANUP'; checkpoint=$null; destructive=$true }
)

function Set-DevFleetBaselineBinding {
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][psobject]$Fingerprint)
    $baseline=Get-DevFleetAcceptedBaseline -WorkspaceRoot $WorkspaceRoot -Fingerprint $Fingerprint
    $script:ActiveBaselineWorkspaceRoot=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $script:ActiveBaselineFingerprint=$Fingerprint
    return $baseline
}
function Get-FullReleasePhasePlan {
    $baselineName='DevFleet-E2E-CLEAN'
    if($script:ActiveBaselineWorkspaceRoot){
        $baseline=Get-DevFleetAcceptedBaseline -WorkspaceRoot $script:ActiveBaselineWorkspaceRoot -Fingerprint $script:ActiveBaselineFingerprint
        $baselineName=[string]$baseline.name
    }
    return @($script:FullReleasePhases|ForEach-Object{
        [pscustomobject]@{id=$_.id;label=$_.label;checkpoint=if([string]$_.checkpoint -ceq 'DevFleet-E2E-CLEAN'){$baselineName}else{$_.checkpoint};destructive=[bool]$_.destructive}
    })
}

function Assert-FullReleaseDisposableOwnership {
    param([Parameter(Mandatory)][psobject]$Vm)
    if ($Vm.Name -notlike 'DevFleet-E2E-*') { throw "Ownership check failed for $($Vm.Name)." }
    $true
}

function Get-AssertedDisposableVm {
    param([Parameter(Mandatory)][psobject]$ExpectedVm)
    Assert-FullReleaseDisposableOwnership -Vm $ExpectedVm | Out-Null
    try { $expectedId = [guid][string]$ExpectedVm.Id }
    catch { throw "Disposable VM has an invalid recorded ID: $($ExpectedVm.Id)." }
    $actual = Get-VM -Id $expectedId -ErrorAction Stop
    if ($actual.Id -ne $expectedId -or $actual.Name -cne [string]$ExpectedVm.Name) {
        throw "Disposable VM identity/name mismatch for $($ExpectedVm.Name)/$expectedId."
    }
    return $actual
}

function Get-ExactCheckpoint {
    param([Parameter(Mandatory)][psobject]$Vm,[Parameter(Mandatory)][string]$Name)
    $currentVm = Get-AssertedDisposableVm -ExpectedVm $Vm
    $baseline=$null
    if($Name -ceq 'DevFleet-E2E-CLEAN' -or $Name -ceq 'DevFleet-E2E-CLEAN-R2'){
        $root=if($script:ActiveBaselineWorkspaceRoot){$script:ActiveBaselineWorkspaceRoot}else{(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
        if(-not $script:ActiveBaselineWorkspaceRoot -and (Test-Path -LiteralPath (Join-Path $root 'evidence\baselines\CURRENT.json') -PathType Leaf)){
            throw 'Adopted baseline requires an explicit current candidate binding before checkpoint access.'
        }
        $baseline=Get-DevFleetAcceptedBaseline -WorkspaceRoot $root -Fingerprint $script:ActiveBaselineFingerprint
        if($Name -cne [string]$baseline.name){throw 'Requested CLEAN name is not the accepted baseline name.'}
    }
    $snapshots = @(Get-VMSnapshot -VM $currentVm -ErrorAction Stop | Where-Object { $_.Name -ceq $Name })
    if ($snapshots.Count -ne 1) { throw "Expected exactly one checkpoint named '$Name' for owned VM '$($Vm.Name)'; found $($snapshots.Count)." }
    if($baseline){
        if([string]$snapshots[0].Id -cne [string]$baseline.id -or [string]$snapshots[0].VMId -cne [string]$baseline.vmId){throw 'Accepted baseline checkpoint GUID or L1 binding differs.'}
        if(-not $baseline.legacyOriginal -and [string]$snapshots[0].ParentSnapshotId -cne [string]$baseline.predecessorId){throw 'Accepted baseline checkpoint parent differs.'}
    }
    return $snapshots[0]
}

function Assert-MaintenanceReadyProvenance {
    param(
        [Parameter(Mandatory)][psobject]$Provenance,
        [Parameter(Mandatory)][psobject]$Vm,
        [Parameter(Mandatory)][psobject]$Snapshot,
        [Parameter(Mandatory)][psobject]$Fingerprint
    )
    if ([int]$Provenance.schemaVersion -ne 1 -or [string]$Provenance.contract -ne 'maintenance-ready-provenance-v1') {
        throw 'MAINTENANCE-READY provenance is missing or unsupported.'
    }
    if ([string]$Provenance.vmName -cne [string]$Vm.Name -or [string]$Provenance.vmId -cne [string]$Vm.Id) {
        throw 'MAINTENANCE-READY provenance is bound to a different disposable VM.'
    }
    if ([string]$Provenance.checkpointName -cne [string]$Snapshot.Name -or [string]$Provenance.checkpointId -cne [string]$Snapshot.Id) {
        throw 'MAINTENANCE-READY provenance is bound to a different checkpoint.'
    }
    $expected = [ordered]@{
        gitCommit=[string]$Fingerprint.gitCommit
        releaseVersion=[string]$Fingerprint.releaseVersion
        installerVersion=[string]$Fingerprint.installerVersion
        releaseFingerprintId=[string]$Fingerprint.releaseFingerprintId
        toolingFingerprintId=[string]$Fingerprint.toolingFingerprintId
        payloadSha256=[string]$Fingerprint.tar.sha256
    }
    foreach ($field in $expected.Keys) {
        if ([string]$Provenance.candidate.$field -cne $expected[$field]) { throw "MAINTENANCE-READY provenance candidate mismatch: $field." }
    }
    if ([int]$Provenance.ownership.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$Provenance.ownership.installationGeneration)) {
        throw 'MAINTENANCE-READY provenance has no current ownership-ledger identity.'
    }
    if ([string]$Provenance.install.installationGeneration -cne [string]$Provenance.ownership.installationGeneration) {
        throw 'MAINTENANCE-READY provenance installation and ownership generations differ.'
    }
    $hasVault=if($Provenance-is[System.Collections.IDictionary]){$Provenance.Contains('vault')}else{$null-ne$Provenance.PSObject.Properties['vault']}
    if(-not$hasVault-or[string]$Provenance.vault.status-cne'PASS'-or$Provenance.vault.configurationPresent-isnot[bool]-or-not$Provenance.vault.configurationPresent-or$Provenance.vault.proofCredit-isnot[bool]-or$Provenance.vault.proofCredit){throw 'MAINTENANCE-READY lacks its configured Primary Vault prerequisite.'}
    if([string]$Provenance.vault.payloadSha256-cne[string]$Fingerprint.tar.sha256-or[string]$Provenance.vault.primaryRole-cne'primary'){throw 'MAINTENANCE-READY Vault payload/Primary binding differs.'}
    if($Provenance.vault.authenticatedTransport-isnot[bool]-or-not$Provenance.vault.authenticatedTransport){throw 'MAINTENANCE-READY Vault transport is not authenticated.'}
    foreach($key in @('primaryId','vaultId','deploymentId')){$id=[guid]::Empty;if(-not[guid]::TryParse([string]$Provenance.vault.$key,[ref]$id)-or$id-eq[guid]::Empty){throw "MAINTENANCE-READY Vault $key is invalid."}}
    return $true
}

function Invoke-MaintenanceReadyProductLifecycle {
    <# Dedicated maintenance provisioning entrypoint. It intentionally does
       not route through REBOOT-RESUME and has no synthetic PFRO switch. #>
    param([Parameter(Mandatory)][psobject]$Context,[Parameter(Mandatory)][string]$WorkspaceRoot)
    $modulePath=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1'
    if(-not (Test-Path -LiteralPath $modulePath -PathType Leaf)){throw 'Dedicated maintenance product lifecycle executor is missing.'}
    Import-Module $modulePath -Force
    $Context.phaseId='MAINTENANCE-READY-PROVISION'
    return Invoke-ProductLifecycleConsumer -Context $Context
}

function Invoke-MaintenanceReadyGuestValidation {
    param([Parameter(Mandatory)][guid]$VmId,[Parameter(Mandatory)][psobject]$Fingerprint,[datetime]$OwnerDeadlineUtc=[datetime]::MinValue,[object]$Session)
    $deadline=[datetime]::UtcNow.AddSeconds(180)
    if($OwnerDeadlineUtc-ne[datetime]::MinValue-and$OwnerDeadlineUtc.ToUniversalTime()-lt$deadline){$deadline=$OwnerDeadlineUtc.ToUniversalTime()}
    $ownsSession=$false
    try {
        if(($deadline-[datetime]::UtcNow).TotalSeconds-le$(if($Session){10}else{70})){throw 'MAINTENANCE-READY owner budget cannot cover session/collection margins.'}
        if(-not$Session){$Session=Connect-DevFleetGuest -VmId $VmId;$ownsSession=$true}
        if([guid]$Session.Runspace.ConnectionInfo.VMGuid-ne$VmId){throw 'MAINTENANCE-READY session is bound to a different VM identity.'}
        $protocolSource=Join-Path $PSScriptRoot '../../../source/windows/DevFleet-HostAgentProtocol.psm1'
        $protocolSha256=(Get-FileHash -LiteralPath $protocolSource -Algorithm SHA256).Hash.ToLowerInvariant()
        $validationScript={
            param([string]$RequestJson)
            $ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
            $request=$RequestJson|ConvertFrom-Json -ErrorAction Stop
            $expectedVersion=[string]$request.version;$expectedInstaller=[string]$request.installer;$expectedPayload=[string]$request.payload
            if($PSVersionTable.PSEdition-ne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'MAINTENANCE-READY requires PowerShell7.'}
            $installPath='C:\ProgramData\M-TechLabs\DevFleet\Installer\install-state.json'
            $ownershipPath='C:\ProgramData\DevFleetHostAgent\integration-ownership.json'
            $ownershipModule='C:\ProgramData\DevFleetHostAgent\DevFleet-WindowsIntegrationOwnership.psm1'
            foreach($path in @($installPath,$ownershipPath,$ownershipModule)) {
                if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "MAINTENANCE-READY guest prerequisite is missing: $path"}
                if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "MAINTENANCE-READY guest prerequisite is a reparse point: $path"}
            }
            $install=Get-Content -LiteralPath $installPath -Raw|ConvertFrom-Json
            if([string]$install.DevFleetVersion -cne $expectedVersion -or [string]$install.InstallerVersion -cne $expectedInstaller -or [string]$install.PackageSha256 -cne $expectedPayload){throw 'MAINTENANCE-READY installed candidate identity is stale or mismatched.'}
            if([string]$install.WindowsIntegrationOwnershipPath -cne $ownershipPath -or [string]::IsNullOrWhiteSpace([string]$install.InstallationGeneration)){throw 'MAINTENANCE-READY install ledger lacks the canonical ownership binding.'}
            Import-Module $ownershipModule -Force
            $ownership=Read-DevFleetIntegrationOwnership -Path $ownershipPath
            if([int]$ownership.SchemaVersion -ne 1 -or [string]$ownership.InstallationGeneration -ne [string]$install.InstallationGeneration){throw 'MAINTENANCE-READY ownership generation/schema is not current.'}
            $bindings=@($ownership.ScheduledTasks)+@($ownership.FirewallRules)+@($ownership.Services)
            if($bindings.Count -lt 1){throw 'MAINTENANCE-READY ownership ledger has no installed integrations.'}
            foreach($binding in @($ownership.ScheduledTasks)) {
                $task=Get-ScheduledTask -TaskName ([string]$binding.Name) -ErrorAction Stop
                if(@($task.Actions).Count -ne 1){throw 'MAINTENANCE-READY scheduled-task ownership is ambiguous.'}
                $actual=@{Name=[string]$task.TaskName;Executable=[string]$task.Actions[0].Execute;Arguments=[string]$task.Actions[0].Arguments;Principal=[string]$task.Principal.UserId;LogonType=[string]$task.Principal.LogonType;RunLevel=[string]$task.Principal.RunLevel;Description=[string]$task.Description;Generation=[string]$binding.Generation}
                Assert-DevFleetTaskBinding -Expected $binding -Actual $actual|Out-Null
            }
            function Get-MaintenanceReadyFirewallActual {
                param([Parameter(Mandatory)]$Binding)
                $rules=@(Get-NetFirewallRule -Name ([string]$Binding.Name) -ErrorAction Stop)
                if($rules.Count -ne 1){throw 'MAINTENANCE-READY firewall ownership is ambiguous.'}
                $rule=$rules[0]
                $ports=@($rule|Get-NetFirewallPortFilter -ErrorAction Stop)
                $addresses=@($rule|Get-NetFirewallAddressFilter -ErrorAction Stop)
                $interfaces=@($rule|Get-NetFirewallInterfaceFilter -ErrorAction Stop)
                if($ports.Count -ne 1 -or $addresses.Count -ne 1 -or $interfaces.Count -ne 1){throw 'MAINTENANCE-READY firewall rule filter identity is ambiguous.'}
                $port=$ports[0];$address=$addresses[0];$interface=$interfaces[0]
                return @{Name=[string]$rule.Name;DisplayName=[string]$rule.DisplayName;Group=[string]$rule.Group;Description=[string]$rule.Description;Direction=[string]$rule.Direction;Action=[string]$rule.Action;Protocol=[string]$port.Protocol;LocalPort=[string]$port.LocalPort;InterfaceAlias=[string]$interface.InterfaceAlias;RemoteAddress=[string]$address.RemoteAddress;Profile=[string]$rule.Profile;Generation=[string]$Binding.Generation}
            }
            function Get-MaintenanceReadyFirewallExpected {
                param([Parameter(Mandatory)]$OriginalBinding)
                $currentOwnership=Read-DevFleetIntegrationOwnership -Path $ownershipPath
                if([int]$currentOwnership.SchemaVersion -ne 1 -or [string]$currentOwnership.InstallationGeneration -cne [string]$install.InstallationGeneration){throw 'MAINTENANCE-READY firewall ownership ledger changed generation/schema during convergence.'}
                $current=@($currentOwnership.FirewallRules|Where-Object{[string]$_.Name-ceq[string]$OriginalBinding.Name})
                if($current.Count-ne1){throw 'MAINTENANCE-READY firewall ownership binding is missing or ambiguous during convergence.'}
                # The product may refresh only provider-backed fields. Keep the
                # original ledger binding as an immutable baseline so a foreign
                # or tampered ledger cannot be adopted while waiting.
                Assert-DevFleetFirewallRefreshIdentity -Expected $OriginalBinding -Actual $current[0]|Out-Null
                return $current[0]
            }
            function Assert-MaintenanceReadyFirewallBinding {
                param([Parameter(Mandatory)]$Binding,[ValidateRange(1,120)][int]$WaitSeconds=60)
                $deadline=[datetime]::UtcNow.AddSeconds($WaitSeconds);$attempts=0
                do {
                    $attempts++
                    $expected=Get-MaintenanceReadyFirewallExpected -OriginalBinding $Binding
                    $actual=Get-MaintenanceReadyFirewallActual -Binding $expected
                    # Provider-backed InterfaceAlias/RemoteAddress may settle
                    # after a virtual adapter recreation. Immutable ownership
                    # identity is always checked before any convergence wait.
                    Assert-DevFleetFirewallRefreshIdentity -Expected $expected -Actual $actual|Out-Null
                    try {
                        Assert-DevFleetFirewallBinding -Expected $expected -Actual $actual|Out-Null
                        return [ordered]@{name=[string]$Binding.Name;attempts=$attempts;converged=$true}
                    } catch {
                        if([datetime]::UtcNow-ge$deadline){throw}
                        Start-Sleep -Seconds 1
                    }
                } while($true)
            }
            $firewallConvergence=[System.Collections.Generic.List[object]]::new()
            foreach($binding in @($ownership.FirewallRules)) {
                $firewallConvergence.Add((Assert-MaintenanceReadyFirewallBinding -Bindin