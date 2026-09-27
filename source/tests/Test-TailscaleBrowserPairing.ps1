$ErrorActionPreference='Stop'
$WarningPreference='SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot '../windows/DevFleet.Tailscale.psm1') -Force
$module=Get-Module DevFleet.Tailscale
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$results.Add([pscustomobject]@{case=$Name;pass=$Pass})}
foreach($item in @(
    @('https://login.tailscale.com/a/fixture123',$true),
    @('http://login.tailscale.com/a/fixture123',$false),
    @('https://login.tailscale.com.evil.example/a/fixture123',$false),
    @('https://evil.example/?https://login.tailscale.com/a/fixture123',$false),
    @('https://evil@login.tailscale.com/a/fixture123',$false),
    @('https://login.tailscale.com:8443/a/fixture123',$false),
    @('https://login.tailscale.com/a/fixture123?redirect=evil',$false),
    @('https://login.tailscale.com/a/fixture123#evil',$false),
    @('https://login.tailscale.com/a/one https://login.tailscale.com/a/two',$false),
    @('https://login.tailscale.com/a/fixture123 https://login.tailscale.com/a/fixture123',$true)
)){
    $uri=&$module {param($s)Get-DevFleetTailscaleAuthenticationUri $s} $item[0]
    Check ('official browser URL case '+$results.Count) ([bool]$uri-eq$item[1])
}
foreach($item in @(@('Running','100.64.1.2',$true),@('NeedsLogin','100.64.1.2',$false),@('Running','192.168.1.2',$false),@('Running','100.1.1.2',$false),@('Running','100.128.1.2',$false),@('Running','fd7a:115c:a1e0::1',$false))){
    $ip=&$module {param($s,$ip)Get-DevFleetAuthenticatedTailscaleIPv4 (@{BackendState=$s;TailscaleIPs=@($ip)}|ConvertTo-Json -Compress)} $item[0] $item[1]
    Check ('authenticated private IPv4 '+$item[0]+'/'+$item[1]) ([bool]$ip-eq$item[2])
}
&$module {
    function script:Get-DevFleetDeadlineContext {return $script:PairingFixtureContext}
    function script:Open-DevFleetTailscaleAuthenticationPage {param($Uri)$script:PairingFixtureOpened++;if($Uri.AbsoluteUri-cne'https://login.tailscale.com/a/fixture123'){throw 'Unexpected browser target.'}}
    function script:Start-Sleep {param($Milliseconds)}
    function script:Invoke-External {
        param($FilePath,$ArgumentList,[switch]$Capture,[switch]$IgnoreExitCode,$TimeoutSeconds,$DeadlineUtc)
        if(-not$Capture-or-not$IgnoreExitCode-or$TimeoutSeconds-gt35-or$DeadlineUtc-gt$script:PairingFixtureDeadline){throw 'Native command lost its bounded capture contract.'}
        $script:PairingFixtureCalls.Add([pscustomobject]@{path=$FilePath;args=@($ArgumentList);timeout=$TimeoutSeconds})
        if($ArgumentList-contains'up'){
            $script:PairingFixtureUp++
            if($ArgumentList-notcontains'--timeout=30s'-or$ArgumentList-notcontains'--accept-dns=false'-or$ArgumentList-contains'--auth-key'){throw 'Unexpected authentication authority.'}
            if($script:PairingFixtureCase-eq'bad-url'){return 'https://evil.example/a/fake'}
            return 'To authenticate, visit: https://login.tailscale.com/a/fixture123'
        }
        if($ArgumentList-notcontains'--json'){throw 'Status request arguments were lost.'}
        if($script:PairingFixtureCase-eq'malformed'){return 'malformed status'}
        $connected=$script:PairingFixtureCase-eq'already-connected'-or$script:PairingFixtureOpened-gt0
        return (@{BackendState=if($connected){'Running'}else{'NeedsLogin'};TailscaleIPs=if($connected){@('100.64.1.2')}else{@()}}|ConvertTo-Json -Compress)
    }
}
foreach($target in @('windows','guest')){
    foreach($case in @('already-connected','browser-required','bad-url','deadline-exhausted','parent-deadline')){
        $v=&$module {
            param($Case,$Target)
            $script:PairingFixtureCase=$Case;$script:PairingFixtureOpened=0;$script:PairingFixtureUp=0;$script:PairingFixtureCalls=[Collections.Generic.List[object]]::new();$script:PairingFixtureContext=$null
            $script:PairingFixtureDeadline=[datetime]::UtcNow.AddSeconds($(if($Case-eq'deadline-exhausted'){3}else{60}))
            if($Case-eq'parent-deadline'){$script:PairingFixtureContext=[pscustomobject]@{StageDeadlineUtc=[datetime]::UtcNow.AddSeconds(3)}}
            $parameters=@{FilePath=if($Target-eq'guest'){'multipass-fixture.exe'}else{'tailscale-fixture.exe'};Hostname='devfleet-fixture';DeadlineUtc=$script:PairingFixtureDeadline}
            if($Target-eq'guest'){$parameters.InstanceName='devfleet-vault'}
            $result=$null;$failed=$false
            try{$result=Invoke-DevFleetTailscaleBrowserPairing @parameters}catch{$failed=$true}
            [pscustomobject]@{result=$result;failed=$failed;calls=@($script:PairingFixtureCalls);up=$script:PairingFixtureUp;opened=$script:PairingFixtureOpened}
        } $case $target
        $pass=switch($case){
            'already-connected' {-not$v.failed-and$v.result.authenticated-and$v.up-eq0-and$v.opened-eq0}
            'browser-required' {-not$v.failed-and$v.result.authenticated-and$v.up-eq1-and$v.opened-eq1}
            'bad-url' {$v.failed-and$v.up-eq1-and$v.opened-eq0}
            default {$v.failed-and$v.calls.Count-eq0-and$v.opened-eq0}
        }
        if($target-eq'guest'-and$v.calls.Count){$pass=$pass-and($v.calls[0].args[0..4]-join' ')-ceq'exec devfleet-vault -- sudo tailscale'}
        Check ($target+' '+$case) $pass
    }
}
$results|ConvertTo-Json -Depth 4
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Browser pairing qualification failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) browser pairing checks; no browser, network or VM operations performed."
