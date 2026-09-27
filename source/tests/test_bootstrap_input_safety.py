from pathlib import Path
import json
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]


def python_heredocs(name):
    lines = (ROOT / "linux" / name).read_text(encoding="utf-8").splitlines()
    blocks = []
    for index, line in enumerate(lines):
        if "<<'PY'" in line:
            end = lines.index("PY", index + 1)
            blocks.append((index + 2, "\n".join(lines[index + 1 : end]) + "\n"))
    assert blocks, f"No embedded Python found in {name}"
    return blocks


@pytest.mark.parametrize("name", ["bootstrap-compute.sh", "bootstrap-vault.sh"])
def test_bootstrap_embedded_python_compiles(name):
    # bash -n cannot parse embedded Python; compile the exact production bodies.
    for line, body in python_heredocs(name):
        compile(body, f"{name}:heredoc-at-line-{line}", "exec")


@pytest.mark.parametrize("forbidden", [None, "\x00", "\r", "\n"])
def test_compute_secret_writer_executes_atomically_and_rejects_controls(tmp_path, monkeypatch, forbidden):
    bodies = [body for _, body in python_heredocs("bootstrap-compute.sh") if "target.replace('/etc/devfleet/secrets.env')" in body]
    assert len(bodies) == 1
    body = compile(bodies[0], "bootstrap-compute.sh:secret-writer", "exec")
    source, temporary, destination = (tmp_path / name for name in ("input.json", "temporary.env", "secrets.env"))
    password = 'fixture-\\$`"' + (forbidden or "")
    source.write_text(json.dumps({"AdminUser": "fixture-user", "AdminPassword": password, "ApiToken": "fixture-token"}), encoding="utf-8")
    temporary.touch()
    destination.write_text("original fixture\n", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", ["-", str(temporary), str(source)])
    original_replace = Path.replace

    def redirected_replace(path, target):
        assert path == temporary and target == "/etc/devfleet/secrets.env"
        return original_replace(path, destination)

    monkeypatch.setattr(Path, "replace", redirected_replace)
    if forbidden:
        with pytest.raises(SystemExit, match="forbidden control character"):
            exec(body, {})
        assert destination.read_text(encoding="utf-8") == "original fixture\n"
        assert temporary.read_bytes() == b""
    else:
        exec(body, {})
        encoded = password.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
        expected = 'DEVFLEET_ADMIN_USER="fixture-user"\nDEVFLEET_ADMIN_PASSWORD="' + encoded + '"\nDEVFLEET_API_TOKEN="fixture-token"\n'
        assert destination.read_bytes() == expected.encode("utf-8")
        assert not temporary.exists()
    assert source.exists()


def test_compute_bootstrap_validates_numeric_and_secret_boundaries_before_templates():
    source = (ROOT / "linux" / "bootstrap-compute.sh").read_text(encoding="utf-8")
    assert "PORT =~ ^[0-9]+$" in source
    assert "BACKUP_INTERVAL =~ ^[0-9]+$" in source
    assert "value != *$'\\r'*" in source
    assert "value != *$'\\n'*" in source
    assert "python3 - \"$SECRETS_ENV_TMP\"" in source
    assert "target.replace('/etc/devfleet/secrets.env')" in source
    assert "DEVFLEET_ADMIN_PASSWORD=$ADMIN_PASSWORD" not in source


def test_compute_bootstrap_uses_structured_json_generation():
    source = (ROOT / "linux" / "bootstrap-compute.sh").read_text(encoding="utf-8")
    assert "jq -n" in source
    assert "--arg" in source
    assert "--argjson" in source
    assert 's|__PORT__|$PORT|g' in source
    assert 's|__WORKSPACES__|$WORKSPACES|g' in source
    assert 's|__QUARANTINE__|$QUARANTINE|g' in source


def test_bootstrap_entrypoints_bind_identity_and_install_cleanup_before_stdin_capture():
    for name in ("bootstrap-compute.sh", "bootstrap-vault.sh"):
        source = (ROOT / "linux" / name).read_text(encoding="utf-8")
        argument_parser = source[: source.index("done", source.index("while (($#))"))]
        assert "cat >" not in argument_parser
        assert "--package-version" in argument_parser
        assert "--node-role" in argument_parser
        capture = source.index("devfleet_capture_json_stdin")
        assert source.index("BOOTSTRAP_DEADLINE_EPOCH") < capture
        assert source.index("trap '") < capture
        assert source.index("begin_component secretsInput") < capture
        assert "SECRETS_INPUT_MAX_SECONDS=60" in source


def test_bootstrap_input_helper_is_deadline_bounded_and_never_logs_input():
    source = (ROOT / "linux" / "bootstrap-input.sh").read_text(encoding="utf-8")
    assert 'timeout --foreground --kill-after=5s "${remaining}s" cat >"$secret_path"' in source
    assert "rm -f -- \"$secret_path\"" in source
    assert "jq -e 'type == \"object\"'" in source
    assert "cat \"$secret_path\"" not in source
