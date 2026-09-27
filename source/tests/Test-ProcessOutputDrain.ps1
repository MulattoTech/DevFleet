$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'windows\DevFleet.Common.psm1') -Force

$shell=(Get-Command powershell.exe -ErrorAction Stop).Source
$normal=Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command',"[Console]::Out.Write('complete-output')") -Capture
if($normal -cne 'complete-output'){throw 'Invoke-External did not preserve ordinary complete output.'}

$pidPath=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-common-inherited-pipe-"+[guid]::NewGuid().ToString('N')+'.pid')
$descendantPid=0
try{
    $escapedPidPath=$pidPath.Replace("'","''")
    $parentCommand="`$childInfo=[Diagnostics.ProcessStartInfo]::new();`$childInfo.FileName=(Get-Command powershell.exe).Source;`$childInfo.UseShellExecute=`$false;`$childInfo.CreateNoWindow=`$true;`$childInfo.ArgumentList.Add('-NoProfile');`$childInfo.ArgumentList.Add('-NonInteractive');`$childInfo.ArgumentList.Add('-Command');`$childInfo.ArgumentList.Add('Start-Sleep -Seconds 30');`$child=[Diagnostics.Process]::Start(`$childInfo);[IO.File]::WriteAllText('$escapedPidPath',[string]`$child.Id);exit 0"
    $timer=[Diagnostics.Stopwatch]::StartNew();$blocked=$false
    try{Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command',$parentCommand) -Capture|Out-Null}catch{if($_.Exception.Message -match 'redirected output was incomplete after the bounded post-exit drain'){$blocked=$true}else{throw}}
    $timer.Stop()
    if(-not $blocked -or $timer.Elapsed -ge [TimeSpan]::FromSeconds(15)){throw 'Invoke-External did not fail closed within the bounded post-exit drain allowance.'}
    if(-not(Test-Path -LiteralPath $pidPath) -or -not [int]::TryParse([IO.File]::ReadAllText($pidPath),[ref]$descendantPid)){throw 'Invoke-External inherited-handle fixture did not publish its descendant PID.'}
    $descendant=Get-Process -Id $descendantPid -ErrorAction Stop
    if($descendant.HasExited){throw 'Invoke-External killed a descendant merely to manufacture redirected-output EOF.'}
}finally{
    if($descendantPid -gt 0){Stop-Process -Id $descendantPid -Force -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

$tx='a'*32;$payload='b'*64
$computeBoundary=New-DevFleetBootstrapBoundary -Kind compute -InstanceName 'devfleet-primary' -TransactionId $tx -PayloadSha256 $payload -BootstrapMaxSeconds 6600 -PackageVersion '1.2.13' -NodeRole 'primary'
if($computeBoundary.multipassResolvedStageName -cne 'compute-devfleet-primary-multipass-resolved' -or $computeBoundary.isolationVerifiedStageName -cne 'compute-devfleet-primary-isolation-verified' -or $computeBoundary.instanceAbsentStageName -cne 'compute-devfleet-primary-instance-absent' -or $computeBoundary.instanceLaunchedStageName -cne 'compute-devfleet-primary-instance-launched' -or $computeBoundary.instanceReadyStageName -cne 'compute-devfleet-primary-instance-ready' -or $computeBoundary.payloadTransferredStageName -cne 'compute-devfleet-primary-payload-transferred' -or $computeBoundary.payloadExtractedStageName -cne 'compute-devfleet-primary-payload-extracted' -or $computeBoundary.completionStageName -cne 'compute-devfleet-primary'){throw 'Compute bootstrap boundary did not produce the allowlisted substep names.'}
if($computeBoundary.extractionCommand -notmatch 'unzip.+devfleet-payload\.zip' -or $computeBoundary.extractionCommand -match 'sudo\s+bash|(?i)password|apitoken|secret='){throw 'Compute extraction did not remain a distinct non-secret production boundary.'}
if($computeBoundary.bootstrapCommand -notmatch "bootstrap-compute\.sh.*--transaction-id '$tx'.*--payload-sha256 '$payload'.*--bootstrap-max-seconds '6600'.*--package-version '1\.2\.13'.*--node-role 'primary'" -or $computeBoundary.bootstrapCommand -match '(?i)password|apitoken|secret='){throw 'Compute bootstrap command did not preserve its non-secret identity contract.'}
$vaultBoundary=New-DevFleetBootstrapBoundary -Kind vault -InstanceName 'devfleet-vault' -TransactionId $tx -PayloadSha256 $payload -BootstrapMaxSeconds 3900 -PackageVersion 'vault' -NodeRole 'vault'
if($vaultBoundary.multipassResolvedStageName -cne 'vault-multipass-resolved' -or $vaultBoundary.isolationVerifiedStageName -cne 'vault-isolation-verified' -or $vaultBoundary.instancePresentStageName -cne 'vault-instance-present' -or $vaultBoundary.instanceStartedStageName -cne 'vault-instance-started' -or $vaultBoundary.instanceReadyStageName -cne 'vault-instance-ready' -or $vaultBoundary.payloadTransferredStageName -cne 'vault-payload-transferred' -or $vaultBoundary.payloadExtractedStageName -cne 'vault-payload-extracted' -or $vaultBoundary.completionStageName -cne 'vault'){throw 'Vault bootstrap boundary did not produce the allowlisted substep names.'}
if($vaultBoundary.extractionCommand -notmatch 'unzip.+devfleet-vault-payload\.zip' -or $vaultBoundary.extractionCommand -match 'sudo\s+bash|(?i)password|resticpassword|secret='){throw 'Vault extraction did not remain a distinct non-secret production boundary.'}
if($vaultBoundary.bootstrapCommand -notmatch "bootstrap-vault\.sh.*--transaction-id '$tx'.*--payload-sha256 '$payload'.*--bootstrap-max-seconds '3900'.*--package-version 'vault'.*--node-role 'vault'" -or $vaultBoundary.bootstrapCommand -match '(?i)password|resticpassword|secret='){throw 'Vault bootstrap command did not preserve its non-secret identity contract.'}

[ordered]@{ok=$true;tests=8;ordinaryCompleteOutput=$true;inheritedPipeFailsClosedBoundedly=$true;computeExtractionSeparated=$true;vaultExtractionSeparated=$true;computeBoundaryIdentityBound=$true;vaultBoundaryIdentityBound=$true;substepNamesAllowlisted=$true;secretsExcludedFromArguments=$true}|ConvertTo-Json -Compress
