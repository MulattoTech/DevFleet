# Build and test from a clean clone

DevFleet product 1.2.13; installer 1.4.1. These are developer instructions, not certification results. Work in a new clone, never the frozen original checkout. First read `source/README-FIRST.md`, `source/docs/00-HARD-STOPS-AND-ASSUMPTIONS.md`, `installer-source/BUILDING.md` and `docs/ai/devfleet-release/START-HERE.md`.

## Prerequisites

- Windows x64 for the WPF installer; .NET 8 SDK with Windows Desktop targeting support; PowerShell 7 and Windows PowerShell 5.1; Git; Python with venv/pip.
- .NET metadata in the snapshot mentions SDK 8.0.424 and an older verification record mentions 8.0.408. Record the actual SDK with `dotnet --info`; byte-identical reproduction across toolchains is not asserted.
- Product Python runtime pins are in `source/app/requirements.txt`; hash-pinned closure in `source/app/requirements-hashed.txt`. Release-only pins are in `tools/release-tooling-requirements.txt`. External tools, VMs and OS licenses are not vendored.
- Linux service installation uses systemd, Docker/Multipass and networking as specified by the product scripts and dependency metadata. Review the host/guest boundary and configure your own hosts. Never execute the original MulattoTechBox VM identities against another machine.

## Source verification and Python checks

```powershell
python .\ai\verify_source_export.py
python -m venv .venv-dev
$Python = (Resolve-Path .\.venv-dev\Scripts\python.exe).Path
& $Python -m pip install --require-hashes -r .\source\app\requirements-hashed.txt
& $Python -m pip install --require-hashes -r .\tools\release-tooling-requirements.txt
& $Python -m pip install pytest
& $Python --version
dotnet --info
pwsh --version
```

Select tests by their environment in `tools/audit-test-manifest.json`. Do not interpret an indiscriminate Windows run of Linux/systemd tests as product failure or mark unsupported tests PASS. This package's native audit validation report records any bounded clean-extraction tests actually executed during packaging. Python/pytest itself is not locked by this export; record installed versions in returned evidence.

## Unsigned WPF developer build from the included payload

From the repository root:

```powershell
$Repo = (Resolve-Path .).Path
$DevOut = Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-dev-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $DevOut | Out-Null
$Project = Join-Path $Repo 'installer-source\DevFleet.Setup\DevFleet.Setup.csproj'
$Tests = Join-Path $Repo 'installer-source\DevFleet.Setup.Tests\DevFleet.Setup.Tests.csproj'
dotnet restore $Project --source https://api.nuget.org/v3/index.json --runtime win-x64
if ($LASTEXITCODE) { throw 'restore failed' }
dotnet build $Project -c Release --no-restore
if ($LASTEXITCODE) { throw 'build failed' }
dotnet run --project $Tests -c Release
if ($LASTEXITCODE) { throw 'installer tests failed' }
dotnet publish $Project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o (Join-Path $DevOut 'publish')
if ($LASTEXITCODE) { throw 'publish failed' }
$Exe = Join-Path $DevOut 'publish\DevFleet.Setup.exe'
$env:DEVFLEET_SELF_TEST_OUTPUT = Join-Path $DevOut 'unsigned-self-test.txt'
try {
    & $Exe --self-test
    if ($LASTEXITCODE) { throw 'self-test failed' }
    Get-Content $env:DEVFLEET_SELF_TEST_OUTPUT
} finally {
    Remove-Item Env:DEVFLEET_SELF_TEST_OUTPUT -ErrorAction SilentlyContinue
}
```

The project already embeds `installer-source/DevFleet.Setup/Payload/devfleet-v1.2.13.tar.gz`. Direct `dotnet publish` builds the existing payload snapshot. After changing product source, regenerate release inputs before claiming the binary includes those changes. The self-test uses scratch roots and is not a real installed lifecycle/role proof. A genuine certification qualification must run under the native standard-token runner and correct non-administrator account; this developer check does not replace it.

## Bounded harness checks in a disposable working copy

```powershell
pwsh -NoProfile -File .\automation\release-e2e\tests\Test-WpfLaunchBoundaryBehavior.ps1 -WorkspaceRoot $Repo
pwsh -NoProfile -File .\automation\release-e2e\tests\Test-LifecycleObserverBehavior.ps1 -WorkspaceRoot $Repo
```

Read test source and platform requirements before expanding the selection. The original full preflight is included as historical PASS at its original tuple. This export did not rerun qualification or the full preflight simply for packaging.

## Canonical prepared release pipeline (separate from developer publish)

Both scripts require `-SourceRoot`, `-PreviousPortableZip`, `-OutputDirectory`. The complete outer ZIP includes the current portable artifact under `current-artifacts/`; a clone alone contains no previous portable ZIP. Obtain the exact hash-listed seed from this package or a separately reviewed artifact source. An AI audit ZIP is not a valid portable seed.

```powershell
$Seed = (Resolve-Path '<package-root>\current-artifacts\DevFleet-v1.2.13-Portable-Codebase-Verified-r1.zip').Path
$ReleaseOut = Join-Path $DevOut 'release'
.\installer-source\Prepare-ReleaseInputs.ps1 -Mode Prepare -SourceRoot (Join-Path $Repo 'source') -PreviousPortableZip $Seed -OutputDirectory $ReleaseOut -SigningProfile PrivateSelfSigned -ProveIdempotent
if ($LASTEXITCODE) { throw 'prepare failed' }
# Review and commit prepared shipping inputs in this new development clone.
# Only after the intended inputs are frozen:
.\installer-source\Build-Release.ps1 -SourceRoot (Join-Path $Repo 'source') -PreviousPortableZip $Seed -OutputDirectory $ReleaseOut -DotNet dotnet -UnsignedDeveloperBuild -VerifyFrozenInputs
```

Inspect actual argument contracts before use. Preparing inputs mutates generated payload/metadata; do not do this merely to rebuild an audit. Signing a real candidate requires the separately authorized existing provider/key and native build gates. No private key is supplied, no trust store change is part of these instructions, and an unsigned result never earns release eligibility.

The outer native audit reported diagnostic PASS_WITH_BLOCKER, not release acceptance. A clone-built unsigned artifact cannot be substituted into the original exact-candidate proofs.
