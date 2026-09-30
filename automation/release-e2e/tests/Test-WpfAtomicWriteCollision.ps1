[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    Write-Host 'SKIP Windows WPF atomic-write contention fixture'
    return
}

$modulePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/executors/Invoke-RealProductPhase.psm1'
$tokens=$null
$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$tokens,[ref]$parseErrors)
$writers=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Write-Atomic'
},$true))
if($parseErrors.Count -ne 0 -or $writers.Count -ne 1){throw 'Exact WPF atomic writer could not be identified.'}
. ([scriptblock]::Create($writers[0].Extent.Text))

$scratch=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-wpf-atomic-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$destination=Join-Path $scratch 'launch-request.json'
[IO.File]::WriteAllText($destination,'{"version":"old"}',[Text.UTF8Encoding]::new($false))
$held=$null
try {
    $held=[IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $threw=$false
    try {
        & { $ErrorActionPreference='Continue'; Write-Atomic -Path $destination -Value @{version='new'} }
    } catch {
        $threw=$true
    }
    if(-not $threw){throw 'Locked WPF launch request was reported as successfully replaced.'}
    if(([IO.File]::ReadAllText($destination)) -cne '{"version":"old"}'){
        throw 'Locked WPF launch request changed despite the failed replacement.'
    }
    if(@(Get-ChildItem -LiteralPath $scratch -Filter '*.tmp').Count){
        throw 'Failed WPF replacement left an owned temporary file.'
    }
    $held.Dispose()
    $held=$null
    Write-Atomic -Path $destination -Value @{version='new'}
    $value=Get-Content -LiteralPath $destination -Raw | ConvertFrom-Json
    if($value.version -cne 'new'){throw 'Normal WPF launch request replacement failed.'}
    Write-Host 'PASS WPF atomic move collision throws; normal replacement succeeds'
} finally {
    if($held){$held.Dispose()}
    $resolved=[IO.Path]::GetFullPath($scratch)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
       (Split-Path -Leaf $resolved) -notmatch '^devfleet-wpf-atomic-[a-f0-9]{32}$'){
        throw 'WPF fixture cleanup path rejected.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
