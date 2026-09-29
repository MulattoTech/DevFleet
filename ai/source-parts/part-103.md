# DevFleet source part 103

Full-source UTF-8 byte interval [4743000, 4789500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7377a7932cbed68f24f55da423bc630e42eb1be28691750f6d6cdc5b11efae77

<!-- BEGIN SOURCE SLICE -->
\')).MakeRelativeUri([Uri]::new($file.FullName)).ToString()).Replace('/','/')
            if ($excluded | Where-Object { $relative -match $_ }) { continue }
            $entryName = $relative
            if ($seen.ContainsKey($entryName)) {
                if ($root -eq $installer -and $entryName -eq 'dependencies.json') { continue }
                $existingHash = $seen[$entryName]
                $currentHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                if ($existingHash -ne $currentHash) { throw "Source archive collision with different contents: $entryName" }
                continue
            }
            $entry = $zip.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
            $input = [IO.File]::OpenRead($file.FullName); $outputStream = $entry.Open()
            try { $input.CopyTo($outputStream) } finally { $outputStream.Dispose(); $input.Dispose() }
            $seen[$entryName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
} finally { $zip.Dispose() }
$result = Get-Item -LiteralPath $output
Write-Host "Installer source archive generated: $output ($($result.Length) bytes)"

```


## FILE: source/tools/Verify-Package.ps1

SHA256: 823ed5d1f17bf4b46a0f8f306ff73833df46ab50221734ff5116a8cac7e84cec | Bytes: 3453 | Git mode: 100644

```
[CmdletBinding()]
param([switch]$SkipChecksums)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$required=@('VERSION','README-FIRST.md','Upgrade-DevFleet.ps1','DevFleet-v1.1.0-MIGRATION.md','DevFleet-v1.1.0-VALIDATION.md','DevFleet-v1.1.0-FILE-CHANGES.md','config\devfleet.config.json','config\ollama-profiles.json','client\Configure-SSH.ps1','client\Configure-DockerContext.ps1','windows\Migrate-Config.ps1','windows\Configure-Ollama.ps1','windows\Set-DevFleetDockerMode.ps1','linux\devfleet-switch-docker-mode','app\devfleet\main.py','docs\13-PERFORMANCE-TUNING.md')
foreach($r in $required){if(-not(Test-Path(Join-Path $root $r))){throw "Missing $r"}}
$errors=@();Get-ChildItem $root -Recurse -File|Where-Object Extension -in @('.ps1','.psm1')|ForEach-Object{$tokens=$null;$parse=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$parse);foreach($e in $parse){$errors+="$($_.FullName):$($e.Extent.StartLineNumber): $($e.Message)"}};if($errors){throw "PowerShell parsing failed:`n$($errors -join "`n")"}
$jsonErrors=@();Get-ChildItem $root -Recurse -File -Filter *.json|Where-Object{$_.FullName -notmatch '[\\/](\.git|\.pytest_cache|\.test-runtime|__pycache__|runtime-migrations)[\\/]'}|ForEach-Object{try{[void](Get-Content $_.FullName -Raw|ConvertFrom-Json)}catch{$jsonErrors+="$($_.FullName): $($_.Exception.Message)"}};if($jsonErrors){throw "JSON parsing failed:`n$($jsonErrors -join "`n")"}
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim();$cfg=Get-Content (Join-Path $root 'config\devfleet.config.json') -Raw|ConvertFrom-Json;if([int]$cfg.SchemaVersion -ne 2 -or [string]$cfg.PackageVersion -ne $version){throw "Default configuration is not schema 2 / v$version."}
$transientPackageParts=@('.git','.pytest_cache','.test-runtime','__pycache__','runtime-migrations','outputs','audit-extract');$bad=Get-ChildItem $root -Recurse -File|Where-Object{$relative=$_.FullName.Substring($root.Length).TrimStart([char]92,[char]47).Replace([char]92,[char]47);$parts=$relative.Split('/');$generated=($parts|Where-Object{$_ -eq '.venv' -or $_ -like '.venv-*' -or $transientPackageParts -contains $_}).Count -gt 0;(-not $generated) -and $_.Length -eq 0 -and $_.Name -ne '__init__.py'};if($bad){throw "Unexpected empty files: $($bad.FullName -join ', ')"}
if(-not $SkipChecksums){$manifest=Join-Path $root 'CHECKSUMS.sha256';foreach($line in Get-Content $manifest){if($line -notmatch '^([0-9a-f]{64})  (.+)$'){continue};$expected=$Matches[1];$rel=$Matches[2].Replace('/','\');$path=Join-Path $root $rel;if(-not(Test-Path $path)){throw "Missing checksum target $rel"};$actual=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant();if($actual -ne $expected){$bytes=[IO.File]::ReadAllBytes($path);$hasLoneCr=$false;for($i=0;$i -lt $bytes.Length;$i++){if($bytes[$i] -eq 13 -and ($i+1 -ge $bytes.Length -or $bytes[$i+1] -ne 10)){$hasLoneCr=$true;break}};if(-not $hasLoneCr -and ($bytes -contains 13)){$normalized=[Text.Encoding]::UTF8.GetBytes(([Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n"));$sha=[Security.Cryptography.SHA256]::Create();try{$actual=([BitConverter]::ToString($sha.ComputeHash($normalized))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}};if($actual -ne $expected){throw "Checksum mismatch $rel"}}}
Write-Host 'Package structure, PowerShell AST syntax, JSON/schema, and checksums verified.' -ForegroundColor Green

```


## FILE: source/tools/build_release.py

SHA256: 59e38747a1c410ea7710b522c5bb2dab73adb841e892503c87114aed97dc5712 | Bytes: 8017 | Git mode: 100644

```
"""Reproducible DevFleet TAR and portable bundle builder."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import stat
import tarfile
import zipfile
from pathlib import Path

from hook_modes import executable_template_hooks, hook_mode_manifest

TRANSIENT = {".git", ".pytest_cache", ".test-runtime", "__pycache__", "runtime-migrations"}


def is_transient_part(part: str) -> bool:
    return part in TRANSIENT or part.startswith(".venv")


def files(root: Path) -> list[Path]:
    candidates = (
        p
        for p in root.rglob("*")
        if p.is_file()
        and not any(is_transient_part(part) for part in p.relative_to(root).parts)
    )
    return sorted(
        candidates,
        key=lambda path: path.relative_to(root).as_posix().encode("utf-8"),
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_checksums(root: Path) -> None:
    manifest = root / "CHECKSUMS.sha256"
    lines = [f"{sha256(path)}  {path.relative_to(root).as_posix()}" for path in files(root) if path != manifest]
    # Keep the tracked manifest byte-identical to a Git archive on Windows;
    # newline translation here would make a frozen commit unreproducible.
    manifest.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def build_tar(root: Path, output: Path) -> set[str]:
    hooks = executable_template_hooks(root)
    with output.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed, tarfile.open(fileobj=compressed, mode="w") as archive:
        for path in files(root):
            rel = path.relative_to(root).as_posix()
            info = archive.gettarinfo(str(path), arcname=rel)
            info.mode = 0o755 if rel in hooks else 0o644
            info.mtime = 0; info.uid = 0; info.gid = 0; info.uname = "root"; info.gname = "root"
            with path.open("rb") as stream:
                archive.addfile(info, stream)
    return hooks


def portable_metadata(entries: list[tuple[str, bytes]], version: str, nested_tar: Path, root: Path) -> list[tuple[str, bytes]]:
    nested_tar_name = nested_tar.name
    current_source = [("source/" + path.relative_to(root).as_posix(), path.read_bytes()) for path in files(root)]
    source_names = [name for name, _ in current_source]
    source_hashes = [{"path": name, "sha256": sha256_bytes(data)} for name, data in current_source]
    manifest = {"version": version, "file_count": len(source_names), "files": source_hashes}
    canonical_docs = {
        "README.md": (
            f"# DevFleet Safe Remote Development v{version}\n\n"
            f"This is the clean-room v{version} portable bundle. The TAR is the authoritative POSIX-mode artifact.\n\n"
            f"Verify `CHECKSUMS.sha256`, then run `python source/tools/verify_package.py --archive {nested_tar_name}` from the extracted bundle root.\n"
        ).encode(),
        "CLEAN-ROOM-VERIFICATION.md": (
            f"# DevFleet {version} clean-room verification\n\n"
            "Extract this ZIP into a fresh directory. From the extracted bundle root, run:\n\n"
            f"`python source/tools/verify_package.py --archive {nested_tar_name}`\n\n"
            "The command must complete successfully before the portable package is accepted.\n"
        ).encode(),
        "DIRECTORY-LAYOUT.md": (
            f"# DevFleet {version} portable layout\n\n"
            f"`source/` contains the complete canonical source. `{nested_tar_name}` preserves the release source and trusted POSIX hook modes.\n"
        ).encode(),
    }
    rebuilt: list[tuple[str, bytes]] = []
    for name, data in entries:
        if name.startswith("devfleet-v1.2.") and name.endswith(".tar.gz"):
            continue
        if name.startswith("source/"):
            continue
        if name in {"portable-codebase-manifest.json", "portable-codebase-sha256.txt", "source-tree-manifest.json", "source-tree-sha256.txt"}:
            continue
        if name in canonical_docs:
            continue
        rebuilt.append((name, data))
    rebuilt.extend(canonical_docs.items())
    rebuilt.append((nested_tar_name, nested_tar.read_bytes()))
    rebuilt.extend(current_source)
    rebuilt.append(("portable-codebase-manifest.json", json.dumps(manifest, indent=2).encode()))
    rebuilt.append(("source-tree-manifest.json", json.dumps({"version": version, "file_count": len(source_names), "files": source_hashes}, indent=2).encode()))
    rebuilt.append(("source-tree-sha256.txt", ("\n".join(f"{item['sha256']}  {item['path']}" for item in source_hashes) + "\n").encode()))
    rebuilt.append(("portable-codebase-sha256.txt", ("\n".join(f"{sha256_bytes(data)}  {name}" for name, data in sorted(rebuilt, key=lambda item: item[0].encode("utf-8")) if name not in {"portable-codebase-sha256.txt"}) + "\n").encode()))
    _assert_portable_instruction_identity(rebuilt, version, nested_tar_name)
    return rebuilt


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _assert_portable_instruction_identity(entries: list[tuple[str, bytes]], version: str, nested_tar_name: str) -> None:
    instruction_names = {"README.md", "CLEAN-ROOM-VERIFICATION.md", "DIRECTORY-LAYOUT.md"}
    stale_version = re.compile(r"(?:DevFleet\s+v|devfleet-v)(\d+\.\d+\.\d+)")
    for name, data in entries:
        if name not in instruction_names:
            continue
        text = data.decode("utf-8", errors="strict")
        for match in stale_version.finditer(text):
            context = text[max(0, match.start() - 80):match.end() + 80].lower()
            if match.group(1) != version and "historical" not in context:
                raise ValueError(f"Portable release instruction {name} contains an unapproved prior release identity.")
        if name == "CLEAN-ROOM-VERIFICATION.md" and nested_tar_name not in text:
            raise ValueError(f"Portable clean-room instructions do not name {nested_tar_name}.")


def main() -> None:
    global args, root
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--old-portable", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    root = args.source.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (root / "CHECKSUMS.sha256").unlink(missing_ok=True)
    write_checksums(root)
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    tar = args.output_dir / f"devfleet-v{version}.tar.gz"
    hooks = build_tar(root, tar)
    with zipfile.ZipFile(args.old_portable) as source_zip:
        entries = [(item.filename, source_zip.read(item.filename)) for item in source_zip.infolist() if not item.is_dir()]
    portable = args.output_dir / f"DevFleet-v{version}-Portable-Codebase-Verified-r1.zip"
    rebuilt = portable_metadata(entries, version, tar, root)
    with zipfile.ZipFile(portable, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        for name, data in sorted(rebuilt, key=lambda item: item[0].encode("utf-8")):
            info = zipfile.ZipInfo(name)
            mode = 0o755 if name.removeprefix("source/") in hooks else 0o644
            info.create_system = 3  # Unix origin; required for standard unzip mode restoration.
            info.external_attr = (stat.S_IFREG | mode) << 16
            out.writestr(info, data)
    manifest = hook_mode_manifest(root); manifest.update({"version": version, "mode": "0755"})
    (args.output_dir / "hook-mode-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"tar": str(tar), "portable": str(portable), "hook_count": len(hooks), "tar_sha256": sha256(tar), "portable_sha256": sha256(portable)}, indent=2))


if __name__ == "__main__":
    main()

```


## FILE: source/tools/check_dependency_advisories.py

SHA256: 8901ed5ad3d19846030f2c6b8af5f03274277ef76b641b540a127d9994906185 | Bytes: 11275 | Git mode: 100644

```
"""Reproducible OSV freshness gate for the exact DevFleet dependency lock."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from packaging.markers import Marker
from packaging.requirements import InvalidRequirement, Requirement
from packaging.utils import canonicalize_name

try:
    from cvss import CVSS2, CVSS3, CVSS4
    from cvss.exceptions import CVSSError
except ImportError as exc:  # pragma: no cover - exercised by release preflight
    raise RuntimeError(
        "release dependency gate requires the pinned 'cvss' release-tool dependency"
    ) from exc


OSV_QUERY_URL = "https://api.osv.dev/v1/query"
TIMEOUT_SECONDS = 8
HIGH_SCORE = 7.0
CRITICAL_SCORE = 9.0
KNOWN_SEVERITIES = {"NONE", "LOW", "MEDIUM", "MODERATE", "HIGH", "CRITICAL"}
BLOCKING_SEVERITIES = {"HIGH", "CRITICAL", "UNKNOWN"}


def _logical_requirement_lines(lock: Path) -> list[str]:
    """Return requirement expressions from a pip-compile style lock.

    Hashes and pip-compile annotations are deliberately ignored.  A continued
    marker expression is retained, while a continued requirement is finalized
    before the next top-level package line.
    """
    expressions: list[str] = []
    pending: str | None = None
    for physical in lock.read_text(encoding="utf-8").splitlines():
        line = physical.strip()
        if not line or line.startswith("#") or line.startswith("--hash="):
            continue
        # pip-compile may emit other option continuations; none are part of the
        # PEP 508 requirement we need to query.
        if line.startswith("--"):
            continue
        if " #" in line:
            line = line.split(" #", 1)[0].rstrip()
        if not line:
            continue
        if pending is not None:
            if line.startswith(";") or line.startswith(","):
                pending = f"{pending} {line}"
                if pending.endswith("\\"):
                    pending = pending[:-1].rstrip()
                continue
            expressions.append(pending)
            pending = None
        if line.endswith("\\"):
            pending = line[:-1].rstrip()
        else:
            expressions.append(line)
    if pending is not None:
        expressions.append(pending)
    return expressions


def _requirement_expression(line: str) -> tuple[str, str, str | None]:
    try:
        requirement = Requirement(line)
    except InvalidRequirement as exc:
        raise ValueError(f"unsupported lock requirement: {line!r}") from exc
    specifiers = list(requirement.specifier)
    if len(specifiers) != 1 or specifiers[0].operator != "==" or specifiers[0].version.endswith(".*"):
        raise ValueError(f"lock requirement is not an exact == pin: {line!r}")
    version = specifiers[0].version.strip()
    if not version or any(ch.isspace() for ch in version) or ";" in version:
        raise ValueError(f"lock requirement has an invalid pinned version: {line!r}")
    marker = str(requirement.marker) if requirement.marker else None
    # Constructing Marker validates the complete expression, and makes the
    # target-environment policy explicit even though all exact lock pins are
    # queried conservatively below.
    if marker:
        Marker(marker)
    return canonicalize_name(requirement.name), version, marker


def lock_requirements(lock: Path) -> list[tuple[str, str, str | None]]:
    parsed = [_requirement_expression(line) for line in _logical_requirement_lines(lock)]
    if not parsed:
        raise ValueError(f"lock contains no exact pinned requirements: {lock}")
    # A compiled lock is the certified dependency set.  Query every exact pin,
    # including platform-marked pins, rather than silently dropping a supported
    # target.  Duplicate name/version rows are queried once.
    unique: list[tuple[str, str, str | None]] = []
    seen: set[tuple[str, str]] = set()
    for package, version, marker in parsed:
        key = (package, version)
        if key not in seen:
            seen.add(key)
            unique.append((package, version, marker))
    return unique


def lock_packages(lock: Path) -> list[tuple[str, str]]:
    return [(package, version) for package, version, _marker in lock_requirements(lock)]


def _score(vulnerability: dict) -> float | None:
    scores: list[float] = []
    for item in vulnerability.get("severity", []) or []:
        raw = str(item.get("score", ""))
        if not raw:
            continue
        try:
            kind = str(item.get("type") or "").upper()
            if raw.startswith("CVSS:2.0/") or kind == "CVSS_V2":
                scores.append(float(CVSS2(raw).scores()[0]))
            elif raw.startswith(("CVSS:3.0/", "CVSS:3.1/")) or kind == "CVSS_V3":
                scores.append(float(CVSS3(raw).scores()[0]))
            elif raw.startswith("CVSS:4.0/") or kind == "CVSS_V4":
                scores.append(float(CVSS4(raw).scores()[0]))
            else:
                # OSV has historically emitted numeric scores for some records;
                # accept only a complete numeric value in the valid CVSS range.
                numeric = float(raw)
                if 0.0 <= numeric <= 10.0:
                    scores.append(numeric)
        except (TypeError, ValueError, IndexError, CVSSError):
            continue
    return max(scores) if scores else None


def _declared_severities(vulnerability: dict) -> list[str]:
    values: list[str] = []
    specific = vulnerability.get("database_specific") or {}
    for value in (specific.get("severity"),):
        if value is not None:
            values.append(str(value).upper())
    for affected in vulnerability.get("affected", []) or []:
        if not isinstance(affected, dict):
            continue
        ecosystem_specific = affected.get("ecosystem_specific") or {}
        if ecosystem_specific.get("severity") is not None:
            values.append(str(ecosystem_specific["severity"]).upper())
    return values


def _severity(vulnerability: dict) -> str:
    declared_values = _declared_severities(vulnerability)
    invalid_declared = [value for value in declared_values if value not in KNOWN_SEVERITIES]
    declared = max(
        (value for value in declared_values if value in KNOWN_SEVERITIES),
        key=lambda value: {"NONE": 0, "LOW": 1, "MEDIUM": 2, "MODERATE": 2, "HIGH": 3, "CRITICAL": 4}[value],
        default="",
    )
    score = _score(vulnerability)
    if score is not None:
        score_label = "CRITICAL" if score >= CRITICAL_SCORE else "HIGH" if score >= HIGH_SCORE else "MEDIUM" if score >= 4.0 else "LOW" if score > 0 else "NONE"
        rank = {"NONE": 0, "LOW": 1, "MEDIUM": 2, "MODERATE": 2, "HIGH": 3, "CRITICAL": 4}
        if rank[score_label] > rank.get(declared, -1):
            declared = score_label
    invalid_vectors = any(
        str(item.get("score") or "").upper().startswith("CVSS:") and _score({"severity": [item]}) is None
        for item in vulnerability.get("severity", []) or []
        if isinstance(item, dict)
    )
    if (invalid_declared or invalid_vectors) and declared not in {"HIGH", "CRITICAL"}:
        return "UNKNOWN"
    if score is not None and score >= CRITICAL_SCORE:
        return "CRITICAL"
    if score is not None and score >= HIGH_SCORE:
        return "HIGH"
    return declared or "UNKNOWN"


def query(package: str, version: str) -> dict:
    body = json.dumps({"package": {"name": package, "ecosystem": "PyPI"}, "version": version}).encode()
    request = urllib.request.Request(OSV_QUERY_URL, data=body, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.load(response)


def run(lock: Path, allowlist: Path) -> dict:
    checked_at = datetime.now(timezone.utc).isoformat()
    lock_bytes = lock.read_bytes()
    allowlist_bytes = allowlist.read_bytes() if allowlist.is_file() else b'{"exceptions": []}'
    allowed = json.loads(allowlist.read_text(encoding="utf-8")) if allowlist.is_file() else {"exceptions": []}
    exceptions = {
        (str(item.get("advisory_id")), str(item.get("package")).lower().replace("_", "-"), str(item.get("affected_version"))): item
        for item in allowed.get("exceptions", [])
        if isinstance(item, dict)
    }
    results: list[dict] = []
    blocking: list[dict] = []
    errors: list[str] = []
    for package, version, marker in lock_requirements(lock):
        try:
            response = query(package, version)
            vulnerabilities = response.get("vulns", []) or []
            advisories = []
            for vulnerability in vulnerabilities:
                advisory_id = str(vulnerability.get("id") or "unknown")
                severity = _severity(vulnerability)
                item = {"id": advisory_id, "severity": severity, "summary": str(vulnerability.get("summary") or "")[:500]}
                advisories.append(item)
                if severity in BLOCKING_SEVERITIES and (advisory_id, package, version) not in exceptions:
                    blocking.append({"package": package, "version": version, **item})
            results.append({"package": package, "version": version, "marker": marker, "query": {"package": {"name": package, "ecosystem": "PyPI"}, "version": version}, "advisories": advisories, "status": "PASS" if not advisories else "ADVISORIES_REVIEWED"})
        except (OSError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            errors.append(f"{package}=={version}: {type(exc).__name__}: {exc}")
            results.append({"package": package, "version": version, "status": "ERROR", "error": str(exc)[:500]})
    status = "BLOCKED" if blocking or errors else "PASS"
    return {
        "schema_version": 2,
        "checker": "DevFleet dependency advisory gate",
        "checker_version": "2.0.0",
        "status": status,
        "source": OSV_QUERY_URL,
        "checked_at": checked_at,
        "lock": str(lock),
        "lock_sha256": hashlib.sha256(lock_bytes).hexdigest(),
        "allowlist": str(allowlist),
        "allowlist_sha256": hashlib.sha256(allowlist_bytes).hexdigest(),
        "target_environment_policy": "query every exact pin in the compiled lock, including platform-marked pins; deduplicate only identical canonical package/version pairs",
        "packages": results,
        "blocking_advisories": blocking,
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--allowlist", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = run(args.lock, args.allowlist)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "packages": len(report["packages"]), "blocking": len(report["blocking_advisories"]), "errors": len(report["errors"])}))
    return 0 if report["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/tools/hook_modes.py

SHA256: 3010bf588f088c9e6d4e956c2127a06abfec78f4875eec3441475383b6e02e54 | Bytes: 5491 | Git mode: 100644

```
"""Single source of truth for executable template hook closure and modes."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
import sys

COMMAND_FIELDS = ("bootstrap_command", "health_command", "test_command", "codexpro_command")
LOCAL_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_./-])(?:\./)?(?P<path>\.devfleet/[A-Za-z0-9._-]+\.sh)(?![A-Za-z0-9_./-])")
ABSOLUTE_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_./-])/(?P<path>(?:[^\s\"']+/)*\.devfleet/[A-Za-z0-9._-]+\.sh)")
LOCALISH_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_])(?P<path>(?:\./)?\.devfleet/[^\s\"'`()]+\.sh)")


@dataclass(frozen=True)
class HookClosure:
    """The complete, validated local executable-script closure for a template."""

    direct: frozenset[str]
    transitive: frozenset[str]

    @property
    def executable(self) -> frozenset[str]:
        return self.direct | self.transitive


def _local_references(text: str, *, origin: Path) -> set[str]:
    """Extract only local .devfleet script references and reject unsafe lookalikes."""
    absolute = ABSOLUTE_HOOK_RE.search(text)
    if absolute:
        raise ValueError(f"absolute external hook reference in {origin}: {absolute.group('path')}")
    for candidate in LOCALISH_HOOK_RE.finditer(text):
        path = candidate.group("path")
        if ".." in Path(path).parts or "/" in path.removeprefix("./.devfleet/"):
            raise ValueError(f"unsafe local hook reference in {origin}: {path}")
    return {match.group("path") for match in LOCAL_HOOK_RE.finditer(text)}


def _resolve_local(root: Path, template_dir: Path, relative: str, *, origin: Path) -> tuple[str, Path]:
    candidate = (template_dir / relative).resolve(strict=False)
    template_root = template_dir.resolve()
    try:
        candidate.relative_to(template_root)
    except ValueError as exc:
        raise ValueError(f"hook reference escapes template root in {origin}: {relative}") from exc
    if candidate.parent != (template_dir / ".devfleet").resolve():
        raise ValueError(f"hook reference is not a local .devfleet script in {origin}: {relative}")
    package_relative = candidate.relative_to(root.resolve()).as_posix()
    return package_relative, candidate


def executable_template_hook_closure(root: Path) -> dict[str, HookClosure]:
    """Discover and validate metadata plus transitive local-script references."""
    result: dict[str, HookClosure] = {}
    for metadata in sorted((root / "templates").glob("*/.devfleet/template.json")):
        data = json.loads(metadata.read_text(encoding="utf-8"))
        template_dir = metadata.parent.parent
        direct: set[str] = set()
        pending: list[tuple[str, Path]] = []
        for field in COMMAND_FIELDS:
            command = data.get(field)
            if not isinstance(command, str):
                continue
            for reference in _local_references(command, origin=metadata):
                package_relative, candidate = _resolve_local(root, template_dir, reference, origin=metadata)
                direct.add(package_relative)
                pending.append((package_relative, candidate))

        all_hooks = set(direct)
        while pending:
            package_relative, script = pending.pop()
            if not script.is_file() or script.is_symlink():
                raise ValueError(f"referenced hook is not a regular file: {package_relative}")
            for reference in _local_references(script.read_text(encoding="utf-8"), origin=script):
                child_relative, child = _resolve_local(root, template_dir, reference, origin=script)
                if child_relative not in all_hooks:
                    all_hooks.add(child_relative)
                    pending.append((child_relative, child))
        missing = [rel for rel in sorted(all_hooks) if not (root / rel).is_file()]
        if missing:
            raise ValueError(f"referenced hook does not exist: {missing[0]}")
        direct_set = frozenset(direct)
        result[template_dir.name] = HookClosure(direct_set, frozenset(all_hooks - direct_set))
    return result


def executable_template_hooks(root: Path) -> set[str]:
    """Return package-relative paths in the complete executable hook closure."""
    return set().union(*(closure.executable for closure in executable_template_hook_closure(root).values()))


def hook_mode_manifest(root: Path) -> dict[str, object]:
    closures = executable_template_hook_closure(root)
    hooks = sorted(set().union(*(closure.executable for closure in closures.values())))
    all_scripts = sorted(
        p.relative_to(root).as_posix()
        for p in (root / "templates").glob("*/.devfleet/*.sh")
        if p.is_file()
    )
    return {
        "executable_by_contract": hooks,
        "count": len(hooks),
        "classification": {
            rel: "executable-by-contract" if rel in hooks else "non-executable-source/helper"
            for rel in all_scripts
        },
        "templates": {
            name: {"direct": sorted(c.direct), "transitive": sorted(c.transitive)}
            for name, c in sorted(closures.items())
        },
    }


def is_executable_template_hook(root: Path, path: Path) -> bool:
    return path.relative_to(root).as_posix() in executable_template_hooks(root)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python hook_modes.py <source-root>")
    print(json.dumps(hook_mode_manifest(Path(sys.argv[1]).resolve()), sort_keys=True))

```


## FILE: source/tools/migrate_config.py

SHA256: 38e5b6be41be5d9a22039b047a5489ab476dce3ea02d9217e3737d3f07e4bdaa | Bytes: 763 | Git mode: 100644

```
#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app'))
from devfleet.configuration import migrate_cluster_config,validate_cluster_config
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--output',type=Path);p.add_argument('--clean-install',action='store_true');p.add_argument('--write',action='store_true');a=p.parse_args();data=json.loads(a.source.read_text());out,changes=migrate_cluster_config(data,clean_install=a.clean_install);validate_cluster_config(out);print(json.dumps({'changes':changes,'configuration':out},indent=2));
if a.write:(a.output or a.source).write_text(json.dumps(out,indent=2)+'\n')

```


## FILE: source/tools/release_fingerprint.py

SHA256: f5440bfaeafb54607fa71d284ec6d63e115fe15e2de6e72bc7f1de644363cf6b | Bytes: 5826 | Git mode: 100644

```
"""Build a deterministic fingerprint for the shipping packaging closure."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

try:
    from hook_modes import executable_template_hooks
except ModuleNotFoundError:  # imported as tools.release_fingerprint in tests
    from .hook_modes import executable_template_hooks


TRANSIENT_PARTS = {
    ".git",
    ".pytest_cache",
    ".test-runtime",
    "__pycache__",
    "bin",
    "obj",
    "outputs",
    "audit",
    "Payload",
}


def is_transient_part(part: str) -> bool:
    return part in TRANSIENT_PARTS or part.startswith(".venv")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _included(path: Path, root: Path) -> bool:
    relative = path.relative_to(root)
    return path.is_file() and not any(is_transient_part(part) for part in relative.parts)


def _entries(root: Path, label: str, *, executable_by_contract: set[str] | frozenset[str] = frozenset()) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for path in sorted(root.rglob("*")):
        if not _included(path, root):
            continue
        relative = path.relative_to(root).as_posix()
        result.append(
            {
                "root": label,
                "path": relative,
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
                # This is the mode written into the canonical TAR/portable
                # payload, never the incidental mode of the checkout host.
                "mode": "0755" if relative in executable_by_contract else "0644",
            }
        )
    return result


def _tooling_fingerprint(source_root: Path) -> dict[str, object]:
    """Fingerprint non-shipping release/audit tooling separately.

    The shipping release identity intentionally excludes repository-level tooling and
    automation so a review-bundle or harness change cannot silently invalidate a
    byte-identical application candidate.  Tooling still receives its own identity.
    """
    workspace = source_root.parent
    roots = [(workspace / "tools", "tools"), (workspace / "automation", "automation")]
    entries = [entry for root, label in roots if root.exists() for entry in _entries(root, label)]
    canonical = {"schemaVersion": 1, "toolingInputs": entries}
    serialized = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {**canonical, "toolingFingerprintId": hashlib.sha256(serialized.encode("utf-8")).hexdigest()}


def build_fingerprint(
    source_root: Path,
    installer_root: Path,
    artifacts: dict[str, Path] | None = None,
    *,
    source_executable_paths: set[str] | None = None,
) -> dict[str, object]:
    source_root = source_root.resolve()
    installer_root = installer_root.resolve()
    version = (source_root / "VERSION").read_text(encoding="utf-8").strip()
    installer_version = (installer_root / "INSTALLER_VERSION").read_text(encoding="utf-8").strip()
    executable_paths = executable_template_hooks(source_root) if source_executable_paths is None else set(source_executable_paths)
    unknown_executables = sorted(executable_paths - {path.relative_to(source_root).as_posix() for path in source_root.rglob("*") if _included(path, source_root)})
    if unknown_executables:
        raise ValueError(f"shipping mode contract names a missing file: {unknown_executables[0]}")
    entries = _entries(source_root, "source", executable_by_contract=executable_paths) + _entries(installer_root, "installer-source")
    artifact_entries: list[dict[str, object]] = []
    for name, path in sorted((artifacts or {}).items()):
        if not path.exists():
            continue
        artifact_entries.append({"name": name, "bytes": path.stat().st_size, "sha256": sha256(path)})
    canonical = {
        "schemaVersion": 2,
        "devfleetVersion": version,
        "installerVersion": installer_version,
        "shippingModeContract": {
            "schemaVersion": 1,
            "defaultMode": "0644",
            "executableMode": "0755",
            "executableByContract": sorted(executable_paths),
        },
        "shippingInputs": entries,
        "artifacts": artifact_entries,
    }
    serialized = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {
        **canonical,
        "releaseFingerprintId": hashlib.sha256(serialized.encode("utf-8")).hexdigest(),
        "toolingFingerprint": _tooling_fingerprint(source_root),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--installer-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--artifact", action="append", default=[], metavar="NAME=PATH")
    args = parser.parse_args()
    artifacts = {}
    for value in args.artifact:
        name, separator, raw_path = value.partition("=")
        if not separator or not name or not raw_path:
            parser.error(f"artifact must be NAME=PATH: {value}")
        artifacts[name] = Path(raw_path)
    output = build_fingerprint(args.source_root, args.installer_root, artifacts)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, args.output)
    print(output["releaseFingerprintId"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/tools/validate_ai_audit_bundle.py

SHA256: d9f46d511192d552013ce289ffe7547bb3befd1d9c65d40b61038e979e93a70c | Bytes: 26859 | Git mode: 100644

```
"""Validate the universal DevFleet AI audit bundle.

This validator is intentionally independent of the PowerShell packager.  It
extracts the ZIP into a temporary directory whose name contains spaces and
checks the archive's source closure, hashes, modes, candidate tuple, and
security exclusions.  It does not trust a completeness claim made by the
bundle manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


REQUIRED = {
    "AUDIT-README.md",
    "AUDIT-MANIFEST.json",
    "CURRENT-CANDIDATE.json",
    "AUDIT-TREE.txt",
    "SHA256SUMS.txt",
    "SOURCE-MODES.json",
    "finalization-state.json",
    "outputs/final-artifact-hashes.json",
    "outputs/release-fingerprint.json",
    "outputs/tooling-fingerprint-current.json",
    "outputs/dependency-advisory-gate.json",
}
RELEASE_REQUIRED = REQUIRED | {"outputs/independent-osv-reconciliation.json"}
FORBIDDEN_PARTS = {
    ".git",
    ".venv",
    "node_modules",
    "bin",
    "obj",
    "__pycache__",
    ".pytest_cache",
    "build",
    "dist",
    "vhdx",
    "snapshots",
    "browser-profile",
}
ALLOWED_OUTPUT_METADATA = {
    "outputs/final-artifact-hashes.json",
    "outputs/release-fingerprint.json",
    "outputs/tooling-fingerprint-current.json",
    "outputs/dependency-advisory-gate.json",
    "outputs/independent-osv-reconciliation.json",
}
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(?:ghp|github_pat|tskey)-[A-Za-z0-9_:-]{20,}"),
    re.compile(r"(?i)\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~-]{24,}"),
)
FAILED_ATTEMPT_SNAPSHOT = "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
FAILED_ATTEMPT_BLOCKER = "REPLACEMENT_CANDIDATE_BINDING_MISMATCH"
FAILED_ATTEMPT_CURRENT_RECORDS = (
    "evidence/CURRENT-PROOF.json",
    "audit/attemptedReplacementCandidate.json",
    "audit/candidateBindingFailure.json",
)
FAILED_ATTEMPT_INVENTORY_FILES = ("EVIDENCE-MODES.json", "EVIDENCE-SHA256SUMS.txt")


def _json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _validate_failed_attempt_records(extracted: Path, names: set[str], manifest: dict[str, Any]) -> None:
    missing = sorted((set(FAILED_ATTEMPT_CURRENT_RECORDS) | set(FAILED_ATTEMPT_INVENTORY_FILES)) - names)
    if missing:
        raise ValueError(f"failed-attempt diagnostic blocker records are missing: {missing}")
    proof = _json(extracted / "evidence/CURRENT-PROOF.json")
    attempted = _json(extracted / "audit/attemptedReplacementCandidate.json")
    failure = _json(extracted / "audit/candidateBindingFailure.json")
    if str(proof.get("status") or "") != "NOT_OBSERVED" or str(proof.get("outcome") or "") != "NOT_OBSERVED" or str(proof.get("blockerCode") or "") != FAILED_ATTEMPT_BLOCKER:
        raise ValueError("failed-attempt CURRENT-PROOF is not the current NOT_OBSERVED blocker record")
    expected = {
        "attemptedCommit": "21752fc0e50978183322204c523b40947d073aa0",
        "commitShippingInputIdentity": "6e0bac4b4eebc83cdcd9eddda2008607ba15c8835e5c72a931792f5b83c653f4",
        "buildTimeShippingInputIdentity": "3a65fd54d70fe05565ac3a32f73100ca2c81a77a4008feb361f99f229f025f8a",
    }
    if attempted.get("snapshotPath") != FAILED_ATTEMPT_SNAPSHOT or attempted.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or any(attempted.get(key) != value for key, value in expected.items()):
        raise ValueError("attemptedReplacementCandidate does not bind the failed-attempt snapshot and identities")
    if attempted.get("artifactTupleValid") is not True or attempted.get("artifactTupleMatchesCandidate") is not False or attempted.get("buildInvocationCount") != 1 or attempted.get("signingInvocationCount") != 1:
        raise ValueError("attemptedReplacementCandidate one-shot/artifact state is contradictory")
    if failure.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or any(failure.get(key) != value for key, value in expected.items()) or failure.get("artifactTupleValid") is not True or failure.get("artifactTupleMatchesCandidate") is not False:
        raise ValueError("candidateBindingFailure contradicts attempted replacement evidence")
    if failure.get("currentProofOutcome") != "NOT_OBSERVED" or failure.get("fullReleasePassed") is not False or failure.get("releaseEligible") is not False:
        raise ValueError("candidateBindingFailure permits an unobserved proof or release")
    inventory = manifest.get("evidenceInventory")
    if not isinstance(inventory, list):
        raise ValueError("failed-attempt diagnostic manifest is missing evidenceInventory")
    inventory_by_path = {str(row.get("path")): row for row in inventory if isinstance(row, dict)}
    if set(inventory_by_path) != set(FAILED_ATTEMPT_CURRENT_RECORDS):
        raise ValueError("failed-attempt evidenceInventory does not contain exactly the required blocker records")
    for relative in FAILED_ATTEMPT_CURRENT_RECORDS:
        row = inventory_by_path[relative]
        path = extracted / Path(*relative.split("/"))
        if not path.is_file() or int(row.get("bytes", -1)) != path.stat().st_size or str(row.get("sha256") or "").lower() != _sha(path) or row.get("mode") != "0644":
            raise ValueError(f"failed-attempt evidenceInventory hash/mode mismatch: {relative}")
    modes = _json(extracted / "EVIDENCE-MODES.json")
    mode_by_path = {str(row.get("path")): row for row in modes if isinstance(row, dict)} if isinstance(modes, list) else {}
    if set(mode_by_path) != set(FAILED_ATTEMPT_CURRENT_RECORDS) or any(row.get("posixMode") != 420 or row.get("mode") != "0644" for row in mode_by_path.values()):
        raise ValueError("failed-attempt evidence mode inventory is missing or contradictory")
    hash_rows = {}
    for line in (extracted / "EVIDENCE-SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
        if line.strip():
            digest, relative = line.split("  ", 1)
            hash_rows[relative] = digest.lower()
    if set(hash_rows) != set(FAILED_ATTEMPT_CURRENT_RECORDS) or any(hash_rows[path] != inventory_by_path[path]["sha256"] for path in FAILED_ATTEMPT_CURRENT_RECORDS):
        raise ValueError("failed-attempt evidence hash inventory is missing or contradictory")


def _safe_name(name: str) -> str:
    normalized = name.replace("\\", "/")
    pure = PurePosixPath(normalized)
    if not normalized or pure.is_absolute() or ".." in pure.parts:
        raise ValueError(f"unsafe ZIP entry: {name}")
    if any(part.lower() in FORBIDDEN_PARTS for part in pure.parts):
        raise ValueError(f"transient or generated ZIP entry: {name}")
    if "outputs" in {part.lower() for part in pure.parts} and normalized not in ALLOWED_OUTPUT_METADATA:
        raise ValueError(f"non-metadata output ZIP entry: {name}")
    if pure.name.lower().endswith((".pyc", ".pyo")):
        raise ValueError(f"compiled Python ZIP entry: {name}")
    return str(pure)


def _extract(archive: Path, destination: Path) -> list[str]:
    names: list[str] = []
    with zipfile.ZipFile(archive) as bundle:
        for info in bundle.infolist():
            name = _safe_name(info.filename)
            if name in names:
                raise ValueError(f"duplicate ZIP entry: {name}")
            names.append(name)
            file_type = (info.external_attr >> 16) & stat.S_IFMT(0o170000)
            if file_type in (stat.S_IFLNK, stat.S_IFCHR, stat.S_IFBLK, stat.S_IFIFO):
                raise ValueError(f"unsupported special ZIP entry: {name}")
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if not info.is_dir():
                with bundle.open(info) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)
                mode = (info.external_attr >> 16) & 0o777
                if mode and os.name != "nt":
                    target.chmod(mode)
    return names


def _run_optional(command: list[str], cwd: Path, timeout: int = 120) -> dict[str, Any]:
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return {"status": "SKIPPED", "reason": f"tool unavailable: {command[0]}"}
    except subprocess.TimeoutExpired:
        return {"status": "FAIL", "reason": f"timeout: {' '.join(command)}"}
    if completed.returncode:
        return {
            "status": "FAIL",
            "reason": f"exit {completed.returncode}: {(completed.stderr or completed.stdout)[-2000:]}",
        }
    return {"status": "PASS", "command": command, "stdout": completed.stdout, "stderr": completed.stderr}


def _run_candidate_validator(command: list[str], cwd: Path, mode: str) -> dict[str, Any]:
    """Run and preserve the candidate-bound validator's structured result."""
    result = _run_optional(command, cwd)
    if result.get("status") != "PASS":
        return result
    