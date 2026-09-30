"""Read-only check of every commit that a public DevFleet branch would push.

This is a source-review guard, not a native certification or secret scanner oracle.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path


PUBLIC_AUDIT_SCRIPT = 'audit/run-exact-candidate-proof.ps1'
PRIVATE_PREFIXES = (
    'audit/', 'outputs/', 'evidence/', 'private-evidence/', 'current-artifacts/',
    'windows-e2e/evidence/', 'windows-e2e/run-state/',
)
PRIVATE_SUFFIXES = (
    '.dpapi', '.secret', '.token', '.pem', '.key', '.pfx', '.p12', '.snk',
    '.vhd', '.vhdx', '.vmdk', '.vmcx', '.vmrs', '.run-state.json',
)
SECRET_PATTERNS = (
    re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
    re.compile(rb'\b(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}\b'),
    re.compile(rb'\bAKIA[0-9A-Z]{16}\b'),
    re.compile(rb'\bsk-[A-Za-z0-9]{32,}\b'),
    re.compile(rb'''(?i)\b(?:password|api[_-]?key|client[_-]?secret|secret[_-]?key)\b\s*[:=]\s*['"][^'"\r\n]{12,}['"]'''),
)


def git(repo, *args):
    result = subprocess.run(['git', '-C', str(repo), *args],
                            capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f'Git command failed ({args[0]}); verify refs and repository')
    return result.stdout


def blocked_path(path):
    name = path.replace(chr(92), '/').lower()
    parts = name.split('/')
    if name.startswith('/') or any(part in ('', '.', '..') for part in parts):
        return 'UNSAFE_PATH'
    if name == PUBLIC_AUDIT_SCRIPT:
        return None
    if name.startswith(PRIVATE_PREFIXES) or any(part in ('credentials', 'secrets', '.test-runtime') for part in parts):
        return 'PRIVATE_OR_GENERATED_PATH'
    if name.endswith(PRIVATE_SUFFIXES):
        return 'CREDENTIAL_SIGNING_OR_VM_FILE'
    return None


def added_lines(repo, parent, commit, path):
    patch = git(repo, 'diff', '--no-ext-diff', '--no-color', '--unified=0',
                parent, commit, '--', path)
    return (line[1:] for line in patch.splitlines()
            if line.startswith(b'+') and not line.startswith(b'+++'))


def validate(repo, base, head):
    root = Path(git(repo, 'rev-parse', '--show-toplevel').decode().strip()).resolve()
    repo = root
    merge_base = git(repo, 'merge-base', base, head).decode().strip()
    commits = git(repo, 'rev-list', '--reverse', '--topo-order',
                  f'{merge_base}..{head}').decode().splitlines()
    findings = []
    for commit in commits:
        parents = git(repo, 'show', '-s', '--format=%P', commit).decode().split()
        if not parents:
            raise ValueError('Root commit requires a reviewed public import')
        parent = parents[0]
        names = git(repo, 'diff', '--name-only', '-z', '--diff-filter=ACMR',
                    parent, commit, '--').split(b'\0')
        for raw_name in filter(None, names):
            name = raw_name.decode('utf-8', errors='replace')
            reason = blocked_path(name)
            if reason:
                findings.append((commit[:12], name, reason))
                continue
            if any(pattern.search(line) for line in added_lines(repo, parent, commit, name)
                   for pattern in SECRET_PATTERNS):
                findings.append((commit[:12], name, 'SECRET_PATTERN'))
    return commits, findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--base', required=True, help='Remote branch tip or origin/main for a new branch')
    parser.add_argument('--head', required=True, help='Local tip being pushed')
    args = parser.parse_args()
    try:
        commits, findings = validate(args.repo, args.base, args.head)
    except (OSError, ValueError, UnicodeError) as exc:
        print(f'PUBLIC_PUSH_BLOCKED: {exc}', file=sys.stderr)
        return 1
    for commit, name, reason in findings:
        print(f'PUBLIC_PUSH_BLOCKED: {commit} {name}: {reason}', file=sys.stderr)
    if findings:
        return 1
    print(f'PUBLIC_PUSH_PASS: {len(commits)} outgoing commits; source review only, native credit 0')
    return 0


if __name__ == '__main__':
    sys.exit(main())
