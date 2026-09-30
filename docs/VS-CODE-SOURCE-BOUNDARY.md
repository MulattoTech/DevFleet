# VS Code: native evidence and public source

DevFleet has two separate Git histories. The original Windows checkout holds the signed candidate, native authority, ledgers, lab state and evidence. The public `MulattoTech/DevFleet` checkout holds source and reviewable tooling. On this host the public checkout is `C:\Tools\Dev\DevFleet-GitHub`; confirm the actual root in each terminal with `git rev-parse --show-toplevel` and `git remote -v`. Do not infer the checkout from a tab title or Source Control count.

## Use separate VS Code windows

Open a public task branch or isolated worktree in one window. Its committed `.vscode/settings.json` asks before Sync, disables Smart Commit and hides the status-bar Sync shortcut. Review and stage individual files. Do not put the native and public roots into one multi-root workspace: VS Code can show multiple repositories in a single Source Control view.

For read-only native inspection, save a **local** `Native-Evidence.code-workspace` outside both checkouts, with your actual native root substituted below, then open that workspace in a separate VS Code window:

```json
{
  "folders": [{"name": "DevFleet native evidence", "path": "C:/path/to/original/DevFleet-v1.2.13-development"}],
  "settings": {"git.enabled": false}
}
```

This hides VS Code's Git actions in that native window; it does not alter Git, evidence or release authority. Keep using native commands only through the authorized release operator. If the native folder is opened normally instead, thousands of tracked evidence changes may appear; they are not a public commit backlog.

## Before a public push

From the public task worktree, inspect the exact outgoing history and destination:

```powershell
git rev-parse --show-toplevel
git remote -v
git branch --show-current
git status --short
git fetch origin main
git diff --name-status origin/main...HEAD
git diff --check origin/main...HEAD
python tools/validate_public_push.py --base origin/main --head HEAD
```

Publish source, tests, tooling and documentation through a task branch and PR. Review the diff for private evidence and secret values before committing. Reject `audit/` run evidence (the tracked `audit/run-exact-candidate-proof.ps1` source script is the narrow exception), `outputs/`, native run state, VM disks, credentials, DPAPI material, signing keys and generated `.test-runtime` files. `.gitignore` does not protect tracked history. Do not bulk stage or commit the native checkout to make Source Control look clean.

The read-only validator examines **every outgoing commit**, including a file added in one commit and removed in another. It reports blocked paths or high-confidence secret markers without printing matched values. It is a review aid, so inspect the complete diff as well. To enable its optional pre-push hook in the public repository and its linked public worktrees:

```powershell
git config --local core.hooksPath .githooks
```

Do not install that hook in the separate native checkout. A public PR or CI PASS is source evidence only; current native authority alone determines certification and internal release eligibility.
