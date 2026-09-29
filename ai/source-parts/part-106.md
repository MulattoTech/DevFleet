# DevFleet source part 106

Full-source UTF-8 byte interval [4882500, 4929000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: c96e994d477d4781d536120c54dbd249e84cceb53f8ded9e341cc5698726b485

<!-- BEGIN SOURCE SLICE -->
cs/11-REMOTE-VSCODE.md", "docs/12-UPGRADING-FROM-1.0.0.md",
    "docs/13-PERFORMANCE-TUNING.md",
]
CORE = {"generic", "python", "python-fastapi", "node", "typescript-node",
        "typescript-next", "go-service", "dotnet-service", "java-spring", "rust-service"}


DEFAULT_EXTERNAL_TIMEOUT_SECONDS = 120
DEFAULT_EXTERNAL_OUTPUT_LIMIT = 2 * 1024 * 1024


def _terminate_process_tree(process: subprocess.Popen[bytes]) -> None:
    """Terminate one external hook and descendants without relying on shell quoting."""
    if process.poll() is not None:
        return
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=10,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass
    else:
        try:
            import signal

            os.killpg(process.pid, signal.SIGKILL)
        except (OSError, ProcessLookupError):
            pass
    try:
        process.kill()
    except OSError:
        pass


def run_bounded(
    args: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: float = DEFAULT_EXTERNAL_TIMEOUT_SECONDS,
    output_limit: int = DEFAULT_EXTERNAL_OUTPUT_LIMIT,
    label: str = "external hook",
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """Run a package hook with a deadline, process-tree kill, and bounded output."""
    if output_limit <= 0 or timeout <= 0:
        raise ValueError("run_bounded limits must be positive")
    creationflags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0) if os.name == "nt" else 0
    process = subprocess.Popen(
        args,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=os.name != "nt",
        creationflags=creationflags,
    )
    captured: dict[str, bytearray] = {"stdout": bytearray(), "stderr": bytearray()}
    overflow = threading.Event()

    def drain(name: str, stream: object) -> None:
        assert hasattr(stream, "read")
        reader = stream  # type: ignore[assignment]
        while True:
            chunk = reader.read(65536)
            if not chunk:
                return
            remaining = output_limit - len(captured[name])
            if len(chunk) > remaining:
                if remaining > 0:
                    captured[name].extend(chunk[:remaining])
                overflow.set()
                return
            captured[name].extend(chunk)

    threads = [
        threading.Thread(target=drain, args=(name, stream), daemon=True)
        for name, stream in (("stdout", process.stdout), ("stderr", process.stderr))
    ]
    for thread in threads:
        thread.start()
    deadline = time.monotonic() + timeout
    timed_out = False
    while process.poll() is None:
        if overflow.is_set():
            _terminate_process_tree(process)
            break
        if time.monotonic() >= deadline:
            timed_out = True
            _terminate_process_tree(process)
            break
        time.sleep(0.02)
    if timed_out:
        reason = f"{label} exceeded {timeout:g}s timeout"
    elif overflow.is_set():
        reason = f"{label} exceeded {output_limit} byte output limit"
    else:
        reason = ""
    if reason:
        process.wait(timeout=10)
    for thread in threads:
        thread.join(timeout=10)
    result = subprocess.CompletedProcess(
        args,
        process.returncode,
        captured["stdout"].decode(errors="replace"),
        captured["stderr"].decode(errors="replace"),
    )
    if reason:
        raise RuntimeError(f"{reason}; stdout/stderr excerpt: {result.stdout[-1000:]} {result.stderr[-1000:]}")
    if check and result.returncode:
        raise subprocess.CalledProcessError(result.returncode, args, result.stdout, result.stderr)
    return result


def is_transient(path: Path, root: Path = ROOT) -> bool:
    """Return whether a path belongs to generated/test state excluded from a package."""
    return any(is_transient_part(part) for part in path.relative_to(root).parts)


def package_files(root: Path = ROOT) -> set[str]:
    return {
        p.relative_to(root).as_posix()
        for p in root.rglob("*")
        if p.is_file() and not is_transient(p, root)
    }


def require_files(root: Path = ROOT) -> None:
    for rel in REQUIRED:
        assert (root / rel).is_file(), f"missing {rel}"


def parse_data(root: Path = ROOT) -> None:
    for rel in package_files(root):
        p = root / rel
        if p.suffix == ".json":
            json.loads(p.read_text(encoding="utf-8"))
    vscode = root / "client/vscode-settings.jsonc"
    json.loads(re.sub(r"(?m)^\s*//.*$", "", vscode.read_text(encoding="utf-8")))
    for p in list((root / "cloud-init").glob("*.yaml")) + list((root / "templates").glob("*/compose.yaml")):
        assert isinstance(yaml.safe_load(p.read_text(encoding="utf-8")), dict), f"YAML root is not mapping: {p}"


def compile_python_jinja(root: Path = ROOT) -> None:
    with tempfile.TemporaryDirectory() as td:
        cache = Path(td)
        for rel in package_files(root):
            p = root / rel
            if p.suffix == ".py":
                py_compile.compile(str(p), cfile=str(cache / (hashlib.sha256(rel.encode()).hexdigest() + ".pyc")), doraise=True)
    jinja2.Environment().parse((root / "app/templates/index.html").read_text(encoding="utf-8"))


def bash_available() -> bool:
    try:
        return shutil.which("bash") is not None and run_bounded(["bash", "-c", "exit 0"], timeout=5, label="bash probe", check=False).returncode == 0
    except (OSError, RuntimeError):
        return False


def bash_syntax(root: Path = ROOT) -> None:
    if not bash_available():
        return
    for rel in package_files(root):
        p = root / rel
        if p.suffix == ".sh" or (p.parts and p.parts[-1] == "devfleet-switch-docker-mode"):
            run_bounded(["bash", "-n", str(p)], label=f"bash syntax check {p}")


def linux_executable_hooks(root: Path = ROOT) -> None:
    """Require every command-referenced template hook to be exactly 0755."""
    hooks = executable_template_hooks(root)
    assert hooks, "no executable template hooks were derived from metadata"
    for rel in sorted(hooks):
        p = root / rel
        assert p.is_file(), f"trusted hook is not a regular file: {p}"
        if os.name != "nt":
            assert p.stat().st_mode & 0o777 == 0o755, f"template hook mode is not 0755: {p}"
        first = p.read_text(encoding="utf-8").splitlines()[0] if p.stat().st_size else ""
        assert first == "#!/usr/bin/env bash", f"trusted hook has invalid shebang: {p}"


def powershell_lexical(root: Path = ROOT) -> None:
    pairs = {"(": ")", "[": "]", "{": "}"}
    for rel in package_files(root):
        p = root / rel
        if p.suffix not in {".ps1", ".psm1"}:
            continue
        t = p.read_text(encoding="utf-8-sig")
        stack: list[str] = []
        quote = here = None
        i = 0
        line = True
        while i < len(t):
            if here:
                end = "'@" if here == "'" else '"@'
                if line and t.startswith(end, i):
                    here = None; i += 2; line = False; continue
                line = t[i] == "\n"; i += 1; continue
            c = t[i]
            if quote:
                if c == "`": i += 2; continue
                if c == quote:
                    if quote == "'" and i + 1 < len(t) and t[i + 1] == "'": i += 2; continue
                    quote = None
                line = c == "\n"; i += 1; continue
            if line and t.startswith("@'", i): here = "'"; i += 2; line = False; continue
            if line and t.startswith('@"', i): here = '"'; i += 2; line = False; continue
            if c == "#":
                while i < len(t) and t[i] != "\n": i += 1
                line = True; continue
            if c in "'\"": quote = c
            elif c in pairs: stack.append(c)
            elif c in pairs.values(): assert stack and pairs[stack.pop()] == c, f"unbalanced {c} in {p}"
            line = c == "\n"; i += 1
        assert not stack and quote is None and here is None, f"unbalanced PowerShell structure: {p}"


def template_smoke(root: Path = ROOT) -> None:
    if not bash_available():
        return
    for source in (root / "templates").glob("*"):
        if not source.is_dir() or is_transient(source, root):
            continue
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "demo"; shutil.copytree(source, dest)
            for p in dest.rglob("*"):
                if p.is_file() and not p.is_symlink():
                    try:
                        p.write_text(p.read_text().replace("__PROJECT_SLUG__", "demo-project").replace("__PROJECT_NAME__", "Demo Project").replace("__PROJECT_PROFILE__", "balanced").replace("__PROJECT_LANGUAGE__", "test").replace("__PROJECT_FRAMEWORK__", "test").replace("__OLLAMA_BASE_URL__", "http://127.0.0.1:11434/v1").replace("__OLLAMA_MODEL__", "test-model"))
                    except UnicodeDecodeError:
                        pass
            meta = json.loads((dest / ".devfleet/template.json").read_text())
            smoke = ".devfleet/smoke-test.sh"
            if (dest / smoke).is_file():
                run_bounded(["bash", str(dest / smoke)], cwd=dest, label=f"template smoke {source.name}")
            if source.name in CORE:
                for key in ("bootstrap_command", "format_command", "lint_command", "test_command", "health_command"):
                    assert meta.get(key), f"{source.name} missing {key}"


def codexpro_guard_tests(root: Path = ROOT) -> None:
    """Exercise the production /workspaces guard without running CodexPro."""
    if not bash_available():
        print("CodexPro guard tests skipped: POSIX bash is unavailable.")
        return
    hook = root / "templates/generic/.devfleet/codexpro-bootstrap.sh"
    with tempfile.TemporaryDirectory() as outside:
        refused = run_bounded(["bash", str(hook)], cwd=Path(outside), label="CodexPro guard refusal", check=False)
        assert refused.returncode == 2, "CodexPro hook must refuse a non-/workspaces project root"
        assert "must be under /workspaces" in refused.stderr
    workspaces = Path("/workspaces")
    try:
        workspaces.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=workspaces) as valid:
            accepted = run_bounded(["bash", str(hook)], cwd=Path(valid), label="CodexPro guard success", check=False)
            assert accepted.returncode == 0, accepted.stderr
    except (OSError, PermissionError):
        print("CodexPro success-path test skipped: /workspaces is unavailable.")


def fastapi_smoke(root: Path = ROOT) -> None:
    try:
        import fastapi  # noqa: F401
    except ModuleNotFoundError as exc:
        print(f"FastAPI smoke skipped: verification environment does not provide runtime dependency {exc.name}.")
        return
    except SystemError as exc:
        if "pydantic-core version" in str(exc):
            print("FastAPI smoke skipped: local Python dependency set has an existing pydantic/pydantic-core mismatch.")
            return
        raise
    with tempfile.TemporaryDirectory() as td:
        b = Path(td); [(b / d).mkdir() for d in ("workspaces", "quarantine", "runtime", "cache")]
        cfg = {"node_name": "verify", "node_role": "primary", "friendly_name": "CodexDevVM", "portal_port": 8787, "workspaces": str(b / "workspaces"), "quarantine": str(b / "quarantine"), "peer_file": str(b / "peer.json"), "runtime_root": str(b / "runtime"), "cache_root": str(b / "cache"), "development_profile": "balanced", "docker_mode": "rootless", "ollama_base_url": "", "ollama_model": "", "ollama_profile": "stable-interactive", "require_tailscale": False, "public_binding_allowed": True}
        (b / "config.json").write_text(json.dumps(cfg)); (b / "peer.json").write_text("{}")
        env = os.environ.copy(); env.update({"PYTHONPATH": str(root / "app"), "DEVFLEET_CONFIG_PATH": str(b / "config.json"), "DEVFLEET_STATIC_DIR": str(root / "app/static"), "DEVFLEET_TEMPLATE_DIR": str(root / "app/templates"), "DEVFLEET_ADMIN_USER": "x", "DEVFLEET_ADMIN_PASSWORD": "y", "DEVFLEET_API_TOKEN": "z"})
        code = 'from fastapi.testclient import TestClient;from devfleet.main import app;r=TestClient(app).get("/healthz");assert r.status_code==200 and r.json()["agent_version"]=="' + PACKAGE_VERSION + '"'
        run_bounded([sys.executable, "-c", code], env=env, label="FastAPI smoke")


def verify_checksums(root: Path = ROOT) -> None:
    p = root / CHECKSUM_MANIFEST
    assert p.is_file(), "missing checksum manifest"
    entries: dict[str, str] = {}
    for line in p.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        parts = line.split("  ", 1)
        assert len(parts) == 2 and re.fullmatch(r"[0-9a-fA-F]{64}", parts[0]), f"malformed checksum line: {line}"
        expected, rel = parts; rel = rel.replace("\\", "/")
        assert rel != CHECKSUM_MANIFEST and not is_transient(root / rel, root), f"invalid checksum target: {rel}"
        assert rel not in entries, f"duplicate checksum entry: {rel}"
        target = root / rel
        try:
            target.resolve().relative_to(root.resolve())
        except ValueError:
            raise AssertionError(f"checksum target escapes package root: {rel}")
        assert target.is_file(), f"missing checksum target {rel}"
        actual = hashlib.sha256(target.read_bytes()).hexdigest().lower()
        if actual != expected.lower() and target.is_file():
            # Windows may materialize committed LF text as CRLF. Accept only
            # the exact LF-normalized bytes; content changes still fail.
            raw = target.read_bytes()
            if b"\r" in raw.replace(b"\r\n", b""):
                normalized = None
            else:
                normalized = raw.replace(b"\r\n", b"\n")
            if normalized is not None:
                actual = hashlib.sha256(normalized).hexdigest().lower()
        assert actual == expected.lower(), f"checksum mismatch {rel}"
        entries[rel] = expected.lower()
    eligible = package_files(root) - {CHECKSUM_MANIFEST}
    assert set(entries) == eligible, f"checksum manifest coverage mismatch: missing={sorted(eligible-set(entries))[:10]} extra={sorted(set(entries)-eligible)[:10]}"


def no_empty(root: Path = ROOT) -> None:
    assert not [rel for rel in package_files(root) if (root / rel).stat().st_size == 0 and Path(rel).name != "__init__.py"]


def baseline_preserved(root: Path = ROOT) -> None:
    for rel in (root / "BASELINE-v1.0.0-FILES.txt").read_text(encoding="utf-8").splitlines():
        if rel.strip(): assert (root / rel).exists(), f"v1 baseline path removed: {rel}"


def _safe_member(name: str) -> str:
    normalized = name.replace("\\", "/")
    pure = PurePosixPath(normalized)
    assert normalized and not pure.is_absolute() and ".." not in pure.parts, f"unsafe archive member: {name}"
    assert not any(is_transient_part(part) for part in pure.parts), f"transient archive member: {name}"
    return str(pure)


def _safe_target(dest: Path, name: str) -> Path:
    target = dest / name
    try:
        target.resolve().relative_to(dest.resolve())
    except ValueError:
        raise AssertionError(f"archive member escapes extraction root: {name}")
    return target


def _extract_regular_zip_member(archive: zipfile.ZipFile, info: zipfile.ZipInfo, dest: Path, name: str) -> None:
    target = _safe_target(dest, name)
    target.parent.mkdir(parents=True, exist_ok=True)
    mode = (info.external_attr >> 16) & 0o170000
    assert mode not in (stat.S_IFLNK, stat.S_IFDIR), f"unsupported ZIP entry type: {name}"
    with archive.open(info, "r") as source, target.open("xb") as output:
        shutil.copyfileobj(source, output)
    archived_mode = (info.external_attr >> 16) & 0o777
    if archived_mode and os.name != "nt":
        target.chmod(archived_mode)


def _extract_regular_tar_member(archive: tarfile.TarFile, info: tarfile.TarInfo, dest: Path, name: str) -> None:
    assert info.isfile(), f"unsupported TAR entry type: {name}"
    target = _safe_target(dest, name)
    target.parent.mkdir(parents=True, exist_ok=True)
    source = archive.extractfile(info)
    assert source is not None, f"TAR member could not be read: {name}"
    with source, target.open("xb") as output:
        shutil.copyfileobj(source, output)
    if os.name != "nt":
        target.chmod(info.mode & 0o777)


def verify_archive(path: Path) -> None:
    """Validate and clean-extract a zip/tar release archive without running it."""
    assert path.is_file(), f"archive not found: {path}"
    with tempfile.TemporaryDirectory() as td:
        dest = Path(td); names: set[str] = set(); modes: dict[str, int] = {}
        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as archive:
                for info in archive.infolist():
                    name = _safe_member(info.filename)
                    if name.endswith("/"): continue
                    assert name not in names, f"duplicate archive member: {name}"; names.add(name)
                    modes[name] = (info.external_attr >> 16) & 0o777
                    _extract_regular_zip_member(archive, info, dest, name)
        else:
            with tarfile.open(path, "r:*") as archive:
                for info in archive.getmembers():
                    name = _safe_member(info.name)
                    if info.isdir(): continue
                    assert name not in names, f"duplicate archive member: {name}"; names.add(name); modes[name] = info.mode & 0o777
                    assert info.isfile(), f"unsupported TAR entry type: {name}"
                    _extract_regular_tar_member(archive, info, dest, name)
        assert set(REQUIRED).issubset(names), f"archive missing required files: {sorted(set(REQUIRED)-names)[:10]}"
        hooks = [name for name in names if name in executable_template_hooks(dest)]
        assert hooks, "archive contains no trusted template hooks"
        for name in hooks:
            assert modes.get(name, 0) == 0o755, f"template hook does not have 0755 mode in archive: {name}"
            # Windows extraction APIs do not expose POSIX execute bits. The
            # archive mode is still checked above; on POSIX, also verify the
            # mode survived the actual clean extraction.
            if os.name != "nt":
                assert (dest / name).stat().st_mode & 0o111, f"trusted template hook lost executable mode after extraction: {name}"
        assert CHECKSUM_MANIFEST in names, "archive missing checksum manifest"


def archive_structural_checks(root: Path = ROOT) -> None:
    """Round-trip a clean tar archive to exercise release structure and modes."""
    with tempfile.TemporaryDirectory() as td:
        archive = Path(td) / "package.tar.gz"
        hooks = executable_template_hooks(root)
        with tarfile.open(archive, "w:gz") as out:
            for rel in sorted(package_files(root)):
                source = root / rel; info = out.gettarinfo(str(source), arcname=rel)
                if rel in hooks: info.mode = 0o755
                with source.open("rb") as stream: out.addfile(info, stream)
        verify_archive(archive)


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(); parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    assert re.fullmatch(r"\d+\.\d+\.\d+", PACKAGE_VERSION), PACKAGE_VERSION
    require_files(); parse_data(); compile_python_jinja(); bash_syntax(); linux_executable_hooks(); powershell_lexical(); template_smoke(); codexpro_guard_tests(); fastapi_smoke(); no_empty(); baseline_preserved(); verify_checksums(); archive_structural_checks()
    if args.archive: verify_archive(args.archive)
    print(f"DevFleet v{PACKAGE_VERSION} offline package verification passed.")


if __name__ == "__main__":
    main()

```


## FILE: source/tools/write_posix_zip.py

SHA256: 10088dbe4b07289b6f3df8811a75a2c58a2ad65b0b44f728f448c7cbc2129cda | Bytes: 1706 | Git mode: 100644

```
"""Write a deterministic ZIP whose entries advertise Unix file modes."""
from __future__ import annotations

import argparse
import json
import stat
import zipfile
from pathlib import Path


def _mode_map(path: Path) -> dict[str, int]:
    values = json.loads(path.read_text(encoding="utf-8-sig"))
    return {str(item["path"]): int(item["posixMode"]) for item in values}


def write_zip(stage: Path, output: Path, modes_path: Path) -> None:
    modes = _mode_map(modes_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        paths = sorted(stage.rglob("*"), key=lambda item: item.relative_to(stage).as_posix())
        for path in paths:
            name = path.relative_to(stage).as_posix()
            if path.is_dir():
                continue
            if not path.is_file():
                continue
            mode = modes.get(name, 0o644)
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | (mode & 0o7777)) << 16
            with path.open("rb") as handle:
                archive.writestr(info, handle.read(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--modes", type=Path, required=True)
    args = parser.parse_args()
    write_zip(args.stage, args.output, args.modes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/windows/00-Preflight.ps1

SHA256: e9a3edb41802e9a01d76641f133430d683c84d37cf43604a492ebf106827c731 | Bytes: 4118 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role,[ValidateSet('Offline','Connected')][string]$InstallationMode='Offline')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7; Assert-Administrator
$config=Get-DevFleetConfig

Write-Host "`nPreflight for $Role on $env:COMPUTERNAME ($InstallationMode)" -ForegroundColor Cyan
$os=Get-CimInstance Win32_OperatingSystem
$cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$sys=Get-CimInstance Win32_ComputerSystem
$drive=Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
$virtFirmware=$cpu.VirtualizationFirmwareEnabled
$slat=$cpu.SecondLevelAddressTranslationExtensions
$nestedHyperVOperational=$false
if (-not $slat) {
  try { Get-VMHost -ErrorAction Stop | Out-Null; $nestedHyperVOperational=$true } catch { }
}

[pscustomobject]@{
  Windows=$os.Caption
  Version=$os.Version
  CPU=$cpu.Name
  LogicalProcessors=$sys.NumberOfLogicalProcessors
  RAMGB=[math]::Round($sys.TotalPhysicalMemory/1GB,1)
  SystemDriveFreeGB=[math]::Round($drive.Free/1GB,1)
  VirtualizationFirmwareEnabled=$virtFirmware
  SLAT=$slat
  OperationalHyperVHost=$nestedHyperVOperational
} | Format-List

if (-not $virtFirmware) { throw 'Hardware virtualization is disabled in UEFI/BIOS.' }
if (-not $slat -and -not $nestedHyperVOperational) { throw 'Second Level Address Translation is required.' }
# Conservatively adapt defaults to this machine instead of overcommitting RAM/CPU.
$ramGB=[math]::Floor($sys.TotalPhysicalMemory/1GB);$logical=[int]$sys.NumberOfLogicalProcessors;$changed=$false
if($Role -eq 'Desktop'){
  $mem=[math]::Max(8,[math]::Min(32,[math]::Floor($ramGB*0.60)));$cpus=[math]::Max(2,[math]::Min(12,$logical-2))
  if($config.Primary.Memory -ne "${mem}G"){$config.Primary.Memory="${mem}G";$changed=$true}
  if([int]$config.Primary.Cpus -ne $cpus){$config.Primary.Cpus=$cpus;$changed=$true}
}else{
  $profile=$config.RoleProfiles.LaptopSurrogate
  if(-not $profile -or -not $profile.Recommended -or -not $profile.MinimumTested){throw 'Laptop/Surrogate resource policy is missing from the canonical configuration.'}
  $failMem=[int]([string]$profile.Recommended.FailoverMemory -replace '[^0-9.]','')
  $vaultMem=[int]([string]$profile.Recommended.VaultMemory -replace '[^0-9.]','')
  $minimumFailMem=[int]([string]$profile.MinimumTested.FailoverMemory -replace '[^0-9.]','')
  $minimumVaultMem=[int]([string]$profile.MinimumTested.VaultMemory -replace '[^0-9.]','')
  if($failMem -lt $minimumFailMem -or $vaultMem -lt $minimumVaultMem){throw 'Canonical Laptop/Surrogate resource policy is below the tested minimum.'}
  $failCpu=[math]::Max(2,[math]::Min(4,$logical-2));$vaultCpu=[math]::Max(1,[math]::Min(2,[math]::Floor($logical/4)))
  if($config.Failover.Memory -ne "${failMem}G"){$config.Failover.Memory="${failMem}G";$changed=$true}
  if($config.Vault.Memory -ne "${vaultMem}G"){$config.Vault.Memory="${vaultMem}G";$changed=$true}
  if([int]$config.Failover.Cpus -ne $failCpu){$config.Failover.Cpus=$failCpu;$changed=$true}
  if([int]$config.Vault.Cpus -ne $vaultCpu){$config.Vault.Cpus=$vaultCpu;$changed=$true}
}
if($changed){Save-DevFleetConfig $config;Write-Host 'VM CPU/RAM defaults were adjusted conservatively for this computer.' -ForegroundColor Yellow}
$requiredFree = if ($Role -eq 'Desktop') { 120 } else { 100 }
if (($drive.Free/1GB) -lt $requiredFree) { throw "At least $requiredFree GB free is required with current defaults. Reduce VM disk sizes in the config or free space." }

$edition=(Get-ComputerInfo -Property WindowsProductName).WindowsProductName
$hyperVCapable=$edition -match 'Pro|Enterprise|Education'
if (-not $hyperVCapable) { Write-Warning 'Hyper-V is not included in this Windows edition. Multipass will require VirtualBox.' }

$conflicts=Get-Process -Name 'MuMuPlayer','NemuHeadless','VBoxHeadless','vmware' -ErrorAction SilentlyContinue
if ($conflicts) { Write-Warning 'A virtualization/emulator process is running. Close it before installing or changing a hypervisor.' }
Write-Host 'Preflight passed.' -ForegroundColor Green

```


## FILE: source/windows/01-Install-Prerequisites.ps1

SHA256: bc4d60449c0633509984438a3a41a8d5077222e66ca57e79f20f621fe076f81b | Bytes: 12943 | Git mode: 100644

```
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role,
  [Parameter(Mandatory)][string]$OfflinePackageRoot,
  [ValidateSet('Offline','Connected')][string]$InstallationMode='Offline',
  [switch]$SkipWindowsUpdates
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7; Assert-Administrator

function Test-InstalledCommand([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
$manifest=Get-CanonicalDependencyManifest -PackageRoot $OfflinePackageRoot
function Get-OfflinePayload([string]$PackageId) {
  $manifestPath=Join-Path $OfflinePackageRoot 'OFFLINE-DEPENDENCIES.json'
  if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ throw 'Release-bound offline dependency manifest is missing.' }
  $offline=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if($offline.schemaVersion -ne 2 -or [string]$offline.devfleetVersion -ne '1.2.13' -or -not $offline.releaseBinding){ throw 'Offline dependency manifest is not bound to this DevFleet release.' }
  $entries=@($offline.payloads)
  $duplicateDependency=$entries | Group-Object dependencyId | Where-Object Count -ne 1
  $duplicateFile=$entries | Group-Object filename | Where-Object Count -ne 1
  if($duplicateDependency -or $duplicateFile){ throw 'Offline dependency manifest contains duplicate payload identities.' }
  # PowerShell unwraps a one-item pipeline result. Keep the exact-match
  # collection an array before reading Count so a valid singleton payload
  # cannot fail with a missing-property error.
  $entry=@($entries | Where-Object { [string]$_.dependencyId -eq $PackageId })
  if($entry.Count -ne 1){ throw "No exact release-bound offline payload exists for $PackageId. Connected mode is required for this target." }
  if([IO.Path]::IsPathRooted([string]$entry[0].filename) -or ([string]$entry[0].filename).Contains('..')){ throw 'Offline payload filename escapes the release package root.' }
  $payloadPath=Join-Path $OfflinePackageRoot ([string]$entry[0].filename)
  if(-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)){ throw "Exact offline payload is missing: $($entry[0].filename)." }
  $item=Get-Item -LiteralPath $payloadPath -Force
  if([int64]$item.Length -ne [int64]$entry[0].sizeBytes){ throw "Offline payload size mismatch for $($item.Name)." }
  $actual=(Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual -ne ([string]$entry[0].sha256).ToLowerInvariant()){ throw "Offline prerequisite hash mismatch for $($item.Name)." }
  $allFiles=@(Get-ChildItem -LiteralPath $OfflinePackageRoot -File -Recurse | Where-Object Name -ne 'OFFLINE-DEPENDENCIES.json')
  $allowed=@($entries | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $OfflinePackageRoot ([string]$_.filename))) })
  if(@($allFiles | Where-Object { $allowed -notcontains $_.FullName }).Count -gt 0){ throw 'Unlisted offline payload files are rejected.' }
  return $payloadPath
}
function Install-OfflinePayload([string]$PackageId,[string[]]$Arguments) {
  $payload=Get-OfflinePayload $PackageId
  $dependency=@($manifest.dependencies)|Where-Object id -eq $PackageId|Select-Object -First 1
  if(-not $dependency){throw "Dependency id is not present in canonical manifest: $PackageId"}
  $strategy=Get-AuthenticityStrategy $dependency.installerAuthenticityPolicy
  if($strategy -ne 'VendorReleaseSha256'){Test-OfficialSigner -Path $payload -Policy $dependency.installerAuthenticityPolicy}
  $ext=[IO.Path]::GetExtension($payload).ToLowerInvariant()
  if($ext -eq '.msi') { $msiexec=Join-Path $env:WINDIR 'System32\msiexec.exe';if(-not (Test-TrustedExecutableCandidate $msiexec)){throw 'Trusted Windows Installer executable was not found.'};Invoke-External -FilePath $msiexec -ArgumentList (@('/i',$payload,'/qn','/norestart')) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') -AllowedExitCodes @(0,3010) | Out-Null }
  elseif($ext -eq '.exe') { Invoke-External -FilePath $payload -ArgumentList $Arguments -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') -AllowedExitCodes @(0,3010) | Out-Null }
  else { throw "Unsupported offline installer type for ${PackageId}: $ext" }
}
function Ensure-Dependency([string]$Id,[switch]$FeatureRequested) {
  $dependency=@($manifest.dependencies)|Where-Object id -eq $Id|Select-Object -First 1
  if(-not $dependency){throw "Dependency id is not present in canonical manifest: $Id"}
  $detected=if($Id -ceq 'multipass'){
    Wait-DevFleetDependencyStatus -Dependency $dependency -MaximumAttempts (Get-DevFleetDependencyProbeAttemptLimit -Dependency $dependency)
  }else{
    Get-DependencyStatus -Dependency $dependency
  }
  Write-Host "$($dependency.displayName): detected=$($detected.Version) path=$($detected.Path) status=$($detected.Status)" -ForegroundColor Cyan
   if($detected.Status -eq 'Compatible'){Write-Host "Preserving compatible prerequisite: $($dependency.displayName)";return}
  if(-not $dependency.required -and [string]$dependency.classification -in @('OPTIONAL','RECOMMENDED') -and -not $FeatureRequested){Write-Warning "$($dependency.displayName) is $($dependency.classification.ToLowerInvariant()) for core installation; leaving its feature unavailable rather than forcing acquisition.";return}
  if($detected.Status -eq 'Unsupported-Major'){throw "$($dependency.displayName) major version $($detected.Version) is outside the supported policy."}
  if($InstallationMode -eq 'Offline'){
    if($dependency.required){Install-OfflinePayload $dependency.wingetPackageId @()}
    else{Write-Warning "Optional prerequisite is absent or incompatible and no local payload was selected: $($dependency.displayName)"}
  }else{
    $health=Get-WingetHealth
    if($health.Status -eq 'Healthy' -and $dependency.wingetPackageId){
      try { Install-WingetPackage -Id $dependency.wingetPackageId -Upgrade:($detected.Status -eq 'Outdated') }
      catch {
        if($_.Exception.Message -notmatch '(?i)External command timed out' -or -not $dependency.directOfficialVendorResolver){throw}
        Write-Warning "WinGet stalled for $($dependency.displayName); switching to the authenticated official vendor resolver."
        Install-OfficialDependency -Dependency $dependency
      }
    }
    else{Write-Warning "WinGet $($health.Status); using direct official fallback for $($dependency.displayName).";Install-OfficialDependency -Dependency $dependency}
  }
  $after=if($Id -ceq 'multipass'){
    Wait-DevFleetDependencyStatus -Dependency $dependency -MaximumAttempts (Get-DevFleetDependencyProbeAttemptLimit -Dependency $dependency)
  }else{
    Get-DependencyStatus -Dependency $dependency
  }
  if($after.Status -notin @('Compatible')){throw "$($dependency.displayName) did not reach a compatible post-install state: $($after.Status) ($($after.Detail))"}
  Write-Host "Verified post-install: $($dependency.displayName) $($after.Version) at $($after.Path)" -ForegroundColor Green
}

function Install-VsCodeExtension([string]$CodeCli,[string]$Extension) {
  $cmd=Join-Path $env:WINDIR 'System32\cmd.exe'
  if(-not (Test-TrustedExecutableCandidate $cmd)){throw 'Trusted command interpreter was not found for the optional VS Code integration.'}
  $quotedCode='"'+$CodeCli.Replace('"','""')+'"'
  $quotedExtension='"'+$Extension.Replace('"','""')+'"'
  Invoke-External -FilePath $cmd -ArgumentList @('/d','/s','/c',"$quotedCode --install-extension $quotedExtension --force") -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'vscodeExtension') | Out-Null
}

function Invoke-MultipassConfigurationProbe([string]$Multipass,[string[]]$Arguments,[string]$FailureMessage) {
  $context=Get-DevFleetDeadlineContext
  $operationDeadline=[DateTime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'multipassConfiguration'))
  if($context -and ([datetime]$context.StageDeadlineUtc -lt $operationDeadline)){$operationDeadline=[datetime]$context.StageDeadlineUtc}
  # The configured operation deadline is the finite retry bound. A fixed
  # attempt count can expire during a transient Multipass daemon/backend
  # readiness window after a Hyper-V checkpoint restore even though the
  # inherited 600-second operation budget is still available.
  while([DateTime]::UtcNow -lt $operationDeadline){
    $remaining=[int][math]::Floor(($operationDeadline-[DateTime]::UtcNow).TotalSeconds)
    if($remaining -le 0){break}
    try {
      return (Invoke-External $Multipass $Arguments -Capture -TimeoutSeconds ([math]::Min(60,$remaining)) -DeadlineUtc $operationDeadline)
    } catch {
      $sleepSeconds=[math]::Min(1,[math]::Max(0,$remaining-1))
      if($sleepSeconds -gt 0){Start-Sleep -Seconds $sleepSeconds}
    }
  }
  throw $FailureMessage
}

Write-Host "`nInstalling/updating Windows prerequisites ($InstallationMode) ..." -ForegroundColor Cyan
Ensure-Dependency 'git'
Ensure-Dependency 'multipass'
Ensure-Dependency 'tailscale'
Ensure-Dependency 'github-cli'
Ensure-Dependency 'sevenzip'
Ensure-Dependency 'vscode'

$ssh=Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Client*' | Select-Object -First 1
if(-not $ssh){ throw 'Windows OpenSSH Client capability was not found.' }
if($ssh.State -ne 'Installed'){
  if($InstallationMode -eq 'Offline'){ throw 'OpenSSH Client is not installed and Windows capability acquisition is not supported by this Full Offline profile.' }
  Add-WindowsCapability -Online -Name $ssh.Name | Out-Null
}

$edition=(Get-ComputerInfo -Property WindowsProductName).WindowsProductName
if($edition -match 'Pro|Enterprise|Education'){
  $feature=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
  if($feature.State -ne 'Enabled'){
    Write-Warning 'Enabling Hyper-V. A reboot will be required before VM provisioning.'
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart | Out-Null
  }
}else{
  Ensure-Dependency 'virtualbox' -FeatureRequested
}

if(-not (Test-PendingReboot)){
  $mp=Get-MultipassExe
  $desiredDriver=if($edition -match 'Pro|Enterprise|Education'){'hyperv'}else{'virtualbox'}
  # Verify the restored daemon state before writing it. Re-applying an already
  # selected driver can restart Multipass while a nested instance is starting,
  # leaving the control-plane socket unavailable to the following probe.
  $selectedDriver=([string](Invoke-MultipassConfigurationProbe $mp @('get','local.driver') 'Multipass did not become ready before driver verification.')).Trim()
  if($selectedDriver -ne $desiredDriver){
    Invoke-External $mp @('set',"local.driver=$desiredDriver") -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'multipassConfiguration')
    $selectedDriver=([string](Invoke-MultipassConfigurationProbe $mp @('get','local.driver') 'Multipass did not become ready after the driver setting was applied.')).Trim()
  }
  if($selectedDriver -ne $desiredDriver){throw "Multipass did not select the required driver: $selectedDriver (expected $desiredDriver)"}
  $selectedPrivilegedMounts=([string](Invoke-MultipassConfigurationProbe $mp @('get','local.privileged-mounts') 'Multipass did not become ready before privileged-mount verification.')).Trim()
  if($selectedPrivilegedMounts -ne 'false'){
    Invoke-External $mp @('set','local.privileged-mounts=false') -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'multipassConfiguration')
    Invoke-MultipassConfigurationProbe $mp @('get','local.privileged-mounts') 'Multipass did not become ready after privileged mounts were disabled.'
  }
}else{ Write-Warning 'Hypervisor configuration will finish automatically when this installer is re-run after reboot.' }

$code=Get-VsCodeCli
if($code){
  $vsixRoot=Join-Path $OfflinePackageRoot 'vsix'
  foreach($ext in @('ms-vscode-remote.remote-ssh','ms-vscode-remote.remote-containers','ms-vscode.remote-explorer')){
    if($InstallationMode -eq 'Offline'){
      $vsix=Get-ChildItem -LiteralPath $vsixRoot -Filter "*$ext*.vsix" -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if($vsix){ Install-VsCodeExtension $code $vsix.FullName } else { Write-Warning "Optional VS Code extension payload is absent: $ext" }
    }else{ Install-VsCodeExtension $code $ext }
  }
}else{ Write-Warning 'VS Code integration is optional and its CLI is not available.' }

if(-not $SkipWindowsUpdates){ Write-Host 'Windows Update is not forced automatically. Install pending Windows security updates, then reboot if Windows requests it.' -ForegroundColor Yellow }
# A prerequisite stage is not durably complete while servicing still requires a
# reboot.  Leaving the marker absent makes the resumed transaction rerun only
# this idempotent prerequisite stage and then advance normally.
if(-not (Test-PendingReboot)){ Write-StageMarker "prereqs-$Role" } else { Write-Warning 'Prerequisite stage remains pending until Windows servicing settles; no completion marker was written.' }

```


## FILE: source/windows/02-Provision-ComputeNode.ps1

SHA256: e06b31924cb383c9d6383c70376b89b49213248f1f09e61aef5dc15d8afff7d1 | Bytes: 9264 | Git mode: 100644

```
[CmdletBinding()]
param(
 [Parameter(Mandatory)][ValidateSet('Primary','Failover')][string]$NodeRole,
 [switch]$ForceReprovision,
 [string]$TransactionId,
 [string]$TransactionPayloadSha256,
 [string]$TransactionAction,
 [string]$TransactionRole,
 [string]$TransactionPreparedUtc
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7; Assert-Administrator
$deadlineContext=Get-DevFleetDeadlineContext
if(-not $deadlineContext){$fallbackDeadline=[DateTime]::UtcNow.AddSeconds((Get-DevFleetStageBudgetSeconds 'compute'));Set-DevFleetDeadlineContext -TransactionDeadlineUtc $fallbackDeadline -StageName 'compute' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'compute') | Out-Null}
$config=Get-DevFleetConfig
$node=if($NodeRole -eq 'Primary'){$config.Primary}else{$config.Failover}
$name=$node.InstanceName
$package=Get-PackageRootFromState
$packageVersion=(Get-Content -LiteralPath (Join-Path $package 'VERSION') -Raw).Trim()
$bootstrapSeconds=Get-DevFleetOperationMaximumSeconds 'guestBootstrap'
$expectedRole=if($NodeRole -eq 'Primary'){'Desktop'}else{'Laptop'}
$activeTransaction=Wait-ActiveDevFleetTransaction -ExpectedRole $expectedRole
if(-not $activeTransaction -and $TransactionId -and $TransactionPayloadSha256 -and $TransactionAction -and $TransactionRole -and $TransactionPreparedUtc){
 $propagated=[pscustomobject]@{transactionId=$TransactionId;payloadSha256=$TransactionPayloadSha256;action=$TransactionAction;role=$TransactionRole;preparedUtc=$TransactionPreparedUtc}
 if(Test-DevFleetTransactionBinding -Transaction $propagated -ExpectedRole $expectedRole){$activeTransaction=$propagated}
}
if(-not $activeTransaction) { throw 'Active DevFleet transaction is missing, malformed, or not bound to this compute role.' }
$bootstrapNodeRole=if($NodeRole -eq 'Failover'){'surrogate'}else{'primary'}
$bootstrapBoundary=New-DevFleetBootstrapBoundary -Kind compute -InstanceName $name -TransactionId ([string]$activeTransaction.transactionId) -PayloadSha256 ([string]$activeTransaction.payloadSha256) -BootstrapMaxSeconds $bootstrapSeconds -PackageVersion $packageVersion -NodeRole $bootstrapNodeRole
$mp=Get-MultipassExe
Write-StageMarker -Name $bootstrapBoundary.multipassResolvedStageName -Transaction $activeTransaction
Assert-MultipassIsolation -InstanceNames @($name)
Write-StageMarker -Name $bootstrapBoundary.isolationVerifiedStageName -Transaction $activeTransaction
$secrets=Get-OrCreateSecrets
$nodeIdentity=Get-OrCreateNodeIdentity -Role $(if($NodeRole -eq 'Primary'){'Desktop'}else{'Laptop'})

$instancePresent=Test-MultipassInstance $name
Write-StageMarker -Name $(if($instancePresent){$bootstrapBoundary.instancePresentStageName}else{$bootstrapBoundary.instanceAbsentStageName}) -Transaction $activeTransaction
if($instancePresent){
 if($ForceReprovision){ throw "Refusing automatic destruction of existing $name. Remove it manually only after verifying backups." }
 Write-Host "$name already exists; updating the DevFleet payload in place." -ForegroundColor Yellow
  Invoke-External $mp @('start',$name) -IgnoreExitCode
  Write-StageMarker -Name $bootstrapBoundary.instanceStartedStageName -Transaction $activeTransaction
  Wait-MultipassReady $name 1200
}else{
 $cloud=Join-Path (Get-DevFleetStateRoot) "tmp\cloud-$name.yaml"
 $template=Get-Content (Join-Path $package 'cloud-init\compute.yaml') -Raw
 $template=$template.Replace('__NODE_NAME__',(ConvertTo-YamlSingleQuotedScalar $name)).Replace('__NODE_ROLE__',(ConvertTo-YamlSingleQuotedScalar $NodeRole.ToLower())).Replace('__GIT_NAME_SHELL__',(ConvertTo-ShellSingleQuotedScalar $config.Git.UserName)).Replace('__GIT_EMAIL_SHELL__',(ConvertTo-ShellSingleQuotedScalar $config.Git.Email))
 Set-Content $cloud $template -Encoding utf8
  # PowerShell `if` is a statement, not an expression; resolve the owning
  # stage deadline before passing it to the fresh-launch recovery helper.
  $launchDeadline=[datetime]::MinValue
  if($deadlineContext){$launchDeadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
  try {
   Invoke-MultipassLaunchWithReadinessRecovery -InstanceName $name -LaunchArguments @('launch',[string]$node.UbuntuImage,'--name',$name,'--cpus',[string]$node.Cpus,'--memory',[string]$node.Memory,'--disk',[string]$node.Disk,'--cloud-init',$cloud) -ReadinessTimeoutSeconds 1200 -DeadlineUtc $launchDeadline -OnInstanceEstablished { param($launch) Write-StageMarker -Name $bootstrapBoundary.instanceLaunchedStageName -Transaction $activeTransaction }
  } catch {
   # Windows servicing can become reboot-pending while Multipass is inside its
   # bounded launch/recovery envelope. Preserve the original launch error for
   # the post-reboot attempt, but first return the native 3010 contract so the
   # installer advances the durable checkpoint instead of treating the stale
   # Hyper-V state as a terminal compute failure.
   if(Test-PendingReboot){Write-Warning 'Windows reported a new reboot requirement during compute launch. Re-run this same transaction after reboot; completed stages will be detected.';exit 3010}
   throw
  }
  if(Test-PendingReboot){Write-Warning 'Windows reported a new reboot requirement after compute launch. Re-run this same transaction after reboot; completed stages will be detected.';exit 3010}
}
Write-StageMarker -Name $bootstrapBoundary.instanceReadyStageName -Transaction $activeTransaction

$tmp=Join-Path (Get-DevFleetStateRoot) "tmp\payload-$name"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $tmp -Force | Out-Null
foreach($d in @('linux','app','templates')){ Copy-Item (Join-Path $package $d) $tmp -Recurse }
Copy-Item (Join-Path $package 'VERSION') (Join-Path $tmp 'VERSION')
$nodeSecrets=[ordered]@{
 NodeName=$name; NodeRole=$bootstrapNodeRole; FriendlyName=[string]$node.FriendlyName; PortalPort=$config.Network.PortalPort; DeploymentId=[string]$nodeIdentity.deployment_id; NodeId=[string]$nodeIdentity.node_id; CoordinatorNodeId=[string]$nodeIdentity.coordinator_node_id; ProtocolVersion=[int]$nodeIdentity.protocol_version
 AdminUser=$secrets.PortalAdminUser; AdminPassword=$secrets.PortalAdminPassword; ApiToken=$secrets.NodeApiToken
 GitName=$config.Git.UserName; GitEmail=$config.Git.Email; OllamaBaseUrl=($(if($config.Ollama.PreferredBaseUrl){$config.Ollama.PreferredBaseUrl}else{$config.Ollama.BaseUrl})); OllamaModel=$config.Ollama.Model; OllamaProfile=$config.Ollama.Profile
 DevelopmentProfile=$config.Development.Profile; DockerMode=($(if($NodeRole -eq 'Primary'){$config.Docker.PrimaryMode}else{$config.Docker.FailoverMode}))
 EnableSharedCaches=[bool]$config.Development.EnableSharedBuildCaches; EnableAnalyzerCache=[bool]$config.Development.EnableAnalyzerCache; AutoStartCodexPro=[bool]$config.Development.AutoStartCodexPro; AllowTailnetPorts=[b