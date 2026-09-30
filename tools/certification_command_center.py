"""Read-only localhost observer for DevFleet native certification evidence.

This viewer never runs native admission, refresh, VM, ledger, or release commands.
Its output is an observation, never certification credit or promotion authority.
"""

import argparse
import hashlib
import html
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


TUPLE_KEYS = ('repositoryHead', 'candidateCommit', 'shippingInputIdentity',
              'releaseFingerprintId', 'toolingFingerprintId')
REQUIRED = {
    'authority': ('evidence/CURRENT-RELEASE-AUTHORITY.json', 'generatedAtUtc'),
    'status': ('evidence/CURRENT-STATUS.json', 'generatedAtUtc'),
    'gates': ('evidence/CURRENT-GATES.json', 'generatedAtUtc'),
    'full': ('evidence/FULLRELEASE-SUMMARY.json', 'generatedAtUtc'),
    'proof': ('evidence/CURRENT-PROOF.json', 'authorityGeneratedAtUtc'),
}
RUN_ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,150}\Z')


def stamp(value):
    return value.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')


def parse_utc(value):
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        return parsed.astimezone(timezone.utc) if parsed.tzinfo else None
    except ValueError:
        return None


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('DUPLICATE_JSON_PROPERTY')
        result[key] = value
    return result


def read_json(root, relative, time_key, now, max_age):
    info = {'path': str(relative).replace(chr(92), '/'), 'state': 'UNKNOWN',
            'timestampSource': 'UNKNOWN', 'observedUtc': None}
    root = Path(root).resolve()
    path = (root / relative).resolve()
    if not path.is_relative_to(root):
        info['state'] = 'CONFLICT'
        info['reason'] = 'PATH_OUTSIDE_NATIVE_ROOT'
        return None, info
    if not path.is_file():
        info['reason'] = 'MISSING'
        return None, info
    try:
        raw = path.read_bytes()
        data = json.loads(raw.decode('utf-8-sig'), object_pairs_hook=no_duplicate_keys)
        if not isinstance(data, dict):
            raise ValueError('JSON_OBJECT_REQUIRED')
    except (OSError, UnicodeError, ValueError) as exc:
        info['state'] = 'CONFLICT'
        info['reason'] = type(exc).__name__
        return None, info
    info['sha256'] = hashlib.sha256(raw).hexdigest()
    try:
        info['fileModifiedUtc'] = stamp(datetime.fromtimestamp(path.stat().st_mtime, timezone.utc))
    except OSError:
        info['state'] = 'UNKNOWN'
        info['reason'] = 'FILE_CHANGED_DURING_READ'
        return None, info
    observed = parse_utc(data.get(time_key)) if time_key else None
    if observed is None:
        info['timestampSource'] = 'FILE_MTIME_ONLY'
        info['observedUtc'] = info['fileModifiedUtc']
        info['state'] = 'RECORDED' if time_key is None else 'UNKNOWN'
        return data, info
    info['timestampSource'] = time_key
    info['observedUtc'] = stamp(observed)
    age = now - observed
    if age < -timedelta(minutes=5):
        info['state'] = 'CONFLICT'
        info['reason'] = 'FUTURE_TIMESTAMP'
    elif age > max_age:
        info['state'] = 'STALE'
    else:
        info['state'] = 'CURRENT'
    return data, info


def git_info(root):
    result = {'state': 'UNKNOWN', 'head': 'UNKNOWN', 'branch': 'UNKNOWN',
              'trackedChanges': None}
    if root is None:
        return result
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    def command(*args):
        run = subprocess.run(['git', '--no-optional-locks', '-C', str(root), *args],
                             capture_output=True, text=True, timeout=6, env=environment)
        if run.returncode:
            raise ValueError('GIT_READ_FAILED')
        return run.stdout.strip()
    try:
        result['head'] = command('rev-parse', 'HEAD')
        result['branch'] = command('branch', '--show-current') or 'DETACHED'
        result['trackedChanges'] = len(command('status', '--porcelain', '-uno').splitlines())
        result['state'] = 'RECORDED'
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return result


def ledger_view(data):
    if not isinstance(data, dict):
        return None, 'UNKNOWN'
    limits, attempts = data.get('limits'), data.get('attempts')
    if not isinstance(limits, dict) or not isinstance(attempts, list):
        return None, 'CONFLICT'
    if any(type(value) is not int or value < 0 for value in limits.values()):
        return None, 'CONFLICT'
    if any(not isinstance(row, dict) for row in attempts):
        return None, 'CONFLICT'
    ids = [row.get('runId') for row in attempts]
    if (any(not isinstance(run_id, str) or not RUN_ID.fullmatch(run_id) for run_id in ids)
            or len(set(ids)) != len(ids)):
        return None, 'CONFLICT'
    if any(row.get('operation') not in limits
           or row.get('state') not in ('RESERVED_CHARGED', 'TERMINAL') for row in attempts):
        return None, 'CONFLICT'
    active = [row.get('runId') for row in attempts if row.get('state') == 'RESERVED_CHARGED']
    active_id = data.get('activeRunId')
    if active != ([] if active_id is None else [active_id]):
        return None, 'CONFLICT'
    charges = {}
    for category, limit in limits.items():
        used = sum(row.get('operation') == category for row in attempts)
        if used > limit:
            return None, 'CONFLICT'
        charges[category] = {'limit': limit, 'used': used, 'remaining': limit - used}
    return {'charges': charges, 'activeRunId': active_id, 'attempts': attempts}, 'RECORDED'


def latest_attempt(attempts, operation):
    return next((row for row in reversed(attempts) if row.get('operation') == operation), None)


def lab_observation(cleanup, now, max_age):
    result = {}
    for key in ('l1', 'l2'):
        row = cleanup.get(key) if isinstance(cleanup, dict) else None
        observed = parse_utc(row.get('observedUtc')) if isinstance(row, dict) else None
        state = 'UNKNOWN' if observed is None else ('STALE' if now - observed > max_age else 'RECORDED')
        result[key] = {'lastObserved': row.get('status', 'UNKNOWN') if isinstance(row, dict) else 'UNKNOWN',
                       'observedUtc': stamp(observed) if observed else None,
                       'state': state, 'liveState': 'UNVERIFIED'}
    return result


def build_snapshot(native_root, ledger_relative, public_root=None, *, now=None,
                   max_age=timedelta(minutes=30), operator_snapshot=None):
    now = now or datetime.now(timezone.utc)
    native_root = Path(native_root).resolve()
    public_root = Path(public_root).resolve() if public_root else None
    sources, documents, conflicts = {}, {}, []
    for name, (relative, time_key) in REQUIRED.items():
        documents[name], sources[name] = read_json(native_root, relative, time_key, now, max_age)
    authority = documents['authority'] or {}
    for name in ('status', 'gates', 'full', 'proof'):
        document = documents[name]
        if not document:
            continue
        candidate = document.get('candidateGitCommit', document.get('candidateCommit'))
        if (document.get('authorityId') != authority.get('authorityId')
                or any((candidate if key == 'candidateCommit' else document.get(key)) != authority.get(key)
                       for key in TUPLE_KEYS)):
            sources[name]['state'] = 'CONFLICT'
            conflicts.append(name)
            continue
        source_time = parse_utc(document.get(REQUIRED[name][1]))
        authority_time = parse_utc(authority.get('generatedAtUtc'))
        if source_time and authority_time and abs((source_time - authority_time).total_seconds()) > 5:
            sources[name]['state'] = 'CONFLICT'
            conflicts.append(name)
        if name == 'status' and (document.get('status') != authority.get('status')
                or document.get('fullReleasePassed') is not authority.get('fullReleasePassed')
                or document.get('internalPromotionAllowed') is not authority.get('internalPromotionAllowed')):
            sources[name]['state'] = 'CONFLICT'
            conflicts.append(name)
    ledger, sources['ledger'] = read_json(native_root, ledger_relative, None, now, max_age)
    ledger_data, ledger_state = ledger_view(ledger)
    if ledger is not None and (ledger_state == 'CONFLICT'
                               or ledger.get('policyId') != Path(ledger_relative).parent.name):
        sources['ledger']['state'] = 'CONFLICT'
        conflicts.append('ledger')
    charges = ledger_data['charges'] if ledger_data else {}
    attempts = ledger_data['attempts'] if ledger_data else []
    active = ledger_data['activeRunId'] if ledger_data else None
    proof_run_expected = authority.get('currentProofRunId')
    if proof_run_expected and (not isinstance(proof_run_expected, str)
                               or proof_run_expected not in {row['runId'] for row in attempts}):
        conflicts.append('proofRun')
    latest = {operation: latest_attempt(attempts, operation) for operation in
              ('standard-token', 'diagnostic', 'laptop-proof', 'desktop-proof', 'fullrelease')}
    result_dir = Path(ledger_relative).parent / 'results'
    qualification = {'state': 'UNKNOWN', 'runId': None, 'recordedClassification': None}
    token = latest['standard-token']
    if token and isinstance(token.get('runId'), str) and RUN_ID.fullmatch(token['runId']):
        qualification['runId'] = token['runId']
        receipt_path = result_dir / f"{token['runId']}-standard-token-result.json"
        receipt, sources['qualification'] = read_json(native_root, receipt_path, 'resultUtc', now, max_age)
        qualification['recordedClassification'] = token.get('classification')
        if receipt and (receipt.get('runId') == token['runId']
                        and receipt.get('candidateHead') == authority.get('repositoryHead')
                        and receipt.get('classification') == token.get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
                        and receipt.get('exitCode') == token.get('exitCode') == 0):
            qualification['state'] = ('RECORDED_PASS' if sources['qualification']['state'] == 'CURRENT'
                                      else sources['qualification']['state'])
        elif receipt:
            qualification['state'] = 'CONFLICT'
            sources['qualification']['state'] = 'CONFLICT'
            conflicts.append('qualification')
    else:
        sources['qualification'] = {'state': 'UNKNOWN', 'reason': 'NO_STANDARD_TOKEN_ATTEMPT'}
    safety = {'state': 'UNKNOWN', 'timestampSource': 'UNKNOWN', 'startSafe': None}
    result_path = (native_root / result_dir).resolve()
    try:
        candidates = sorted(result_path.glob('*-host-safety.json'),
                            key=lambda path: path.stat().st_mtime, reverse=True) if result_path.is_relative_to(native_root) and result_path.is_dir() else []
    except OSError:
        candidates = []
    if candidates:
        relative = candidates[0].relative_to(native_root)
        sample, sources['hostSafety'] = read_json(native_root, relative, 'observedUtc', now, max_age)
        safety = {'state': sources['hostSafety']['state'],
                  'timestampSource': sources['hostSafety']['timestampSource'],
                  'observedUtc': sources['hostSafety'].get('observedUtc'),
                  'startSafe': sample.get('startSafe') if sample and type(sample.get('startSafe')) is bool else None,
                  'commitLimitGiB': sample.get('commitLimitGiB') if sample else None,
                  'committedGiB': sample.get('committedGiB') if sample else None,
                  'expectedVmStartCostGiB': sample.get('expectedVmStartCostGiB') if sample else None,
                  'projectedCommitHeadroomGiB': sample.get('projectedCommitHeadroomGiB') if sample else None,
                  'commitHeadroomFloorGiB': sample.get('commitHeadroomFloorGiB') if sample else None,
                  'blockingReasons': sample.get('blockingReasons', []) if sample else []}
    else:
        sources['hostSafety'] = {'state': 'UNKNOWN', 'reason': 'NO_RECORDED_SAMPLE'}
    proof = documents['proof'] or {}
    proof_run = proof.get('runId')
    first_failure = 'UNKNOWN'
    if proof_run_expected and proof_run != proof_run_expected:
        conflicts.append('proofRun')
    if isinstance(proof_run, str) and RUN_ID.fullmatch(proof_run):
        bound = next((row for row in attempts if row['runId'] == proof_run), None)
        if bound and bound['operation'] in ('laptop-proof', 'desktop-proof'):
            session_path = result_dir / f"{proof_run}-{bound['operation']}-session.json"
            session, sources['proofSession'] = read_json(native_root, session_path, 'finishedUtc', now, max_age)
        else:
            session = None
            sources['proofSession'] = {'state': 'UNKNOWN', 'reason': 'NO_BOUND_ROLE_ATTEMPT'}
        if session and session.get('runId') != proof_run:
            sources['proofSession']['state'] = 'CONFLICT'
            conflicts.append('proofSession')
        elif session and session.get('firstTechnicalFailure'):
            first_failure = str(session['firstTechnicalFailure'])[:500]
    else:
        sources['proofSession'] = {'state': 'UNKNOWN', 'reason': 'NO_BOUND_PROOF_RUN'}
    progress = proof.get('progress') if isinstance(proof.get('progress'), dict) else {}
    cleanup = proof.get('cleanup') if isinstance(proof.get('cleanup'), dict) else {}
    if cleanup.get('runId') != proof_run:
        cleanup = {}
    native_git, public_git = git_info(native_root), git_info(public_root)
    if native_git['state'] == 'RECORDED' and authority.get('repositoryHead') \
            and native_git['head'] != authority['repositoryHead']:
        native_git['state'] = 'CONFLICT'
        conflicts.append('nativeGit')
    operator = {'root': 'UNKNOWN', 'model': 'UNKNOWN', 'helpers': [], 'state': 'UNKNOWN'}
    if operator_snapshot:
        record, sources['operator'] = read_json(native_root, operator_snapshot, 'observedUtc', now, max_age)
        if record:
            operator = {'root': str(record.get('root') or 'UNKNOWN')[:120],
                        'model': str(record.get('model') or 'UNKNOWN')[:80],
                        'helpers': record.get('helpers') if isinstance(record.get('helpers'), list) else [],
                        'state': sources['operator']['state']}
    else:
        sources['operator'] = {'state': 'UNKNOWN', 'reason': 'NO_OPERATOR_SNAPSHOT'}
    required_names = [*REQUIRED, 'ledger', 'hostSafety']
    if token:
        required_names.append('qualification')
    if proof_run:
        required_names.append('proofSession')
    required_states = [sources[name]['state'] for name in required_names]
    if conflicts or 'CONFLICT' in required_states or native_git['state'] == 'CONFLICT':
        observer_state = 'CONFLICT'
    elif 'UNKNOWN' in required_states or native_git['state'] == 'UNKNOWN':
        observer_state = 'UNKNOWN'
    elif 'STALE' in required_states:
        observer_state = 'STALE'
    else:
        observer_state = 'CURRENT'
    role_attempts = {}
    for label, operation in (('Laptop', 'laptop-proof'), ('Desktop', 'desktop-proof')):
        row = latest[operation]
        role_attempts[label] = row.get('classification') or row.get('state') if row else 'NOT_RUN'
    return {
        'schemaVersion': 1, 'observerState': observer_state, 'readAtUtc': stamp(now),
        'certificationCredit': False, 'releaseEligibleClaim': False,
        'conflicts': sorted(set(conflicts)), 'sources': sources,
        'native': {
            'recordedStatus': authority.get('status', 'UNKNOWN'),
            'authorityId': authority.get('authorityId', 'UNKNOWN'),
            'tuple': {key: authority.get(key, 'UNKNOWN') for key in TUPLE_KEYS},
            'blockerClassification': authority.get('blockerClassification', 'UNKNOWN'),
            'blocker': str(authority.get('blocker') or 'UNKNOWN')[:500],
            'roles': {'passed': (authority.get('proofs') if isinstance(authority.get('proofs'), dict) else {}).get('passing', 'UNKNOWN'),
                      'required': (authority.get('proofs') if isinstance(authority.get('proofs'), dict) else {}).get('required', 'UNKNOWN'),
                      'attempts': role_attempts},
            'fullRelease': (authority.get('fullRelease') if isinstance(authority.get('fullRelease'), dict) else {}).get('status', 'UNKNOWN'),
            'charges': charges, 'activeRunId': active if ledger_data else 'UNKNOWN',
            'ledgerSha256': sources['ledger'].get('sha256'),
            'qualification': qualification, 'hostSafety': safety,
            'proof': {'runId': proof_run or 'UNKNOWN', 'firstTechnicalFailure': first_failure,
                      'proofTerminalError': proof.get('terminalError') or 'UNKNOWN',
                      'observerTerminal': progress.get('terminalReason') or 'UNKNOWN',
                      'lastMeaningfulProgressUtc': progress.get('lastMeaningfulProgressUtc'),
                      'cleanup': cleanup.get('status') or 'UNKNOWN'},
            'lab': lab_observation(cleanup, now, max_age), 'operator': operator,
            'recordedFlags': {key: authority.get(key) if type(authority.get(key)) is bool else None
                              for key in ('validationEvidenceCurrent', 'fullReleasePassed',
                                          'internalPromotionAllowed', 'publicPromotionAllowed')},
        },
        'nativeGit': native_git, 'publicGit': public_git,
    }


def render_html(snapshot):
    def show(value):
        if isinstance(value, (dict, list)):
            value = json.dumps(value, ensure_ascii=False)
        return html.escape(str(value if value is not None else 'UNKNOWN'))
    sections = [
        ('Authority', [('Observer', snapshot['observerState']),
                       ('Recorded release', snapshot['native']['recordedStatus']),
                       ('Blocker', snapshot['native']['blocker']),
                       ('Tuple', snapshot['native']['tuple']),
                       ('Promotion flags (recorded)', snapshot['native']['recordedFlags'])]),
        ('Execution', [('Roles', snapshot['native']['roles']),
                       ('FullRelease', snapshot['native']['fullRelease']),
                       ('Charges', snapshot['native']['charges']),
                       ('Active RunId (recorded)', snapshot['native']['activeRunId']),
                       ('Qualification', snapshot['native']['qualification'])]),
        ('Observations', [('HostSafety', snapshot['native']['hostSafety']),
                          ('L1/L2 last observed', snapshot['native']['lab']),
                          ('First failure / observer / cleanup', snapshot['native']['proof']),
                          ('Root / model / helpers', snapshot['native']['operator'])]),
        ('Git histories', [('Native', snapshot['nativeGit']), ('Public', snapshot['publicGit'])]),
        ('Provenance', [('Sources', snapshot['sources']), ('Conflicts', snapshot['conflicts'])]),
    ]
    cards = ''.join('<section><h2>' + html.escape(title) + '</h2><dl>' + ''.join(
        '<dt>' + html.escape(label) + '</dt><dd>' + show(value) + '</dd>' for label, value in rows
    ) + '</dl></section>' for title, rows in sections)
    return ('<!doctype html><html lang="en"><meta charset="utf-8">'
            '<meta http-equiv="refresh" content="5"><title>DevFleet Command Center</title>'
            '<style>body{font:16px system-ui;background:#101824;color:#e9eef5;max-width:1100px;margin:auto;padding:1.5rem}'
            'section{background:#1b2737;padding:1rem;margin:1rem 0;border-radius:8px}'
            'dl{display:grid;grid-template-columns:13rem 1fr;gap:.5rem}dt{font-weight:bold}dd{margin:0;overflow-wrap:anywhere}'
            'a{color:#9cd9ff}</style><h1>DevFleet Certification Command Center</h1>'
            '<p>Read-only observations. UNKNOWN and STALE are not native PASS. '
            'This view grants no certification credit or release eligibility.</p>'
            '<p><a href="/snapshot.json">JSON snapshot</a> · refreshes every 5 seconds</p>' + cards + '</html>')


def serve(native, ledger, public, port, max_age, operator):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in ('/', '/snapshot.json'):
                self.send_error(404)
                return
            snapshot = build_snapshot(native, ledger, public, max_age=max_age,
                                      operator_snapshot=operator)
            if self.path == '/snapshot.json':
                body = json.dumps(snapshot, indent=2, ensure_ascii=False).encode('utf-8')
                content_type = 'application/json; charset=utf-8'
            else:
                body = render_html(snapshot).encode('utf-8')
                content_type = 'text/html; charset=utf-8'
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    print(f'READ_ONLY_COMMAND_CENTER http://127.0.0.1:{server.server_port}/', flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-root', type=Path, required=True)
    parser.add_argument('--ledger', required=True, help='Relative path to selected successor ledger')
    parser.add_argument('--public-root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--operator-snapshot', help='Optional native-root-relative, non-credit session snapshot')
    parser.add_argument('--max-age-minutes', type=int, default=30)
    parser.add_argument('--port', type=int, default=8768)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--once', action='store_true')
    mode.add_argument('--serve', action='store_true')
    args = parser.parse_args()
    if args.max_age_minutes < 1 or not 1 <= args.port <= 65535:
        parser.error('Finite age and valid loopback port required')
    if args.serve:
        serve(args.native_root, args.ledger, args.public_root, args.port,
              timedelta(minutes=args.max_age_minutes), args.operator_snapshot)
    else:
        snapshot = build_snapshot(args.native_root, args.ledger, args.public_root,
                                  max_age=timedelta(minutes=args.max_age_minutes),
                                  operator_snapshot=args.operator_snapshot)
        print(json.dumps(snapshot, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    sys.exit(main())
