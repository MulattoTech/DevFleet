[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    Write-Host 'SKIP Windows file replacement contention fixture'
    return
}

$modulePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/Evidence.psm1'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-evidence-atomic-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$destination=Join-Path $scratch 'current.json'
[IO.File]::WriteAllText($destination,'{"version":"old"}',[Text.UTF8Encoding]::new($false))
$job=$null
$held=$null
try {
    # A reader that does not grant delete sharing prevents replacement on Windows.
    $held=[IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $job=Start-Job -ScriptBlock {
        param($module,$path)
        $ErrorActionPreference='Continue'
        Import-Module $module -Force
        try {
            Write-EvidenceJson -Path $path -Value @{version='new'}
            [pscustomobject]@{status='RETURNED'}
        } catch {
            [pscustomobject]@{status='THREW';errorId=$_.FullyQualifiedErrorId}
        }
    } -ArgumentList $modulePath,$destination
    if(-not (Wait-Job -Job $job -Timeout 20)){
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        throw 'Evidence writer fixture exceeded its finite job deadline.'
    }
    $output=@(Receive-Job -Job $job -ErrorAction SilentlyContinue)
    if($output.Count -ne 1 -or $output[0].status -cne 'THREW'){
        throw 'A failed move escaped the writer catch or was reported as a successful write.'
    }
    if(([IO.File]::ReadAllText($destination)) -cne '{"version":"old"}'){
        throw 'The locked destination changed despite the failed replacement.'
    }
    if(@(Get-ChildItem -LiteralPath $scratch -Filter '*.tmp').Count){
        throw 'A failed replacement left an owned temporary file.'
    }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    $job=$null
    $held.Dispose()
    $held=$null
    Import-Module $modulePath -Force
    Write-EvidenceJson -Path $destination -Value @{version='new'}
    $value=Get-Content -LiteralPath $destination -Raw | ConvertFrom-Json
    if($value.version -cne 'new'){throw 'Normal evidence replacement did not persist.'}
    Write-Host 'PASS evidence move contention is terminal within writer; normal replacement succeeds'
} finally {
    if($job){Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
    if($held){$held.Dispose()}
    $resolved=[IO.Path]::GetFullPath($scratch)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
       (Split-Path -Leaf $resolved) -notmatch '^devfleet-evidence-atomic-[a-f0-9]{32}$'){
        throw 'Evidence fixture cleanup path rejected.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
