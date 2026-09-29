# DevFleet source part 110

Full-source UTF-8 byte interval [5068500, 5115000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 744ee8ac30f3fc29fd0310727dc042a38f7d4f91983a90b9791a882686560f8a

<!-- BEGIN SOURCE SLICE -->
| Bytes: 5596 | Git mode: 100644

```
function ConvertFrom-DevFleetJsonc {
    param([Parameter(Mandatory)][string]$Text)
    $out = New-Object Text.StringBuilder
    $inString = $false; $escape = $false; $lineComment = $false; $blockComment = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]; $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        if ($lineComment) { if ($c -eq "`r" -or $c -eq "`n") { $lineComment = $false; [void]$out.Append($c) }; continue }
        if ($blockComment) { if ($c -eq '*' -and $next -eq '/') { $blockComment = $false; $i++ }; continue }
        if ($inString) {
            [void]$out.Append($c)
            if ($escape) { $escape = $false } elseif ($c -eq '\') { $escape = $true } elseif ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '"') { $inString = $true; [void]$out.Append($c); continue }
        if ($c -eq '/' -and $next -eq '/') { $lineComment = $true; $i++; continue }
        if ($c -eq '/' -and $next -eq '*') { $blockComment = $true; $i++; continue }
        [void]$out.Append($c)
    }
    return [regex]::Replace($out.ToString(), ',\s*([}\]])', '$1')
}

function Read-DevFleetVsCodeSettings {
    param([Parameter(Mandatory)][string]$Path)
    $raw = [IO.File]::ReadAllText($Path)
    try { return [pscustomobject]@{Raw=$raw;Data=(ConvertFrom-DevFleetJsonc $raw | ConvertFrom-Json -AsHashtable)} }
    catch {
        # Preserve the evidence before reporting malformed user settings. No
        # replacement is written when parsing fails.
        $backup = "$Path.devfleet-backup-$([guid]::NewGuid().ToString('N')).jsonc"
        [IO.File]::Copy($Path, $backup, $false)
        throw "VS Code settings are not valid JSONC; preserved backup $backup"
    }
}

function Write-DevFleetVsCodeSettings {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Data)
    $json = $Data | ConvertTo-Json -Depth 50
    $backup = "$Path.devfleet-backup-$([guid]::NewGuid().ToString('N')).jsonc"
    [IO.File]::Copy($Path, $backup, $false)
    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try { [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false))); Move-Item -LiteralPath $tmp -Destination $Path -Force }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return $backup
}

function Set-DevFleetVsCodeRemotePlatform {
    param([Parameter(Mandatory)][string[]]$Paths,[Parameter(Mandatory)][string]$Alias)
    $updated = @(); $skipped = @()
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { $skipped += $path; continue }
        $settings = Read-DevFleetVsCodeSettings $path
        $data = $settings.Data
        if ($null -eq $data) { $data = @{} }
        if (-not ($data -is [hashtable])) { throw "VS Code settings root must be an object: $path" }
        $mapping = if ($data.ContainsKey('remote.SSH.remotePlatform') -and $data['remote.SSH.remotePlatform'] -is [hashtable]) { $data['remote.SSH.remotePlatform'] } else { @{} }
        if ([string]$mapping[$Alias] -eq 'linux') { $skipped += $path; continue }
        $mapping[$Alias] = 'linux'; $data['remote.SSH.remotePlatform'] = $mapping
        $backup = Write-DevFleetVsCodeSettings $path $data
        $updated += [ordered]@{path=$path;backup=$backup;alias=$Alias;platform='linux'}
    }
    return [ordered]@{ok=$true;status='updated';updated_paths=@($updated);skipped_paths=@($skipped);alias=$Alias;platform='linux'}
}

function Remove-DevFleetVsCodeRemotePlatform {
    param([Parameter(Mandatory)][string[]]$Paths,[Parameter(Mandatory)][string]$Alias)
    $removed = @(); $skipped = @()
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { $skipped += $path; continue }
        $settings = Read-DevFleetVsCodeSettings $path; $data = $settings.Data
        if ($null -eq $data -or -not ($data -is [hashtable])) { throw "VS Code settings root must be an object: $path" }
        $mapping = $data['remote.SSH.remotePlatform']
        if ($mapping -isnot [hashtable] -or -not $mapping.ContainsKey($Alias)) { $skipped += $path; continue }
        $mapping.Remove($Alias)
        if ($mapping.Count -eq 0) { $data.Remove('remote.SSH.remotePlatform') }
        $backup = Write-DevFleetVsCodeSettings $path $data
        $removed += [ordered]@{path=$path;backup=$backup;alias=$Alias}
    }
    return [ordered]@{ok=$true;status='updated';removed_paths=@($removed);skipped_paths=@($skipped);alias=$Alias}
}

function Get-DevFleetVsCodeSettingsPaths {
    $values = @($script:Config.VsCodeSettingsPaths)
    return @($values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Sync-DevFleetVsCodeRemotePlatform {
    param([Parameter(Mandatory)][string]$Alias)
    $paths = @(Get-DevFleetVsCodeSettingsPaths)
    $knownExecutables = @(
        (Join-Path ${env:ProgramFiles} 'Microsoft VS Code\Code.exe'),
        (Join-Path ${env:LOCALAPPDATA} 'Programs\Microsoft VS Code\Code.exe'),
        (Join-Path ${env:ProgramFiles} 'Microsoft VS Code Insiders\Code - Insiders.exe'),
        (Join-Path ${env:LOCALAPPDATA} 'Programs\Microsoft VS Code Insiders\Code - Insiders.exe')
    )
    if (-not ($knownExecutables | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) { return [ordered]@{ok=$true;status='skipped';reason='VS Code is not installed.';updated_paths=@();alias=$Alias;platform='linux'} }
    return Set-DevFleetVsCodeRemotePlatform $paths $Alias
}

```


## FILE: source/windows/DevFleet-WindowsIntegrationOwnership.psm1

SHA256: a05f3e85b4033d59e61d4ccdaa06bc8051befb711ae2b6fb26880f1ae89f1b0e | Bytes: 16444 | Git mode: 100644

```
Set-StrictMode -Version Latest

function ConvertTo-DevFleetCanonicalPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Windows integration executable path is empty.' }
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
}

function ConvertTo-DevFleetCanonicalFirewallRemoteAddress {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $text = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    $parts = $text -split '/', 2
    if ($parts.Count -ne 2) { return $text }

    $address = $null
    if (-not [Net.IPAddress]::TryParse($parts[0].Trim(), [ref]$address) -or
        $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $text }

    $maskText = $parts[1].Trim()
    $prefix = -1
    if (-not [int]::TryParse($maskText, [ref]$prefix)) {
        $maskAddress = $null
        if (-not [Net.IPAddress]::TryParse($maskText, [ref]$maskAddress) -or
            $maskAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $text }
        $maskBytes = $maskAddress.GetAddressBytes()
        $zeroSeen = $false
        $prefix = 0
        foreach ($maskByte in $maskBytes) {
            for ($bit = 7; $bit -ge 0; $bit--) {
                $set = (($maskByte -band (1 -shl $bit)) -ne 0)
                if ($set) {
                    if ($zeroSeen) { return $text }
                    $prefix++
                } else {
                    $zeroSeen = $true
                }
            }
        }
    }
    if ($prefix -lt 0 -or $prefix -gt 32) { return $text }

    $addressBytes = $address.GetAddressBytes()
    $canonicalMaskBytes = New-Object byte[] 4
    $remaining = $prefix
    for ($index = 0; $index -lt 4; $index++) {
        if ($remaining -ge 8) {
            $canonicalMaskBytes[$index] = 255
            $remaining -= 8
        } elseif ($remaining -le 0) {
            $canonicalMaskBytes[$index] = 0
        } else {
            $canonicalMaskBytes[$index] = [byte](256 - (1 -shl (8 - $remaining)))
            $remaining = 0
        }
    }

    $networkBytes = New-Object byte[] 4
    for ($index = 0; $index -lt 4; $index++) {
        $networkBytes[$index] = [byte]($addressBytes[$index] -band $canonicalMaskBytes[$index])
    }
    $network = ([Net.IPAddress]::new($networkBytes)).ToString()
    $canonicalMask = ([Net.IPAddress]::new($canonicalMaskBytes)).ToString()
    return "$network/$canonicalMask"
}

function Assert-DevFleetExactFields {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][hashtable]$Expected,
        [Parameter(Mandatory)][hashtable]$Actual,
        [Parameter(Mandatory)][string[]]$Fields
    )
    foreach ($field in $Fields) {
        $expectedValue = [string]$Expected[$field]
        $actualValue = [string]$Actual[$field]
        if ($field -eq 'RemoteAddress') {
            $expectedValue = ConvertTo-DevFleetCanonicalFirewallRemoteAddress $expectedValue
            $actualValue = ConvertTo-DevFleetCanonicalFirewallRemoteAddress $actualValue
        }
        $comparison = if ($field -in @('Arguments','Description')) { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
        if (-not [string]::Equals($expectedValue,$actualValue,$comparison)) {
            throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: $Kind field '$field' does not match the installation ownership ledger. Foreign resource preserved."
        }
    }
    return $true
}

function Assert-DevFleetTaskBinding {
    param([Parameter(Mandatory)][hashtable]$Expected,[Parameter(Mandatory)][hashtable]$Actual)
    $Expected.Executable = ConvertTo-DevFleetCanonicalPath ([string]$Expected.Executable)
    $Actual.Executable = ConvertTo-DevFleetCanonicalPath ([string]$Actual.Executable)
    Assert-DevFleetExactFields 'scheduled task' $Expected $Actual @('Name','Executable','Arguments','Principal','LogonType','RunLevel','Description','Generation')
}

function Assert-DevFleetFirewallBinding {
    param([Parameter(Mandatory)][hashtable]$Expected,[Parameter(Mandatory)][hashtable]$Actual)
    Assert-DevFleetExactFields 'firewall rule' $Expected $Actual @('Name','DisplayName','Group','Description','Direction','Action','Protocol','LocalPort','InterfaceAlias','RemoteAddress','Profile','Generation')
}

function Assert-DevFleetFirewallRefreshIdentity {
    param([Parameter(Mandatory)][hashtable]$Expected,[Parameter(Mandatory)][hashtable]$Actual)
    # InterfaceAlias and RemoteAddress are provider-backed network state. They
    # can legitimately change when a virtual adapter is recreated or its
    # subnet is renumbered. Every other rule field remains an immutable
    # ownership proof before a refresh is permitted.
    Assert-DevFleetExactFields 'firewall refresh' $Expected $Actual @('Name','DisplayName','Group','Description','Direction','Action','Protocol','LocalPort','Profile','Generation')
}

function Get-DevFleetLiveFirewallBinding {
    param([Parameter(Mandatory)]$Rule,[Parameter(Mandatory)][string]$Generation)
    $portFilters = @($Rule | Get-NetFirewallPortFilter -ErrorAction Stop)
    $addressFilters = @($Rule | Get-NetFirewallAddressFilter -ErrorAction Stop)
    $interfaceFilters = @($Rule | Get-NetFirewallInterfaceFilter -ErrorAction Stop)
    if ($portFilters.Count -ne 1 -or $addressFilters.Count -ne 1 -or $interfaceFilters.Count -ne 1) {
        throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall rule filter identity is ambiguous. Foreign resource preserved.'
    }
    $port = $portFilters[0]
    $address = $addressFilters[0]
    $interface = $interfaceFilters[0]
    return @{
        Name = [string]$Rule.Name
        DisplayName = [string]$Rule.DisplayName
        Group = [string]$Rule.Group
        Description = [string]$Rule.Description
        Direction = [string]$Rule.Direction
        Action = [string]$Rule.Action
        Protocol = [string]$port.Protocol
        LocalPort = [string]$port.LocalPort
        InterfaceAlias = [string]$interface.InterfaceAlias
        RemoteAddress = [string]$address.RemoteAddress
        Profile = [string]$Rule.Profile
        Generation = $Generation
    }
}

function Invoke-DevFleetOwnedFirewallRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(0,120)][int]$WaitSeconds = 0
    )
    $ledger = Read-DevFleetIntegrationOwnership -Path $Path -AllowMissing
    if (-not $ledger) {
        return [pscustomobject]@{ status = 'NO_LEDGER'; changed = 0; skipped = 0 }
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $newBindings = @()
    $changed = 0
    $skipped = 0
    foreach ($binding in @($ledger.FirewallRules)) {
        $bindingName = [string]$binding.Name
        $scope = if ($bindingName -match '-Multipass$') { 'Multipass' } elseif ($bindingName -match '-Tailscale$') { 'Tailscale' } else { $null }
        if (-not $scope) {
            throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall binding '$bindingName' has no supported DevFleet interface scope. Foreign resource preserved."
        }

        $adapterName = if ($scope -eq 'Multipass') { 'vEthernet (Default Switch)' } else { 'Tailscale' }
        $adapter = $null
        $multipassAddress = $null
        do {
            $adapter = @(Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $adapterName -and [string]$_.Status -eq 'Up' } | Select-Object -First 1)
            if ($adapter.Count -eq 0) { $adapter = $null }
            if ($adapter -and $scope -eq 'Multipass') {
                $multipassAddress = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1)
                if ($multipassAddress.Count -eq 0) { $multipassAddress = $null }
            }
            if ($adapter -and ($scope -eq 'Tailscale' -or $multipassAddress)) { break }
            if ((Get-Date) -ge $deadline) { break }
            Start-Sleep -Seconds 1
        } while ($true)

        if (-not $adapter -or ($scope -eq 'Multipass' -and -not $multipassAddress)) {
            # A deferred Tailscale installation legitimately has no Tailscale
            # adapter yet. Preserve the ledger and rule until a later startup
            # or explicit host-agent restart can reconcile it.
            $skipped++
            $newBindings += @{} + $binding
            continue
        }

        $desired = @{}
        foreach ($key in $binding.Keys) { $desired[$key] = $binding[$key] }
        $desired.InterfaceAlias = [string]$adapter.Name
        $desired.RemoteAddress = if ($scope -eq 'Multipass') {
            ConvertTo-DevFleetCanonicalFirewallRemoteAddress "$($multipassAddress.IPAddress)/$($multipassAddress.PrefixLength)"
        } else {
            ConvertTo-DevFleetCanonicalFirewallRemoteAddress '100.64.0.0/10'
        }

        $liveRules = @(Get-NetFirewallRule -Name $bindingName -ErrorAction SilentlyContinue)
        if ($liveRules.Count -eq 0) {
            $newBindings += $desired
            continue
        }
        if ($liveRules.Count -ne 1) {
            throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall identity '$bindingName' is ambiguous. Foreign resources preserved."
        }

        $live = $liveRules[0]
        $actual = Get-DevFleetLiveFirewallBinding -Rule $live -Generation ([string]$binding.Generation)
        Assert-DevFleetFirewallRefreshIdentity -Expected $binding -Actual $actual | Out-Null

        $actualRemote = ConvertTo-DevFleetCanonicalFirewallRemoteAddress ([string]$actual.RemoteAddress)
        $desiredRemote = ConvertTo-DevFleetCanonicalFirewallRemoteAddress ([string]$desired.RemoteAddress)
        $interfaceChanged = -not [string]::Equals([string]$actual.InterfaceAlias,[string]$desired.InterfaceAlias,[StringComparison]::OrdinalIgnoreCase)
        $addressChanged = -not [string]::Equals($actualRemote,$desiredRemote,[StringComparison]::OrdinalIgnoreCase)
        if ($interfaceChanged) {
            $interfaceFilter = @($live | Get-NetFirewallInterfaceFilter -ErrorAction Stop)
            if ($interfaceFilter.Count -ne 1) { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall interface filter '$bindingName' is ambiguous. Foreign resource preserved." }
            $interfaceFilter[0] | Set-NetFirewallInterfaceFilter -InterfaceAlias ([string]$desired.InterfaceAlias) -ErrorAction Stop | Out-Null
        }
        if ($addressChanged) {
            $addressFilter = @($live | Get-NetFirewallAddressFilter -ErrorAction Stop)
            if ($addressFilter.Count -ne 1) { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall address filter '$bindingName' is ambiguous. Foreign resource preserved." }
            $addressFilter[0] | Set-NetFirewallAddressFilter -RemoteAddress ([string]$desired.RemoteAddress) -ErrorAction Stop | Out-Null
        }

        if ($interfaceChanged -or $addressChanged) {
            $refreshedRule = @(Get-NetFirewallRule -Name $bindingName -ErrorAction Stop)
            if ($refreshedRule.Count -ne 1) { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: refreshed firewall identity '$bindingName' is ambiguous. Foreign resource preserved." }
            $refreshedActual = Get-DevFleetLiveFirewallBinding -Rule $refreshedRule[0] -Generation ([string]$binding.Generation)
            Assert-DevFleetFirewallBinding -Expected $desired -Actual $refreshedActual | Out-Null
            $changed++
        }
        $newBindings += $desired
    }

    if ($changed -gt 0) {
        $ledger.FirewallRules = @($newBindings)
        $ledger.UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Write-DevFleetIntegrationOwnership -Path $Path -Ledger $ledger
    }
    return [pscustomobject]@{ status = if ($changed -gt 0) { 'REFRESHED' } elseif ($skipped -gt 0) { 'PARTIAL' } else { 'CURRENT' }; changed = $changed; skipped = $skipped }
}

function Assert-DevFleetServiceBinding {
    param([Parameter(Mandatory)][hashtable]$Expected,[Parameter(Mandatory)][hashtable]$Actual)
    $Expected.ImagePath = ConvertTo-DevFleetCanonicalPath ([string]$Expected.ImagePath)
    $liveImage = [string]$Actual.ImagePath
    if ($liveImage.StartsWith('"')) {
        $closingQuote = $liveImage.IndexOf('"',1)
        if ($closingQuote -lt 2) { throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: service image path is malformed. Foreign service preserved.' }
        $liveImage = $liveImage.Substring(1,$closingQuote - 1)
    } else {
        $liveImage = ($liveImage -split '\s+',2)[0]
    }
    $Actual.ImagePath = ConvertTo-DevFleetCanonicalPath $liveImage
    Assert-DevFleetExactFields 'service' $Expected $Actual @('Name','ImagePath','Account','StartMode','Generation')
}

function Read-DevFleetIntegrationOwnership {
    param([Parameter(Mandatory)][string]$Path,[switch]$AllowMissing)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($AllowMissing) { return $null }
        throw "Windows integration ownership ledger is missing: $Path"
    }
    if ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Windows integration ownership ledger is a reparse point; all resources preserved.'
    }
    $ledger = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if (-not $ledger -or [int]$ledger.SchemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$ledger.InstallationGeneration)) {
        throw 'Windows integration ownership ledger is malformed or unsupported.'
    }
    $generation = [guid]::Empty
    if (-not [guid]::TryParse([string]$ledger.InstallationGeneration,[ref]$generation) -or $generation -eq [guid]::Empty) {
        throw 'Windows integration ownership ledger generation is invalid.'
    }
    $identities = @{}
    foreach ($kindAndBindings in @(@('ScheduledTask',@($ledger.ScheduledTasks)),@('FirewallRule',@($ledger.FirewallRules)),@('Service',@($ledger.Services)))) {
        $kind = [string]$kindAndBindings[0]
        foreach ($binding in @($kindAndBindings[1])) {
        if ([string]$binding.Generation -ne [string]$ledger.InstallationGeneration) {
            throw 'Windows integration ownership ledger contains a cross-generation binding.'
        }
            $name = [string]$binding.Name
            if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('*') -or $name.Contains('?')) { throw 'Windows integration ownership ledger contains an ambiguous identity.' }
            $identity = "$kind`0$name".ToLowerInvariant()
            if ($identities.ContainsKey($identity)) { throw 'Windows integration ownership ledger contains a duplicate identity.' }
            $identities[$identity] = $true
            $required = switch ($kind) {
                'ScheduledTask' { @('Marker','Executable','Arguments','Principal','LogonType','RunLevel','Description') }
                'FirewallRule' { @('Marker','DisplayName','Group','Description','Direction','Action','Protocol','LocalPort','InterfaceAlias','RemoteAddress','Profile') }
                'Service' { @('Marker','ImagePath','Account','StartMode') }
            }
            foreach ($field in $required) {
                if ([string]::IsNullOrWhiteSpace([string]$binding[$field])) { throw "Windows integration ownership ledger contains an incomplete $kind binding." }
            }
        }
    }
    return $ledger
}

function Write-DevFleetIntegrationOwnership {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][hashtable]$Ledger)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,($Ledger | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function ConvertTo-DevFleetCanonicalPath,ConvertTo-DevFleetCanonicalFirewallRemoteAddress,Assert-DevFleetTaskBinding,Assert-DevFleetFirewallBinding,Assert-DevFleetFirewallRefreshIdentity,Assert-DevFleetServiceBinding,Read-DevFleetIntegrationOwnership,Write-DevFleetIntegrationOwnership,Invoke-DevFleetOwnedFirewallRefresh

```


## FILE: source/windows/DevFleet.Common.psm1

SHA256: 29e4a7fae0fde808e7e295bf4c9371be7da0cd2a37979d4347f3fb207f0c59d7 | Bytes: 108153 | Git mode: 100644

```
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DevFleetPackageRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-DevFleetStateRoot {
    Join-Path $env:ProgramData 'DevFleet'
}

function Get-ActiveDevFleetTransaction {
    $path = Join-Path (Get-DevFleetStateRoot) 'active-transaction.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $value = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ([string]$value.transactionId -notmatch '^[0-9a-fA-F]{32}$' -or [string]$value.payloadSha256 -notmatch '^[0-9a-fA-F]{64}$' -or [string]$value.action -notin @('FreshInstall','Repair','CleanReinstall','LocalUpdate') -or [string]$value.role -notin @('Laptop','Desktop')) { return $null }
        return $value
    } catch { return $null }
}

function Wait-ActiveDevFleetTransaction {
    param(
        [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$ExpectedRole,
        [int]$TimeoutSeconds = 60
    )
    if ($TimeoutSeconds -le 0) { throw 'Active transaction wait timeout must be positive.' }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $deadlineContext = Get-DevFleetDeadlineContext
    if ($deadlineContext -and [datetime]$deadlineContext.StageDeadlineUtc -lt $deadline) { $deadline = [datetime]$deadlineContext.StageDeadlineUtc }
    do {
        $transaction = Get-ActiveDevFleetTransaction
        if (Test-DevFleetTransactionBinding -Transaction $transaction -ExpectedRole $ExpectedRole) { return $transaction }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Seconds 1
    } while ($true)
    return $null
}

function ConvertTo-DevFleetPreparedUtcText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('o') }
    return ([string]$Value).Trim()
}

function Test-DevFleetTransactionBinding {
    param(
        [AllowNull()][object]$Transaction,
        [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$ExpectedRole
    )
    if (-not $Transaction) { return $false }
    $preparedUtcText = ConvertTo-DevFleetPreparedUtcText $Transaction.preparedUtc
    return ([string]$Transaction.role).Trim() -ceq $ExpectedRole -and
        ([string]$Transaction.action).Trim() -in @('FreshInstall','Repair','CleanReinstall','LocalUpdate') -and
        ([string]$Transaction.transactionId).Trim() -match '^[0-9a-fA-F]{32}$' -and
        ([string]$Transaction.payloadSha256).Trim() -match '^[0-9a-fA-F]{64}$' -and
        $preparedUtcText -match 'T'
}

function Set-DevFleetDeadlineContext {
    param(
        [Parameter(Mandatory)][datetime]$TransactionDeadlineUtc,
        [Parameter(Mandatory)][string]$StageName,
        [Parameter(Mandatory)][int]$StageBudgetSeconds
    )
    if ($StageBudgetSeconds -le 0) { throw "Stage '$StageName' must have a finite positive budget." }
    $transactionDeadline = $TransactionDeadlineUtc.ToUniversalTime()
    if ($transactionDeadline -le [datetime]::UtcNow) { throw 'The owning DevFleet transaction deadline has expired.' }
    $stageDeadline = [datetime]::UtcNow.AddSeconds($StageBudgetSeconds)
    if ($stageDeadline -gt $transactionDeadline) { $stageDeadline = $transactionDeadline }
    $global:DevFleetDeadlineContext = [pscustomobject]@{
        TransactionDeadlineUtc = $transactionDeadline
        StageName = $StageName
        StageDeadlineUtc = $stageDeadline
        StageBudgetSeconds = $StageBudgetSeconds
    }
    return $global:DevFleetDeadlineContext
}

function Get-DevFleetDeadlineContext {
    $variable=Get-Variable -Scope Global -Name DevFleetDeadlineContext -ErrorAction SilentlyContinue
    if($variable){return $variable.Value}
    return $null
}

function Get-DevFleetStageBudgetSeconds {
    param([Parameter(Mandatory)][string]$StageName)
    if ($StageName -eq 'compute') {
        return (Get-DevFleetOperationMaximumSeconds 'multipassLaunch') + (Get-DevFleetOperationMaximumSeconds 'multipassReadiness') + (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') + (Get-DevFleetOperationMaximumSeconds 'guestBootstrap') + (Get-DevFleetOperationMaximumSeconds 'sshAndMarker')
    }
    if ($StageName -eq 'vault') {
        return (Get-DevFleetOperationMaximumSeconds 'vaultSnapshot') + (Get-DevFleetOperationMaximumSeconds 'multipassLaunch') + (Get-DevFleetOperationMaximumSeconds 'multipassReadiness') + (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') + (Get-DevFleetOperationMaximumSeconds 'vaultBootstrap') + (Get-DevFleetOperationMaximumSeconds 'sshAndMarker')
    }
    $budgets = @{
        bootstrap = (Get-DevFleetOperationMaximumSeconds 'bootstrap')
        preflight = (Get-DevFleetOperationMaximumSeconds 'preflight')
        prerequisites = (6 * ((Get-DevFleetOperationMaximumSeconds 'dependencyProbe') + (Get-DevFleetOperationMaximumSeconds 'dependencyHealth') + (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') + (Get-DevFleetOperationMaximumSeconds 'dependencyVerification'))) + (Get-DevFleetOperationMaximumSeconds 'windowsCapability') + (Get-DevFleetOperationMaximumSeconds 'windowsFeature') + (4 * (Get-DevFleetOperationMaximumSeconds 'multipassConfiguration')) + (3 * (Get-DevFleetOperationMaximumSeconds 'vscodeExtension'))
        windowsTailscale = 900
        hostAgent = 300
        tailscale = 900
        vaultClient = 300
        shortcuts = 180
        export = 300
        verification = 300
    }
    if (-not $budgets.ContainsKey($StageName)) { throw "No finite deadline policy exists for stage '$StageName'." }
    return [int]$budgets[$StageName]
}

function Get-DevFleetOperationMaximumSeconds {
    param([Parameter(Mandatory)][ValidateSet('bootstrap','preflight','prerequisites','dependencyProbe','dependencyHealth','dependencyInstall','dependencyVerification','windowsCapability','windowsFeature','multipassConfiguration','vscodeExtension','windowsTailscale','hostAgent','multipassLaunch','multipassReadiness','payloadTransfer','guestBootstrap','vaultBootstrap','sshAndMarker','vaultSnapshot','tailscale','vaultClient','shortcuts','export','verification')][string]$OperationName)
    $operation = [ordered]@{
        bootstrap = 240; preflight = 120; prerequisites = 0; dependencyProbe = 60; dependencyHealth = 180; dependencyInstall = 1800; dependencyVerification = 60; windowsCapability = 900; windowsFeature = 900; multipassConfiguration = 600; vscodeExtension = 300; windowsTailscale = 900; hostAgent = 300
        multipassLaunch = 900; multipassReadiness = 1200; payloadTransfer = 900
        guestBootstrap = (900 + 1200 + 1200 + 600 + 600 + 1200 + 600) + 300
        vaultBootstrap = 3900
        sshAndMarker = 300; vaultSnapshot = 300; tailscale = 900; vaultClient = 300
        shortcuts = 180; export = 300; verification = 300
    }
    $operation.prerequisites = 6 * ($operation.dependencyProbe + $operation.dependencyHealth + $operation.dependencyInstall + $operation.dependencyVerification) + $operation.windowsCapability + $operation.windowsFeature + (4 * $operation.multipassConfiguration) + (3 * $operation.vscodeExtension)
    return [int]$operation[$OperationName]
}

function Get-DevFleetTransactionBudgetSeconds {
    param([Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role)
    $stageNames = if ($Role -eq 'Laptop') {
        @('bootstrap','preflight','prerequisites','windowsTailscale','hostAgent','compute','vault','tailscale','tailscale','vaultClient','shortcuts','export','verification')
    } else {
        @('bootstrap','preflight','prerequisites','windowsTailscale','hostAgent','compute','tailscale','shortcuts','export','verification')
    }
    $total = 0
    foreach ($stage in $stageNames) { $total += Get-DevFleetStageBudgetSeconds $stage }
    return $total + 600
}

function Assert-PowerShell7 {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'PowerShell 7 or newer is required. Re-run Bootstrap-Install.ps1 so the verified local PowerShell payload can be installed.'
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    if (-not (Test-Administrator)) { throw 'Run PowerShell 7 as Administrator.' }
}

function Initialize-DevFleetState {
    param([Parameter(Mandatory)][string]$PackageRoot)
    $root = Get-DevFleetStateRoot
    foreach ($dir in @($root, "$root\exports", "$root\logs", "$root\secrets", "$root\tmp")) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $configPath = Join-Path $root 'devfleet.config.json'
    if (-not (Test-Path $configPath)) {
        Copy-Item (Join-Path $PackageRoot 'config\devfleet.config.json') $configPath
    }
    Set-Content -Path (Join-Path $root 'package-root.txt') -Value $PackageRoot -Encoding utf8
    Protect-DevFleetStateAcl
}

function Get-OrCreateNodeIdentity {
    param([Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role)
    $path = Join-Path (Get-DevFleetStateRoot) 'node-identity.json'
    if (Test-Path -LiteralPath $path) { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    $isPrimary = $Role -eq 'Desktop'
    $identity = [ordered]@{
        schema_version = 1
        deployment_id = if ($isPrimary) { [guid]::NewGuid().ToString() } else { '' }
        node_id = [guid]::NewGuid().ToString()
        node_name = $env:COMPUTERNAME
        node_role = if ($isPrimary) { 'primary' } else { 'surrogate' }
        coordinator_node_id = $null
        protocol_version = 1
        registration_state = if ($isPrimary) { 'coordinator' } else { 'awaiting-primary-join' }
        created_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $identity | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
    Protect-DevFleetStateAcl
    return $identity | ConvertTo-Json | ConvertFrom-Json
}

function Get-OrCreateVaultIdentity {
    $path = Join-Path (Get-DevFleetStateRoot) 'vault-node-identity.json'
    if (Test-Path -LiteralPath $path) {
        $identity = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ([string]$identity.node_role -ne 'vault' -or [string]$identity.node_id -notmatch '^[0-9a-fA-F-]{36}$' -or ([string]$identity.deployment_id -and [string]$identity.deployment_id -notmatch '^[0-9a-fA-F-]{36}$')) { throw 'Vault identity is invalid; explicit recovery is required.' }
        return $identity
    }
    $hostIdentity = Get-OrCreateNodeIdentity -Role Laptop
    $identity = [ordered]@{schema_version=1;deployment_id=[string]$hostIdentity.deployment_id;node_id=[guid]::NewGuid().ToString('D');node_name=(Get-DevFleetConfig).Vault.InstanceName;node_role='vault';created_at=(Get-Date).ToUniversalTime().ToString('o')}
    $identity | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
    Protect-DevFleetStateAcl
    return $identity | ConvertTo-Json | ConvertFrom-Json
}

function Protect-DevFleetStateAcl {
    $root = Get-DevFleetStateRoot
    if (-not (Test-Path $root)) { return }
    $acl = Get-Acl $root
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($existing in @($acl.Access)) { $acl.RemoveAccessRuleAll($existing) }
    foreach ($rule in @(
        [Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow'),
        [Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow'),
        [Security.AccessControl.FileSystemAccessRule]::new("$env:USERDOMAIN\$env:USERNAME",'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    )) { $acl.AddAccessRule($rule) | Out-Null }
    Set-Acl -Path $root -AclObject $acl
}

function Get-DevFleetConfig {
    $path = Join-Path (Get-DevFleetStateRoot) 'devfleet.config.json'
    if (-not (Test-Path $path)) { throw "Missing config: $path" }
    Get-Content $path -Raw | ConvertFrom-Json
}

function Save-DevFleetConfig {
    param([Parameter(Mandatory)]$Config)
    $path = Join-Path (Get-DevFleetStateRoot) 'devfleet.config.json'
    $Config | ConvertTo-Json -Depth 20 | Set-Content $path -Encoding utf8
}

function Get-PackageRootFromState {
    $p = Join-Path (Get-DevFleetStateRoot) 'package-root.txt'
    if (Test-Path $p) { return (Get-Content $p -Raw).Trim() }
    Get-DevFleetPackageRoot
}

function New-RandomSecret {
    param([int]$Bytes = 32)
    $data = New-Object byte[] $Bytes
    [Security.Cryptography.RandomNumberGenerator]::Fill($data)
    [Convert]::ToBase64String($data).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function ConvertTo-YamlSingleQuotedScalar {
    param([AllowNull()][string]$Value)
    $text = if ($null -eq $Value) { '' } else { $Value }
    if ($text.IndexOfAny([char[]]"`0`r`n") -ge 0) { throw 'YAML scalar contains a forbidden control or newline character.' }
    return "'" + $text.Replace("'", "''") + "'"
}

function ConvertTo-ShellSingleQuotedScalar {
    param([AllowNull()][string]$Value)
    $text = if ($null -eq $Value) { '' } else { $Value }
    if ($text.IndexOfAny([char[]]"`0`r`n") -ge 0) { throw 'Shell scalar contains a forbidden control or newline character.' }
    return "'" + $text.Replace("'", "'\''") + "'"
}

function Test-ExistingDeploymentState {
    $root = Get-DevFleetStateRoot
    foreach ($name in @('node-identity.json','deployment.json','host-agent-registry.json','projects.json')) {
        $candidate = Join-Path $root $name
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Get-Item -LiteralPath $candidate).Length -gt 2) { return $true }
    }
    return $false
}

function Test-DevFleetSecretRecord {
    param([Parameter(Mandatory)]$Secrets)
    foreach ($field in @('PortalAdminUser','PortalAdminPassword','NodeApiToken','ResticPassword','VaultRestUser','VaultRestPassword')) {
        if (-not $Secrets.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$Secrets.$field)) { return $false }
    }
    if ([string]$Secrets.PortalAdminPassword -match '[\r\n]' -or [string]$Secrets.NodeApiToken -match '[\r\n]' -or [string]$Secrets.ResticPassword -match '[\r\n]' -or [string]$Secrets.VaultRestPassword -match '[\r\n]') { return $false }
    if ([string]$Secrets.NodeApiToken -notmatch '^[A-Za-z0-9_-]{40,}$' -or [string]$Secrets.ResticPassword -notmatch '^[A-Za-z0-9_-]{40,}$') { return $false }
    if ($Secrets.PSObject.Properties['SecretGeneration'] -and $Secrets.SecretGeneration) {
        $generation = [guid]::Empty
        if (-not [guid]::TryParse([string]$Secrets.SecretGeneration,[ref]$generation) -or $generation -eq [guid]::Empty) { return $false }
    }
    return $true
}

function New-DevFleetSecretRecord {
    param([string]$Generation = ([guid]::NewGuid().ToString('D')))
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Generation,[ref]$parsed) -or $parsed -eq [guid]::Empty) { throw 'Secret generation must be a non-empty UUID.' }
    [ordered]@{
        SchemaVersion = 2
        SecretGeneration = $Generation
        PortalAdminUser = 'dylan'
        PortalAdminPassword = New-RandomSecret 24
        NodeApiToken = New-RandomSecret 32
        ResticPassword = New-RandomSecret 40
        VaultRestUser = "devfleet-client-$($Generation.Substring(0,8))"
        VaultRestPassword = New-RandomSecret 32
        Created = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-OrCreateSecrets {
    $path = Join-Path (Get-DevFleetStateRoot) 'secrets\host-secrets.json'
    if (-not (Test-Path $path)) {
        if (Test-ExistingDeploymentState) { throw 'SECRET RECOVERY REQUIRED: host secrets are missing while existing DevFleet deployment state is present. Use the explicit re-key/repair workflow.' }
        $obj = New-DevFleetSecretRecord
        $obj | ConvertTo-Json | Set-Content $path -Encoding utf8
        Protect-DevFleetStateAcl
    }
    try {
        $secrets = Get-Content $path -Raw | ConvertFrom-Json
        if (-not (Test-DevFleetSecretRecord -Secrets $secrets)) { throw 'Host secret record is incomplete or invalid.' }
        return $secrets
    }
    catch {
        if (Test-ExistingDeploymentState) { throw 'SECRET RECOVERY REQUIRED: host secrets are corrupt while existing DevFleet deployment state is present. Use the explicit re-key/repair workflow.' }
        throw 'Host secrets are corrupt; remove the incomplete fresh-install state and restart setup.'
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @(),
        [Parameter()][int[]]$RedactArgumentIndexes = @(),
        [Parameter()][int]$TimeoutSeconds = 900,
        [Parameter()][int]$MaxDiagnosticChars = 12000,
        [Parameter()][string]$EvidenceLogPath = '',
        [Parameter()][string]$StandardInputText = '',
        [Parameter()][datetime]$DeadlineUtc = [datetime]::MinValue,
        [Parameter()][int[]]$AllowedExitCodes = @(0),
        [switch]$IgnoreExitCode,
        [switch]$Capture
    )
    # Parameter binding may receive a scalar or null when a caller supplies a
    # single/empty argument set. Normalize before indexing or reading Count.
    $ArgumentList = @($ArgumentList)
    $deadlineContext=Get-DevFleetDeadlineContext
    # An explicit child deadline is subordinate to the active owning stage.
    # Taking the minimum here prevents a nested helper (for example readiness
    # or a bounded retry loop) from accidentally escaping its stage merely by
    # supplying its own finite deadline.
    $deadlines = @()
    if ($DeadlineUtc -gt [datetime]::MinValue) { $deadlines += $DeadlineUtc.ToUniversalTime() }
    if ($deadlineContext) { $deadlines += ([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime() }
    $deadline = if ($deadlines.Count -gt 0) { ($deadlines | Measure-Object -Minimum).Minimum } else { [datetime]::MinValue }
    if ($deadline -gt [datetime]::MinValue) {
        $remaining = [int][math]::Floor(($deadline - [datetime]::UtcNow).TotalSeconds)
        if ($remaining -le 0) { throw "Owning deadline expired before starting external command: $FilePath" }
        $TimeoutSeconds = [math]::Min($TimeoutSeconds, $remaining)
    }
    if ($TimeoutSeconds -le 0) { throw 'External command timeout must remain positive after deadline propagation.' }
    # One immutable operation deadline owns process start, stdin delivery and
    # execution.  Do not grant WaitForExit a fresh full timeout after a slow or
    # blocked input write has already consumed owner time.
    $operationDeadlineUtc = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    if ($deadline -gt [datetime]::MinValue -and $deadline -lt $operationDeadlineUtc) { $operationDeadlineUtc = $deadline }
    $remainingMilliseconds = {
        $milliseconds = [math]::Ceiling(($operationDeadlineUtc - [datetime]::UtcNow).TotalMilliseconds)
        if ($milliseconds -le 0) { return 0 }
        return [int][math]::Min([int]::MaxValue, $milliseconds)
    }
    $safeArguments = for($i=0;$i -lt $ArgumentList.Count;$i++){ if($RedactArgumentIndexes -contains $i){ '<redacted-secret>' } else { [string]$ArgumentList[$i] } }
    Write-Verbose ("Executing: {0} {1}" -f $FilePath, ($safeArguments -join ' '))
    $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$FilePath;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.RedirectStandardInput=($null -ne $StandardInputText -and $StandardInputText.Length -gt 0)
    if($psi.RedirectStandardInput){$psi.StandardInputEncoding=[Text.UTF8Encoding]::new($false)}
    foreach($argument in $ArgumentList){[void]$psi.ArgumentList.Add([string]$argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$psi;$stdoutTail=[Text.StringBuilder]::new();$stderrTail=[Text.StringBuilder]::new();$logWriter=$null;$inputError=''
    try {
        if($EvidenceLogPath){$parent=Split-Path -Parent $EvidenceLogPath;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$logWriter=[IO.StreamWriter]::new($EvidenceLogPath,$false,[Text.Encoding]::UTF8)}
        if(-not $process.Start()){throw "Unable to start external command: $FilePath"}
        # Drain both output streams before delivering input.  A child is
        # allowed to write output before reading stdin; reversing this order
        # can deadlock both sides on finite OS pipe buffers.
        $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
        if($psi.RedirectStandardInput){
            $inputTask=$null
            try {$inputTask=$process.StandardInput.WriteAsync($StandardInputText)} catch {$inputError=$_.Exception.GetBaseException().Message}
            if($inputTask){
                $inputCompleted=$false
                try {$inputCompleted=$inputTask.Wait((&$remainingMilliseconds))} catch {$inputCompleted=$true;$inputError=$_.Exception.GetBaseException().Message}
                if(-not $inputCompleted){
                    try{$process.Kill($true)}catch{}
                    try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
                    throw "External command input delivery timed out before the owning deadline: $FilePath $($safeArguments -join ' ')"
                }
                if(-not $inputError){
                    try {[void]$inputTask.GetAwaiter().GetResult();$flushTask=$process.StandardInput.FlushAsync();$flushCompleted=$flushTask.Wait((&$remainingMilliseconds));if(-not $flushCompleted){try{$process.Kill($true)}catch{};throw "External command input flush timed out before the owning deadline: $FilePath $($safeArguments -join ' ')"};[void]$flushTask.GetAwaiter().GetResult()} catch {$inputError=$_.Exception.GetBaseException().Message}
                }
            }
            try {$process.StandardInput.Close()} catch {if(-not $inputError){$inputError=$_.Exception.GetBaseException().Message}}
            if($inputError -and -not $process.HasExited){
                # Give an exiting child a short slice of the existing owner
                # budget so its direct exit code remains the primary result.
                # A child that stays alive after breaking its input pipe is
                # terminated exactly and reported as an input transport fault,
                # not allowed to consume the rest of the deadline and obscure it.
                $exitObservationMilliseconds=[math]::Min(500,(&$remainingMilliseconds))
                if($exitObservationMilliseconds -gt 0){try{[void]$process.WaitForExit($exitObservationMilliseconds)}catch{}}
                if(-not $process.HasExited){
                    try{$process.Kill($true)}catch{}
                    try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
                    throw "External command input delivery failed: $FilePath $($safeArguments -join ' ')`n$inputError"
                }
            }
        }
        $executionRemainingMilliseconds=&$remainingMilliseconds
        if($executionRemainingMilliseconds -le 0 -or -not $process.WaitForExit($executionRemainingMilliseconds)){
            try{$process.Kill($true)}catch{}
            try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
            throw "External command timed out after $TimeoutSeconds seconds: $FilePath $($safeArguments -join ' ')"
        }
        $exitCode=$process.ExitCode
        $outputComplete=$false
        try{$outputComplete=[Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5))}catch{$outputComplete=$false}
        $stdout=if($stdoutTask.Status -eq [Threading.Tasks.