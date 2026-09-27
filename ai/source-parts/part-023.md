# DevFleet source part 023

Full-source UTF-8 byte interval [1023000, 1069500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ee54f66c81ba6fbbd05b8f6cf23053a463dcdf5f4be5a2a55171b6fab4183b8b

<!-- BEGIN SOURCE SLICE -->
   if(-not $data -or -not $data.PSObject.Properties['tailscaleOAuthClientSecretDpapi'] -or [string]::IsNullOrWhiteSpace([string]$data.tailscaleOAuthClientSecretDpapi)){return [pscustomobject]@{available=$false;provider='OAuthClientSecretStore';reason='Tailscale OAuth client secret is not configured';secret=$null;clientId=$clientId;path=$path;invalid=$false}}
    try {
        $secure=ConvertTo-SecureString -String ([string]$data.tailscaleOAuthClientSecretDpapi) -ErrorAction Stop
        $plain=ConvertTo-DevFleetPlainSecret -Secret $secure
        if([string]::IsNullOrWhiteSpace($plain) -or $plain.IndexOfAny([char[]]"`0`r`n") -ge 0 -or $plain.Length -gt 2048){throw 'decrypted secret is malformed'}
        return [pscustomobject]@{available=$true;provider='OAuthClientSecretStore';reason='DPAPI-bound local OAuth secret available';secret=$plain;clientId=$clientId;path=$path;invalid=$false}
    } catch { return [pscustomobject]@{available=$false;provider='OAuthClientSecretStore';reason='Tailscale OAuth client secret could not be decrypted';secret=$null;clientId='';path=$path;invalid=$true} }
}

function Remove-DevFleetTailscaleOAuthCredential {
    $path=Get-DevFleetE2ESecretPath;$data=$null
    try{$data=Read-DevFleetE2ESecretRecord -Path $path}catch{return $false}
    if(-not $data -or -not $data.PSObject.Properties['tailscaleOAuthClientSecretDpapi']){return $false}
    $record=[ordered]@{schemaVersion=if($data.PSObject.Properties['schemaVersion']){[int]$data.schemaVersion}else{2};username=if($data.PSObject.Properties['username']){[string]$data.username}else{''};passwordDpapi=if($data.PSObject.Properties['passwordDpapi']){[string]$data.passwordDpapi}else{''};createdAt=(Get-Date).ToUniversalTime().ToString('o')}
    Write-DevFleetE2ESecretRecord -Path $path -Data $record
    $true
}

function Get-DevFleetE2ECredential {
    $path = Get-DevFleetE2ESecretPath
    if (-not (Test-Path -LiteralPath $path)) { throw "Secure E2E credential store not initialized: $path" }
    $data = Read-DevFleetE2ESecretRecord -Path $path
    if(-not $data.PSObject.Properties['username'] -or -not $data.PSObject.Properties['passwordDpapi']){throw "Secure E2E credential store lacks the interactive credential: $path"}
    [pscredential]::new([string]$data.username,(ConvertTo-SecureString -String ([string]$data.passwordDpapi)))
}

Export-ModuleMember -Function Get-DevFleetE2ESecretPath,Save-DevFleetE2ECredential,Get-DevFleetE2ECredential,Save-DevFleetTailscaleOAuthCredential,Get-DevFleetTailscaleOAuthCredential,Remove-DevFleetTailscaleOAuthCredential

```


## FILE: automation/release-e2e/modules/TailscaleE2E.psm1

SHA256: 32a289807948843d8f965cdd4f3c3950dbdc37bfe51dffc9bcae0deaa86ee397 | Bytes: 37483 | Git mode: 100644

```
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Secrets.psm1') -Force

function ConvertTo-TailscaleSafeText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $text = [regex]::Replace($text, '(?i)tskey-[A-Za-z0-9._~+/=-]+', '<redacted-tskey>')
    $text = [regex]::Replace($text, '(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+', '$1<redacted-token>')
    $text = [regex]::Replace($text, '(?i)(\b(?:oauth|client-secret|client_secret|access-token|access_token|api-token|api_token|auth-key|auth_key|token|secret)\b\s*[:=]\s*)[^\s,;]+', '$1<redacted-secret>')
    return $text
}

function Invoke-TailscaleRemoteBounded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [ValidateRange(1,600)][int]$MaximumSeconds = 30
    )
    $deadline = $OwnerDeadlineUtc.ToUniversalTime()
    $remaining = [int][math]::Floor(($deadline - [datetime]::UtcNow).TotalSeconds)
    if ($remaining -le 1) { throw 'TAILSCALE_READINESS_OWNER_DEADLINE_EXPIRED' }
    $limit = [math]::Min($MaximumSeconds, $remaining - 1)
    $job = $null
    try {
        try { $job = Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -AsJob -ErrorAction Stop }
        catch { throw 'TAILSCALE_READINESS_REMOTE_START_FAILED' }
        $completed = Wait-Job -Job $job -Timeout $limit
        if (-not $completed) {
            try { Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null } catch { }
            throw 'TAILSCALE_READINESS_REMOTE_TIMEOUT'
        }
        if ([string]$job.State -ceq 'Failed') { throw 'TAILSCALE_READINESS_REMOTE_FAILED' }
        try { Receive-Job -Job $job -ErrorAction Stop }
        catch { throw 'TAILSCALE_READINESS_REMOTE_FAILED' }
    } finally {
        if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    }
}

function Get-TailscaleGuestStatus {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [string]$ExpectedNodePattern = 'DevFleet-E2E-*',
        [string]$ExpectedTag = '',
        [datetime]$OwnerDeadlineUtc = ([datetime]::UtcNow.AddSeconds(30))
    )
    $remoteStatus = Invoke-TailscaleRemoteBounded -Session $Session -ScriptBlock {
        param($pattern, $expectedTag)

        $statusText = (& tailscale status --json --peers=false 2>&1 | Out-String).Trim()
        $statusExit = [int]$LASTEXITCODE
        $ipText = (& tailscale ip -4 2>&1 | Out-String).Trim()
        $ipExit = [int]$LASTEXITCODE
        $versionText = (& tailscale version 2>&1 | Select-Object -First 1 | Out-String).Trim()
        $prefsText = (& tailscale debug prefs 2>&1 | Out-String).Trim()
        $prefsExit = [int]$LASTEXITCODE
        $lockText = (& tailscale lock status --json 2>&1 | Out-String).Trim()
        $lockExit = [int]$LASTEXITCODE

        $json = $null
        $prefs = $null
        $lock = $null
        try { $json = $statusText | ConvertFrom-Json -ErrorAction Stop } catch { }
        try { $prefs = $prefsText | ConvertFrom-Json -ErrorAction Stop } catch { }
        try { $lock = $lockText | ConvertFrom-Json -ErrorAction Stop } catch { }

        $node = ''
        $online = $false
        if ($json -and $json.PSObject.Properties['Self'] -and $json.Self) {
            if ($json.Self.PSObject.Properties['HostName']) { $node = [string]$json.Self.HostName }
            elseif ($json.Self.PSObject.Properties['DNSName']) { $node = [string]$json.Self.DNSName }
            if ($json.Self.PSObject.Properties['Online']) { $online = [bool]$json.Self.Online }
        }
        if ($node -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { $node = '' }

        $backend = if ($json -and $json.PSObject.Properties['BackendState']) { [string]$json.BackendState } else { '' }
        $candidateIps = [Collections.Generic.List[string]]::new()
        if ($json -and $json.PSObject.Properties['TailscaleIPs']) {
            foreach ($address in @($json.TailscaleIPs)) { [void]$candidateIps.Add([string]$address) }
        }
        foreach ($address in @($ipText -split '\s+')) { if ($address) { [void]$candidateIps.Add([string]$address) } }
        $ip = ''
        foreach ($address in $candidateIps) {
            $parsed = $null
            if ([Net.IPAddress]::TryParse($address, [ref]$parsed) -and $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
                $bytes = $parsed.GetAddressBytes()
                if ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) { $ip = $parsed.ToString(); break }
            }
        }

        $tags = [Collections.Generic.List[string]]::new()
        if ($json -and $json.PSObject.Properties['Self'] -and $json.Self -and $json.Self.PSObject.Properties['Tags']) {
            foreach ($tag in @($json.Self.Tags)) { if ([string]$tag -match '^tag:[A-Za-z0-9][A-Za-z0-9_-]*$') { [void]$tags.Add([string]$tag) } }
        }
        if ($prefs -and $prefs.PSObject.Properties['AdvertiseTags']) {
            $tags = [Collections.Generic.List[string]]::new()
            foreach ($tag in @($prefs.AdvertiseTags)) { if ([string]$tag -match '^tag:[A-Za-z0-9][A-Za-z0-9_-]*$') { [void]$tags.Add([string]$tag) } }
        }

        $healthErrors = @()
        if ($json -and $json.PSObject.Properties['Health'] -and $json.Health) {
            $healthErrors = @($json.Health | ForEach-Object { [string]$_ } | Where-Object { $_ -and $_ -notmatch '(?i)^ok$' })
        }
        $lockEnabled = $null
        if ($lock -and $lock.PSObject.Properties['Enabled']) { $lockEnabled = [bool]$lock.Enabled }

        [pscustomobject]@{
            statusExit = $statusExit
            ipExit = $ipExit
            backendState = $backend
            needsLogin = $backend -in @('NeedsLogin', 'NoState')
            online = $online
            node = $node
            ip = $ip
            version = if ($versionText -match '^(\S+)') { $Matches[1] } else { '' }
            expectedNode = $node -like $pattern
            tags = @($tags)
            expectedTag = if ($expectedTag) { $expectedTag } else { '' }
            expectedTagMatch = if ($expectedTag) { @($tags) -contains $expectedTag } else { $null }
            healthErrorPresent = $healthErrors.Count -gt 0
            lockStatus = if ($lockEnabled -eq $true) { 'ENABLED' } elseif ($lockEnabled -eq $false) { 'DISABLED' } else { 'UNKNOWN' }
            lockExit = $lockExit
            prefsExit = $prefsExit
            credentialsStored = $false
        }
    } -ArgumentList @($ExpectedNodePattern, $ExpectedTag) -OwnerDeadlineUtc $OwnerDeadlineUtc -MaximumSeconds 25
    $remoteStatus
}

function Test-TailscaleConnected {
    param([Parameter(Mandatory)][psobject]$Status)
    $statusExit = if ($Status.PSObject.Properties['statusExit']) { [int]$Status.statusExit } else { -1 }
    $ipExit = if ($Status.PSObject.Properties['ipExit']) { [int]$Status.ipExit } else { -1 }
    $prefsExit = if ($Status.PSObject.Properties['prefsExit']) { [int]$Status.prefsExit } else { -1 }
    $backend = if ($Status.PSObject.Properties['backendState']) { [string]$Status.backendState } else { '' }
    $needsLogin = if ($Status.PSObject.Properties['needsLogin']) { [bool]$Status.needsLogin } else { $true }
    $online = if ($Status.PSObject.Properties['online']) { [bool]$Status.online } else { $false }
    $expected = if ($Status.PSObject.Properties['expectedNode']) { [bool]$Status.expectedNode } else { $false }
    $ip = if ($Status.PSObject.Properties['ip']) { [string]$Status.ip } else { '' }
    $healthError = $Status.PSObject.Properties['healthErrorPresent'] -and [bool]$Status.healthErrorPresent
    $tagPass = $true
    if ($Status.PSObject.Properties['expectedTagMatch'] -and $null -ne $Status.expectedTagMatch) { $tagPass = [bool]$Status.expectedTagMatch }
    $tagCommandPass = $true
    if ($Status.PSObject.Properties['expectedTagMatch'] -and $null -ne $Status.expectedTagMatch) { $tagCommandPass = $prefsExit -eq 0 }
    return ($statusExit -eq 0 -and $ipExit -eq 0 -and $backend -ceq 'Running' -and -not $needsLogin -and $online -and $expected -and $tagPass -and $tagCommandPass -and -not $healthError -and $ip -match '^100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}$')
}

function Get-TailscaleAuthenticationSecret {
    param([Parameter(Mandatory)][psobject]$Config)
    $auth = if ($Config.PSObject.Properties['Authentication']) { $Config.Authentication } else { $null }
    $provider = if ($auth -and $auth.PSObject.Properties['Provider']) { [string]$auth.Provider } else { '' }
    if ($provider -in @('OAuthClientSecretStore', 'OAuthAutomation', 'OAuthClientSecretDpapi')) {
        $credential = Get-DevFleetTailscaleOAuthCredential
        return [pscustomobject]@{
            available = [bool]$credential.available
            provider = $provider
            reason = [string]$credential.reason
            secret = if ($credential.available) { [string]$credential.secret } else { $null }
            clientId = [string]$credential.clientId
            invalid = [bool]$credential.invalid
            userActionRequired = -not [bool]$credential.available
        }
    }
    $variable = if ($auth -and $auth.PSObject.Properties['SecretEnvironmentVariable']) { [string]$auth.SecretEnvironmentVariable } else { '' }
    if ($provider -ne 'AuthKeyEnvironment' -or [string]::IsNullOrWhiteSpace($variable)) {
        return [pscustomobject]@{ available=$false; provider=$provider; reason='configured Tailscale provider and protected secret source are required'; secret=$null; invalid=$false; userActionRequired=$true }
    }
    $secret = [Environment]::GetEnvironmentVariable($variable, 'Process')
    if ([string]::IsNullOrWhiteSpace($secret)) {
        return [pscustomobject]@{ available=$false; provider=$provider; reason='configured process-local Tailscale auth secret is absent'; secret=$null; invalid=$false; userActionRequired=$true }
    }
    [pscustomobject]@{ available=$true; provider=$provider; reason='process-local secret available'; secret=$secret; invalid=$false; userActionRequired=$false }
}

function Set-TailscaleProviderFileAcl {
    param([Parameter(Mandatory)][string]$Path)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $security = [Security.AccessControl.FileSecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    $security.SetOwner($identity)
    foreach ($rule in @(
        [Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'Allow'),
        [Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators', 'FullControl', 'Allow'),
        [Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')
    )) { [void]$security.AddAccessRule($rule) }
    Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
}

function Invoke-TailscaleAuthKeyFileCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AuthKey,[ValidateRange(1,600)][int]$TimeoutSeconds=120,[scriptblock]$CommandInvoker)
    if ([string]::IsNullOrWhiteSpace($AuthKey)) { throw 'Tailscale auth key input is empty.' }
    $authFile = $null
    $result = $null
    $primary = $null
    function Set-ProviderFileAcl {
        param([Parameter(Mandatory)][string]$Path)
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().User;$security=[Security.AccessControl.FileSecurity]::new();$security.SetAccessRuleProtection($true,$false);$security.SetOwner($identity)
        foreach($rule in @([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','Allow'),[Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators','FullControl','Allow'),[Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM','FullControl','Allow'))){[void]$security.AddAccessRule($rule)}
        Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
    }
    try {
        $authFile = Join-Path ([IO.Path]::GetTempPath()) ('.devfleet-tailscale-auth-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($authFile, '', [Text.UTF8Encoding]::new($false))
        Set-ProviderFileAcl -Path $authFile
        [IO.File]::WriteAllText($authFile, $AuthKey, [Text.UTF8Encoding]::new($false))
        $arguments = @('up', "--auth-key=file:$authFile", '--accept-dns=false', "--timeout=$TimeoutSeconds`s")
        if ($CommandInvoker) { $result = & $CommandInvoker $authFile $arguments }
        else { $output = (& tailscale @arguments 2>&1 | Out-String); $result = [pscustomobject]@{ exitCode=[int]$LASTEXITCODE; output=$output } }
    } catch { $primary = $_ } finally {
        if ($authFile) {
            try {
                if (Test-Path -LiteralPath $authFile -PathType Leaf) {
                    $length = (Get-Item -LiteralPath $authFile -Force).Length
                    if ($length -gt 0) { [IO.File]::WriteAllBytes($authFile, [byte[]]::new($length)) }
                    Remove-Item -LiteralPath $authFile -Force -ErrorAction Stop
                }
            } catch { if (-not $primary) { $primary = $_ } }
        }
    }
    if ($primary) { throw $primary }
    $safeOutput=[string]$result.output
    $safeOutput=[regex]::Replace($safeOutput,'(?i)tskey-[A-Za-z0-9._~+/=-]+','<redacted-tskey>')
    $safeOutput=[regex]::Replace($safeOutput,'(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+','$1<redacted-token>')
    $safeOutput=[regex]::Replace($safeOutput,'(?i)(\b(?:oauth|client-secret|client_secret|access-token|access_token|api-token|api_token|auth-key|auth_key|token|secret)\b\s*[:=]\s*)[^\s,;]+','$1<redacted-secret>')
    [pscustomobject]@{ exitCode=[int]$result.exitCode; output=$safeOutput; authKeyFileRemoved=$true }
}

function Invoke-TailscaleOAuthClientSecretFileCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClientSecret,
        [string]$Tag='tag:devfleet-e2e',
        [Parameter(Mandatory)][string]$Hostname,
        [bool]$Ephemeral=$true,
        [bool]$Preauthorized=$true,
        [bool]$Unattended=$false,
        [ValidateRange(1,600)][int]$TimeoutSeconds=120,
        [scriptblock]$CommandInvoker
    )
    if ([string]::IsNullOrWhiteSpace($ClientSecret)) { throw 'Tailscale OAuth client secret input is empty.' }
    if ($Tag -notmatch '^tag:[A-Za-z0-9][A-Za-z0-9_-]*$' -or $Hostname -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$') { throw 'Tailscale OAuth enrollment identity is malformed.' }
    $payload = "${ClientSecret}?ephemeral=$($Ephemeral.ToString().ToLowerInvariant())&preauthorized=$($Preauthorized.ToString().ToLowerInvariant())"
    $authFile = $null
    $result = $null
    $primary = $null
    function Set-ProviderFileAcl {
        param([Parameter(Mandatory)][string]$Path)
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().User;$security=[Security.AccessControl.FileSecurity]::new();$security.SetAccessRuleProtection($true,$false);$security.SetOwner($identity)
        foreach($rule in @([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','Allow'),[Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators','FullControl','Allow'),[Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM','FullControl','Allow'))){[void]$security.AddAccessRule($rule)}
        Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
    }
    try {
        $authFile = Join-Path ([IO.Path]::GetTempPath()) ('.devfleet-tailscale-oauth-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($authFile, '', [Text.UTF8Encoding]::new($false))
        Set-ProviderFileAcl -Path $authFile
        [IO.File]::WriteAllText($authFile, $payload, [Text.UTF8Encoding]::new($false))
        $arguments = @('up', "--client-secret=file:$authFile", "--advertise-tags=$Tag", "--hostname=$Hostname", '--accept-dns=false')
        if ($Unattended) { $arguments += '--unattended=true' }
        $arguments += "--timeout=$TimeoutSeconds`s"
        if ($CommandInvoker) { $result = & $CommandInvoker $authFile $arguments }
        else { $output = (& tailscale @arguments 2>&1 | Out-String); $result = [pscustomobject]@{ exitCode=[int]$LASTEXITCODE; output=$output } }
    } catch { $primary = $_ } finally {
        if ($authFile) {
            try {
                if (Test-Path -LiteralPath $authFile -PathType Leaf) {
                    $length = (Get-Item -LiteralPath $authFile -Force).Length
                    if ($length -gt 0) { [IO.File]::WriteAllBytes($authFile, [byte[]]::new($length)) }
                    Remove-Item -LiteralPath $authFile -Force -ErrorAction Stop
                }
            } catch { if (-not $primary) { $primary = $_ } }
        }
        $payload = $null
    }
    if ($primary) { throw $primary }
    $safeOutput=[string]$result.output
    $safeOutput=[regex]::Replace($safeOutput,'(?i)tskey-[A-Za-z0-9._~+/=-]+','<redacted-tskey>')
    $safeOutput=[regex]::Replace($safeOutput,'(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+','$1<redacted-token>')
    $safeOutput=[regex]::Replace($safeOutput,'(?i)(\b(?:oauth|client-secret|client_secret|access-token|access_token|api-token|api_token|auth-key|auth_key|token|secret)\b\s*[:=]\s*)[^\s,;]+','$1<redacted-secret>')
    [pscustomobject]@{ exitCode=[int]$result.exitCode; output=$safeOutput; oauthSecretFileRemoved=$true }
}

function Get-TailscaleReadinessFromStatus {
    param([Parameter(Mandatory)][psobject]$Status,[Parameter(Mandatory)][string]$ExpectedNodePattern,[string]$ExpectedTag='')
    $backend = if ($Status.PSObject.Properties['backendState']) { [string]$Status.backendState } else { '' }
    $statusExit = if ($Status.PSObject.Properties['statusExit']) { [int]$Status.statusExit } else { 0 }
    $ipExit = if ($Status.PSObject.Properties['ipExit']) { [int]$Status.ipExit } else { 0 }
    $prefsExit = if ($Status.PSObject.Properties['prefsExit']) { [int]$Status.prefsExit } else { 0 }
    $needsLogin = $Status.PSObject.Properties['needsLogin'] -and [bool]$Status.needsLogin
    $ip = if ($Status.PSObject.Properties['ip']) { [string]$Status.ip } else { '' }
    $online = $Status.PSObject.Properties['online'] -and [bool]$Status.online
    $expectedNode = $Status.PSObject.Properties['expectedNode'] -and [bool]$Status.expectedNode
    $expectedTagMatch = if ($ExpectedTag) { if ($Status.PSObject.Properties['expectedTagMatch']) { [bool]$Status.expectedTagMatch } else { $false } } else { $null }
    $healthError = $Status.PSObject.Properties['healthErrorPresent'] -and [bool]$Status.healthErrorPresent
    $statusClass = 'MALFORMED'
    $failureClass = 'TAILSCALE_HEALTH_ERROR'
    if ($statusExit -ne 0) { $statusClass='CONTROL_PLANE_OFFLINE';$failureClass='TAILSCALE_CONTROL_PLANE_OFFLINE' }
    elseif ($ipExit -ne 0) { $statusClass='NO_IP';$failureClass='TAILSCALE_NO_IP' }
    elseif ($ExpectedTag -and $prefsExit -ne 0) { $statusClass='WRONG_TAG';$failureClass='TAILSCALE_WRONG_TAG' }
    elseif ($needsLogin) { $statusClass='NEEDS_LOGIN';$failureClass='TAILSCALE_NEEDS_LOGIN' }
    elseif ($backend -ne 'Running') { $statusClass='CONTROL_PLANE_OFFLINE';$failureClass='TAILSCALE_CONTROL_PLANE_OFFLINE' }
    elseif ($healthError) { $statusClass='HEALTH_ERROR';$failureClass='TAILSCALE_HEALTH_ERROR' }
    elseif (-not $ip) { $statusClass='NO_IP';$failureClass='TAILSCALE_NO_IP' }
    elseif (-not $online) { $statusClass='OFFLINE';$failureClass='TAILSCALE_CONTROL_PLANE_OFFLINE' }
    elseif (-not $expectedNode) { $statusClass='WRONG_IDENTITY';$failureClass='TAILSCALE_WRONG_TAG' }
    elseif ($ExpectedTag -and -not $expectedTagMatch) { $statusClass='WRONG_TAG';$failureClass='TAILSCALE_WRONG_TAG' }
    else { $statusClass='READY';$failureClass='' }
    [pscustomobject][ordered]@{
        schemaVersion=1;ready=($statusClass -ceq 'READY');statusClass=$statusClass;failureClass=$failureClass;expectedNodePattern=$ExpectedNodePattern
        layer1Service='PASS';layer2Authenticated=($statusClass -ceq 'READY');layer2=$Status;layer3Peer='NOT_CONFIGURED';layer3FailureClass='';layer4Endpoint='NOT_CONFIGURED';layer4FailureClass=''
    }
}

function Get-TailscaleReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$ExpectedNodePattern,
        [string]$ExpectedTag='',
        [string]$ExpectedPeer='',
        [ValidateRange(0,65535)][int]$ServicePort=0,
        [string]$ServicePath='/healthz',
        [datetime]$OwnerDeadlineUtc = ([datetime]::UtcNow.AddSeconds(30))
    )
    if ($ExpectedPeer -and $ExpectedPeer -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$|^100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}$') { throw 'Expected Tailscale peer identity is malformed.' }
    if ($ServicePort -and $ServicePath -notmatch '^/[A-Za-z0-9._~!$&''()*+,;=:@%/-]{0,255}$') { throw 'DevFleet service readiness path is malformed.' }
    $status = Get-TailscaleGuestStatus -Session $Session -ExpectedNodePattern $ExpectedNodePattern -ExpectedTag $ExpectedTag -OwnerDeadlineUtc $OwnerDeadlineUtc
    $readiness = Get-TailscaleReadinessFromStatus -Status $status -ExpectedNodePattern $ExpectedNodePattern -ExpectedTag $ExpectedTag
    if (-not $readiness.layer2Authenticated) { $readiness.layer3Peer='BLOCKED_BY_LAYER2';$readiness.layer4Endpoint='BLOCKED_BY_LAYER2';return $readiness }
    if ($ExpectedPeer) {
        try {
            $peer = Invoke-TailscaleRemoteBounded -Session $Session -ScriptBlock {
                param($target)
                $output = (& tailscale ping --tsmp --c=1 --timeout=5s --until-direct=false $target 2>&1 | Out-String)
                $exitCode = [int]$LASTEXITCODE
                [pscustomobject]@{ exitCode=$exitCode; outputClass=if ($exitCode -eq 0) { 'PASS' } elseif ($output -match '(?i)acl|denied|not permitted') { 'ACL_BLOCKED' } else { 'UNREACHABLE' } }
            } -ArgumentList @($ExpectedPeer) -OwnerDeadlineUtc $OwnerDeadlineUtc -MaximumSeconds 7
        } catch {
            $readiness.layer3Peer='FAIL';$readiness.layer3FailureClass='TAILSCALE_PEER_UNREACHABLE';$readiness.failureClass=$readiness.layer3FailureClass;$readiness.ready=$false;return $readiness
        }
        if ([int]$peer.exitCode -ne 0) { $readiness.layer3Peer='FAIL';$readiness.layer3FailureClass=if ([string]$peer.outputClass -ceq 'ACL_BLOCKED') { 'TAILSCALE_ACL_BLOCKED' } else { 'TAILSCALE_PEER_UNREACHABLE' };$readiness.failureClass=$readiness.layer3FailureClass;$readiness.ready=$false;return $readiness }
        $readiness.layer3Peer='PASS'
    }
    if ($ServicePort) {
        if (-not $ExpectedPeer) { $readiness.layer4Endpoint='BLOCKED_NO_PEER';$readiness.layer4FailureClass='DEVFLEET_SERVICE_UNREACHABLE_OVER_TAILSCALE';$readiness.failureClass=$readiness.layer4FailureClass;$readiness.ready=$false;return $readiness }
        try {
            $endpoint = Invoke-TailscaleRemoteBounded -Session $Session -ScriptBlock {
                param($target,$port,$path)
                $uri = "http://${target}:$port$path"
                try { Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 10 -ErrorAction Stop | Out-Null;[pscustomobject]@{exitCode=0} }
                catch { [pscustomobject]@{exitCode=1} }
            } -ArgumentList @($ExpectedPeer,$ServicePort,$ServicePath) -OwnerDeadlineUtc $OwnerDeadlineUtc -MaximumSeconds 12
        } catch {
            $readiness.layer4Endpoint='FAIL';$readiness.layer4FailureClass='DEVFLEET_SERVICE_UNREACHABLE_OVER_TAILSCALE';$readiness.failureClass=$readiness.layer4FailureClass;$readiness.ready=$false;return $readiness
        }
        if ([int]$endpoint.exitCode -ne 0) { $readiness.layer4Endpoint='FAIL';$readiness.layer4FailureClass='DEVFLEET_SERVICE_UNREACHABLE_OVER_TAILSCALE';$readiness.failureClass=$readiness.layer4FailureClass;$readiness.ready=$false;return $readiness }
        $readiness.layer4Endpoint='PASS'
    }
    $readiness.ready=$true;$readiness.failureClass='';return $readiness
}

function Get-TailscaleStableSuffix {
    param([Parameter(Mandatory)][string]$Value)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant().Substring(0,10) }
    finally { $sha.Dispose() }
}

function Get-TailscaleE2EHostname {
    param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][ValidateSet('windows','primary','failover','vault')][string]$Role)
    if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'E2E Tailscale hostname requires a sanitized run identity.' }
    "devfleet-e2e-$(Get-TailscaleStableSuffix "$RunId/$Role")-$Role"
}

function New-TailscaleE2EEnrollmentProfile {
    param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][psobject]$Config)
    $guestHostnames=[ordered]@{}
    foreach($entry in @([pscustomobject]@{key='Primary';role='primary'},[pscustomobject]@{key='Failover';role='failover'},[pscustomobject]@{key='Vault';role='vault'})) {
        if($Config.PSObject.Properties[$entry.key] -and $Config.$($entry.key).PSObject.Properties['InstanceName']) {
            $name=[string]$Config.$($entry.key).InstanceName
            if($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'){throw "Configured $($entry.key) instance identity is malformed."}
            $guestHostnames[$name]=Get-TailscaleE2EHostname -RunId $RunId -Role $entry.role
        }
    }
    [pscustomobject][ordered]@{schemaVersion=1;mode='e2e';tag='tag:devfleet-e2e';ephemeral=$true;preauthorized=$true;hostName=(Get-TailscaleE2EHostname -RunId $RunId -Role 'windows');guestHostnames=$guestHostnames}
}

function Stage-TailscaleOAuthCredential {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][psobject]$Config,[psobject]$ProductConfig)
    $auth=if($Config.PSObject.Properties['Authentication']){$Config.Authentication}else{$null};$provider=if($auth -and $auth.PSObject.Properties['Provider']){[string]$auth.Provider}else{''}
    if($provider -notin @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){return [ordered]@{status='SKIPPED';provider=$provider;reason='OAuth staging is not used by the configured authentication provider';staged=$false}}
    $credential=Get-TailscaleAuthenticationSecret -Config $Config
    if(-not [bool]$credential.available){Write-TailscaleOAuthActionRequired;$class=if([bool]$credential.invalid){'TAILSCALE_CREDENTIAL_INVALID'}else{'TAILSCALE_CREDENTIAL_MISSING'};throw "${class}: $([string]$credential.reason)"}
    $profileConfig=if($ProductConfig){$ProductConfig}else{$Config};$profile=New-TailscaleE2EEnrollmentProfile -RunId $RunId -Config $profileConfig;$profileJson=$profile|ConvertTo-Json -Depth 8 -Compress
    $remote=Invoke-Command -Session $Session -ScriptBlock {
        param($secret,$profileText)
        $root='C:\ProgramData\DevFleet\secrets';$secretPath=Join-Path $root 'tailscale-oauth-client.secret';$profilePath=Join-Path $root 'tailscale-enrollment-profile.json';New-Item -ItemType Directory -Path $root -Force|Out-Null
        function Set-ProtectedAcl([string]$Path){$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User;$security=[Security.AccessControl.FileSecurity]::new();$security.SetAccessRuleProtection($true,$false);$security.SetOwner($identity);foreach($rule in @([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','Allow'),[Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators','FullControl','Allow'),[Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM','FullControl','Allow'))){[void]$security.AddAccessRule($rule)};Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop}
        function Write-ProtectedAtomic([string]$Path,[string]$Text){$tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp";try{[IO.File]::WriteAllText($tmp,'',[Text.UTF8Encoding]::new($false));Set-ProtectedAcl $tmp;[IO.File]::WriteAllText($tmp,$Text,[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $tmp -Destination $Path -Force;Set-ProtectedAcl $Path}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}}
        foreach($path in @($secretPath,$profilePath)){if(Test-Path -LiteralPath $path -PathType Leaf){$item=Get-Item -LiteralPath $path -Force;if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'Existing Tailscale credential path is a reparse point.'}}}
        if([string]::IsNullOrWhiteSpace($secret)){throw 'Remote Tailscale OAuth credential staging received empty input.'}
        try {
            Write-ProtectedAtomic $secretPath ($secret+"`n");Write-ProtectedAtomic $profilePath ($profileText+"`n");[ordered]@{staged=$true;secretPath=$secretPath;profilePath=$profilePath;profile=($profileText|ConvertFrom-Json)}
        } catch {
            foreach($path in @($secretPath,$profilePath)){try{if(Test-Path -LiteralPath $path -PathType Leaf){$item=Get-Item -LiteralPath $path -Force;if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-eq0){if($path -eq $secretPath-and$item.Length-gt0){[IO.File]::WriteAllBytes($path,[byte[]]::new($item.Length))};Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}}catch{}}
            throw
        }
    } -ArgumentList ([string]$credential.secret),$profileJson
    [ordered]@{status='PASS';provider=$provider;staged=[bool]$remote.staged;remoteSecretPath=[string]$remote.secretPath;remoteProfilePath=[string]$remote.profilePath;profile=$remote.profile;credentialsStoredInEvidence=$false}
}

function Remove-StagedTailscaleOAuthCredential {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    Invoke-Command -Session $Session -ScriptBlock {
        $paths=@('C:\ProgramData\DevFleet\secrets\tailscale-oauth-client.secret','C:\ProgramData\DevFleet\secrets\tailscale-enrollment-profile.json');$removed=[ordered]@{}
        foreach($path in $paths){$removed[$path]=$false;if(Test-Path -LiteralPath $path -PathType Leaf){$item=Get-Item -LiteralPath $path -Force;if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Refusing to remove reparse-point credential path: $path"};if($path -like '*oauth-client.secret'){$length=$item.Length;if($length-gt0){[IO.File]::WriteAllBytes($path,[byte[]]::new($length))}};Remove-Item -LiteralPath $path -Force -ErrorAction Stop;$removed[$path]=$true}}
        [ordered]@{status='PASS';removed=$removed}
    }
}

function Write-TailscaleOAuthActionRequired {
    Write-Host "`a" -ForegroundColor Yellow
    try { [System.Media.SystemSounds]::Exclamation.Play() } catch { }
    try { [Console]::Beep(1200,450);Start-Sleep -Milliseconds 100;[Console]::Beep(1700,700) } catch { }
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host '>>> DYLAN ACTION REQUIRED - TAILSCALE OAUTH CREDENTIAL <<< ' -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Yellow
    $commandPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Set-DevFleetTailscaleOAuthCredential.ps1'))
    Write-Host "Run once in a local PowerShell prompt; enter the secret only into its secure prompt:" -ForegroundColor Yellow
    Write-Host "& '$commandPath'" -ForegroundColor Yellow
}

function Get-TailscaleProviderSource {
    param([Parameter(Mandatory)][bool]$AuthKey)
    if($AuthKey){return ${function:Invoke-TailscaleAuthKeyFileCommand}.ToString()}
    ${function:Invoke-TailscaleOAuthClientSecretFileCommand}.ToString()
}

function Invoke-TailscaleAuthentication {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][psobject]$Config,[datetime]$OwnerDeadlineUtc = ([datetime]::UtcNow.AddSeconds(150)))
    $credential=Get-TailscaleAuthenticationSecret -Config $Config
    if(-not [bool]$credential.available){return [ordered]@{authenticationAttempted=$false;authenticationSucceeded=$false;provider=[string]$credential.provider;userActionRequired=[bool]$credential.userActionRequired;credentialInvalid=[bool]$credential.invalid;failureClass=if([bool]$credential.invalid){'TAILSCALE_CREDENTIAL_INVALID'}else{'TAILSCALE_CREDENTIAL_MISSING'};reason=[string]$credential.reason}}
    try {
        try {
            $lock=Invoke-TailscaleRemoteBounded -Session $Session -ScriptBlock {$raw=(& tailscale lock status --json 2>&1|Out-String);$exit=[int]$LASTEXITCODE;try{$json=$raw|ConvertFrom-Json -ErrorAction Stop;if($json.PSObject.Properties['Enabled']){[pscustomobject]@{exitCode=$exit;enabled=[bool]$json.Enabled}}else{[pscustomobject]@{exitCode=$exit;enabled=$null}}}catch{[pscustomobject]@{exitCode=$exit;enabled=$null}}} -OwnerDeadlineUtc $OwnerDeadlineUtc -MaximumSeconds 15
        } catch { return [ordered]@{authenticationAttempted=$false;authenticationSucceeded=$false;provider=[string]$credential.provider;userActionRequired=$false;failureClass='TAILNET_LOCK_SIGNING_REQUIRED';reason='Tailnet Lock state was not established within the owner deadline.'} }
        if([int]$lock.exitCode -ne 0){return [ordered]@{authenticationAttempted=$false;authenticationSucceeded=$false;provider=[string]$credential.provider;userActionRequired=$false;failureClass='TAILNET_LOCK_SIGNING_REQUIRED';reason='Tailnet Lock status command failed; automatic enrollment is blocked.'}}
        if($lock.enabled -eq $true){return [ordered]@{authenticationAttempted=$false;authenticationSucceeded=$false;provider=[string]$credential.provider;userActionRequired=$false;failureClass='TAILNET_LOCK_SIGNING_REQUIRED';reason='Tailnet Lock is enabled; a trusted signing path is required.'}}
        if($lock.enabled -ne $false){return [ordered]@{authenticationAttempted=$false;authenticationSucceeded=$false;provider=[string]$credential.provider;userActionRequired=$false;failureClass='TAILNET_LOCK_SIGNING_REQUIRED';reason='Tailnet Lock state was not established; automatic enrollment is blocked.'}}
        $auth=$Config.Authentication;$tag=if($auth.PSObject.Properties['Tag']){[string]$auth.Tag}else{'tag:devfleet-e2e'};$hostname=if($auth.PSObject.Properties['Hostname']){[string]$auth.Hostname}else{'devfleet-e2e-auth'};$ephemeral=if($auth.PSObject.Properties['Ephemeral']){[bool]$auth.Ephemeral}else{$true};$preauth=if($auth.PSObject.Properties['Preauthorized']){[bool]$auth.Preauthorized}else{$true};$unattended=if($auth.PSObject.Properties['Unattended']){[bool]$auth.Unattended}else{$true};$timeout=if($Config.PSObject.Properties['PollTimeoutSeconds']){[int]$Config.PollTimeoutSeconds}else{120}
        $authKey=[string]$credential.provider -ceq 'AuthKeyEnvironment';$source=Get-TailscaleProviderSource -AuthKey:$authKey
        $authMaximum=[math]::Max(1,[math]::Min(600,$timeout+5))
        $result=Invoke-TailscaleRemoteBounded -Session $Session -ScriptBlock {param($secret,$provider,$source,$tag,$hostname,$ephemeral,$preauth,$unattended,$timeout)$fn=[scriptblock]::Create($source);if($provider-ceq'AuthKeyEnvironment'){&$fn -AuthKey $secret -TimeoutSeconds $timeout}else{&$fn -ClientSecret $secret -Tag $tag -Hostname $hostname -Ephemeral:$ephemeral -Preauthorized:$preauth -Unattended:$unattended -TimeoutSeconds $timeout}} -ArgumentList ([string]$credential.secret),[string]$credential.provider,$source,$tag,$hostname,$ephemeral,$preauth,$unattended,$timeout -OwnerDeadlineUtc $OwnerDeadlineUtc -MaximumSeconds $authMaximum
        $ok=[int]$result.exitCode -eq 0
        [ordered]@{authenticationAttempted=$true;authenticationSucceeded=$ok;provider=[string]$credential.provider;userActionRequired=$false;credentialInvalid=$false;exitCode=[int]$result.exitCode;output=ConvertTo-TailscaleSafeText ([string]$result.output);failureClass=if($ok){''}else{'TAILSCALE_AUTH_FAILED'}}
    } catch { [ordered]@{authenticationAttempted=$true;authenticationSucceeded=$false;provider=[string]$credential.provider;userActionRequired=$false;credentialInvalid=[bool]$credential.invalid;failureClass='TAILSCALE_AUTH_FAILED';error='Tailscale authentication provider invocation failed'} }
}

function Assert-TailscaleAuthenticationResult {
    param([Parameter(Mandatory)][psobject]$Result)
    if($Result.PSObject.Properties['failureClass'] -and [string]$Result.failureClass){$reason=if($Result.PSObject.Properties['reason']){[string]$Result.reason}else{''};throw (([string]$Result.failureClass)+$(if($reason){": $reason"}else{''}))}
    if(-not [bool]$Result.authenticationAttempted){throw 'TAILSCALE-AUTH cannot pass when authenticationAttempted=false.'}
    if(-not [bool]$Result.authenticationSucceeded){throw 'TAILSCALE-AUTH authentication provider did not establish authentication.'}
    $true
}

Export-ModuleMember -Function Get-TailscaleGuestStatus,Test-TailscaleConnected,Get-TailscaleAuthenticationSecret,Invoke-TailscaleAuthKeyFileCommand,Invoke-TailscaleOAuthClientSecretFileCommand,Get-TailscaleReadinessFromStatus,Get-TailscaleReadiness,Get-TailscaleE2EHostname,New-TailscaleE2EEnrollmentProfile,Stage-TailscaleOAuthCredential,Remove-StagedTailscaleOAuthCredential,Write-TailscaleOAuthActionRequired,Invoke-TailscaleAuthentication,Assert-TailscaleAuthenticationResult

```


## FILE: automation/release-e2e/modules/executors/Invoke-AuditPhase.ps1

SHA256: b01b6c2141955adb2c9544ecf9ab4d7d4ce3322ec01e62bfffd20009e216da95 | Bytes: 234 | Git mode: 100644

```
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
Import-Module (Join-Path $PSScriptRoot 'Invoke-RealProductPhase.psm1') -Force
Invoke-RealProductPhase -ContextJson $ContextJson | ConvertTo-Json -Depth 32 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-DependencyMatrix.ps1

SHA256: b01b6c2141955adb2c9544ecf9ab4d7d4ce3322ec01e62bfffd20009e216da95 | Bytes: 234 | Git mode: 100644

```
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
Import-Module (Join-Path $PSScriptRoot 'Invoke-RealProductPhase.psm1') -Force
Invoke-RealProductPhase -ContextJson $ContextJson | ConvertTo-Json -Depth 32 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-HostAgentPhase.ps1

SHA256: b01b6c2141955adb2c9544ecf9ab4d7d4ce3322ec01e62bfffd20009e216da95 | Bytes: 234 | Git mode: 100644

```
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
Import-Module (Join-Path $PSScriptRoot 'Invoke-RealProductPhase.psm1') -Force
Invoke-RealProductPhase -ContextJson $ContextJson | ConvertTo-Json -Depth 32 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-HttpHostilePhase.ps1

SHA256: e2d8ba28381c7fc3c3872312d6b7f964ca8e7b48d5dc03ada9d6c6b9a6f17ee1 | Bytes: 3111 | Git mode: 100644

```
[CmdletBinding()]
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
$ErrorActionPreference = 'Stop'
$context = $ContextJson | ConvertFrom-Json -ErrorAction Stop
$tarPath = [string]$context.candidate.tar.path
$tarItem = Get-Item -LiteralPath $tarPath -ErrorAction Stop
$tarHash = (Get-FileHash -LiteralPath $tarItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($tarHash -ne [string]$context.candidate.tar.sha256 -or [int64]$tarItem.Length -ne [int64]$context.candidate.tar.bytes) { throw 'HTTP-HOSTILE exact candidate TAR identity changed.' }

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$python = if (Test-Path -LiteralPath (Join-Path $workspace '.venv-test\Scripts\python.exe')) { Join-Path $workspace '.venv-test\Scripts\python.exe' } else { (Get-Command python.exe -ErrorAction Stop).Source }
$extractRoot = Join-Path ([string]$context.runDir) 'HTTP-HOSTILE-extracted'
$outputPath = Join-Path ([string]$context.runDir) 'HTTP-HOSTILE-pytest.txt'
try {
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    & tar.exe -xzf $tarItem.FullName -C $extractRoot
    if ($LASTEXITCODE -ne 0) { throw 'HTTP-HOSTILE exact candidate TAR extraction failed.' }
    $testPath = Join-Path $extractRoot 'tests\test_request_admission.py'
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) { throw 'HTTP-HOSTILE request-admission suite is absent from the exact candidate TAR.' }
    $priorPythonPath = $env:PYTHONPATH
    $priorPluginState = $env:PYTEST_DISABLE_PLUGIN_AUTOLOAD
    try {
        $env:PYTHONPATH = "$extractRoot;$extractRoot\app"
        $env:PYTEST_DISABLE_PLUGIN_AUTOLOAD = '1'
        $output = @(& $python -m pytest -q $testPath -rs 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $priorPythonPath) { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue } else { $env:PYTHONPATH = $priorPythonPath }
        if ($null -eq $priorPluginState) { Remove-Item Env:PYTEST_DISABLE_PLUGIN_AUTOLOAD -ErrorAction SilentlyContinue } else { $env:PYTEST_DISABLE_PLUGIN_AUTOLOAD = $priorPluginState }
    }
    $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    $text | Set-Content -LiteralPath $outputPath -Encoding utf8
    if ($exitCode -ne 0) { throw "HTTP-HOSTILE exact candidate regression failed; evidence=$outputPath" }
    $match = [regex]::Match($text, '(?m)(\d+) passed')
    if (-not $match.Success -or [int]$match.Groups[1].Value -lt 10) { throw 'HTTP-HOSTILE did not report the complete request-admission regression count.' }
    [ordered]@{status='PASS';phase='HTTP-HOSTILE';contract='exact-candidate-asgi-request-admission-regression';tar=[ordered]@{path=$tarItem.FullName;bytes=[int64]$tarItem.Length;sha256=$tarHash};tests=[ordered]@{passed=[int]$match.Groups[1].Value;failed=0;outputPath=$outputPath};networkBeforeBody=$true;invalidTokenZeroConsumption=$true;declaredAndChunkedLimits=$true} | ConvertTo-Json -Depth 8 -Compress
} finally {
    if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }
}

```


## FILE: automation/release-e2e/modules/executors/Invoke-LinuxPhase.ps1

SHA256: 37bf83af6eb4acf2d956473bed6e5629bd423d6309ad7d0067b5ab98d0a18858 | Bytes: 237 | Git mode: 100644

```
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
Import-Module (Join-Path $PSScriptRoot 'Invoke-RealProductPhase.psm1') -Force
Invoke-LinuxBootstrapPhase -ContextJson $ContextJson | ConvertTo-Json -Depth 32 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1

SHA256: b01b6c2141955adb2c9544ecf9ab4d7d4ce3322ec01e62bfffd20009e216da95 | Bytes: 234 | Git mode: 100644

```
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
Import-Module (Join-Path $PSScriptRoot 'Invoke-RealProductPhase.psm1') -Force
Invoke-RealProductPhase -ContextJson $ContextJson | ConvertTo-Json -Depth 32 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-PrimaryPhase.ps1

SHA256: 69f0b4b0b9e7204235b768adc34df5cc265cd77ac632515a79c838b8f8acb541 | Bytes: 234 | Git mode: 100644

```
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
Import-Module (Join-Path $PSScriptRoot 'Invoke-RealProductPhase.psm1') -Force
Invoke-PrimaryRolePhase -ContextJson $ContextJson | ConvertTo-Json -Depth 32 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-ProductLifecycleScenario.py

SHA256: 301a7f1227b24a6315846bd41e495ae038b1d4aa21f5e4707641687ea5e00ad2 | Bytes: 24956 | Git mode: 100644

```
#!/usr/bin/env python3
"""Run one bounded release scenario against an extracted exact-candidate tree."""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import 