[CmdletBinding()]
param([string]$PythonPath='python.exe',[string]$FixtureRoot,[string]$ReportPath)
$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if(-not$FixtureRoot){
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $root=Join-Path $parent ('devfleet-maintenance-runtime-'+[guid]::NewGuid().ToString('N'))
    $server=$null
    try{
        New-Item -ItemType Directory -Path (Join-Path $root 'DevFleetHostAgent'),(Join-Path $root 'M-TechLabs/DevFleet/Installer')|Out-Null
        [IO.File]::SetAttributes($root,([IO.File]::GetAttributes($root)-bor[IO.FileAttributes]::Hidden))
        foreach($name in @('DevFleet-HostAgentProtocol.psm1','DevFleet-WindowsIntegrationOwnership.psm1')){Copy-Item -LiteralPath (Join-Path $repo ('source/windows/'+$name)) -Destination (Join-Path $root ('DevFleetHostAgent/'+$name))}
        [IO.File]::WriteAllText((Join-Path $root 'DevFleetHostAgent/token.txt'),('x'*48))
        [IO.File]::WriteAllText((Join-Path $root 'case.txt'),'healthy')
        $generation=[guid]::NewGuid().ToString()
        $service=@{Name='FixtureService';ImagePath='C:\Fixture\service.exe';Account='LocalSystem';StartMode='Auto';Marker='fixture-owned';Generation=$generation}
        $ownership=@{SchemaVersion=1;InstallationGeneration=$generation;ScheduledTasks=@();FirewallRules=@();Services=@($service)}
        $install=@{DevFleetVersion='1.2.13';InstallerVersion='1.4.1';PackageSha256=('b'*64);WindowsIntegrationOwnershipPath=(Join-Path $root 'DevFleetHostAgent/integration-ownership.json');InstallationGeneration=$generation}
        $ownership|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'DevFleetHostAgent/integration-ownership.json')
        $install|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'M-TechLabs/DevFleet/Installer/install-state.json')
        @{Name=$service.Name;PathName=$service.ImagePath;StartName=$service.Account;StartMode=$service.StartMode}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'service.json')
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=(Get-Command $PythonPath).Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
        foreach($arg in @((Join-Path $PSScriptRoot 'fixtures/host-health-server.py'),$root)){[void]$psi.ArgumentList.Add($arg)}
        $server=[Diagnostics.Process]::Start($psi);$until=[datetime]::UtcNow.AddSeconds(10)
        while(-not(Test-Path -LiteralPath (Join-Path $root 'port.txt'))-and[datetime]::UtcNow-lt$until-and-not$server.HasExited){Start-Sleep -Milliseconds 100}
        if(-not(Test-Path -LiteralPath (Join-Path $root 'port.txt'))){throw 'Owned maintenance fixture server did not become ready.'}
        $reports=@()
        foreach($engine in @('powershell.exe','pwsh.exe')){
            $output=Join-Path $root ($engine+'.json')
            & $engine -NoProfile -File $PSCommandPath -FixtureRoot $root -ReportPath $output
            $code=$LASTEXITCODE
            if(Test-Path -LiteralPath $output){$reports+=Get-Content -Raw -LiteralPath $output|ConvertFrom-Json}
            if($ReportPath){$reports|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $ReportPath}
            if($code-ne0){throw "Maintenance runtime checks failed under $engine."}
        }
        Write-Host "PASS $(($reports|Measure-Object passed -Sum).Sum)/$(($reports|Measure-Object total -Sum).Sum) maintenance runtime checks"
    }finally{
        if($server){if(-not$server.HasExited){$server.Kill();[void]$server.WaitForExit(5000)};$server.Dispose()}
        $resolved=[IO.Path]::GetFullPath($root)
        if([IO.Path]::GetDirectoryName($resolved)-cne$parent-or[IO.Path]::GetFileName($resolved)-notmatch'^devfleet-maintenance-runtime-[0-9a-f]{32}$'){throw 'Fixture cleanup escaped its owner.'}
        if(Test-Path -LiteralPath $resolved){if((Get-Item -LiteralPath $resolved -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Fixture root reparse refused.'};Remove-Item -LiteralPath $resolved -Recurse -Force}
    }
    return
}
Import-Module (Join-Path $repo 'automation/release-e2e/modules/FullRelease.psm1') -Force -DisableNameChecking
$module=Get-Module FullRelease
& $module {
    param($Root)
    $script:FixtureRoot=$Root;$script:FixtureCase='';$script:FixtureOpened=0;$script:FixtureClosed=0;$script:FixtureCalls=0
    function script:Connect-DevFleetGuest {param($VmId)$script:FixtureOpened++;return [pscustomobject]@{Runspace=@{ConnectionInfo=@{VMGuid=$VmId}}}}
    function script:Remove-DevFleetGuestSession {param($Session)$script:FixtureClosed++}
    function script:Invoke-DevFleetBoundedGuestProcess {
        param($Session,$FilePath,$ArgumentList,$OwnerDeadlineUtc)
        $script:FixtureCalls++;$script:FixtureBudget=($OwnerDeadlineUtc-[datetime]::UtcNow).TotalSeconds
        if($FilePath-cne'C:\Program Files\PowerShell\7\pwsh.exe'-or$ArgumentList.Count-ne4-or$ArgumentList[2]-cne'-EncodedCommand'){throw 'PS7 encoded launch contract differs.'}
        $body=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[3]))
        if($body.Contains('x'*48)){throw 'Synthetic secret escaped into process arguments.'}
        $body=$body.Replace('C:\ProgramData',$script:FixtureRoot).Replace('http://127.0.0.1:8790/healthz',('http://127.0.0.1:'+(Get-Content (Join-Path $script:FixtureRoot 'port.txt'))+'/healthz'))
        $prefix='$env:ProgramData='''+$script:FixtureRoot.Replace("'","''")+''';function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) Get-Content -Raw -LiteralPath (Join-Path $env:ProgramData ''service.json'')|ConvertFrom-Json};'
        $arguments=@('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prefix+$body)))
        $json=@{filePath=$FilePath;arguments=$arguments;deadlineUnixMilliseconds=([DateTimeOffset]$OwnerDeadlineUtc).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress
        $raw=& (Get-DevFleetBoundedProcessScriptBlock) $json
        if($script:FixtureCase-eq'incomplete'){$raw.outputComplete=$false}
        if($script:FixtureCase-eq'late'){Start-Sleep -Milliseconds ([int][math]::Max(1,($OwnerDeadlineUtc-[datetime]::UtcNow).TotalMilliseconds+20))}
        if($script:FixtureCase-eq'old-runtime'){$value=$raw.stdout|ConvertFrom-Json;$value.runtimeVersion='5.1';$raw.stdout=$value|ConvertTo-Json -Depth 8 -Compress}
        if($script:FixtureCase-eq'forged-boolean'){$value=$raw.stdout|ConvertFrom-Json;$value.hostAgentHealth.authenticated='true';$raw.stdout=$value|ConvertTo-Json -Depth 8 -Compress}
        return $raw
    }
} $FixtureRoot
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$results.Add([pscustomobject]@{case=$Name;pass=$Pass})}
$installPath=Join-Path $FixtureRoot 'M-TechLabs/DevFleet/Installer/install-state.json'
$ownershipPath=Join-Path $FixtureRoot 'DevFleetHostAgent/integration-ownership.json'
$protocolPath=Join-Path $FixtureRoot 'DevFleetHostAgent/DevFleet-HostAgentProtocol.psm1'
$originalInstall=[IO.File]::ReadAllBytes($installPath);$originalOwnership=[IO.File]::ReadAllBytes($ownershipPath);$originalProtocol=[IO.File]::ReadAllBytes($protocolPath)
foreach($case in @('healthy','owned-session','wrong-session','bad-signature','wrong-host','unauthorized','not-ok','string-health','wrong-payload','wrong-ownership','wrong-protocol','incomplete','old-runtime','forged-boolean','expired','late')){
    [IO.File]::WriteAllBytes($installPath,$originalInstall);[IO.File]::WriteAllBytes($ownershipPath,$originalOwnership);[IO.File]::WriteAllBytes($protocolPath,$originalProtocol)
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'case.txt'),$(if($case-in@('bad-signature','wrong-host','unauthorized','not-ok','string-health')){$case}else{'healthy'}))
    if($case-eq'wrong-payload'){$v=Get-Content -Raw $installPath|ConvertFrom-Json;$v.PackageSha256='a'*64;$v|ConvertTo-Json|Set-Content -LiteralPath $installPath}
    if($case-eq'wrong-ownership'){$v=Get-Content -Raw $ownershipPath|ConvertFrom-Json;$v.InstallationGeneration=[guid]::NewGuid().ToString();$v|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ownershipPath}
    if($case-eq'wrong-protocol'){Add-Content -LiteralPath $protocolPath -Value '# fixture mismatch'}
    $observed=& $module {
        param($Case)
        $script:FixtureCase=$Case;$opened=$script:FixtureOpened;$closed=$script:FixtureClosed;$calls=$script:FixtureCalls
        $deadline=[datetime]::UtcNow.AddSeconds($(if($Case-eq'expired'){-1}elseif($Case-eq'late'){11.5}else{100}))
        $args=@{VmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';Fingerprint=[pscustomobject]@{releaseVersion='1.2.13';installerVersion='1.4.1';tar=@{sha256=('b'*64)}};OwnerDeadlineUtc=$deadline}
        if($Case-ne'owned-session'){$args.Session=[pscustomobject]@{Runspace=@{ConnectionInfo=@{VMGuid=$(if($Case-eq'wrong-session'){[guid]::NewGuid()}else{$args.VmId})}}}}
        $value=$null;$errorText=''
        try{$value=Invoke-MaintenanceReadyGuestValidation @args}catch{$errorText=$_.Exception.Message}
        [pscustomobject]@{value=$value;error=$errorText;opened=$script:FixtureOpened-$opened;closed=$script:FixtureClosed-$closed;calls=$script:FixtureCalls-$calls;budget=$script:FixtureBudget}
    } $case
    $expectedPass=$case-in@('healthy','owned-session')
    $pass=if($expectedPass){$observed.value.status-eq'PASS'-and$observed.value.runtimeVersion-like'7.*'-and$observed.value.hostAgentHealth.authenticated}else{-not$observed.value-and[bool]$observed.error}
    if($case-eq'owned-session'){$pass=$pass-and$observed.opened-eq1-and$observed.closed-eq1}else{$pass=$pass-and$observed.opened-eq0-and$observed.closed-eq0}
    if($case-in@('expired','wrong-session')){$pass=$pass-and$observed.calls-eq0}
    $pass=$pass-and($observed|ConvertTo-Json -Depth 8)-notmatch('x'*48)
    Check $case $pass
    if(-not$pass){Write-Host ($case+': '+$observed.error)}
}
[IO.File]::WriteAllBytes($installPath,$originalInstall);[IO.File]::WriteAllBytes($ownershipPath,$originalOwnership);[IO.File]::WriteAllBytes($protocolPath,$originalProtocol)
$report=@{parentPowerShellVersion=$PSVersionTable.PSVersion.ToString();actualSecretUsed=$false;vmOperations=0;passed=@($results|Where-Object pass).Count;total=$results.Count;cases=@($results)}
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath
Write-Host "PS $($report.parentPowerShellVersion): $($report.passed)/$($report.total) maintenance runtime checks"
if($report.passed-ne$report.total){$results|Where-Object{-not$_.pass}|Format-Table;exit 1}
