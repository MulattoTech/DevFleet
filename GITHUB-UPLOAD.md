# Upload DevFleet to MulattoTech/DevFleet

Target: https://github.com/MulattoTech/DevFleet

These instructions prepare a new initial source commit. No push was performed by this packaging task. Only `github-repository/` belongs in the initial upload. Keep the sibling `private-evidence/` and `current-artifacts/` directories local. Review any existing host/example configuration before publishing. Source publication does not imply product release certification or public publisher trust.

## 1. Extract and verify

Extract the complete ZIP into a new directory, not over the active certification checkout. From that directory run:

```powershell
python .\verify_package.py
```

Expect `PASS` with no missing or modified files. Then enter its `github-repository` subdirectory. Install Git for Windows and authenticate to GitHub using its normal browser/credential-manager flow. Never paste a GitHub access token into an AI chat or repository file.

## 2. Initialize locally

```powershell
Set-Location <path-to-extracted-github-repository>
git init -b main
git config core.autocrlf false
git add --all
# audit/ is ignored in the original project; explicitly add its tracked source script.
git add -f -- audit/run-exact-candidate-proof.ps1
python .\ai\prepare_git_index.py
git status --short
git diff --cached --stat
git commit -m "Import DevFleet v1.2.13 source and diagnostic documentation"
git remote add origin https://github.com/MulattoTech/DevFleet.git
git remote -v
git ls-remote --heads origin
```

`prepare_git_index.py` stages the exact exported source paths (including ignored tracked scripts), restores recorded executable bits, and checks the staged path set. If any displayed file is unexpected, review it before committing. Git may request your normal commit name/email if not already configured. The original Unix executable modes are recorded in `ai/ORIGINAL-SOURCE-INVENTORY.json`.

## 3. Push after reviewing the staged contents

For an empty repository (no branch returned by `git ls-remote --heads origin`):

```powershell
git push -u origin main
git rev-parse HEAD
```

If the remote already contains commits, stop and reconcile them through a reviewed branch/PR; do not force-push or discard remote work. The public unauthenticated GitHub request returned 404 during packaging, which does not distinguish a private repository from a missing one. The URL came from the owner; visibility was not changed.

## 4. Verify a fresh clone

```powershell
Set-Location ..
git clone https://github.com/MulattoTech/DevFleet.git DevFleet-clone-check
Set-Location .\DevFleet-clone-check
python .\ai\verify_source_export.py
```

Follow `BUILD-FROM-CLONE.md`. The verifier accepts exact bytes or the explicitly recorded CRLF materialization of a text file; it reports that distinction. The GitHub commit is new provenance, not the original certification commit.

## 5. Give ChatJimmy access

Upload `ai/CHATJIMMY-START-HERE.md` from the export (below 50,000 bytes), or paste its contents. It points at `main` in this repository. For a stable review, give the AI the uploaded commit SHA and replace `/main/` in raw links with that SHA, or ask it to pin all retrievals to that commit.

The repo must be accessible to the AI's actual retrieval tool. A private GitHub repo is not readable merely because you can view it in your own browser. Do not provide account passwords/tokens to ChatJimmy. If it cannot fetch a source part, attach the requested file from `ai/source-parts/` (each below 50,000 bytes). Multiple attachments can exceed the model's conversation/context limit; ask it to keep a reviewed-file index and avoid claiming complete coverage if earlier parts are unavailable.

The full source text is also in `ai/DEVFLEET-FULL-SOURCE.md` for larger-capacity tools. Its binary payload is represented by path/hash; the actual payload is in the source tree. The full text document itself exceeds ChatJimmy's upload cap.

## Artifacts and licensing

The source tree has its required tracked installer payload. The optional sibling current signed artifacts are preserved for original-candidate testing and release-build seeding, not placed in the source commit. If you later choose to distribute them, use a separately reviewed artifact/release workflow. Do not publish a certified release label while status remains INCOMPLETE. Existing upstream notices/licenses remain intact; this export does not invent or change a project license.

Reference: [GitHub's instructions for adding locally hosted code](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github).
