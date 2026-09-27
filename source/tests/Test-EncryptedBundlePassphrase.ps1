[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\DevFleet.Common.psm1'
$bundleModule = Import-Module $modulePath -Force -PassThru -DisableNameChecking
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "devfleet-pairing-passphrase-$([guid]::NewGuid().ToString('N'))"
$fixtureRoot = [IO.Path]::GetFullPath($fixtureRoot)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $fixtureRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture root escaped the temporary directory.' }
$checks = [Collections.Generic.List[object]]::new()
$fixturePassphrase = 'isolated-pairing-passphrase-2026'
$secure = ConvertTo-SecureString $fixturePassphrase -AsPlainText -Force
$wrong = ConvertTo-SecureString 'different-isolated-passphrase' -AsPlainText -Force
$short = ConvertTo-SecureString 'short' -AsPlainText -Force
$empty = [Security.SecureString]::new()

function Check([string]$Name, [bool]$Pass) {
    $checks.Add([pscustomobject]@{name=$Name;pass=$Pass})
    if (-not $Pass) { throw "Encrypted bundle regression failed: $Name" }
}
function Rejects([scriptblock]$Action) {
    try { & $Action | Out-Null; return $false }
    catch {
        if ($_.Exception.Message.Contains($fixturePassphrase)) { throw 'Passphrase was included in an exception.' }
        return $true
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $payload = Join-Path $fixtureRoot 'payload'; New-Item -ItemType Directory -Path $payload | Out-Null
    [IO.File]::WriteAllText((Join-Path $payload 'public-fixture.json'), '{"fixture":"isolated-pairing"}', [Text.UTF8Encoding]::new($false))
    & $bundleModule {
        param([Security.SecureString]$Value)
        $script:BundleTestPromptValue = $Value
        $script:BundleTestPromptCount = 0
        $script:BundleTestAllowPrompt = $false
        function script:Read-Host {
            param([string]$Prompt, [switch]$AsSecureString)
            $script:BundleTestPromptCount++
            if (-not $script:BundleTestAllowPrompt -or -not $AsSecureString) { throw 'Unexpected interactive passphrase request.' }
            return $script:BundleTestPromptValue
        }
    } $secure

    Check 'common helper parameters are SecureString' ((Get-Command New-EncryptedBundle).Parameters['Passphrase'].ParameterType -eq [Security.SecureString] -and (Get-Command Expand-EncryptedBundle).Parameters['Passphrase'].ParameterType -eq [Security.SecureString])
    foreach ($scriptName in @('10-Export-Desktop-Pairing.ps1', 'Complete-Cluster.ps1')) {
        $command = Get-Command (Join-Path (Split-Path -Parent $modulePath) $scriptName)
        Check "$scriptName accepts an in-process SecureString" ($command.Parameters['BundlePassphrase'].ParameterType -eq [Security.SecureString])
    }

    $bundle = Join-Path $fixtureRoot 'supplied.dfe'; $restored = Join-Path $fixtureRoot 'restored'
    $output = @(& {
        New-EncryptedBundle -SourceDirectory $payload -OutputPath $bundle -Passphrase $secure
        Expand-EncryptedBundle -BundlePath $bundle -Destination $restored -Passphrase $secure
    } *>&1)
    Check 'supplied passphrase round-trips without prompting' ((& $bundleModule { $script:BundleTestPromptCount }) -eq 0 -and (Get-FileHash (Join-Path $payload 'public-fixture.json')).Hash -ceq (Get-FileHash (Join-Path $restored 'public-fixture.json')).Hash)
    Check 'caller retains its SecureString and output is passphrase-free' ($secure.Length -eq $fixturePassphrase.Length -and -not (($output | ForEach-Object { [string]$_ }) -join "`n").Contains($fixturePassphrase))
    Check 'temporary ZIP is removed on successful creation and expansion' (-not (Test-Path -LiteralPath "$bundle.zip.tmp"))

    $wrongDestination = Join-Path $fixtureRoot 'wrong-password'
    Check 'incorrect passphrase is rejected before extraction' (Rejects { Expand-EncryptedBundle -BundlePath $bundle -Destination $wrongDestination -Passphrase $wrong })
    Check 'failed authentication leaves no plaintext destination or ZIP' (-not (Test-Path -LiteralPath $wrongDestination) -and -not (Test-Path -LiteralPath "$bundle.zip.tmp"))
    $tampered = Join-Path $fixtureRoot 'tampered.dfe'; $tamperedBytes = [IO.File]::ReadAllBytes($bundle)
    $tamperedBytes[$tamperedBytes.Length - 1] = $tamperedBytes[$tamperedBytes.Length - 1] -bxor 1
    [IO.File]::WriteAllBytes($tampered, $tamperedBytes)
    Check 'tampered authentication tag remains rejected' (Rejects { Expand-EncryptedBundle -BundlePath $tampered -Destination (Join-Path $fixtureRoot 'tampered-output') -Passphrase $secure })
    Check 'short explicitly supplied passphrase never falls back to prompting' (Rejects { New-EncryptedBundle -SourceDirectory $payload -OutputPath (Join-Path $fixtureRoot 'short.dfe') -Passphrase $short })
    Check 'empty explicitly supplied passphrase never falls back to prompting' (Rejects { New-EncryptedBundle -SourceDirectory $payload -OutputPath (Join-Path $fixtureRoot 'empty.dfe') -Passphrase $empty })
    Check 'failure paths did not prompt' ((& $bundleModule { $script:BundleTestPromptCount }) -eq 0)

    & $bundleModule { $script:BundleTestAllowPrompt = $true }
    $interactive = Join-Path $fixtureRoot 'interactive.dfe'
    New-EncryptedBundle -SourceDirectory $payload -OutputPath $interactive
    Expand-EncryptedBundle -BundlePath $interactive -Destination (Join-Path $fixtureRoot 'interactive-output')
    Check 'omitted passphrases retain both interactive SecureString prompts' ((& $bundleModule { $script:BundleTestPromptCount }) -eq 2)
    $leakedFiles = @(Get-ChildItem -LiteralPath $fixtureRoot -File -Recurse | Where-Object { [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($_.FullName)).Contains($fixturePassphrase) })
    Check 'passphrase was never persisted in any fixture file' ($leakedFiles.Count -eq 0)
    Write-Host "PASS $($checks.Count)/$($checks.Count) encrypted-bundle passphrase checks; temporary files only, no installed state or lab touched."
} finally {
    & $bundleModule { Remove-Item Function:script:Read-Host -ErrorAction SilentlyContinue; Remove-Variable BundleTestPromptValue,BundleTestPromptCount,BundleTestAllowPrompt -Scope Script -ErrorAction SilentlyContinue }
    foreach ($value in @($secure, $wrong, $short, $empty)) { if ($null -ne $value) { $value.Dispose() } }
    if (Test-Path -LiteralPath $fixtureRoot) {
        $resolvedFixture = (Get-Item -LiteralPath $fixtureRoot).FullName
        if (-not $resolvedFixture.Equals($fixtureRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside the exact fixture root.' }
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
