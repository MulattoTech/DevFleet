Set-StrictMode -Version Latest

function ConvertTo-DevFleetBaselineUtc([object]$Value) {
    $parsed=[datetimeoffset]::MinValue
    if($Value -is [datetime]){
        if($Value.Kind -ne [datetimekind]::Utc){throw 'Baseline evidence instant is not UTC.'}
        $parsed=[datetimeoffset]$Value
    }elseif(-not[datetimeoffset]::TryParse([string]$Value,[ref]$parsed)){
        throw 'Baseline evidence instant is malformed.'
    }
    if($parsed.Offset -ne [timespan]::Zero){throw 'Baseline evidence instant is not UTC.'}
    return $parsed
}

function Get-DevFleetAcceptedBaseline {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[psobject]$Fingerprint)
    $root=(Resolve-Path -LiteralPath $WorkspaceRoot -ErrorAction Stop).Path
    $oldName='DevFleet-E2E-CLEAN'
    $oldId='19865b76-4c3a-44f7-ba39-841e9d3c40c9'
    $vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
    $pointerPath=Join-Path $root 'evidence\baselines\CURRENT.json'
    if(-not(Test-Path -LiteralPath $pointerPath -PathType Leaf)){
        return [pscustomobject]@{name=$oldName;id=$oldId;vmName='DevFleet-E2E-Win11-01';vmId=$vmId;predecessorId=$null;receiptSha256=$null;legacyOriginal=$true}
    }
    if($null -eq $Fingerprint){throw 'Adopted baseline requires a current native candidate fingerprint.'}
    $pointerItem=Get-Item -LiteralPath $pointerPath -Force -ErrorAction Stop
    if(($pointerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $pointerItem.Length -gt 1048576){throw 'Accepted baseline pointer is linked or oversized.'}
    $pointer=Get-Content -LiteralPath $pointerPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if([int]$pointer.generation -in @(2,3,4,5)){
        # The rebound reader validates the complete archived pointer and
        # immutable receipt chain in the native strict-JSON transaction module.
        $expected=[ordered]@{
            repositoryHead=[string]$Fingerprint.repositoryHead
            candidateBuildCommit=[string]$Fingerprint.gitCommit
            shippingInputIdentity=[string]$Fingerprint.shippingInputIdentity
            releaseFingerprintId=[string]$Fingerprint.releaseFingerprintId
            toolingFingerprintId=[string]$Fingerprint.toolingFingerprintId
            candidateSha256=[string]$Fingerprint.candidate.sha256
        }
        $tuplePath=[IO.Path]::GetTempFileName()
        try {
            [IO.File]::WriteAllText($tuplePath,($expected|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
            $python=(Get-Command python.exe -ErrorAction Stop).Source
            $script=Join-Path $root 'tools\baseline_lineage.py'
            $lines=@(& $python $script inspect --root $root --tuple $tuplePath)
            if($LASTEXITCODE -ne 0){throw 'Native rebound baseline lineage rejected.'}
            $resolved=($lines -join "`n")|ConvertFrom-Json -ErrorAction Stop
            if([string]$resolved.receiptSha256 -cne [string]$pointer.receiptSha256 -or [string]$resolved.id -cne [string]$pointer.checkpoint.id){throw 'Native rebound baseline result differs.'}
            return $resolved
        } finally {Remove-Item -LiteralPath $tuplePath -Force -ErrorAction SilentlyContinue}
    }
    if([int]$pointer.schemaVersion -ne 1 -or [string]$pointer.contract -cne 'devfleet-accepted-baseline-v1' -or [int]$pointer.generation -ne 1 -or [string]$pointer.status -cne 'ACCEPTED'){
        throw 'Accepted baseline pointer contract is invalid.'
    }
    $receiptFile=[string]$pointer.receiptFile
    if($receiptFile -cnotmatch '^[0-9a-f]{32}\.json$'){throw 'Accepted baseline receipt filename is invalid.'}
    $receiptPath=Join-Path $root (Join-Path 'evidence\baselines\receipts' $receiptFile)
    $receiptItem=Get-Item -LiteralPath $receiptPath -Force -ErrorAction Stop
    if($receiptItem.PSIsContainer -or ($receiptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $receiptItem.Length -gt 1048576){throw 'Accepted baseline receipt is linked or oversized.'}
    $receiptHash=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if([string]$pointer.receiptSha256 -cne $receiptHash){throw 'Accepted baseline receipt hash mismatch.'}
    $receipt=Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if([int]$receipt.schemaVersion -ne 1 -or [string]$receipt.contract -cne 'devfleet-baseline-adoption-receipt-v1' -or [string]$receipt.status -cne 'ADOPTED' -or [string]$receipt.receiptId -cne $receiptFile.Substring(0,32) -or $receipt.certificationCredit -isnot [bool] -or $receipt.certificationCredit -or $receipt.secretValuesRecorded -isnot [bool] -or $receipt.secretValuesRecorded){throw 'Accepted baseline receipt contract is invalid.'}
    if([string]$receipt.predecessor.name -cne $oldName -or [string]$receipt.predecessor.id -cne $oldId){throw 'Accepted baseline predecessor identity differs.'}
    $replacement=$receipt.replacement
    $newId=[guid]::Empty
    if(-not[guid]::TryParse([string]$replacement.id,[ref]$newId) -or $newId -eq [guid]$oldId -or [string]$replacement.name -cne 'DevFleet-E2E-CLEAN-R2' -or [string]$replacement.vmId -cne $vmId -or [string]$replacement.parentSnapshotId -cne $oldId){throw 'Accepted replacement identity or parent differs.'}
    if([string]$pointer.checkpoint.name -cne [string]$replacement.name -or [string]$pointer.checkpoint.id -cne [string]$replacement.id -or [string]$pointer.checkpoint.vmId -cne $vmId -or [string]$pointer.checkpoint.parentSnapshotId -cne $oldId){throw 'Pointer and immutable receipt checkpoint disagree.'}
    $expected=[ordered]@{
        repositoryHead=[string]$Fingerprint.repositoryHead
        candidateBuildCommit=[string]$Fingerprint.gitCommit
        shippingInputIdentity=[string]$Fingerprint.shippingInputIdentity
        releaseFingerprintId=[string]$Fingerprint.releaseFingerprintId
        toolingFingerprintId=[string]$Fingerprint.toolingFingerprintId
        candidateSha256=[string]$Fingerprint.candidate.sha256
    }
    foreach($key in $expected.Keys){
        if([string]$receipt.candidate.$key -cne $expected[$key]){throw "Accepted baseline candidate/material mismatch: $key"}
    }
    $expiry=ConvertTo-DevFleetBaselineUtc $receipt.passwordExpiresUtc
    $lastSet=ConvertTo-DevFleetBaselineUtc $receipt.passwordLastSetUtc
    $storeUpdated=ConvertTo-DevFleetBaselineUtc $receipt.protectedStoreUpdatedUtc
    $authObserved=ConvertTo-DevFleetBaselineUtc $receipt.authenticatedGuest.sourceObservedUtc
    if($expiry -le [datetimeoffset]::UtcNow -or $lastSet -gt $storeUpdated -or $storeUpdated -gt $authObserved -or $authObserved -ge $expiry){throw 'Accepted baseline account freshness or expiry is unknown or elapsed.'}
    if([string]$receipt.adoptionAuthority.decision -cne 'APPROVE' -or [string]$receipt.adoptionAuthority.approvedBy -cne 'ACCOUNT_OWNER' -or [string]$receipt.authenticatedGuest.computerName -cne 'DEVFLEET-E2E-01' -or [string]$receipt.authenticatedGuest.principal -cne 'DEVFLEET-E2E-01\E2EAdmin' -or $receipt.authenticatedGuest.accountEnabled -isnot [bool] -or -not $receipt.authenticatedGuest.accountEnabled -or [string]$receipt.nestedL2.status -cne 'ABSENT' -or $receipt.nestedL2.present -isnot [bool] -or $receipt.nestedL2.present -or [string]$receipt.nestedL2.expectedName -cne 'DevFleet-E2E-Linux-01' -or [int]$receipt.nestedL2.exactMatchCount -ne 0 -or [string]$receipt.finalL1.state -cne 'Off' -or [string]$receipt.finalL1.name -cne 'DevFleet-E2E-Win11-01' -or [string]$receipt.finalL1.id -cne $vmId){throw 'Accepted baseline adoption authority, guest, nested inventory, or terminal L1 is invalid.'}
    $inventories=@($receipt.nestedL2.backendInventories)
    if($inventories.Count -ne 2 -or @($inventories|Where-Object{$_.provider -ceq 'Hyper-V' -and $_.status -ceq 'PASS'}).Count -ne 1 -or @($inventories|Where-Object{$_.provider -ceq 'VirtualBox' -and $_.status -ceq 'PASS'}).Count -ne 1){throw 'Accepted baseline nested backend inventory is incomplete.'}
    foreach($inventory in $inventories){
        if($inventory.names -isnot [array] -or [string]::IsNullOrWhiteSpace([string]$inventory.verification) -or @($inventory.names|Where-Object{$_ -ceq 'DevFleet-E2E-Linux-01'}).Count -gt 0){throw 'Accepted baseline nested backend inventory is incomplete or present.'}
    }
    foreach($sourceKey in @('proposalSha256','predecessorEvidenceSha256','approvalSha256','authenticatedGuestSha256','nativeInventorySha256','currentTupleSha256','r2LedgerSha256')){
        if([string]$receipt.sources.$sourceKey -cnotmatch '^[0-9a-f]{64}$'){throw "Accepted baseline source hash missing: $sourceKey"}
    }
    if([string]$receipt.adoptionAuthority.sourceSha256 -cne [string]$receipt.sources.approvalSha256){throw 'Accepted baseline adoption approval hash differs.'}
    return [pscustomobject]@{name=[string]$replacement.name;id=[string]$replacement.id;vmName='DevFleet-E2E-Win11-01';vmId=$vmId;predecessorId=$oldId;receiptSha256=$receiptHash;receiptFile=$receiptFile;legacyOriginal=$false}
}

Export-ModuleMember -Function Get-DevFleetAcceptedBaseline
