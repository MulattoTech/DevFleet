[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\..\..\tools\BaselineArchiveClosure.psm1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-audit-baseline-' + [guid]::NewGuid().ToString('N'))
$workspace = Join-Path $scratch 'workspace'
$staged = Join-Path $scratch 'staged'
$baseline = Join-Path $workspace 'evidence\baselines'
$count = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:count++
}
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-True $rejected $Message
}
function Write-FixtureJson([string]$Path, $Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
}
function File-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Add-Source([string]$Name) {
    $temporary = Join-Path $scratch ($Name + '.json')
    Write-FixtureJson $temporary ([ordered]@{ name = $Name })
    $hash = File-Hash $temporary
    $target = Join-Path $baseline "sources\$hash.json"
    Copy-Item -LiteralPath $temporary -Destination $target
    return $hash
}
function Add-TextSource([string]$Name) {
    $temporary = Join-Path $scratch ($Name + '.txt')
    [IO.File]::WriteAllText($temporary, "text fixture: $Name", [Text.UTF8Encoding]::new($false))
    $hash = File-Hash $temporary
    Copy-Item -LiteralPath $temporary -Destination (Join-Path $baseline "sources\$hash.txt")
    return $hash
}

try {
    New-Item -ItemType Directory -Force -Path $baseline, $staged, (Join-Path $baseline 'sources'), (Join-Path $baseline 'history') | Out-Null
    $expected = [Collections.Generic.List[string]]::new()
    $checkpoint = [ordered]@{ id = '11111111-2222-4333-8444-555555555555'; name = 'DevFleet-E2E-CLEAN-R2' }
    $previousPointerHash = $null
    $previousReceiptHash = $null
    for ($generation = 1; $generation -le 7; $generation++) {
        $receiptId = ('{0:x32}' -f $generation)
        $receiptFile = "$receiptId.json"
        $receipt = [ordered]@{
            schemaVersion = $generation
            contract = if ($generation -eq 1) { 'devfleet-baseline-adoption-receipt-v1' } else { "devfleet-baseline-rebind-receipt-v$generation" }
            receiptId = $receiptId
            status = if ($generation -eq 1) { 'ADOPTED' } else { 'REBOUND' }
        }
        if ($generation -gt 1) {
            $receipt.previousPointerSha256 = $previousPointerHash
            $receipt.previousReceiptSha256 = $previousReceiptHash
            $receipt.replacement = $checkpoint
        }
        if ($generation -ge 3) {
            $receipt.successorLedgerSha256 = Add-Source "ledger-$generation"
            $receipt.nativeInventorySha256 = Add-Source "inventory-$generation"
            $expected.Add("sources/$($receipt.successorLedgerSha256).json")
            $expected.Add("sources/$($receipt.nativeInventorySha256).json")
        }
        if ($generation -eq 4) {
            $receipt.artifactReceiptSha256 = Add-Source 'signed-output-artifact'
            $expected.Add("sources/$($receipt.artifactReceiptSha256).json")
            $ledgerPath = Join-Path $baseline "sources\$($receipt.successorLedgerSha256).json"
            $ledger = [ordered]@{ artifactReceipt = [ordered]@{ sha256 = $receipt.artifactReceiptSha256 } }
            Write-FixtureJson $ledgerPath $ledger
            $oldHash = $receipt.successorLedgerSha256
            $newHash = File-Hash $ledgerPath
            Move-Item -LiteralPath $ledgerPath -Destination (Join-Path $baseline "sources\$newHash.json")
            $receipt.successorLedgerSha256 = $newHash
            $expected.Remove("sources/$oldHash.json") | Out-Null
            $expected.Add("sources/$newHash.json")
        }
        if ($generation -eq 7) {
            $receipt.approvalSha256 = Add-Source 'baseline-approval-7'
            $receipt.successorAuthorizationSha256 = Add-Source 'successor-authorization-7'
            $receipt.ownerAuthorizationSha256 = Add-TextSource 'owner-authorization-7'
            $receipt.predecessorLedgerSha256 = Add-Source 'predecessor-ledger-7'
            $receipt.failureEvidenceSha256 = [ordered]@{
                wrapper = Add-Source 'failure-wrapper-7'
                proofError = Add-Source 'proof-error-7'
                cleanup = Add-Source 'cleanup-7'
            }
            $pointerHash = Add-Source 'standard-token-pointer-7'
            $canonicalHash = Add-Source 'standard-token-canonical-7'
            $rawHash = Add-TextSource 'standard-token-raw-7'
            $receipt.standardTokenEvidence = [ordered]@{
                runId = 'standard-token-fixture-7'
                pointerSha256 = $pointerHash
                canonicalSha256 = $canonicalHash
                rawReportSha256 = $rawHash
                pointerPath = 'evidence/CURRENT-STANDARD-TOKEN.json'
                canonicalPath = 'evidence/standard-token/standard-token-fixture-7/standard-token-evidence.json'
                rawReportPath = 'evidence/standard-token/standard-token-fixture-7/installer-self-test-raw.txt'
            }
            foreach ($hash in @($receipt.approvalSha256, $receipt.successorAuthorizationSha256, $receipt.predecessorLedgerSha256,
                $receipt.failureEvidenceSha256.wrapper, $receipt.failureEvidenceSha256.proofError,
                $receipt.failureEvidenceSha256.cleanup, $pointerHash, $canonicalHash)) {
                $expected.Add("sources/$hash.json")
            }
            $expected.Add("sources/$rawHash.txt")
            $expected.Add("sources/$($receipt.ownerAuthorizationSha256).txt")
        }
        $receiptPath = Join-Path $baseline "receipts\$receiptFile"
        Write-FixtureJson $receiptPath $receipt
        $receiptHash = File-Hash $receiptPath
        $expected.Add("receipts/$receiptFile")
        $pointer = [ordered]@{
            schemaVersion = $generation
            contract = "devfleet-accepted-baseline-v$generation"
            generation = $generation
            status = 'ACCEPTED'
            receiptFile = $receiptFile
            receiptSha256 = $receiptHash
            checkpoint = $checkpoint
        }
        if ($generation -gt 1) { $pointer.previousPointerSha256 = $previousPointerHash }
        $pointerPath = Join-Path $scratch "pointer-$generation.json"
        Write-FixtureJson $pointerPath $pointer
        if ($generation -gt 1) {
            $historyFile = "$previousPointerHash.json"
            Copy-Item -LiteralPath (Join-Path $scratch "pointer-$($generation - 1).json") -Destination (Join-Path $baseline "history\$historyFile")
            $expected.Add("history/$historyFile")
        }
        $previousPointerHash = File-Hash $pointerPath
        $previousReceiptHash = $receiptHash
    }
    Copy-Item -LiteralPath (Join-Path $scratch 'pointer-7.json') -Destination (Join-Path $baseline 'CURRENT.json')
    $expected.Add('CURRENT.json')

    Import-Module $modulePath -Force
    Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $workspace -EvidenceStage $staged
    foreach ($relative in $expected) {
        $source = Join-Path $baseline $relative
        $copy = Join-Path (Join-Path $staged 'baselines') $relative
        Assert-True (Test-Path -LiteralPath $copy -PathType Leaf) "Archive omitted $relative"
        Assert-True ((File-Hash $copy) -ceq (File-Hash $source)) "Archive changed $relative"
    }
    $receipt7 = Get-Content -LiteralPath (Join-Path $baseline 'receipts\00000000000000000000000000000007.json') -Raw | ConvertFrom-Json
    $approvalSource = Join-Path $baseline "sources\$($receipt7.approvalSha256).json"
    $approvalSaved = Join-Path $scratch 'saved-baseline-approval-7.json'
    Move-Item -LiteralPath $approvalSource -Destination $approvalSaved
    Assert-Rejected { Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $workspace -EvidenceStage (Join-Path $scratch 'approval-missing-stage') } 'Missing baseline approval source was accepted.'
    Move-Item -LiteralPath $approvalSaved -Destination $approvalSource
    [IO.File]::AppendAllText($approvalSource, 'tampered')
    Assert-Rejected { Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $workspace -EvidenceStage (Join-Path $scratch 'approval-corrupt-stage') } 'Changed baseline approval source was accepted.'
    Copy-Item -LiteralPath (Join-Path $scratch 'baseline-approval-7.json') -Destination $approvalSource -Force
    $ownerSource = Join-Path $baseline "sources\$($receipt7.ownerAuthorizationSha256).txt"
    [IO.File]::AppendAllText($ownerSource, 'tampered')
    Assert-Rejected { Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $workspace -EvidenceStage (Join-Path $scratch 'owner-corrupt-stage') } 'Changed owner authorization source was accepted.'
    Copy-Item -LiteralPath (Join-Path $scratch 'owner-authorization-7.txt') -Destination $ownerSource -Force
    $ledger5 = Join-Path $baseline "sources\$((Get-Content -LiteralPath (Join-Path $baseline 'receipts\00000000000000000000000000000005.json') -Raw | ConvertFrom-Json).successorLedgerSha256).json"
    [IO.File]::AppendAllText($ledger5, 'tampered')
    Assert-Rejected { Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $workspace -EvidenceStage (Join-Path $scratch 'corrupt-stage') } 'Changed predecessor source was accepted.'
    $currentPath = Join-Path $baseline 'CURRENT.json'
    $current = Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json
    $current.generation = 8
    $current.schemaVersion = 8
    $current.contract = 'devfleet-accepted-baseline-v8'
    Write-FixtureJson $currentPath $current
    Assert-Rejected { Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $workspace -EvidenceStage (Join-Path $scratch 'unsupported-stage') } 'Unsupported generation was accepted.'
    $current.generation = '7'
    $current.schemaVersion = 7
    $current.contract = 'devfleet-accepted-baseline-v7'
    Write-FixtureJson $currentPath $current
    Assert-Rejected { Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $workspace -EvidenceStage (Join-Path $scratch 'malformed-stage') } 'String valued generation was accepted.'
    $firstWorkspace = Join-Path $scratch 'generation-one-workspace'
    $firstBaseline = Join-Path $firstWorkspace 'evidence\baselines'
    New-Item -ItemType Directory -Force -Path (Join-Path $firstBaseline 'receipts') | Out-Null
    Copy-Item -LiteralPath (Join-Path $scratch 'pointer-1.json') -Destination (Join-Path $firstBaseline 'CURRENT.json')
    Copy-Item -LiteralPath (Join-Path $baseline 'receipts\00000000000000000000000000000001.json') -Destination (Join-Path $firstBaseline 'receipts\00000000000000000000000000000001.json')
    $firstStage = Join-Path $scratch 'generation-one-stage'
    Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $firstWorkspace -EvidenceStage $firstStage
    Assert-True (Test-Path -LiteralPath (Join-Path $firstStage 'baselines\CURRENT.json') -PathType Leaf) 'Generation 1 without history or sources was not staged.'
    Write-Output "PASS: $count baseline archive chain assertions"
} finally {
    $resolvedScratch = [IO.Path]::GetFullPath($scratch)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedScratch.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedScratch) -cnotmatch '^devfleet-audit-baseline-[0-9a-f]{32}$') {
        throw 'Fixture cleanup escaped its exact temporary root.'
    }
    Remove-Item -LiteralPath $resolvedScratch -Recurse -Force -ErrorAction SilentlyContinue
}
