# Admission to a prospective diagnostic, not release acceptance.
function Assert-FreshAttemptAdmission {
 [CmdletBinding()]
 param($Active,[string]$RunId,[string]$CurrentHead,[string]$CurrentScriptHash,
       [int]$CurrentPid,[int]$ParentPid,[string]$ActualOwnerStartUtc)
 if(-not $Active -or $Active.runId -cne $RunId -or $Active.operation -cne 'diagnostic'){
  throw 'FRESH_DIAGNOSTIC_RESERVATION_MISSING_OR_WRONG'
 }
 if($Active.tuple.repositoryHead -cne $CurrentHead -or $Active.entrypointSha256 -cne $CurrentScriptHash){
  throw 'FRESH_DIAGNOSTIC_IDENTITY_DRIFT'
 }
 if($Active.owner.pid -ne $CurrentPid -and $Active.owner.pid -ne $ParentPid){
  throw 'FRESH_DIAGNOSTIC_OWNER_MISMATCH'
 }
 if([datetimeoffset]::Parse($Active.owner.startUtc) -ne [datetimeoffset]::Parse($ActualOwnerStartUtc)){
  throw 'FRESH_DIAGNOSTIC_OWNER_START_MISMATCH'
 }
 if([datetimeoffset]::Parse($Active.deadlineUtc) -le [datetimeoffset]::UtcNow){
  throw 'FRESH_DIAGNOSTIC_DEADLINE_EXPIRED'
 }
}
function Get-FreshDiagnosticAdmission {
 [CmdletBinding()]
 param([string]$LedgerPath,[string]$RunId,[string]$WorkspaceRoot,[string]$ScriptPath)
 if(-not $LedgerPath -or -not $RunId){throw 'FRESH_DIAGNOSTIC_ADMISSION_REQUIRED'}
 $journal=Join-Path $PSScriptRoot 'fresh/fresh_attempts.py'
 $lines=@(& (Get-Command python.exe -ErrorAction Stop).Source $journal status --ledger $LedgerPath)
 if($LASTEXITCODE -ne 0){throw 'FRESH_DIAGNOSTIC_JOURNAL_INVALID'}
 $status=($lines -join "`n")|ConvertFrom-Json -DateKind String -ErrorAction Stop
 $head=(& git -C $WorkspaceRoot rev-parse HEAD).Trim()
 if($LASTEXITCODE -ne 0){throw 'FRESH_DIAGNOSTIC_GIT_IDENTITY_UNAVAILABLE'}
 $hash=(Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
 $self=Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
 if(-not $status.active){throw 'FRESH_DIAGNOSTIC_ACTIVE_RESERVATION_MISSING'}
 $owner=Get-Process -Id ([int]$status.active.owner.pid) -ErrorAction Stop
 $ownerStart=$owner.StartTime.ToUniversalTime().ToString('o')
 Assert-FreshAttemptAdmission -Active $status.active -RunId $RunId -CurrentHead $head `
  -CurrentScriptHash $hash -CurrentPid $PID -ParentPid $self.ParentProcessId -ActualOwnerStartUtc $ownerStart
 return $status.active
}
