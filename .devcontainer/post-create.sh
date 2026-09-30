#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

log()  { printf '\n[DevFleet Codespaces] %s\n' "$*"; }
warn() { printf '\n[DevFleet Codespaces] WARNING: %s\n' "$*" >&2; }

log "Using GitHub's default Codespaces image plus DevFleet bootstrap."
log "This environment is for source development and review only; it is not native certification authority."

required=(git gh python3 node npm)
missing=()
for cmd in "${required[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (("${#missing[@]}" > 0)); then
  printf 'Missing required default-image tools: %s\n' "${missing[*]}" >&2
  exit 1
fi

python_bin="$(command -v python3.12 || command -v python3)"
log "Python: $("$python_bin" --version 2>&1)"
log "Node: $(node --version)"
log "npm: $(npm --version)"
log "GitHub CLI: $(gh --version | head -n 1)"
if command -v pwsh >/dev/null 2>&1; then
  log "PowerShell: $(pwsh --version)"
else
  warn "PowerShell 7 is not present in this Codespaces image. Linux-safe Python/source work is still available."
fi
if command -v dotnet >/dev/null 2>&1; then
  log ".NET: $(dotnet --version)"
else
  warn ".NET SDK is not present. Windows WPF certification remains intentionally out of scope here."
fi

log "Creating/reusing repository-local Python environment."
if [[ ! -x .venv/bin/python ]]; then
  "$python_bin" -m venv .venv
fi
venv_python="$repo_root/.venv/bin/python"
"$venv_python" -m pip install --upgrade pip setuptools wheel

log "Installing DevFleet product and release-tooling Python dependencies."
"$venv_python" -m pip install --require-hashes -r source/app/requirements-hashed.txt
"$venv_python" -m pip install --require-hashes -r tools/release-tooling-requirements.txt
"$venv_python" -m pip install pytest

if command -v codex >/dev/null 2>&1; then
  log "Codex CLI already available: $(codex --version 2>/dev/null || true)"
else
  log "Installing Codex CLI from the official npm package."
  if npm install -g @openai/codex@alpha; then
    log "Codex CLI installed: $(codex --version 2>/dev/null || true)"
  else
    warn "Codex CLI installation failed. The Codespace remains usable; rerun 'npm install -g @openai/codex@alpha' manually."
  fi
fi

log "Verifying the published original source export."
"$venv_python" ai/verify_source_parts.py

mkdir -p "$HOME/.cache"
cat > "$HOME/.cache/devfleet-codespace-bootstrap.txt" <<EOF
DevFleet Codespace bootstrap completed.
Repository: $repo_root
Git HEAD: $(git rev-parse HEAD)
Python: $("$venv_python" --version 2>&1)
Codex: $(command -v codex >/dev/null 2>&1 && codex --version 2>/dev/null || printf 'not installed')
Scope: source development/review only; no native certification authority.
EOF

log "Bootstrap complete."
log "Activate Python with: source .venv/bin/activate"
log "Start Codex with: codex"
log "Read docs/CODESPACES.md before attempting release/certification work."
