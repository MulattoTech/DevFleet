[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$productionScript = Join-Path $sourceRoot 'windows\02-Provision-ComputeNode.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-compute-reboot-' + [guid]::NewGuid().ToString('N'))

try {
    $fixtureWindows = Join-Path $fixtureRoot 'windows'
    $fixturePackage = Join-Path $fixtureRoot 'package'
    $fixtureState = Join-Path $fixtureRoot 'state'
    New-Item -ItemType Directory -Path $fixtureWindows, (Join-Path $fixturePackage 'cloud-init'), (Join-Path $fixtureState 'tmp') -Force | Out-Null
    Copy-Item -LiteralPath $productionScript -Destination (Join-Path $fixtureWindows '02-Provision-ComputeNode.ps1')
    Set-Content -LiteralPath (Join-Path $fixturePackage 'VERSION') -Value '1.2.13' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $fixturePackage 'cloud-init\compute.yaml') -Value "node=__NODE_NAME__`nrole=__NODE_ROLE__`nname=__GIT_NAME_SHELL__`nemail=__GIT_EMAIL_SHELL__" -Encoding utf8

    $markerLog = Join-Path $fixtureRoot 'markers.txt'
    $module = @'
function Assert-PowerShell7 {}
function Assert-Administrator {}
function Get-DevFleetDeadlineContext { [pscustomobject]@{ StageDeadlineUtc = [datetime]::UtcNow.AddMinutes(20) } }
function Set-DevFleetDeadlineContext { param($TransactionDeadlineUtc,$StageName,$StageBudgetSeconds) }
function Get-DevFleetStageBudgetSeconds { param($Name) 1200 }
function Get-DevFleetOperationMaximumSeconds { param($Name) 1200 }
function Get-DevFleetConfig {
    [pscustomobject]@{
        Failover = [pscustomobject]@{ InstanceName='devfleet-failover'; UbuntuImage='24.04'; Cpus=2; Memory='4G'; Disk='20G'; FriendlyName='Failover' }
        Primary = [pscustomobject]@{ InstanceName='devfleet-primary' }
        Git = [pscustomobject]@{ UserName='Fixture User'; Email='fixture@example.invalid' }
    }
}
function Get-PackageRootFromState { $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE }
function Wait-ActiveDevFleetTransaction {
    param($ExpectedRole)
    [pscustomobject]@{ transactionId=('a'*32); payloadSha256=('b'*64); action='FreshInstall'; role='Laptop'; preparedUtc='2026-09-22T00:00:00Z' }
}
function Test-DevFleetTransactionBinding { $true }
function New-DevFleetBootstrapBoundary {
    [pscustomobject]@{
        multipassResolvedStageName='compute-multipass-resolved'
        isolationVerifiedStageName='compute-isolation-verified'
        instancePresentStageName='compute-instance-present'
        instanceAbsentStageName='compute-instance-absent'
        instanceLaunchedStageName='compute-instance-launched'
        instanceStartedStageName='compute-instance-started'
        instanceReadyStageName='compute-instance-ready'
        payloadTransferredStageName='compute-payload-transferred'
        payloadExtractedStageName='compute-payload-extracted'
        completionStageName='compute-complete'
        bootstrapMaxSeconds=1200
        extractionCommand='true'
        bootstrapCommand='true'
    }
}
function Get-MultipassExe { 'multipass.exe' }
function Write-StageMarker { param($Name,$Transaction) Add-Content -LiteralPath $env:DEVFLEET_COMPUTE_REBOOT_MARKERS -Value $Name }
function Assert-MultipassIsolation { param($InstanceNames) }
function Get-OrCreateSecrets { [pscustomobject]@{} }
function Get-OrCreateNodeIdentity { param($Role) [pscustomobject]@{} }
function Test-MultipassInstance { param($Name) $false }
function Get-DevFleetStateRoot { $env:DEVFLEET_COMPUTE_REBOOT_STATE }
function ConvertTo-YamlSingleQuotedScalar { param($Value) "'$Value'" }
function ConvertTo-ShellSingleQuotedScalar { param($Value) "'$Value'" }
function Invoke-MultipassLaunchWithReadinessRecovery { throw 'fixture launch failed after servicing transition' }
function Test-PendingReboot { $env:DEVFLEET_COMPUTE_REBOOT_PENDING -eq '1' }
Export-ModuleMember -Function *
'@
    Set-Content -LiteralPath (Join-Path $fixtureWindows 'DevFleet.Common.psm1') -Value $module -Encoding utf8

    $oldPackage = $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE
    $oldState = $env:DEVFLEET_COMPUTE_REBOOT_STATE
    $oldMarkers = $env:DEVFLEET_COMPUTE_REBOOT_MARKERS
    $oldPending = $env:DEVFLEET_COMPUTE_REBOOT_PENDING
    try {
        $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE = $fixturePackage
        $env:DEVFLEET_COMPUTE_REBOOT_STATE = $fixtureState
        $env:DEVFLEET_COMPUTE_REBOOT_MARKERS = $markerLog
        $env:DEVFLEET_COMPUTE_REBOOT_PENDING = '1'
        $pwsh = (Get-Process -Id $PID).Path
        $process = Start-Process -FilePath $pwsh -ArgumentList @(
            '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
            (Join-Path $fixtureWindows '02-Provision-ComputeNode.ps1'),
            '-NodeRole','Failover'
        ) -Wait -PassThru -NoNewWindow
    } finally {
        $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE = $oldPackage
        $env:DEVFLEET_COMPUTE_REBOOT_STATE = $oldState
        $env:DEVFLEET_COMPUTE_REBOOT_MARKERS = $oldMarkers
        $env:DEVFLEET_COMPUTE_REBOOT_PENDING = $oldPending
    }

    if ($process.ExitCode -ne 3010) {
        throw "Compute launch failure with a new servicing obligation did not hand off as reboot-required: exit=$($process.ExitCode)."
    }
    $markers = @(Get-Content -LiteralPath $markerLog)
    foreach ($required in @('compute-multipass-resolved','compute-isolation-verified','compute-instance-absent')) {
        if ($markers -notcontains $required) { throw "Production compute path did not reach expected pre-launch marker: $required" }
    }
    if ($markers -contains 'compute-instance-ready' -or $markers -contains 'compute-complete') {
        throw 'Reboot-required compute handoff fabricated readiness or completion.'
    }

    $oldPackage = $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE
    $oldState = $env:DEVFLEET_COMPUTE_REBOOT_STATE
    $oldMarkers = $env:DEVFLEET_COMPUTE_REBOOT_MARKERS
    $oldPending = $env:DEVFLEET_COMPUTE_REBOOT_PENDING
    try {
        $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE = $fixturePackage
        $env:DEVFLEET_COMPUTE_REBOOT_STATE = $fixtureState
        $env:DEVFLEET_COMPUTE_REBOOT_MARKERS = $markerLog
        $env:DEVFLEET_COMPUTE_REBOOT_PENDING = '0'
        $nonRebootProcess = Start-Process -FilePath $pwsh -ArgumentList @(
            '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
            (Join-Path $fixtureWindows '02-Provision-ComputeNode.ps1'),
            '-NodeRole','Failover'
        ) -Wait -PassThru -NoNewWindow
    } finally {
        $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE = $oldPackage
        $env:DEVFLEET_COMPUTE_REBOOT_STATE = $oldState
        $env:DEVFLEET_COMPUTE_REBOOT_MARKERS = $oldMarkers
        $env:DEVFLEET_COMPUTE_REBOOT_PENDING = $oldPending
    }
    if ($nonRebootProcess.ExitCode -eq 3010 -or $nonRebootProcess.ExitCode -eq 0) {
        throw "A non-servicing Multipass failure was incorrectly converted to reboot success: exit=$($nonRebootProcess.ExitCode)."
    }

    [ordered]@{
        status = 'PASS'
        exitCode = $process.ExitCode
        rebootRequired = $true
        ordinaryFailureExitCode = $nonRebootProcess.ExitCode
        ordinaryFailurePreserved = $true
        fabricatedCompletion = $false
    } | ConvertTo-Json -Compress
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
