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
