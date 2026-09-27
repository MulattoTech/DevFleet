#requires -Version 7.0
# Read-only observer adapter. Native release state remains the authority.
param(
 [string]$Root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path,
 [ValidateRange(1,300)][int]$IntervalSeconds=3,[switch]$Once,[switch]$Json
)
$ErrorActionPreference='Stop'
$observer='C:\Users\Dylan\AppData\Local\DevFleet\ReleaseContinuation\20260922\Watch-ReleaseStatus.ps1'
if(-not(Test-Path -LiteralPath $observer -PathType Leaf)){throw 'Continuation monitor missing. Restore the previous monitor using Restore-PreviousMonitor.ps1 in the support kit.'}
& $observer -Root $Root -IntervalSeconds $IntervalSeconds -Once:$Once -Json:$Json
