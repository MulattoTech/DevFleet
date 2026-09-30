# DevFleet development in GitHub Codespaces

GitHub Codespaces is a clean **source-development and review environment** for DevFleet. It is deliberately **not** the native certification laboratory.

## What the Codespace config does

The root `.devcontainer/devcontainer.json` intentionally does not select a custom base image. GitHub therefore uses its default, pre-cached multi-language Codespaces image and this repository layers only the DevFleet-specific setup on top.

On first creation, `.devcontainer/post-create.sh`:

- verifies the expected GitHub default-image tools;
- creates the ignored repository-local `.venv`;
- installs the hash-pinned DevFleet Python runtime dependencies;
- installs the hash-pinned release-tooling Python dependencies plus pytest;
- installs Codex CLI from the official npm package if `codex` is not already present;
- verifies the immutable original source export with `ai/verify_source_parts.py`;
- leaves a bootstrap summary at `~/.cache/devfleet-codespace-bootstrap.txt`;
- does **not** run native certification, Hyper-V, WPF, signing, or private evidence operations.

The dev container also enables SSHD and useful VS Code extensions for Python, PowerShell, C#, GitHub pull requests, and EditorConfig.

## First start

Create a Codespace from the branch or commit you intend to work on. After the post-create task finishes:

```bash
cd /workspaces/DevFleet
source .venv/bin/activate
git status
codex --version
```

Authenticate Codex through its supported sign-in flow or a Codespaces secret. Never commit API keys, tokens, DPAPI material, signing keys, native ledgers, VM disks, or private certification evidence.

If the dev-container files change later, rebuild the Codespace so the configuration is reapplied.

## Recommended Codex workflow

Use Codespaces for work that can be proven from source:

1. start from current GitHub `main`;
2. create a task branch;
3. reproduce a defect with deterministic/source-level tests where possible;
4. make the smallest causal change;
5. run focused failing-before/passing-after tests;
6. review `git diff` and `git status`;
7. commit and push the branch;
8. open a pull request for review;
9. merge only reviewed changes;
10. deliberately transfer the reviewed commit/path changes into the original MULATTOTECHBOX certification workspace when native testing is required.

Do not rewrite native certification history to make GitHub and the original checkout share commit IDs. Their histories are intentionally distinct.

## What Codespaces cannot certify

A Linux Codespace cannot replace the original Windows native release authority. In particular, it cannot establish:

- the genuine Windows standard-token qualification;
- the protected E2E credential path;
- Hyper-V L1 or accepted CLEAN checkpoint identity;
- positively verified nested L2 lifecycle;
- PowerShell Direct behavior;
- the WPF desktop/session installation lifecycle;
- private signing-key operations;
- native Laptop/Surrogate or Desktop/Primary role proofs;
- coherent FullRelease, U01-U05, maintenance 5/5, certified CLEANUP, or FINAL-ACCEPTANCE.

A Codespace test result is development evidence, not `PASS — INTERNAL RELEASE ELIGIBLE`.

## SSH from a local terminal or MobaXTerm

Install and authenticate GitHub CLI on the Windows machine:

```powershell
gh auth login
gh codespace list
gh codespace ssh -c <codespace-name>
```

For reusable OpenSSH aliases:

```bash
gh codespace ssh --config > ~/.ssh/codespaces
printf 'Match all\nInclude ~/.ssh/codespaces\n' >> ~/.ssh/config
```

After that, OpenSSH-aware tools can connect to the generated Codespace host aliases. MobaXTerm's local terminal can invoke the same `gh codespace ssh` or OpenSSH command. Prefer this GitHub-CLI-mediated path rather than exposing a public SSH port.

## VS Code alongside Codex CLI

Opening the **same Codespace** in desktop VS Code is recommended for observing diffs, browsing files, running read-only searches, and using the Source Control / Pull Requests views.

Avoid concurrent Git or file mutations while Codex is actively editing:

- do not checkout another branch under Codex;
- do not merge/rebase/reset while Codex is running;
- do not discard or auto-format Codex's working files underneath it;
- if you make a manual edit, tell Codex before it continues;
- let Codex reach a safe/idle boundary, then review, stage, commit, merge, or switch branches.

Multiple viewers are fine. Multiple unsynchronized writers in one working tree are not.
