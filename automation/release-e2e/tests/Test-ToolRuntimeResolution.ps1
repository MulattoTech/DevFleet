[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
Import-Module (Join-Path $WorkspaceRoot 'tools\PythonRuntime.psm1') -Force
$python = Resolve-DevFleetPython -Workspace $WorkspaceRoot
$version = @(& $python --version 2>&1)
$insideWorkspace = [IO.Path]::GetFullPath($python).StartsWith(([IO.Path]::GetFullPath($WorkspaceRoot) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)
$status = if($LASTEXITCODE -eq 0 -and ($version -join ' ') -match '^Python 3\.' -and (Test-Path -LiteralPath $python -PathType Leaf) -and $insideWorkspace){'PASS'}else{'FAIL'}
[pscustomobject]@{status=$status;runtime=[IO.Path]::GetFileName($python);version=($version -join ' ');repositoryLocal=$insideWorkspace}|ConvertTo-Json -Depth 4
if($status -ne 'PASS'){exit 1}
