Set-StrictMode -Version Latest

function Get-DevFleetE2ESecretPath {
    Join-Path $env:LOCALAPPDATA 'DevFleet\E2E\secrets.json'
}

function Protect-DevFleetE2ESecretFile {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $security = [Security.AccessControl.FileSecurity]::new()
        $security.SetAccessRuleProtection($true,$false)
        $security.SetOwner($identity)
        foreach($rule in @(
            [Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','Allow'),
            [Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators','FullControl','Allow'),
            [Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM','FullControl','Allow')
        )) { $security.AddAccessRule($rule) | Out-Null }
        Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
    } catch { throw 'Secure E2E credential store ACL could not be established.' }
}

function Write-DevFleetE2ESecretRecord {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Data)
    $parent=Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        # The temporary file is ACL'd before credential bytes are written.
        [IO.File]::WriteAllText($temporary,'',[Text.UTF8Encoding]::new($false))
        Protect-DevFleetE2ESecretFile -Path $temporary
        [IO.File]::WriteAllText($temporary,(($Data|ConvertTo-Json -Depth 8)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
        Protect-DevFleetE2ESecretFile -Path $Path
        [IO.File]::SetAttributes($Path,[IO.FileAttributes]::Hidden)
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Read-DevFleetE2ESecretRecord {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Secure E2E credential store is a reparse point.' }
    Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Save-DevFleetE2ECredential {
    param([Parameter(Mandatory)][pscredential]$Credential)
    $path = Get-DevFleetE2ESecretPath
    $existing = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { $existing = Read-DevFleetE2ESecretRecord -Path $path } catch { throw 'Secure E2E credential store is corrupt; repair it before replacing the interactive credential.' }
    }
    $data = [ordered]@{ schemaVersion=2; username=$Credential.UserName; passwordDpapi=$Credential.Password | ConvertFrom-SecureString; createdAt=(Get-Date).ToUniversalTime().ToString('o') }
    if ($existing) {
        foreach ($name in @('tailscaleOAuthClientId','tailscaleOAuthClientSecretDpapi')) {
            if ($existing.PSObject.Properties[$name]) { $data[$name] = $existing.$name }
        }
    }
    Write-DevFleetE2ESecretRecord -Path $path -Data $data
    $path
}

function ConvertTo-DevFleetPlainSecret {
    param([Parameter(Mandatory)][securestring]$Secret)
    $bstr=[IntPtr]::Zero
    try { $bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret);return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { if($bstr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)} }
}

function Save-DevFleetTailscaleOAuthCredential {
    [CmdletBinding()]
    param([Parameter(Mandatory)][securestring]$ClientSecret,[string]$ClientId='')
    if($ClientId -and ($ClientId.Length -gt 256 -or $ClientId -match '[\r\n]')){throw 'Tailscale OAuth client ID is malformed.'}
    $plain=ConvertTo-DevFleetPlainSecret -Secret $ClientSecret
    try {
        if([string]::IsNullOrWhiteSpace($plain) -or $plain.IndexOfAny([char[]]"`0`r`n") -ge 0 -or $plain.Length -gt 2048){throw 'Tailscale OAuth client secret is empty or malformed.'}
    } finally { $plain=$null }
    $path=Get-DevFleetE2ESecretPath;$existing=$null
    try {$existing=Read-DevFleetE2ESecretRecord -Path $path} catch { throw 'Secure E2E credential store is corrupt; repair it before adding Tailscale OAuth.' }
    $data=[ordered]@{schemaVersion=2;createdAt=(Get-Date).ToUniversalTime().ToString('o')}
    if($existing){foreach($name in @('username','passwordDpapi','createdAt')){if($existing.PSObject.Properties[$name]){$data[$name]=$existing.$name}}}
    if(-not $data.Contains('username')){$data.username='';$data.passwordDpapi=''}
    $data.tailscaleOAuthClientId=$ClientId
    $data.tailscaleOAuthClientSecretDpapi=($ClientSecret | ConvertFrom-SecureString)
    Write-DevFleetE2ESecretRecord -Path $path -Data $data
    $path
}

function Get-DevFleetTailscaleOAuthCredential {
    $path=Get-DevFleetE2ESecretPath;$data=$null
    try {$data=Read-DevFleetE2ESecretRecord -Path $path} catch { return [pscustomobject]@{available=$false;provider='OAuthClientSecretStore';reason='secure E2E credential store is corrupt';secret=$null;clientId='';path=$path;invalid=$true} }
    $clientId=if($data -and $data.PSObject.Properties['tailscaleOAuthClientId']){[string]$data.tailscaleOAuthClientId}else{''}
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
