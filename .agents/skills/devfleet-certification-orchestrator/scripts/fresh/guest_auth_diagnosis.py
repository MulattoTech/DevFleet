"""Interpret a pinned, read-only guest Security event for one terminal R2 diagnostic.

This is supplementary VM-free evidence. It never changes the historical result,
admits a lab attempt, or grants authentication/certification credit.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re


EXACT_VM = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
EXACT_CLEAN = '19865b76-4c3a-44f7-ba39-841e9d3c40c9'
EXACT_ACCOUNT = 'E2EAdmin'
EXACT_COMPUTER = 'DevFleet-E2E-01'
PINNED_RDC_REPORT_SHA256 = '351d49ffe6038ea4183f26b871a5bbbfdd8a3394eff830c68972ee5037915704'
PINNED_RDC_SECURITY_LOG_SHA256 = 'bb824fb0a8001a91295b9f63e986a992584692d726d9e3517e071fa21114afa6'
HEX64 = re.compile(r'[0-9a-fA-F]{64}\Z')
STATUS = re.compile(r'0x[0-9a-fA-F]{8}\Z')
CLASSIFICATIONS = {
    ('0xc000006e', '0xc0000071'): 'PASSWORD_EXPIRED',
    ('0xc000006d', '0xc000006a'): 'WRONG_PASSWORD',
    ('0xc000006e', '0xc0000072'): 'ACCOUNT_DISABLED',
    ('0xc0000072', '0xc0000072'): 'ACCOUNT_DISABLED',
    ('0xc0000234', '0xc0000234'): 'ACCOUNT_LOCKED',
}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def read_json(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4_000_000,
            'Evidence file missing, linked, or oversized')
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    def invalid(_):
        raise ValueError('Nonfinite JSON number')
    value = json.loads(path.read_text(encoding='utf-8-sig'),
                       object_pairs_hook=pairs, parse_constant=invalid)
    require(isinstance(value, dict), 'Evidence root is not an object')
    return value


def instant(value):
    require(isinstance(value, str) and value.strip(), 'Missing UTC instant')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None and parsed.utcoffset().total_seconds() == 0,
            'Event and reservation instants must be UTC')
    return parsed.astimezone(timezone.utc)


def diagnose(report_path, expected_report_sha256, expected_log_sha256,
             ledger_path, readiness_path, run_id):
    require(isinstance(run_id, str) and run_id.strip(), 'Missing exact RunId')
    require(isinstance(expected_report_sha256, str) and HEX64.fullmatch(expected_report_sha256),
            'Missing trusted report hash')
    require(isinstance(expected_log_sha256, str) and HEX64.fullmatch(expected_log_sha256),
            'Missing trusted guest Security log hash')
    report_path = Path(report_path)
    actual_hash = hashlib.sha256(report_path.read_bytes()).hexdigest()
    require(actual_hash == expected_report_sha256.lower(), 'Report hash is not the pinned source')
    report = read_json(report_path)
    ledger = read_json(ledger_path)
    readiness = read_json(readiness_path)

    require(report.get('scope') == 'OFFLINE_READ_ONLY_GUEST_EVENT_INSPECTION',
            'Report has wrong inspection scope')
    require(report.get('vmId') == EXACT_VM and report.get('parentCheckpointId') == EXACT_CLEAN,
            'Report is not bound to exact L1 and predecessor CLEAN')
    for key in ('diskReadOnlyVerified', 'dismounted', 'diskFileSizeUnchanged',
                'diskWriteTimeUnchanged', 'ledgerUnchanged'):
        require(report.get(key) is True, 'Unverified read-only source chain: ' + key)
    require(report.get('guestAuthenticationAttempted') is False and report.get('vmStarted') is False,
            'Report is not a read-only offline inspection')
    require(report.get('securityLogSha256') == expected_log_sha256.lower(),
            'Guest Security log hash is not independently pinned')

    require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2',
            'Wrong R2 journal')
    attempts = [a for a in ledger.get('attempts', []) if isinstance(a, dict)
                and a.get('runId') == run_id]
    require(len(attempts) == 1 and ledger.get('activeRunId') is None,
            'Run is missing, ambiguous, or still active')
    attempt = attempts[0]
    require(attempt.get('operation') == 'diagnostic' and attempt.get('state') == 'TERMINAL'
            and attempt.get('certificationCredit') is False
            and attempt.get('classification') == 'E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN',
            'Run is not the terminal historical-source diagnostic')
    start, end = instant(attempt.get('reservedUtc')), instant(attempt.get('terminalUtc'))
    require(start < end, 'Invalid terminal window')

    lab = readiness.get('lab') or {}
    auth = readiness.get('liveGuestAuth') or {}
    admission = readiness.get('admission') or {}
    require(lab.get('l1Id') == EXACT_VM and lab.get('cleanId') == EXACT_CLEAN,
            'Readiness lab identity differs')
    require(admission.get('runId') == run_id and admission.get('operation') == 'diagnostic',
            'Readiness admission differs')
    require(auth.get('attempted') is True and auth.get('cleanRestored') is True
            and auth.get('connected') is False and auth.get('finalL1State') == 'Off'
            and auth.get('failureClass') == 'System.Management.Automation.Remoting.PSDirectException'
            and 'E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN' in readiness.get('blockers', [])
            and readiness.get('certificationCredit') is False,
            'Readiness did not record the exact generic authentication rejection')

    matching = []
    events = report.get('events')
    require(isinstance(events, list) and events, 'Missing guest failure events')
    record_ids = set()
    for event in events:
        require(isinstance(event, dict) and type(event.get('recordId')) is int
                and event['recordId'] > 0 and event['recordId'] not in record_ids,
                'Malformed or duplicate event record identity')
        record_ids.add(event['recordId'])
        require(event.get('eventId') == 4625 and STATUS.fullmatch(str(event.get('status', '')))
                and STATUS.fullmatch(str(event.get('subStatus', ''))),
                'Malformed guest failure event')
        event_time = instant(event.get('timeUtc'))
        if start <= event_time <= end and event.get('targetUser') == EXACT_ACCOUNT \
                and event.get('computer', '').lower() == EXACT_COMPUTER.lower():
            matching.append(event)
    require(len(matching) == 1, 'Missing or conflicting exact account failures in run window')
    event = matching[0]
    status, substatus = event['status'].lower(), event['subStatus'].lower()
    return {
        'schemaVersion': 1, 'scope': 'SUPPLEMENTARY_HISTORICAL_DIAGNOSIS',
        'runId': run_id, 'classification': CLASSIFICATIONS.get((status, substatus),
                                                               'UNKNOWN_AUTH_FAILURE'),
        'historicalLedgerClassification': attempt['classification'],
        'guestAuthenticated': False, 'certificationCredit': False,
        'reportSha256': actual_hash, 'securityLogSha256': expected_log_sha256.lower(),
        'vmId': EXACT_VM, 'parentCheckpointId': EXACT_CLEAN,
        'event': {'recordId': event['recordId'], 'eventId': 4625,
                  'timeUtc': event['timeUtc'], 'computer': event['computer'],
                  'targetUser': event['targetUser'], 'status': status, 'subStatus': substatus},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True)
    parser.add_argument('--report-sha256', required=True)
    parser.add_argument('--security-log-sha256', required=True)
    parser.add_argument('--ledger', required=True)
    parser.add_argument('--readiness', required=True)
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    require(args.report_sha256.lower() == PINNED_RDC_REPORT_SHA256
            and args.security_log_sha256.lower() == PINNED_RDC_SECURITY_LOG_SHA256,
            'RDC source hashes are not the independently pinned values')
    print(json.dumps(diagnose(args.report, args.report_sha256, args.security_log_sha256,
                              args.ledger, args.readiness, args.run_id), indent=2))


if __name__ == '__main__':
    main()
