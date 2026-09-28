# DevFleet source part 112

Full-source UTF-8 byte interval [5161500, 5208000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ef9ccfc55941e8bd622e49d8cd19483ee9d36e9bf67ced286a7748c6824c8848

<!-- BEGIN SOURCE SLICE -->
ing]$signature.SignerCertificate.Subject) $exact)){throw "Unexpected signer for $([IO.Path]::GetFileName($Path)): $($signature.SignerCertificate.Subject)"}
    if(@($exact).Count -eq 0 -and @($Policy.allowedSignerPatterns).Count -gt 0){throw "Legacy substring signer policy is rejected for $([IO.Path]::GetFileName($Path)); release policy must provide allowedSignerSubjectsExact."}
}

function Save-AllowlistedHttpsDownload {
    param([Parameter(Mandatory)][Uri]$Uri,[Parameter(Mandatory)][string[]]$AllowedHosts,[Parameter(Mandatory)][string]$Path)
    $current=$Uri
    for($hop=0;$hop -le 5;$hop++){
        if($current.Scheme -ne 'https' -or $current.UserInfo -or $current.Host -notin $AllowedHosts){throw "Download redirect left the allowlisted HTTPS boundary: $current"}
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
        $handler=[System.Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false;$client=[System.Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(60);$response=$null;$input=$null;$output=$null
        try{
            $response=$client.GetAsync($current).GetAwaiter().GetResult()
            if([int]$response.StatusCode -ge 300 -and [int]$response.StatusCode -le 399){
                $location=$response.Headers.Location;$response.Dispose();$response=$null
                if(-not $location){throw 'Allowlisted download redirect omitted Location.'}
                $current=[Uri]::new($current,$location);continue
            }
            if(-not $response.IsSuccessStatusCode){throw "Allowlisted download failed with HTTP $([int]$response.StatusCode)."}
            $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult();$output=[IO.File]::Open($Path,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None);$input.CopyTo($output);$output.Flush();return
        } finally {
            if($output){$output.Dispose()};if($input){$input.Dispose()};if($response){$response.Dispose()};$client.Dispose();$handler.Dispose()
        }
    }
    throw 'Allowlisted download exceeded the redirect limit.'
}

function Install-OfficialDependency {
    param([Parameter(Mandatory)]$Dependency)
    if ($Dependency.directOfficialVendorResolver.type -eq 'windows-capability') {
        $capability = Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Client*' | Select-Object -First 1
        if (-not $capability) { throw 'Official OpenSSH Windows capability was not found.' }
        if ($capability.State -ne 'Installed') { Add-WindowsCapability -Online -Name $capability.Name | Out-Null }
        return
    }
    $resolver = $Dependency.directOfficialVendorResolver
    $assetName = $null
    $assetUri = $null
    $expectedDigest = $null
    if ($resolver.type -eq 'github-release') {
        $metadata = Invoke-RestMethod -UseBasicParsing -TimeoutSec 60 -Uri $resolver.metadataUri -Headers @{ 'User-Agent'='DevFleet-Setup/1.4.1' }
        if ($resolver.PSObject.Properties.Name -contains 'expectedOwner' -and $resolver.expectedOwner) {
            if ([string]$metadata.author.login -ne [string]$resolver.expectedOwner) { throw "Official release owner mismatch for $($Dependency.displayName)." }
        }
        if ($resolver.PSObject.Properties.Name -contains 'expectedRepository' -and $resolver.expectedRepository) {
            if ([string]$metadata.html_url -notmatch ("/" + [regex]::Escape([string]$resolver.expectedOwner) + "/" + [regex]::Escape([string]$resolver.expectedRepository) + "/releases/")) { throw "Official release repository mismatch for $($Dependency.displayName)." }
        }
        $pageAssetName = $null
        if ($resolver.PSObject.Properties.Name -contains 'officialPageUri' -and $resolver.officialPageUri) {
            $page = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $resolver.officialPageUri -Headers @{ 'User-Agent'='DevFleet-Setup/1.4.1' }).Content
            $pageLinks = [regex]::Matches($page, '(?i)href\s*=\s*["''](?<href>[^"'']+)["'']') | ForEach-Object { $_.Groups['href'].Value }
            $tag = [string]$metadata.tag_name
            $pageAsset = $null
            foreach ($href in $pageLinks) {
                if ($href -match ("/releases/download/(?<tag>[^/]+)/(?<file>[^?#]+)$") -and $Matches.tag -eq $tag -and $Matches.file -match $resolver.officialPageAssetRegex) { $pageAsset = $href; break }
            }
            if (-not $pageAsset) { throw "Official 7-Zip page did not identify an asset matching the API release tag for $($Dependency.displayName)." }
            $pageAssetName = [IO.Path]::GetFileName(([Uri]$pageAsset).AbsolutePath)
        }
        $asset = @($metadata.assets) | Where-Object { $_.name -match $resolver.assetRegex -and (-not $pageAssetName -or $_.name -eq $pageAssetName) }
        if (@($asset).Count -ne 1) { throw "Expected exactly one official x64 release asset for $($Dependency.displayName), found $(@($asset).Count)." }
        $asset = @($asset)[0]
        $assetName=[string]$asset.name; $assetUri=[Uri]$asset.browser_download_url
        $expectedOwner = if ($resolver.PSObject.Properties.Name -contains 'expectedOwner') { [string]$resolver.expectedOwner } else { '' }
        $expectedRepository = if ($resolver.PSObject.Properties.Name -contains 'expectedRepository') { [string]$resolver.expectedRepository } else { '' }
        if ($expectedOwner -and $expectedRepository -and $assetUri.AbsolutePath -notmatch ("/" + [regex]::Escape($expectedOwner) + "/" + [regex]::Escape($expectedRepository) + "/releases/download/" + [regex]::Escape([string]$metadata.tag_name) + "/")) { throw "Official release asset path/tag mismatch for $($Dependency.displayName)." }
        if ($asset.PSObject.Properties.Name -contains 'digest') { $expectedDigest = ([string]$asset.digest -replace '^sha256:','') }
    } elseif ($resolver.type -eq 'official-download-page') {
        if ($resolver.PSObject.Properties.Name -contains 'directUri' -and $resolver.directUri) {
            $probe = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Method Head -MaximumRedirection 5 -Uri $resolver.directUri -Headers @{ 'User-Agent'='DevFleet-Setup/1.4.1' }
            $candidate = [Uri]$probe.BaseResponse.RequestMessage.RequestUri
            if ($candidate.Host -in @($resolver.allowedHosts) -and ([IO.Path]::GetFileName($candidate.AbsolutePath) -match $resolver.assetRegex)) { $assetUri=$candidate; $assetName=[IO.Path]::GetFileName($candidate.AbsolutePath) }
        } else {
            $page = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $resolver.metadataUri -Headers @{ 'User-Agent'='DevFleet-Setup/1.4.1' }).Content
            $links = [regex]::Matches($page, '(?i)href\s*=\s*["''](?<href>[^"'']+)["'']') | ForEach-Object { $_.Groups['href'].Value }
            foreach ($href in $links) {
                try { $candidate=[Uri]::new([Uri]$resolver.metadataUri,$href) } catch { continue }
                if ($candidate.Host -in @($resolver.allowedHosts) -and ([IO.Path]::GetFileName($candidate.AbsolutePath) -match $resolver.assetRegex)) { $assetUri=$candidate; $assetName=[IO.Path]::GetFileName($candidate.AbsolutePath); break }
            }
        }
    } else { throw "No implemented authenticated direct resolver for $($Dependency.displayName); official source: $($resolver.metadataUri)" }
    if (-not $assetUri -or $assetUri.Host -notin @($resolver.allowedHosts)) { throw "No authenticated official asset matched for $($Dependency.displayName)." }
    $cache = Join-Path (Get-DevFleetStateRoot) 'InstallerCache\Dependencies'; New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $path = Join-Path $cache $assetName
    $downloaded = $false
    for($attempt=1;$attempt -le 3;$attempt++) { try { Save-AllowlistedHttpsDownload -Uri $assetUri -AllowedHosts @($resolver.allowedHosts) -Path $path; $downloaded=$true; break } catch { if($attempt -eq 3){throw}; Start-Sleep -Seconds $attempt } }
    if (-not $downloaded -or -not (Test-Path -LiteralPath $path)) { throw "Official download did not complete for $($Dependency.displayName)." }
    if ($Dependency.installerAuthenticityPolicy.extensions -notcontains ([IO.Path]::GetExtension($path).ToLowerInvariant())) { throw "Unexpected installer file type for $($Dependency.displayName)." }
    $strategy = Get-AuthenticityStrategy $Dependency.installerAuthenticityPolicy
    if ($strategy -eq 'VendorReleaseSha256' -or $strategy -eq 'AuthenticodeOrVendorReleaseSha256') {
        if (-not $expectedDigest) { throw "Official vendor release did not provide a SHA-256 digest for $($Dependency.displayName)." }
        Test-FileSha256 -Path $path -Expected $expectedDigest | Out-Null
        Write-Host "Verified $($Dependency.displayName) using VendorReleaseSha256 (Authenticode status: $((Get-AuthenticodeSignature -LiteralPath $path).Status))." -ForegroundColor Green
        if ($strategy -eq 'AuthenticodeOrVendorReleaseSha256') {
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            if ($signature.Status -eq 'Valid') { Test-OfficialSigner -Path $path -Policy $Dependency.installerAuthenticityPolicy }
        }
    } else {
        Test-OfficialSigner -Path $path -Policy $Dependency.installerAuthenticityPolicy
    }
    $args = @($Dependency.silentInstallArguments)
    if ([IO.Path]::GetExtension($path).ToLowerInvariant() -eq '.msi') { $msiexec=Join-Path $env:WINDIR 'System32\msiexec.exe';if(-not (Test-TrustedExecutableCandidate $msiexec)){throw 'Trusted Windows Installer executable was not found.'};Invoke-External -FilePath $msiexec -ArgumentList (@('/i',$path)+$args) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') | Out-Null } else { Invoke-External -FilePath $path -ArgumentList $args -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') | Out-Null }
}

function Convert-SecureStringToBundlePassword {
    param([Parameter(Mandatory)][Security.SecureString]$SecureString)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function New-EncryptedBundle {
    param(
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$OutputPath,
        [Security.SecureString]$Passphrase
    )
    # A supplied SecureString stays in-process; callers retain its ownership.
    $secure = if ($null -eq $Passphrase) { Read-Host 'Enter a strong passphrase for this transfer bundle' -AsSecureString } else { $Passphrase }
    $password = Convert-SecureStringToBundlePassword $secure
    if ($password.Length -lt 12) { throw 'Bundle passphrase must be at least 12 characters.' }
    $iterations = 600000
    $salt = [byte[]]::new(16); [Security.Cryptography.RandomNumberGenerator]::Fill($salt)
    $nonce = [byte[]]::new(12); [Security.Cryptography.RandomNumberGenerator]::Fill($nonce)
    $zipPath = "$OutputPath.zip.tmp"
    $key = $null; $plain = $null; $cipher = $null; $tag = $null
    try {
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        [IO.Compression.ZipFile]::CreateFromDirectory($SourceDirectory, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
        $plain = [IO.File]::ReadAllBytes($zipPath)
        $header = [byte[]]::new(40)
        [Array]::Copy([Text.Encoding]::ASCII.GetBytes('DFENV001'), 0, $header, 0, 8)
        [Array]::Copy([BitConverter]::GetBytes([uint32]$iterations), 0, $header, 8, 4)
        [Array]::Copy($salt, 0, $header, 12, 16); [Array]::Copy($nonce, 0, $header, 28, 12)
        $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($password, $salt, $iterations, [Security.Cryptography.HashAlgorithmName]::SHA256)
        try { $key = $kdf.GetBytes(32) } finally { $kdf.Dispose() }
        $cipher = [byte[]]::new($plain.Length); $tag = [byte[]]::new(16)
        $aes = [Security.Cryptography.AesGcm]::new($key, 16)
        try { $aes.Encrypt($nonce, $plain, $cipher, $tag, $header) } finally { $aes.Dispose() }
        $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($header,0,$header.Length); $stream.Write([BitConverter]::GetBytes([int64]$cipher.Length),0,8); $stream.Write($cipher,0,$cipher.Length); $stream.Write($tag,0,$tag.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    } finally {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        if ($plain) { [Array]::Clear($plain,0,$plain.Length) }; if ($cipher) { [Array]::Clear($cipher,0,$cipher.Length) }; if ($key) { [Array]::Clear($key,0,$key.Length) }; $password=$null
    }
}

function Expand-EncryptedBundle {
    param(
        [Parameter(Mandatory)][string]$BundlePath,
        [Parameter(Mandatory)][string]$Destination,
        [Security.SecureString]$Passphrase
    )
    $secure = if ($null -eq $Passphrase) { Read-Host 'Enter the transfer-bundle passphrase' -AsSecureString } else { $Passphrase }
    $password = Convert-SecureStringToBundlePassword $secure
    $raw = $null; $key = $null; $plain = $null; $zipPath = "$BundlePath.zip.tmp"
    try {
        $raw = [IO.File]::ReadAllBytes($BundlePath)
        if ($raw.Length -lt 72) { throw 'Encrypted bundle is truncated.' }
        $header = [byte[]]::new(40); [Array]::Copy($raw,0,$header,0,40)
        if ([Text.Encoding]::ASCII.GetString($header,0,8) -ne 'DFENV001') { throw 'Unsupported encrypted bundle format.' }
        $iterations = [BitConverter]::ToUInt32($header,8); if ($iterations -lt 100000 -or $iterations -gt 2000000) { throw 'Encrypted bundle KDF parameters are invalid.' }
        $salt = [byte[]]::new(16); $nonce = [byte[]]::new(12); [Array]::Copy($header,12,$salt,0,16); [Array]::Copy($header,28,$nonce,0,12)
        $length = [BitConverter]::ToInt64($raw,40); if ($length -lt 1 -or $length -gt 1073741824 -or $raw.Length -ne 48+$length+16) { throw 'Encrypted bundle ciphertext length is invalid.' }
        $cipher = [byte[]]::new([int]$length); $tag = [byte[]]::new(16); [Array]::Copy($raw,48,$cipher,0,$cipher.Length); [Array]::Copy($raw,48+$cipher.Length,$tag,0,16)
        $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($password, $salt, [int]$iterations, [Security.Cryptography.HashAlgorithmName]::SHA256)
        try { $key = $kdf.GetBytes(32) } finally { $kdf.Dispose() }
        $plain = [byte[]]::new($cipher.Length); $aes = [Security.Cryptography.AesGcm]::new($key,16)
        try { $aes.Decrypt($nonce,$cipher,$tag,$plain,$header) } finally { $aes.Dispose() }
        [IO.File]::WriteAllBytes($zipPath,$plain); New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($zipPath,$Destination,$true)
    } finally {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        if ($raw) { [Array]::Clear($raw,0,$raw.Length) }; if ($plain) { [Array]::Clear($plain,0,$plain.Length) }; if ($key) { [Array]::Clear($key,0,$key.Length) }; $password=$null
    }
}

function New-DesktopShortcut {
    param([string]$Name,[string]$Target,[string]$Arguments,[string]$WorkingDirectory,[string]$IconLocation='shell32.dll,13')
    $desktop = [Environment]::GetFolderPath('Desktop')
    $path = Join-Path $desktop "$Name.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($path)
    $sc.TargetPath = $Target
    $sc.Arguments = $Arguments
    $sc.WorkingDirectory = $WorkingDirectory
    $sc.IconLocation = $IconLocation
    $sc.Save()
}

function Write-StageMarker {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Transaction
    )
    $path = Join-Path (Get-DevFleetStateRoot) "stage-$Name.complete"
    if(-not $Transaction){$Transaction=Get-ActiveDevFleetTransaction}
    if (-not $transaction) { throw 'Cannot write an unbound stage marker without an active DevFleet transaction.' }
    $preparedUtcText = ConvertTo-DevFleetPreparedUtcText $transaction.preparedUtc
    if(([string]$transaction.role).Trim() -notin @('Laptop','Desktop') -or
        ([string]$transaction.action).Trim() -notin @('FreshInstall','Repair','CleanReinstall','LocalUpdate') -or
        ([string]$transaction.transactionId).Trim() -notmatch '^[0-9a-fA-F]{32}$' -or
        ([string]$transaction.payloadSha256).Trim() -notmatch '^[0-9a-fA-F]{64}$' -or
        $preparedUtcText -notmatch 'T') { throw 'Cannot write a malformed or unbound stage marker transaction.' }
    $value=[ordered]@{ transactionId = [string]$transaction.transactionId; payloadSha256 = [string]$transaction.payloadSha256; action = [string]$transaction.action; role = [string]$transaction.role; stage = "stage-$Name"; completedUtc = (Get-Date).ToUniversalTime().ToString('o') }
    $temporary=Join-Path (Split-Path -Parent $path) ('.'+[IO.Path]::GetFileName($path)+'.'+[guid]::NewGuid().ToString('N')+'.tmp')
    $stream=$null
    try {
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($value|ConvertTo-Json -Compress))
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true);$stream.Dispose();$stream=$null
        [IO.File]::Move($temporary,$path,$true)
    } finally {
        if($stream){$stream.Dispose()}
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}
function Test-StageMarker {
    param([string]$Name)
    $path = Join-Path (Get-DevFleetStateRoot) "stage-$Name.complete"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $transaction = Get-ActiveDevFleetTransaction
    if (-not $transaction) { return $false }
    try {
        $marker = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return [string]$marker.transactionId -eq [string]$transaction.transactionId -and [string]$marker.payloadSha256 -eq [string]$transaction.payloadSha256 -and [string]$marker.action -eq [string]$transaction.action -and [string]$marker.role -eq [string]$transaction.role -and [string]$marker.stage -eq "stage-$Name"
    } catch { return $false }
}


function Get-OrCreateDevFleetSshKey {
    param([datetime]$DeadlineUtc = [datetime]::MinValue)
    $sshDir = Join-Path $env:USERPROFILE '.ssh'
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    $key = Join-Path $sshDir 'devfleet_ed25519'
    if (-not (Test-Path $key)) {
        $sshKeygen = @(
            (Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'),
            (Join-Path $env:ProgramFiles 'OpenSSH\ssh-keygen.exe')
        ) | Where-Object { $_ -and (Test-TrustedExecutableCandidate $_) } | Select-Object -First 1
        if (-not $sshKeygen) { throw 'OpenSSH Client/ssh-keygen is required.' }
        $null = Invoke-External $sshKeygen @('-t','ed25519','-a','100','-N','','-C',"devfleet-$env:COMPUTERNAME",'-f',$key) -DeadlineUtc $DeadlineUtc
        & icacls.exe $key /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
    }
    return $key
}

function Add-LocalSshKeyToInstance {
    param([Parameter(Mandatory)][string]$InstanceName,[string]$PublicKeyPath)
    $deadlineContext=Get-DevFleetDeadlineContext
    $componentDeadline=[DateTime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'sshAndMarker'))
    if($deadlineContext -and ([datetime]$deadlineContext.StageDeadlineUtc -lt $componentDeadline)){$componentDeadline=[datetime]$deadlineContext.StageDeadlineUtc}
    if (-not $PublicKeyPath) { $PublicKeyPath = "$(Get-OrCreateDevFleetSshKey -DeadlineUtc $componentDeadline).pub" }
    if (-not (Test-Path $PublicKeyPath)) { throw "Public key not found: $PublicKeyPath" }
    $mp = Get-MultipassExe
    Invoke-External $mp @('transfer',$PublicKeyPath,"${InstanceName}:/tmp/devfleet-client.pub") -DeadlineUtc $componentDeadline
    $remote = 'install -d -o devrunner -g devrunner -m 0700 /home/devrunner/.ssh; touch /home/devrunner/.ssh/authorized_keys; key=$(cat /tmp/devfleet-client.pub); grep -qxF "$key" /home/devrunner/.ssh/authorized_keys || echo "$key" >> /home/devrunner/.ssh/authorized_keys; chown devrunner:devrunner /home/devrunner/.ssh/authorized_keys; chmod 0600 /home/devrunner/.ssh/authorized_keys; rm -f /tmp/devfleet-client.pub'
    Invoke-External $mp @('exec',$InstanceName,'--','sudo','bash','-lc',$remote) -DeadlineUtc $componentDeadline
}

function New-DevFleetSnapshotSafe {
    param([Parameter(Mandatory)][string]$InstanceName,[Parameter(Mandatory)][string]$SnapshotName)
    Assert-MultipassIsolation -InstanceNames @($InstanceName)
    $mp = Get-MultipassExe
    $raw = Invoke-External $mp @('info',$InstanceName,'--format','json') -Capture
    $info = $raw | ConvertFrom-Json
    $property = $info.info.PSObject.Properties[$InstanceName]
    if (-not $property) { throw "Multipass instance not found: $InstanceName" }
    $state = [string]$property.Value.state
    $wasRunning = $state -eq 'Running'
    if ($wasRunning) { Invoke-External $mp @('stop',$InstanceName) }
    try { Invoke-External $mp @('snapshot',$InstanceName,'--name',$SnapshotName) }
    finally { if ($wasRunning) { Invoke-External $mp @('start',$InstanceName) } }
    return $SnapshotName
}

Export-ModuleMember -Function *

```


## FILE: source/windows/DevFleet.Tailscale.psm1

SHA256: b64b38830684a097fa8e1e60440f37894ce4b25e765016172ffb6a899bcf6afd | Bytes: 65434 | Git mode: 100644

```
Set-StrictMode -Version Latest
# Reuse Common: forcing a nested reload removes its exports from existing callers.
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1')

function Get-DevFleetTailscaleAuthenticationUri {
    param([string]$Text)
    $uris=@(@(foreach($match in [regex]::Matches($Text,'https?://[^\s<>"'']+')){
        $uri=$null
        if([uri]::TryCreate($match.Value,[UriKind]::Absolute,[ref]$uri)-and$uri.Scheme-ceq'https'-and$uri.Host-ieq'login.tailscale.com'-and$uri.IsDefaultPort-and-not$uri.UserInfo-and$uri.AbsolutePath-match'^/a/[A-Za-z0-9_-]+$'-and-not$uri.Query-and-not$uri.Fragment){$uri.AbsoluteUri}
    })|Sort-Object -Unique)
    if($uris.Count-ne1){return $null}
    return [uri]$uris[0]
}

$script:DevFleetTailscalePairingEventSequence = 0

function ConvertTo-DevFleetTailscaleSafeIdentity {
    param([AllowNull()][object]$Value)
    $text = [string]$Value
    if ($text -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { return $text }
    return ''
}

function Get-DevFleetTailscaleStatusSummary {
    param([string]$StatusJson, [string]$ExpectedHostname)
    $summary = [ordered]@{
        statusClass = 'MALFORMED'
        authenticated = $false
        privateIpv4Observed = $false
        selfHostname = ''
        nodeIdentityMatch = $null
    }
    try {
        $status = $StatusJson | ConvertFrom-Json -ErrorAction Stop
        $backendProperty = $status.PSObject.Properties['BackendState']
        $backend = if ($backendProperty) { [string]$backendProperty.Value } else { '' }
        $selfProperty = $status.PSObject.Properties['Self']
        if ($selfProperty -and $selfProperty.Value) {
            $self = $selfProperty.Value
            $hostProperty = $self.PSObject.Properties['HostName']
            $dnsProperty = $self.PSObject.Properties['DNSName']
            $rawIdentity = if ($hostProperty) { [string]$hostProperty.Value } elseif ($dnsProperty) { [string]$dnsProperty.Value } else { '' }
            $summary.selfHostname = ConvertTo-DevFleetTailscaleSafeIdentity $rawIdentity
            if ($summary.selfHostname) { $summary.nodeIdentityMatch = $summary.selfHostname -ieq $ExpectedHostname }
        }
        if ($backend -ne 'Running') {
            $summary.statusClass = if ($backend) { 'BACKEND_' + (($backend -replace '[^A-Za-z0-9]', '_').ToUpperInvariant()) } else { 'BACKEND_STATE_MISSING' }
            return [pscustomobject]$summary
        }
        $ipProperty = $status.PSObject.Properties['TailscaleIPs']
        foreach ($address in @(if ($ipProperty) { $ipProperty.Value } else { @() })) {
            $parsed = $null
            if ([Net.IPAddress]::TryParse([string]$address, [ref]$parsed) -and $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
                $bytes = $parsed.GetAddressBytes()
                if ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) {
                    $summary.authenticated = $true
                    $summary.privateIpv4Observed = $true
                    $summary.statusClass = 'RUNNING_PRIVATE_IPV4'
                    return [pscustomobject]$summary
                }
            }
        }
        $summary.statusClass = 'RUNNING_NO_PRIVATE_IPV4'
    } catch { }
    return [pscustomobject]$summary
}

function Get-DevFleetTailscalePairingFailureClass {
    param([string]$Message)
    $text = [string]$Message
    if ($text -match '(?i)owning (stage )?deadline|stage time remains') { return 'OWNER_DEADLINE_EXPIRED' }
    if ($text -match '(?i)timed out|timeout') { return 'COMMAND_TIMEOUT' }
    if ($text -match '(?i)unable to start|start external|not found') { return 'COMMAND_START_FAILED' }
    return 'COMMAND_FAILED'
}

function Write-DevFleetTailscalePairingEvent {
    [CmdletBinding()]
    param([string]$Path, [Parameter(Mandatory)][hashtable]$Event)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $parent = Split-Path -Parent $fullPath
        if ([string]::IsNullOrWhiteSpace($parent)) { return }
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $parentItem = Get-Item -LiteralPath $parent -Force -ErrorAction Stop
        if (($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $fileItem = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            if (($fileItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
        }
        $allowed = @(
            'schemaVersion','eventSequence','eventClass','timestampUtc','runId','transactionId','payloadSha256',
            'stage','targetKind','targetRole','instanceName','requestedHostname','ownerDeadlineUtc',
            'ownerProcessId','ownerSessionId','environmentUserInteractive','elevated',
            'command','commandOutcome','commandOutputClass','exitCode','uriValidated','browserLaunchRequested',
            'browserLaunchApiAccepted','browserProcessObserved','browserProcessId','browserProcessSessionId',
            'browserSessionMatchesOwner','browserVisibility','statusClass','authenticated','authenticatedState',
            'authenticatedStateTransition','selfHostname','nodeIdentityMatch','pollCount','lastStatusClass','failureClass',
            'authProvider','expectedTag','enrollmentMode','expectedPeer','servicePort','servicePath','serviceState',
            'authenticationAttempted','authenticationSucceeded','mutation','expectedTagMatch','selfOnline','hasTailscaleIp',
            'blockingHealthError','tailnetLockStatus','tailnetLockObserved','serviceLayer','peerLayer','endpointLayer',
            'credentialAvailable','credentialSource','serviceRecoveryCount','rebootRequired','boundary'
        )
        $record = [ordered]@{}
        foreach ($name in $allowed) {
            if ($Event.ContainsKey($name)) { $record[$name] = ConvertTo-DevFleetTailscaleSafeEvidenceValue -Value $Event[$name] -Name $name }
        }
        $line = ($record | ConvertTo-Json -Compress -Depth 8) + [Environment]::NewLine
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($line)
        $stream = [IO.FileStream]::new($fullPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    } catch { }
}

function Get-DevFleetAuthenticatedTailscaleIPv4 {
    param([string]$StatusJson)
    try {
        $status=$StatusJson|ConvertFrom-Json -ErrorAction Stop
        if([string]$status.BackendState-cne'Running'){return $null}
        foreach($address in @($status.TailscaleIPs)){
            $parsed=$null
            if([Net.IPAddress]::TryParse([string]$address,[ref]$parsed)-and$parsed.AddressFamily-eq[Net.Sockets.AddressFamily]::InterNetwork){
                $bytes=$parsed.GetAddressBytes()
                if($bytes[0]-eq100-and$bytes[1]-ge64-and$bytes[1]-le127){return $parsed.ToString()}
            }
        }
    } catch {}
    return $null
}

function Get-DevFleetTailscaleOAuthSecretPath {
    Join-Path (Join-Path (Get-DevFleetStateRoot) 'secrets') 'tailscale-oauth-client.secret'
}

function Get-DevFleetTailscaleEnrollmentProfilePath {
    Join-Path (Join-Path (Get-DevFleetStateRoot) 'secrets') 'tailscale-enrollment-profile.json'
}

function ConvertTo-DevFleetTailscaleSafeOutput {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    if ([string]::IsNullOrEmpty($text)) { return '' }
    # Keep command diagnostics useful without allowing a caller to leak a
    # forgotten bearer, OAuth, auth-key, or API credential into evidence.
    $text = [regex]::Replace($text, '(?i)tskey-[A-Za-z0-9._~+/=-]+', '<redacted-tskey>')
    $text = [regex]::Replace($text, '(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+', '$1<redacted-token>')
    $text = [regex]::Replace($text, '(?i)(\b(?:oauth|client-secret|client_secret|access-token|access_token|api-token|api_token|auth-key|auth_key|token|secret)\b\s*[:=]\s*)[^\s,;]+', '$1<redacted-secret>')
    return $text
}

function ConvertTo-DevFleetTailscaleSafeEvidenceValue {
    param([AllowNull()][object]$Value,[int]$Depth=0,[string]$Name='')
    if ($Depth -gt 4) { return '<redacted-depth>' }
    if ($Name -match '(?i)(?:secret|password|token|auth.?key|authorization|bearer|credential)') { return '<redacted-secret>' }
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return ConvertTo-DevFleetTailscaleSafeOutput $Value }
    if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $record=[ordered]@{}
        foreach($key in $Value.Keys){$record[[string]$key]=ConvertTo-DevFleetTailscaleSafeEvidenceValue -Value $Value[$key] -Depth ($Depth+1) -Name ([string]$key)}
        return $record
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { ConvertTo-DevFleetTailscaleSafeEvidenceValue -Value $_ -Depth ($Depth+1) -Name $Name })
    }
    $properties=@($Value.PSObject.Properties)
    if ($properties.Count -gt 0) {
        $record=[ordered]@{}
        foreach($property in $properties){$record[[string]$property.Name]=ConvertTo-DevFleetTailscaleSafeEvidenceValue -Value $property.Value -Depth ($Depth+1) -Name ([string]$property.Name)}
        return $record
    }
    return ConvertTo-DevFleetTailscaleSafeOutput $Value
}

function Set-DevFleetTailscaleProtectedFileAcl {
    param([Parameter(Mandatory)][string]$Path)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $security = [Security.AccessControl.FileSecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    $security.SetOwner($identity)
    foreach ($rule in @(
        [Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators','FullControl','Allow'),
        [Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM','FullControl','Allow'),
        [Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','Allow')
    )) { $security.AddAccessRule($rule) | Out-Null }
    Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
}

function Set-DevFleetTailscaleOAuthClientSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory)][securestring]$Secret)
    $path = Get-DevFleetTailscaleOAuthSecretPath
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $bstr = [IntPtr]::Zero
    $plain = $null
    $temporary = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        if ([string]::IsNullOrWhiteSpace($plain) -or $plain.IndexOfAny([char[]]"`0`r`n") -ge 0 -or $plain.Length -gt 2048) { throw 'Tailscale OAuth client secret is empty or malformed.' }
        # Create and ACL the temporary file before writing credential bytes.
        [IO.File]::WriteAllText($temporary, '', [Text.UTF8Encoding]::new($false))
        Set-DevFleetTailscaleProtectedFileAcl -Path $temporary
        [IO.File]::WriteAllText($temporary, $plain + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $path -Force
        Set-DevFleetTailscaleProtectedFileAcl -Path $path
        Protect-DevFleetStateAcl
        return $path
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $plain = $null
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Get-DevFleetTailscaleOAuthClientSecret {
    $path = Get-DevFleetTailscaleOAuthSecretPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'TAILSCALE_CREDENTIAL_INVALID: OAuth credential path is a reparse point.' }
    $value = (Get-Content -LiteralPath $path -Raw -ErrorAction Stop).Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or $value.IndexOfAny([char[]]"`0`r`n") -ge 0 -or $value.Length -gt 2048) { throw 'TAILSCALE_CREDENTIAL_INVALID: OAuth client secret file is malformed.' }
    return $value
}

function Get-DevFleetTailscaleEnrollmentProfile {
    param([string]$Path='')
    $default = [ordered]@{ mode='persistent'; tag='tag:devfleet'; ephemeral=$false; preauthorized=$true; hostName=''; guestHostnames=@{} }
    $path = if($Path){$Path}else{Get-DevFleetTailscaleEnrollmentProfilePath}
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]$default }
    try {
        $value = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $mode = [string]$value.mode
        $tag = [string]$value.tag
        if ($mode -notin @('persistent','e2e') -or $tag -notin @('tag:devfleet','tag:devfleet-e2e')) { throw 'profile mode or tag is not allowlisted' }
        $ephemeral = [bool]$value.ephemeral
        $preauthorized = [bool]$value.preauthorized
        if ($mode -eq 'e2e' -and (-not $ephemeral -or $tag -cne 'tag:devfleet-e2e')) { throw 'E2E profile must be ephemeral and use tag:devfleet-e2e' }
        if ($mode -eq 'persistent' -and ($ephemeral -or $tag -cne 'tag:devfleet')) { throw 'persistent profile must be non-ephemeral and use tag:devfleet' }
        $hostName = [string]$value.hostName
        if ($hostName -and $hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$') { throw 'profile hostName is malformed' }
        $guestHostnames = @{}
        if ($value.PSObject.Properties['guestHostnames'] -and $value.guestHostnames) {
            foreach ($property in @($value.guestHostnames.PSObject.Properties)) {
                if ([string]$property.Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$' -or [string]$property.Value -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$') { throw 'profile guest hostname is malformed' }
                $guestHostnames[[string]$property.Name] = [string]$property.Value
            }
        }
        return [pscustomobject][ordered]@{ mode=$mode; tag=$tag; ephemeral=$ephemeral; preauthorized=$preauthorized; hostName=$hostName; guestHostnames=$guestHostnames }
    } catch { throw "TAILSCALE_CREDENTIAL_INVALID: enrollment profile is invalid: $($_.Exception.Message)" }
}

function Resolve-DevFleetTailscaleProfileHostname {
    param([Parameter(Mandatory)][psobject]$Profile,[Parameter(Mandatory)][string]$RequestedHostname,[string]$InstanceName)
    $hostname = $RequestedHostname
    $hostNameProperty = $Profile.PSObject.Properties['hostName']
    $guestHostnamesProperty = $Profile.PSObject.Properties['guestHostnames']
    $profileHostName = if ($hostNameProperty) { [string]$hostNameProperty.Value } else { '' }
    $guestHostnames = if ($guestHostnamesProperty) { $guestHostnamesProperty.Value } else { $null }
    if ([string]$Profile.mode -ceq 'e2e') {
        if (-not $InstanceName -and $profileHostName) { $hostname = $profileHostName }
        elseif ($InstanceName -and $guestHostnames) {
            $mapped = $null
            if ($guestHostnames -is [hashtable]) {
                if ($guestHostnames.ContainsKey($InstanceName)) { $mapped = $guestHostnames[$InstanceName] }
            } else {
                $property = $guestHostnames.PSObject.Properties[$InstanceName]
                if ($property) { $mapped = $property.Value }
            }
            if ($null -ne $mapped -and [string]$mapped) { $hostname = [string]$mapped }
        }
    }
    return $hostname
}

function Get-DevFleetTailscaleEnrollmentOptions {
    param([Parameter(Mandatory)][string]$RequestedHostname,[string]$InstanceName,[string]$TargetRole)
    $profile = Get-DevFleetTailscaleEnrollmentProfile
    $hostname = Resolve-DevFleetTailscaleProfileHostname -Profile $profile -RequestedHostname $RequestedHostname -InstanceName $InstanceName
    if ($hostname -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$') { throw 'TAILSCALE_CREDENTIAL_INVALID: resolved Tailscale hostname is malformed.' }
    $credential = $null
    try { $credential = Get-DevFleetTailscaleOAuthClientSecret } catch { throw }
    if ([string]::IsNullOrWhiteSpace($credential)) { throw 'TAILSCALE_CREDENTIAL_MISSING: configure the protected Tailscale OAuth client secret before authentication.' }
    [pscustomobject][ordered]@{
        mode=[string]$profile.mode; tag=[string]$profile.tag; ephemeral=[bool]$profile.ephemeral; preauthorized=[bool]$profile.preauthorized
        hostname=$hostname; targetRole=if($TargetRole){$TargetRole}else{''}; instanceName=if($InstanceName){$InstanceName}else{''}; secret=$credential
        credentialSource='protected-local-file'
    }
}

function Get-DevFleetTailscaleReadiness {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StatusJson,[Parameter(Mandatory)][string]$ExpectedHostname,[string]$ExpectedTag,[string]$PreferencesJson)
    $result = [ordered]@{
        schemaVersion=1; ready=$false; statusClass='MALFORMED'; failureClass='TAILSCALE_HEALTH_ERROR'; backendState=''; authenticated=$false; selfOnline=$false
        hasTailscaleIp=$false; tailscaleIpv4=''; selfHostname=''; nodeIdentityMatch=$null; expectedTag=if($ExpectedTag){$ExpectedTag}else{''}; tags=@(); expectedTagMatch=$null
        blockingHealthError=$false; preferenceObserved=$false; serviceLayer='NOT_CHECKED'; peerLayer='NOT_CHECKED'; endpointLayer='NOT_CHECKED'
    }
    try {
        $status = $StatusJson | ConvertFrom-Json -ErrorAction Stop
        $result.backendState = [string]$status.BackendState
        $self = $status.Self
        if ($self) {
            $rawName = if ($self.PSObject.Properties['HostName']) { [string]$self.HostName } elseif ($self.PSObject.Properties['DNSName']) { [string]$self.DNSName } else { '' }
            $result.selfHostname = ConvertTo-DevFleetTailscaleSafeIdentity $rawName
            $result.selfOnline = if ($self.PSObject.Properties['Online']) { [bool]$self.Online } else { $false }
            if ($result.selfHostname) { $result.nodeIdentityMatch = $result.selfHostname -ieq $ExpectedHostname }
            if ($self.PSObject.Properties['Tags'] -and $self.Tags) { $result.tags=@($self.Tags | ForEach-Object { ConvertTo-DevFleetTailscaleSafeOutput $_ } | Where-Object { $_ }) }
        }
        if ($PreferencesJson) {
            try {
                $preferences=$PreferencesJson|ConvertFrom-Json -ErrorAction Stop
                if ($preferences.PSObject.Properties['AdvertiseTags']) {
                    $result.preferenceObserved=$true
                    $result.tags=@($preferences.AdvertiseTags | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^tag:[A-Za-z0-9][A-Za-z0-9_-]*$' })
                }
            } catch { }
        }
        $health = @()
        if ($status.PSObject.Properties['Health'] -and $status.Health) { $health=@($status.Health | ForEach-Object { [string]$_ } | Where-Object { $_ -and $_ -notmatch '^(?i)ok$' }) }
        $result.blockingHealthError = $health.Count -gt 0
        foreach ($address in @($status.TailscaleIPs)) {
            $parsed=$null
            if ([Net.IPAddress]::TryParse([string]$address,[ref]$parsed) -and $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
                $bytes=$parsed.GetAddressBytes()
                if ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) { $result.hasTailscaleIp=$true; $result.tailscaleIpv4=$parsed.ToString(); break }
            }
        }
        $result.authenticated = $result.backendState -eq 'Running' -and $result.selfOnline -and $result.hasTailscaleIp
        if ($ExpectedTag) { $result.expectedTagMatch = $result.tags -contains $ExpectedTag }
        if ($result.backendState -in @('NeedsLogin','NoState')) { $result.statusClass='NEEDS_LOGIN';$result.failureClass='TAILSCALE_NEEDS_LOGIN' }
        elseif (-not $result.backendState -or $result.backendState -in @('Stopped','Starting','Stopping')) { $result.statusClass='CONTROL_PLANE_OFFLINE';$result.failureClass='TAILSCALE_CONTROL_PLANE_OFFLINE' }
        elseif ($result.blockingHealthError) { $result.statusClass='HEALTH_ERROR';$result.failureClass='TAILSCALE_HEALTH_ERROR' }
        elseif (-not $result.hasTailscaleIp) { $result.statusClass='NO_IP';$result.failureClass='TAILSCALE_NO_IP' }
        elseif (-not $result.selfOnline) { $result.statusClass='OFFLINE';$result.failureClass='TAILSCALE_CONTROL_PLANE_OFFLINE' }
        elseif ($result.nodeIdentityMatch -ne $true) { $result.statusClass='WRONG_IDENTITY';$result.failureClass='TAILSCALE_WRONG_TAG' }
        elseif ($ExpectedTag -and $result.expectedTagMatch -ne $true) { $result.statusClass='WRONG_TAG';$result.failureClass='TAILSCALE_WRONG_TAG' }
        else { $result.statusClass='READY';$result.failureClass='';$result.ready=$true }
    } catch { $result.statusClass='MALFORMED';$result.failureClass='TAILSCALE_HEALTH_ERROR' }
    [pscustomobject]$result
}

function Invoke-DevFleetTailscalePeerAndEndpointReadiness {
    param(
        [Parameter(Mandatory)][psobject]$Readiness,
        [string]$ExpectedPeer,
        [int]$ServicePort,
        [string]$ServicePath,
        [Parameter(Mandatory)][scriptblock]$TailscaleInvoker,
        [string]$FilePath,
        [string]$InstanceName,
        [scriptblock]$EndpointInvoker,
        [datetime]$DeadlineUtc=[datetime]::UtcNow.AddSeconds(30)
    )
    if ($ExpectedPeer) {
        # Reobserve transient peer convergence inside the original ten-second
        # command budget. Neither retries nor backoff extend the owner deadline
        # or consume its existing five-second terminalization reserve.
        $peerDeadlineUtc=[datetime]::UtcNow.AddSeconds(10)
        $ownerPeerDeadlineUtc=$DeadlineUtc.ToUniversalTime().AddSeconds(-5)
        if ($ownerPeerDeadlineUtc -lt $peerDeadlineUtc) { $peerDeadlineUtc=$ownerPeerDeadlineUtc }
        $Readiness.peerLayer='FAIL';$Readiness.endpointLayer=if($ServicePort){'BLOCKED_BY_PEER'}else{'NOT_CONFIGURED'};$Readiness.failureClass='TAILSCALE_PEER_UNREACHABLE';$Readiness.ready=$false
        for ($peerAttempt=1; $peerAttempt -le 3; $peerAttempt++) {
            $remaining=[int][math]::Floor(($peerDeadlineUtc-[datetime]::UtcNow).TotalSeconds)
            if ($remaining -le 0) { break }
            $pingSeconds=[math]::Min(5,$remaining)
            $peerResult = & $TailscaleInvoker @('ping','--tsmp','--c=1',("--timeout=${pingSeconds}s"),'--until-direct=false',$ExpectedPeer) $remaining
            if ($peerResult -is [string]) { $peerResult=[pscustomobject]@{exitCode=0;output=[string]$peerResult} }
            $peerOutput=ConvertTo-DevFleetTailscaleSafeOutput ([string]$peerResult.output)
            if ([int]$peerResult.exitCode -eq 0) {
                if ([datetime]::UtcNow -le $peerDeadlineUtc) { $Readiness.peerLayer='PASS' }
                break
            }
            if ($peerOutput -match '(?i)acl|denied|not permitted') { $Readiness.failureClass='TAILSCALE_ACL_BLOCKED';break }
            if ([int]$peerResult.exitCode -eq 124 -or $peerAttempt -ge 3) { break }
            $remainingMilliseconds=[math]::Floor(($peerDeadlineUtc-[datetime]::UtcNow).TotalMilliseconds)
            if ($remainingMilliseconds -le 1000) { break }
            Start-Sleep -Milliseconds ([int][math]::Min(1000,($remainingMilliseconds-1000)))
        }
        if ($Readiness.peerLayer -ne 'PASS') { return $Readiness }
    } elseif ($ServicePort) {
        $Readiness.peerLayer='BLOCKED_NO_PEER';$Readiness.endpointLayer='BLOCKED_NO_PEER';$Readiness.failureClass='DEVFLEET_SERVICE_UNREACHABLE_OVER_TAILSCALE';$Readiness.ready=$false;return $Readiness
    }
    if ($ServicePort) {
        $uri="http://${ExpectedPeer}:$ServicePort$ServicePath"
        $endpointResult=$null
        if ($EndpointInvoker) {
            $endpointResult=& $EndpointInvoker $ExpectedPeer $ServicePort $ServicePath
            if ($endpointResult -is [string]) { $endpointResult=[pscustomobject]@{exitCode=0;output=[string]$endpointResult} }
        } elseif ($InstanceName) {
            $remaining=[int][math]::Floor(($DeadlineUtc.ToUniversalTime()-[datetime]::UtcNow).TotalSeconds)-2
            if ($remaining -le 0) { $endpointResult=[pscustomobject]@{exitCode=124;output='owner deadline expired'} }
            else {
                try {$output=Invoke-External -FilePath $FilePath -ArgumentList @('exec',$InstanceName,'--','curl','--fail','--silent','--show-error','--max-time','10',$uri) -Capture -AllowedExitCodes @(0) -TimeoutSeconds ([math]::Min(10,$remaining)) -DeadlineUtc $DeadlineUtc;$endpointResult=[pscustomobject]@{exitCode