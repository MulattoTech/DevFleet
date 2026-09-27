[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$text=Get-Content (Join-Path $WorkspaceRoot 'tools/Invoke-DevFleetFinalConvergence.ps1') -Raw
$start=$text.IndexOf('$authorityUpdater=Join-Path')
$end=$text.IndexOf('    } catch { Add-SecondaryError "Authority refresh:', $start)
if($start -lt 0 -or $end -le $start){throw 'Native authority call boundary not found'}
$handler=[scriptblock]::Create($text.Substring($start,$end-$start))
$root=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-authority-exit-'+[guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$checks.Add([pscustomobject]@{name=$Name;pass=$Pass})}
function Get-SafeError([object]$Value){[string]$Value}
try {
    New-Item -ItemType Directory -Path (Join-Path $root 'tools') -Force|Out-Null
    $fixture=@'
param($Workspace,$TerminalBlocker,$TerminalBlockerClassification)
$ErrorActionPreference='Stop'
$mode=Get-Content (Join-Path $Workspace 'mode.txt')
if($mode -eq 'throws'){throw 'Fixture authority write rejected'}
if($mode -eq 'native-nonzero'){& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -NonInteractive -Command 'exit 37'}
[ordered]@{workspace=$Workspace;blocker=$TerminalBlocker;classification=$TerminalBlockerClassification;nativeExit=$LASTEXITCODE}|ConvertTo-Json|Set-Content (Join-Path $Workspace 'receipt.json')
'completed updater without terminating error'
'@
    Set-Content (Join-Path $root 'tools/Update-CurrentReleaseAuthority.ps1') $fixture -Encoding utf8
    foreach($mode in @('native-nonzero','inherited-nonzero','throws')){
        Set-Content (Join-Path $root 'mode.txt') $mode -Encoding utf8
        Remove-Item (Join-Path $root 'receipt.json') -ErrorAction SilentlyContinue
        $Workspace=$root;$PrimaryBlocker='EXACT PROOF NOT OBSERVED; fixture';$PrimaryBlockerClassification='BLOCKED - FIXTURE'
        $LASTEXITCODE=37;$caught=$null
        try { & $handler|Out-Null } catch {$caught=$_.Exception.Message}
        $receipt=Join-Path $root 'receipt.json'
        if($mode -eq 'throws'){
            Check 'actual updater exception remains failure' ([bool]$caught)
            Check 'failed updater did not manufacture receipt' (-not(Test-Path $receipt))
        }else{
            Check ($mode+': successful updater accepted') (-not $caught)
            Check ($mode+': updater actually executed') (Test-Path $receipt)
            if(Test-Path $receipt){$j=Get-Content $receipt -Raw|ConvertFrom-Json;Check ($mode+': argument values preserved') ($j.workspace -eq $Workspace -and $j.blocker -eq $PrimaryBlocker -and $j.classification -eq $PrimaryBlockerClassification)}
        }
    }
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
$failed=@($checks|Where-Object {-not $_.pass})
[ordered]@{scope='VM_FREE_NATIVE_FINALIZER_CALL_BOUNDARY';releaseCredit=$false;status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks)}|ConvertTo-Json -Depth 6
if($failed.Count){exit 1}
