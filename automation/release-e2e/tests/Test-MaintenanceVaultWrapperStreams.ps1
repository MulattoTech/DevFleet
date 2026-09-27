param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'

$modulePath=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/MaintenanceVault.psm1'
$tokens=$null
$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count-ne0){throw "MaintenanceVault parse failed: $($parseErrors[0].Message)"}
$wrapperStrings=@($ast.FindAll({
    param($node)
    $node-is[Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Value-match'private-product-operations\.log' -and
        $node.Value-match'Invoke-MaintenanceVaultProvisioning -Request \$request'
},$true))
if($wrapperStrings.Count-ne1){throw 'Generated Maintenance Vault wrapper body is missing or ambiguous.'}
$wrapperLines=@($wrapperStrings[0].Value -split "`r?`n")
$start=-1
$end=-1
for($i=0;$i-lt$wrapperLines.Count;$i++){
    if($start-lt0-and$wrapperLines[$i]-match'^\$privateLog='){$start=$i}
    if($start-ge0-and$wrapperLines[$i]-match'^try\{\$result=Invoke-MaintenanceVaultProvisioning'){$end=$i;break}
}
if($start-lt0-or$end-lt$start){throw 'Generated Maintenance Vault private-stream wrapper segment is missing.'}
$wrapperSegment=($wrapperLines[$start..$end]-join[Environment]::NewLine)

$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-vault-wrapper-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
try{
    function Invoke-WrapperCase {
        param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][bool]$ThrowProvisioning)
        $caseRoot=Join-Path $temp $Name
        [IO.Directory]::CreateDirectory($caseRoot)|Out-Null
        $entryPath=Join-Path $caseRoot 'provisioning-entered.txt'
        $childPath=Join-Path $caseRoot 'wrapper-child.ps1'
        $child=@'
param([Parameter(Mandatory)][string]$WorkRoot,[Parameter(Mandatory)][string]$EntryPath,[Parameter(Mandatory)][string]$Mode)
$ErrorActionPreference='Stop'
$request=[pscustomobject]@{workRoot=$WorkRoot;entryPath=$EntryPath;throwProvisioning=($Mode-ceq'throw')}
function Invoke-MaintenanceVaultProvisioning {
    param([Parameter(Mandatory)]$Request)
    [IO.File]::WriteAllText([string]$Request.entryPath,'ENTERED',[Text.UTF8Encoding]::new($false))
    Write-Warning 'PRIVATE_STREAM_WARNING' -WarningAction Continue
    Write-Verbose 'PRIVATE_STREAM_VERBOSE' -Verbose
    Write-Debug 'PRIVATE_STREAM_DEBUG' -Debug
    Write-Information 'PRIVATE_STREAM_INFORMATION' -InformationAction Continue
    if([bool]$Request.throwProvisioning){throw [InvalidOperationException]::new('PRIVATE_ORIGINAL_PROVISIONING_EXCEPTION')}
    [pscustomobject][ordered]@{status='PASS';contract='maintenance-vault-wrapper-stream-test'}
}
'@
        [IO.File]::WriteAllText($childPath,($child+[Environment]::NewLine+$wrapperSegment),[Text.UTF8Encoding]::new($false))
        $pwsh=(Get-Command pwsh -CommandType Application -ErrorAction Stop).Source
        $psi=[Diagnostics.ProcessStartInfo]::new()
        $psi.FileName=$pwsh
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$childPath,'-WorkRoot',$caseRoot,'-EntryPath',$entryPath,'-Mode',$(if($ThrowProvisioning){'throw'}else{'pass'}))){[void]$psi.ArgumentList.Add($argument)}
        $process=[Diagnostics.Process]::new()
        $process.StartInfo=$psi
        if(-not$process.Start()){throw 'Could not start local PowerShell 7 wrapper regression child.'}
        $stdout=$process.StandardOutput.ReadToEnd()
        $stderr=$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $privateLogs=@(Get-ChildItem -LiteralPath $caseRoot -Filter 'private-product-operations*.log' -File -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            name=$Name
            exitCode=$process.ExitCode
            stdout=$stdout.Trim()
            stderr=$stderr.Trim()
            provisioningEntered=(Test-Path -LiteralPath $entryPath -PathType Leaf)
            privateLogCount=$privateLogs.Count
            privateLogNames=@($privateLogs.Name)
            privateContent=(@($privateLogs|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw})-join[Environment]::NewLine)
        }
    }

    $success=Invoke-WrapperCase -Name success -ThrowProvisioning $false
    $failure=Invoke-WrapperCase -Name exception -ThrowProvisioning $true
    $successJson=$null
    $failureJson=$null
    try{$successJson=$success.stdout|ConvertFrom-Json -ErrorAction Stop}catch{}
    try{$failureJson=$failure.stdout|ConvertFrom-Json -ErrorAction Stop}catch{}

    if($success.exitCode-ne0-and-not$success.provisioningEntered-and
        [string]$successJson.errorCategory-ceq'OpenError'-and
        [string]$successJson.errorType-ceq'System.IO.IOException'){
        throw 'RED_REPRODUCED: duplicate same-file stream redirection raised OpenError/System.IO.IOException before provisioning entry.'
    }
    if($success.exitCode-ne0-or-not$success.provisioningEntered-or[string]$successJson.status-cne'PASS'){
        throw "Success wrapper case failed: exit=$($success.exitCode), entered=$($success.provisioningEntered), stdout=$($success.stdout), stderr=$($success.stderr)"
    }
    if(@($success.stdout -split "`r?`n"|Where-Object{$_}).Count-ne1){throw 'Success wrapper stdout must contain exactly one machine-readable record.'}
    foreach($marker in @('PRIVATE_STREAM_WARNING','PRIVATE_STREAM_VERBOSE','PRIVATE_STREAM_DEBUG','PRIVATE_STREAM_INFORMATION')){
        if($success.privateContent-notmatch[regex]::Escape($marker)){throw "Success wrapper private stream is missing $marker."}
        if($success.stdout-match[regex]::Escape($marker)){throw "Success wrapper leaked $marker to stdout."}
    }
    if($success.privateLogCount-ne1-or$success.privateLogNames[0]-cne'private-product-operations.log'){
        throw 'Success wrapper must merge isolated ephemeral stream sinks into one final private log.'
    }

    if($failure.exitCode-ne1-or-not$failure.provisioningEntered-or[string]$failureJson.status-cne'FAIL'){
        throw "Exception wrapper case did not fail after provisioning entry: exit=$($failure.exitCode), entered=$($failure.provisioningEntered), stdout=$($failure.stdout), stderr=$($failure.stderr)"
    }
    if([string]$failureJson.errorCategory-cne'OperationStopped'-or[string]$failureJson.errorType-cne'System.InvalidOperationException'){
        throw "Provisioning exception classification changed: category=$($failureJson.errorCategory), type=$($failureJson.errorType)"
    }
    if($failure.stdout-match'PRIVATE_' -or[string]$failureJson.message-cne'Configured Primary Vault prerequisite failed; no proof credit.'){
        throw 'Provisioning exception or private stream content leaked to machine-readable stdout.'
    }
    foreach($marker in @('PRIVATE_STREAM_WARNING','PRIVATE_STREAM_VERBOSE','PRIVATE_STREAM_DEBUG','PRIVATE_STREAM_INFORMATION','PRIVATE_ORIGINAL_PROVISIONING_EXCEPTION')){
        if($failure.privateContent-notmatch[regex]::Escape($marker)){throw "Exception wrapper private log is missing $marker."}
    }
    if($failure.privateLogCount-ne1-or$failure.privateLogNames[0]-cne'private-product-operations.log'){
        throw 'Exception wrapper must merge isolated ephemeral stream sinks into one final private log.'
    }
    [ordered]@{status='PASS';cases=2;actualGeneratedWrapper=$true;childRuntime='PowerShell 7';privateStreamIsolation=$true;originalExceptionClassification=$true;vmMutation=$false}|ConvertTo-Json -Compress
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
