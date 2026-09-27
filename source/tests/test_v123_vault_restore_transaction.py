from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
WINDOWS_GIT_BASH = Path(r"C:\Program Files\Git\bin\bash.exe")
BASH = WINDOWS_GIT_BASH if WINDOWS_GIT_BASH.is_file() else Path(shutil.which("bash") or "")


def unix(path: Path) -> str:
    value = path.resolve().as_posix()
    return "/" + value[0].lower() + value[2:] if value[1:3] == ":/" else value


def executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")
    path.chmod(0o755)


@pytest.mark.parametrize("rollback_collision", [False, True])
def test_canonical_promotion_failure_preserves_the_prior_workspace(
    tmp_path: Path, rollback_collision: bool
):
    assert BASH.is_file(), "A Bash runtime is required for the shipped restore transaction test."
    lab = tmp_path / "lab"
    bin_dir = lab / "bin"
    workspaces = lab / "workspaces"
    quarantine = lab / "quarantine"
    for directory in (bin_dir, workspaces, quarantine, lab / "etc", lab / "run"):
        directory.mkdir(parents=True)
    project = "vault-source"
    project_id = "12345678-1234-1234-1234-123456789abc"
    canonical = workspaces / project
    (canonical / ".devfleet").mkdir(parents=True)
    (canonical / "original.txt").write_text("prior-canonical\n", encoding="utf-8")
    (canonical / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": project,
                "project_id": project_id,
            }
        ),
        encoding="utf-8",
    )
    (lab / "etc/restic.env").write_text("RESTIC_REPOSITORY=test\n", encoding="utf-8")
    (lab / "uuid").write_text("deadbeef-1111-2222-3333-444444444444\n", encoding="utf-8")

    script_text = (ROOT / "linux/devfleet-restore-project").read_text(encoding="utf-8")
    script_text = script_text.replace(
        "set -Eeuo pipefail",
        'set -Eeuo pipefail\nPATH="$DEVFLEET_TEST_BIN:/usr/bin:/bin"',
        1,
    )
    for source, replacement in (
        ("/home/devrunner/.devfleet-quarantine", "${DEVFLEET_TEST_ROOT}/quarantine"),
        ("/home/devrunner/workspaces", "${DEVFLEET_TEST_ROOT}/workspaces"),
        ("/etc/devfleet/restic.env", "${DEVFLEET_TEST_ROOT}/etc/restic.env"),
        ("/run/lock/devfleet-vault-operation.lock", "${DEVFLEET_TEST_ROOT}/run/vault.lock"),
        ("/proc/sys/kernel/random/uuid", "${DEVFLEET_TEST_ROOT}/uuid"),
    ):
        script_text = script_text.replace(source, replacement)
    script = lab / "restore-under-test"
    executable(script, script_text)

    executable(bin_dir / "flock", "#!/usr/bin/env bash\nexit 0\n")
    executable(bin_dir / "python3", "#!/usr/bin/env bash\nexit 0\n")
    executable(
        bin_dir / "jq",
        """#!/usr/bin/env bash
if [[ "$*" == *"--arg slug"* ]]; then
  exit 0
fi
cat >/dev/null
printf 'snap-1\\n'
""",
    )
    executable(
        bin_dir / "restic",
        """#!/usr/bin/env bash
if [[ "${1:-}" == snapshots ]]; then
  printf '[{"id":"snap-1","time":"2026-09-16T00:00:00Z"}]\\n'
  exit 0
fi
target=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --target ]]; then target=$2; shift 2; continue; fi
  shift
done
source_dir="$target${DEVFLEET_TEST_ROOT}/workspaces/$PROJECT"
mkdir -p "$source_dir/.devfleet"
printf '{"schema_version":5,"managed_by":"devfleet","slug":"%s","project_id":"%s"}\\n' "$PROJECT" "$PROJECT_ID" >"$source_dir/.devfleet/project.json"
printf 'restored-copy\\n' >"$source_dir/restored.txt"
""",
    )
    executable(
        bin_dir / "mv",
        """#!/usr/bin/env bash
counter="$DEVFLEET_TEST_ROOT/mv-count"
count=0
[[ -f "$counter" ]] && read -r count <"$counter"
count=$((count + 1))
printf '%s\\n' "$count" >"$counter"
if [[ $count -eq 2 ]]; then
  exit 42
fi
if [[ $count -eq 3 && "${ROLLBACK_COLLISION:-0}" == 1 ]]; then
  destination="${@: -1}"
  mkdir -p "$destination"
  printf 'foreign-race\\n' >"$destination/foreign.txt"
fi
exec /usr/bin/mv "$@"
""",
    )

    env = os.environ.copy()
    env.update(
        {
            "DEVFLEET_TEST_ROOT": unix(lab),
            "DEVFLEET_TEST_BIN": unix(bin_dir),
            "PROJECT": project,
            "PROJECT_ID": project_id,
            "ROLLBACK_COLLISION": "1" if rollback_collision else "0",
            "PATH": f"{unix(bin_dir)}:/usr/bin:/bin",
        }
    )
    result = subprocess.run(
        [str(BASH), "--noprofile", "--norc", unix(script), project, project_id, "--canonical"],
        capture_output=True,
        text=True,
        env=env,
        timeout=20,
        check=False,
    )

    assert result.returncode != 0
    quarantined = list(quarantine.glob("transfer-replaced-*"))
    if rollback_collision:
        assert result.returncode == 6
        assert (canonical / "foreign.txt").read_text(encoding="utf-8") == "foreign-race\n"
        assert len(quarantined) == 1
        assert (quarantined[0] / "original.txt").read_text(encoding="utf-8") == "prior-canonical\n"
    else:
        assert (canonical / "original.txt").read_text(encoding="utf-8") == "prior-canonical\n"
        assert not (canonical / "restored.txt").exists()
        assert not quarantined


def test_restore_script_binds_snapshot_to_slug_and_project_id():
    text = (ROOT / "linux/devfleet-restore-project").read_text(encoding="utf-8")
    assert 'python3 -I /opt/devfleet/devfleet/metadata_io.py' in text
    assert '--identity "$workspace" "$project" "$expected_project_id"' in text
    assert '"$expected_deployment_id" "$expected_source_host_id"' in text
    assert 'workspace_identity_matches "$target"' in text
    assert "Canonical restore rollback failed" in text
    assert "rollback did not reach its identity-bound postcondition" in text
