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
