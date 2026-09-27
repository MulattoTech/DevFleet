[CmdletBinding()]
param([Parameter(Mandatory)][string]$Repository)
$ErrorActionPreference='Stop'
$Repository=(Resolve-Path -LiteralPath $Repository).Path
Import-Module (Join-Path $Repository 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $Repository 'automation/release-e2e/modules/HarnessBudget.psm1') -Force -DisableNameChecking
$watch=[Diagnostics.Stopwatch]::StartNew();$passed=0;$failures=[Collections.Generic.List[string]]::new()
function Check([bool]$Ok,[string]$Name){if($Ok){$script:passed++}else{$script:failures.Add($Name)}}
function Denied([scriptblock]$Body,[string]$Name){$caught=$false;try{&$Body|Out-Null}catch{$caught=$true};Check $caught $Name}
$base=[datetime]'2026-01-01T00:00:00Z';$deadline=$base.AddHours(25)
# Real native deadline functions; injected timestamps, no wall-clock changes.
Check ((Get-DeadlineRemainingSeconds -DeadlineUtc $deadline -NowUtc $base)-eq90000) '25-hour remaining budget'
Check ((Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 120 -DeadlineUtc $deadline -NowUtc $base)-eq120) 'child limit preserved'
Check ((Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 120 -DeadlineUtc $deadline -NowUtc $deadline.AddSeconds(-1.5))-eq1) 'fractional remainder floored'
Denied {Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 120 -DeadlineUtc $deadline -NowUtc $deadline} 'exact expiration rejects child'
Denied {Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 120 -DeadlineUtc $deadline -NowUtc $deadline.AddDays(1)} 'expired owner cannot restart budget'
Denied {Get-EffectiveDeadlineTimeoutSeconds -OperationMaximumSeconds 0 -DeadlineUtc $deadline -NowUtc $base} 'zero child timeout rejected'
$prior=[pscustomobject]@{checkpointGeneration=1;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}
$next=[pscustomobject]@{checkpointPresent=$true;checkpoint=[pscustomobject]@{checkpointGeneration=2;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;terminalFailure=$false}
Check ((Get-DurableProgressClassification -Observation $next -PriorCheckpoint $prior -MaxGeneration 3)-ceq'NEXT_REBOOT') 'same transaction next-generation boundary'
$next.checkpoint.transactionId='c'*32
Check ((Get-DurableProgressClassification -Observation $next -PriorCheckpoint $prior -MaxGeneration 3)-ceq'TERMINAL_FAILURE') 'foreign transaction rejected'
$pending=[pscustomobject]@{checkpointPresent=$false;checkpoint=$null;matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;terminalFailure=$false;processTree=@();timestampUtc=$base.ToString('o');progress=[ordered]@{checkpointGeneration=1;checkpointState='waiting-for-reboot';completedStages=@('bootstrap');resumeStage='install';stages=@();cpuSeconds=0;installStateSha256=$null;ownershipSha256=$null;receiptMatch=$false;health=$false;hostAgentTaskState='Running';listener=$false}}
# Invoke the ACTUAL wait loop. Every observation and delay is injected.
# No guest session, external process or network operation is used by the provider.
$state=@{clock=$base;reads=0;sleeps=0};$clock={$now=$state.clock;$state.clock=$now.AddSeconds(300);$state.reads++;$now}.GetNewClosure()
$sleep={param($seconds)$state.sleeps++}.GetNewClosure()
$provider={param($context)$context.providerContext}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-fastlane-fixture-'+[guid]::NewGuid().ToString('N'))
try{
 New-Item -ItemType Directory -Path $temp -ErrorAction Stop|Out-Null
 $result=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Action FreshInstall -Role 'Primary / Desktop' -PriorGeneration 1 -MaxGeneration 3 -BudgetSeconds 90000 -NoProgressBudgetSeconds 1800 -AbsoluteBudgetSeconds 90000 -PollSeconds 5 -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationProvider $provider -ObservationProviderContext $pending -ClockProvider $clock -SleepProvider $sleep -EvidencePath (Join-Path $temp 'fixture-observer.json')
 Check ([string]$result.outcome-ceq'NO_PROGRESS_TIMEOUT') 'unchanged state reaches 30-minute virtual no-progress timeout'
 Check ([datetime]$result.absoluteLifecycleDeadlineUtc-eq$deadline) '25-hour native owner deadline remains unchanged'
 Check ($state.reads-lt100) 'virtual replay iteration count remains bounded'
 Check ([string]$result.outcome-cne'COMPLETED') 'no fabricated install completion'
 $simulated=[math]::Round(($state.clock-$base).TotalSeconds,2)
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
$watch.Stop()
$report=[ordered]@{status=if($failures.Count){'FAIL'}else{'PASS'};scope='INJECTED_CLOCK_NATIVE_FUNCTION_REGRESSION';passed=$passed;failed=@($failures);virtualOwnerHorizonSeconds=90000;virtualObserverSeconds=$simulated;wallSeconds=$watch.Elapsed.TotalSeconds;realVmOperations=0;hostClockChanged=$false;guestClockChanged=$false;certificationCredit=$false;nativeSourceModified=$false}
$report|ConvertTo-Json -Depth 6
if($failures.Count){exit 1}
