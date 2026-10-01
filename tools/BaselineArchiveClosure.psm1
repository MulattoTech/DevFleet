Set-StrictMode -Version Latest

function Read-BaselineArchiveJson([string]$Path) {
    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    } catch {
        throw "Baseline archive JSON is missing or malformed: $Path"
    }
}

function Assert-BaselineArchiveHash([string]$Hash, [string]$Description) {
    if ($Hash -cnotmatch '^[0-9a-f]{64}$') { throw "Baseline archive $Description hash is malformed." }
}

function Assert-BaselineArchiveFile([string]$Path, [string]$ExpectedHash) {
    Assert-BaselineArchiveHash $ExpectedHash 'file'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Baseline archive source is missing: $Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Baseline archive source is a reparse point: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $ExpectedHash) { throw "Baseline archive source hash differs: $Path" }
}

function Copy-BaselineArchiveFile([string]$Source, [string]$Destination, [string]$ExpectedHash) {
    Assert-BaselineArchiveFile $Source $ExpectedHash
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Assert-BaselineArchiveFile $Destination $ExpectedHash
}

function Assert-BaselineArchiveDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Baseline archive directory is missing: $Path" }
    if (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Baseline archive directory is a reparse point: $Path"
    }
}

function Copy-BaselineArchiveSource([string]$BaselineRoot, [string]$StagedRoot, [string]$Hash, [string]$Extension, [string]$Description) {
    Assert-BaselineArchiveHash $Hash $Description
    $file = "$Hash.$Extension"
    $source = Join-Path $BaselineRoot "sources\$file"
    $destination = Join-Path $StagedRoot "sources\$file"
    Copy-BaselineArchiveFile $source $destination $Hash
    return $source
}

function Assert-BaselineArchiveGeneration($Pointer) {
    $generation = $Pointer.generation
    if (($generation -isnot [int] -and $generation -isnot [long]) -or $generation -lt 1 -or $generation -gt 8) {
        throw 'Unsupported accepted baseline generation.'
    }
    if (($Pointer.schemaVersion -isnot [int] -and $Pointer.schemaVersion -isnot [long]) -or
        $Pointer.schemaVersion -ne $generation -or
        [string]$Pointer.contract -cne "devfleet-accepted-baseline-v$generation" -or
        [string]$Pointer.status -cne 'ACCEPTED' -or
        [string]$Pointer.checkpoint.id -eq '' -or [string]$Pointer.checkpoint.name -eq '') {
        throw "Accepted baseline generation $generation pointer is malformed."
    }
    return [int]$generation
}

function Assert-BaselineArchiveReceipt($Pointer, $Receipt, [int]$Generation, [string]$ReceiptFile) {
    $expectedContract = if ($Generation -eq 1) { 'devfleet-baseline-adoption-receipt-v1' } else { "devfleet-baseline-rebind-receipt-v$Generation" }
    $expectedStatus = if ($Generation -eq 1) { 'ADOPTED' } else { 'REBOUND' }
    if (($Receipt.schemaVersion -isnot [int] -and $Receipt.schemaVersion -isnot [long]) -or
        $Receipt.schemaVersion -ne $Generation -or
        [string]$Receipt.contract -cne $expectedContract -or
        [string]$Receipt.status -cne $expectedStatus -or
        "$($Receipt.receiptId).json" -cne $ReceiptFile) {
        throw "Accepted baseline generation $Generation receipt is malformed."
    }
    if ($Generation -gt 1) {
        if ([string]$Receipt.previousPointerSha256 -cne [string]$Pointer.previousPointerSha256 -or
            [string]$Receipt.replacement.id -cne [string]$Pointer.checkpoint.id -or
            [string]$Receipt.replacement.name -cne [string]$Pointer.checkpoint.name) {
            throw "Accepted baseline generation $Generation receipt lineage differs."
        }
        Assert-BaselineArchiveHash ([string]$Receipt.previousReceiptSha256) 'previous receipt'
    }
}

function Copy-DevFleetBaselineArchiveClosure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$EvidenceStage
    )
    $baselineRoot = Join-Path $WorkspaceRoot 'evidence\baselines'
    $stagedRoot = Join-Path $EvidenceStage 'baselines'
    foreach ($directory in @($baselineRoot, (Join-Path $baselineRoot 'receipts'))) {
        Assert-BaselineArchiveDirectory $directory
    }
    $pointerPath = Join-Path $baselineRoot 'CURRENT.json'
    $cursor = Read-BaselineArchiveJson $pointerPath
    $generation = Assert-BaselineArchiveGeneration $cursor
    if ($generation -gt 1) { Assert-BaselineArchiveDirectory (Join-Path $baselineRoot 'history') }
    if ($generation -gt 2) { Assert-BaselineArchiveDirectory (Join-Path $baselineRoot 'sources') }
    $expectedReceiptHash = $null
    $expectedCheckpoint = $null
    while ($true) {
        $currentGeneration = Assert-BaselineArchiveGeneration $cursor
        if ($currentGeneration -ne $generation) { throw 'Accepted baseline generations are not contiguous.' }
        if ($null -ne $expectedReceiptHash -and [string]$cursor.receiptSha256 -cne $expectedReceiptHash) {
            throw 'Accepted baseline predecessor receipt hash differs.'
        }
        if ($null -ne $expectedCheckpoint -and
            ([string]$cursor.checkpoint.id -cne [string]$expectedCheckpoint.id -or
             [string]$cursor.checkpoint.name -cne [string]$expectedCheckpoint.name)) {
            throw 'Accepted baseline checkpoint changed in predecessor chain.'
        }
        $receiptFile = [string]$cursor.receiptFile
        if ($receiptFile -cnotmatch '^[0-9a-f]{32}\.json$') { throw 'Accepted baseline receipt filename is malformed.' }
        $receiptHash = [string]$cursor.receiptSha256
        Assert-BaselineArchiveHash $receiptHash 'receipt'
        $receiptPath = Join-Path $baselineRoot "receipts\$receiptFile"
        $stagedReceipt = Join-Path $stagedRoot "receipts\$receiptFile"
        Copy-BaselineArchiveFile $receiptPath $stagedReceipt $receiptHash
        $receipt = Read-BaselineArchiveJson $receiptPath
        Assert-BaselineArchiveReceipt $cursor $receipt $generation $receiptFile

        if ($generation -ge 3) {
            $ledgerPath = Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$receipt.successorLedgerSha256) 'json' 'successor ledger'
            [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$receipt.nativeInventorySha256) 'json' 'native inventory')
            if ($generation -eq 4) {
                $ledger = Read-BaselineArchiveJson $ledgerPath
                $artifactHash = [string]$receipt.artifactReceiptSha256
                Assert-BaselineArchiveHash $artifactHash 'signed output artifact receipt'
                if ([string]$ledger.artifactReceipt.sha256 -cne $artifactHash) {
                    throw 'Generation-4 signed output artifact receipt is not bound by its successor ledger.'
                }
                [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot $artifactHash 'json' 'signed output artifact receipt')
            }
            if ($generation -eq 7) {
                [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$receipt.approvalSha256) 'json' 'baseline approval')
                foreach ($field in @('successorAuthorizationSha256', 'predecessorLedgerSha256')) {
                    [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$receipt.$field) 'json' $field)
                }
                [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$receipt.ownerAuthorizationSha256) 'txt' 'owner authorization')
                foreach ($field in @('wrapper', 'proofError', 'cleanup')) {
                    [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$receipt.failureEvidenceSha256.$field) 'json' "failure evidence $field")
                }
                $token = $receipt.standardTokenEvidence
                if ([string]$token.runId -cnotmatch '^standard-token-[A-Za-z0-9-]+$' -or
                    [string]$token.pointerPath -cne 'evidence/CURRENT-STANDARD-TOKEN.json' -or
                    [string]$token.canonicalPath -cne "evidence/standard-token/$($token.runId)/standard-token-evidence.json" -or
                    [string]$token.rawReportPath -cne "evidence/standard-token/$($token.runId)/installer-self-test-raw.txt") {
                    throw 'Generation-7 standard token evidence reference is malformed.'
                }
                [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$token.pointerSha256) 'json' 'standard token pointer')
                [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$token.canonicalSha256) 'json' 'standard token canonical evidence')
                [void](Copy-BaselineArchiveSource $baselineRoot $stagedRoot ([string]$token.rawReportSha256) 'txt' 'standard token raw report')
            }
            if ($generation -eq 8) {
                $closure = $receipt.sourceClosure
                if ($closure -isnot [array] -or $closure.Count -lt 1 -or $closure.Count -gt 512) {
                    throw 'Generation-8 source closure manifest is malformed.'
                }
                $seen = @{}
                $totalBytes = [long]0
                foreach ($source in $closure) {
                    $hash = [string]$source.sha256
                    $extension = [string]$source.extension
                    if ($hash -cnotmatch '^[0-9a-f]{64}$' -or $extension -cnotmatch '^\.[a-z0-9]{1,8}$') {
                        throw 'Generation-8 source closure entry is malformed.'
                    }
                    $key = "$hash$extension"
                    if ($seen.ContainsKey($key)) { throw 'Generation-8 source closure repeats an entry.' }
                    $seen[$key] = $true
                    $sourcePath = Join-Path $baselineRoot "sources\$key"
                    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                        throw "Generation-8 source closure member is missing: $key"
                    }
                    $sourceLength = (Get-Item -LiteralPath $sourcePath -Force).Length
                    if ($sourceLength -gt 4000000) {
                        throw "Generation-8 source closure member exceeds 4 MB: $key"
                    }
                    $totalBytes += $sourceLength
                    if ($totalBytes -gt 32000000) { throw 'Generation-8 source closure exceeds its size limit.' }
                    Copy-BaselineArchiveFile $sourcePath (Join-Path $stagedRoot "sources\$key") $hash
                }
            }
        }

        if ($generation -eq 1) { break }
        $previousHash = [string]$cursor.previousPointerSha256
        Assert-BaselineArchiveHash $previousHash 'predecessor pointer'
        $historyPath = Join-Path $baselineRoot "history\$previousHash.json"
        $stagedHistory = Join-Path $stagedRoot "history\$previousHash.json"
        Copy-BaselineArchiveFile $historyPath $stagedHistory $previousHash
        $expectedReceiptHash = [string]$receipt.previousReceiptSha256
        $expectedCheckpoint = $cursor.checkpoint
        $cursor = Read-BaselineArchiveJson $historyPath
        $generation--
    }
    $currentHash = (Get-FileHash -LiteralPath $pointerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-BaselineArchiveFile $pointerPath (Join-Path $stagedRoot 'CURRENT.json') $currentHash
}

Export-ModuleMember -Function Copy-DevFleetBaselineArchiveClosure
