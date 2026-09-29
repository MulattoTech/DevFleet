# DevFleet source part 124

Full-source UTF-8 byte interval [5719500, 5766000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 6d73b17c80f26b227cf06a0c9d29687fdef7c54fd653a205e7d63c639d97e65b

<!-- BEGIN SOURCE SLICE -->
maining = {'standard-token': 0, 'diagnostic': 1, 'laptop-proof': 1,
                 'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                 'build-sign': 0}
    attempts = ledger.get('attempts') or []
    require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-3'
            and journal_status.get('policyId') == ledger['policyId']
            and ledger.get('activeRunId') is None and journal_status.get('active') is None
            and journal_status.get('attemptCount') == 1
            and journal_status.get('remaining') == remaining
            and isinstance(attempts, list) and len(attempts) == 1
            and [a.get('operation') for a in attempts] == ['standard-token']
            and all(a.get('state') == 'TERMINAL' and a.get('exitCode') == 0
                    and a.get('certificationCredit') is False
                    and isinstance(a.get('evidence'), list) and a['evidence'] for a in attempts)
            and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
            and attempts[0].get('tuple') == new_tuple,
            'Native third repair successor lacks exact terminal Developer qualification')
    artifact = ledger.get('artifactReceipt') or {}
    require(set(artifact) == {'path', 'sha256'} and isinstance(artifact.get('path'), str)
            and HEX64.fullmatch(str(artifact.get('sha256', ''))),
            'Native third repair successor artifact receipt binding is missing')
    artifact_path = Path(artifact['path']).resolve(strict=True)
    require(digest(artifact_path) == artifact['sha256'],
            'Native third repair successor artifact receipt hash differs')
    inspected = read_json(artifact_path)
    require(inspected.get('schemaVersion') == 1
            and inspected.get('contract') == 'devfleet-signed-build-output-inspection-v1'
            and inspected.get('status') == 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION'
            and inspected.get('certificationCredit') is False
            and inspected.get('repositoryHead') == new_tuple['candidateBuildCommit']
            and inspected.get('shippingInputIdentity') == new_tuple['shippingInputIdentity']
            and inspected.get('signatureStatus') == 'Valid'
            and inspected.get('publicPromotionAllowed') is False
            and inspected.get('publicPublisherTrust') is False,
            'Native third repair successor artifact receipt differs')
    artifact_rows = inspected.get('artifacts')
    require(isinstance(artifact_rows, list) and len(artifact_rows) == 4
            and {row.get('name') for row in artifact_rows} ==
                {'exe', 'tar', 'portable', 'installerSource'}
            and next(row for row in artifact_rows if row.get('name') == 'exe').get('sha256') ==
                new_tuple['candidateSha256'],
            'Native third repair successor artifact set differs')
    return artifact


def rebind_gen4(root, tuple_path, approval_path, ledger_path, live_path):
    """Append one separately approved new-shipping binding to accepted generation 3."""
    state = _state(root)
    with lock(state / '.adoption.lock'), lock(Path(str(ledger_path) + '.lock')):
        pointer_path = state / 'CURRENT.json'
        pointer = read_json(pointer_path)
        require(pointer.get('generation') == 3,
                'Generation-4 binding requires accepted generation 3')
        old_receipt = read_json(state / 'receipts' / pointer['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        prior = _accepted_rebound_v3(root, pointer, old_tuple)
        new_tuple = exact_tuple(read_json(tuple_path))
        for key in TUPLE_KEYS:
            require(old_tuple[key] != new_tuple[key],
                    'Generation-4 binding requires a distinct signed candidate: ' + key)
        approval = read_json(approval_path)
        require(approval.get('schemaVersion') == 3
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v3'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('shippingChangeApproved') is True
                and approval.get('previousCandidate') == old_tuple
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == pointer['checkpoint']
                and approval.get('previousReceiptSha256') == prior['receiptSha256'],
                'Exact generation-4 account-owner approval is absent')
        ledger = read_json(ledger_path)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native second repair successor journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native second repair successor journal rejected binding')
        journal_status = json.loads(checked.stdout)
        artifact = _validate_v4_successor(ledger, new_tuple, journal_status)
        inventory_sha_before = digest(live_path)
        live = read_json(live_path)
        named = [x for x in live.get('snapshots', [])
                 if isinstance(x, dict) and x.get('name') == NEW_NAME]
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
                and timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2)
                and len(named) == 1 and named[0].get('id') == prior['id']
                and named[0].get('vmId') == VM_ID
                and named[0].get('parentSnapshotId') == OLD_ID,
                'Exact accepted checkpoint is not present with L1 Off')
        ledger_bytes = Path(ledger_path).read_bytes()
        inventory_bytes = Path(live_path).read_bytes()
        ledger_sha = hashlib.sha256(ledger_bytes).hexdigest()
        inventory_sha = hashlib.sha256(inventory_bytes).hexdigest()
        require(inventory_sha == inventory_sha_before,
                'Native inventory changed during generation-4 binding')
        sources = state / 'sources'
        sources.mkdir(parents=True, exist_ok=True)
        _write_exclusive(sources / (ledger_sha + '.json'), ledger_bytes)
        _write_exclusive(sources / (inventory_sha + '.json'), inventory_bytes)
        _write_exclusive(sources / (artifact['sha256'] + '.json'), Path(artifact['path']).read_bytes())
        previous_hash = digest(pointer_path)
        history = state / 'history'
        history.mkdir(parents=True, exist_ok=True)
        _write_exclusive(history / (previous_hash + '.json'), pointer_path.read_bytes())
        receipt_id = uuid.uuid4().hex
        receipt = {'schemaVersion': 4, 'contract': 'devfleet-baseline-rebind-receipt-v4',
                   'receiptId': receipt_id, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': previous_hash,
                   'previousReceiptSha256': prior['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': pointer['checkpoint'],
                   'approval': {**approval, 'sourceSha256': digest(approval_path)},
                   'approvalSha256': digest(approval_path),
                   'successorPolicyId': ledger['policyId'],
                   'successorLedgerSha256': ledger_sha,
                   'artifactReceiptSha256': artifact['sha256'],
                   'finalL1': live['vm'], 'nativeInventorySha256': inventory_sha}
        filename = receipt_id + '.json'
        receipt_path = state / 'receipts' / filename
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 4, 'contract': 'devfleet-accepted-baseline-v4',
                   'generation': 4, 'status': 'ACCEPTED',
                   'receiptFile': filename, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': pointer['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


def rebind_gen3(root, tuple_path, approval_path, ledger_path, live_path):
    """Append one separately approved exact-tuple binding to accepted generation 2."""
    state = _state(root)
    # Journal writers take ledger.json.lock. Hold that same lock until the
    # immutable qualification snapshot and accepted pointer are committed.
    with lock(state / '.adoption.lock'), lock(Path(str(ledger_path) + '.lock')):
        pointer_path = state / 'CURRENT.json'
        pointer = read_json(pointer_path)
        require(pointer.get('generation') == 2,
                'Generation-3 binding requires accepted generation 2')
        old_receipt = read_json(state / 'receipts' / pointer['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        prior = _accepted_rebound_baseline(root, pointer, old_tuple)
        new_tuple = exact_tuple(read_json(tuple_path))
        for key in ('candidateBuildCommit', 'shippingInputIdentity',
                    'releaseFingerprintId', 'candidateSha256'):
            require(old_tuple[key] == new_tuple[key],
                    'Generation-3 binding changed signed shipping identity: ' + key)
        require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
                and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
                'Generation-3 binding requires changed HEAD and tooling identity')
        approval = read_json(approval_path)
        require(approval.get('schemaVersion') == 2
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v2'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == pointer['checkpoint']
                and approval.get('previousReceiptSha256') == prior['receiptSha256'],
                'Exact generation-3 account-owner approval is absent')
        ledger = read_json(ledger_path)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native repair successor journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native repair successor journal rejected binding')
        journal_status = json.loads(checked.stdout)
        required = {'standard-token': 0, 'diagnostic': 1, 'laptop-proof': 1,
                    'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                    'build-sign': 0}
        attempts = ledger.get('attempts') or []
        require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-1'
                and journal_status.get('policyId') == ledger['policyId']
                and ledger.get('activeRunId') is None
                and journal_status.get('active') is None
                and journal_status.get('attemptCount') == 1
                and journal_status.get('remaining') == required
                and isinstance(attempts, list) and len(attempts) == 1
                and attempts[0].get('operation') == 'standard-token'
                and attempts[0].get('state') == 'TERMINAL'
                and attempts[0].get('exitCode') == 0
                and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
                and attempts[0].get('tuple') == new_tuple
                and attempts[0].get('certificationCredit') is False
                and isinstance(attempts[0].get('evidence'), list)
                and len(attempts[0]['evidence']) >= 1,
                'Native repair successor lacks exact terminal Developer qualification')
        inventory_sha_before = digest(live_path)
        live = read_json(live_path)
        named = [x for x in live.get('snapshots', [])
                 if isinstance(x, dict) and x.get('name') == NEW_NAME]
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
                and timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2)
                and len(named) == 1 and named[0].get('id') == prior['id']
                and named[0].get('vmId') == VM_ID
                and named[0].get('parentSnapshotId') == OLD_ID,
                'Exact accepted checkpoint is not present with L1 Off')
        ledger_bytes = Path(ledger_path).read_bytes()
        inventory_bytes = Path(live_path).read_bytes()
        ledger_sha = hashlib.sha256(ledger_bytes).hexdigest()
        inventory_sha = hashlib.sha256(inventory_bytes).hexdigest()
        require(inventory_sha == inventory_sha_before,
                'Native inventory changed during generation-3 binding')
        sources_dir = state / 'sources'
        sources_dir.mkdir(parents=True, exist_ok=True)
        _write_exclusive(sources_dir / (ledger_sha + '.json'), ledger_bytes)
        _write_exclusive(sources_dir / (inventory_sha + '.json'), inventory_bytes)
        previous_hash = digest(pointer_path)
        history_dir = state / 'history'
        history_dir.mkdir(parents=True, exist_ok=True)
        _write_exclusive(history_dir / (previous_hash + '.json'), pointer_path.read_bytes())
        receipt_id = uuid.uuid4().hex
        receipt = {'schemaVersion': 3, 'contract': 'devfleet-baseline-rebind-receipt-v3',
                   'receiptId': receipt_id, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': previous_hash,
                   'previousReceiptSha256': prior['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': pointer['checkpoint'],
                   'approval': {**approval, 'sourceSha256': digest(approval_path)},
                   'approvalSha256': digest(approval_path),
                   'successorPolicyId': ledger['policyId'],
                   'successorLedgerSha256': ledger_sha,
                   'finalL1': live['vm'], 'nativeInventorySha256': inventory_sha}
        filename = receipt_id + '.json'
        receipt_path = state / 'receipts' / filename
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 3, 'contract': 'devfleet-accepted-baseline-v3',
                   'generation': 3, 'status': 'ACCEPTED',
                   'receiptFile': filename, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': pointer['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


def rebind(root, tuple_path, approval_path, ledger_path, live_path):
    """Append one exact-tuple binding for an already owner-approved checkpoint."""
    state = _state(root)
    with lock(state / '.adoption.lock'):
        pointer_path = state / 'CURRENT.json'
        pointer = read_json(pointer_path)
        require(pointer.get('generation') == 1, 'Rebind requires one accepted generation-1 baseline')
        old_receipt = read_json(state / 'receipts' / pointer['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        old = _accepted_v1_baseline(root, pointer, old_tuple)
        new_tuple = exact_tuple(read_json(tuple_path))
        for key in ('candidateBuildCommit', 'shippingInputIdentity',
                    'releaseFingerprintId', 'candidateSha256'):
            require(old_tuple[key] == new_tuple[key],
                    'Rebind changed signed shipping identity: ' + key)
        require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
                and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
                'Rebind requires a changed HEAD and tooling identity')
        approval = read_json(approval_path)
        require(approval.get('schemaVersion') == 1
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v1'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == pointer['checkpoint']
                and approval.get('previousReceiptSha256') == old['receiptSha256'],
                'Exact account-owner rebind approval is absent')
        ledger = read_json(ledger_path)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native one-diagnostic journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native one-diagnostic journal rejected successor')
        journal_status = json.loads(checked.stdout)
        require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-D1'
                and journal_status.get('policyId') == ledger['policyId']
                and ledger.get('activeRunId') is None
                and journal_status.get('active') is None
                and journal_status.get('attemptCount') == 0
                and journal_status.get('remaining', {}).get('diagnostic') == 1
                and all(value == 0 for key, value in journal_status['remaining'].items()
                        if key != 'diagnostic'),
                'Native one-diagnostic successor is not unused and exact')
        live = read_json(live_path)
        named = [x for x in live.get('snapshots', [])
                 if isinstance(x, dict) and x.get('name') == NEW_NAME]
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
                and timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2)
                and len(named) == 1 and named[0].get('id') == old['id']
                and named[0].get('vmId') == VM_ID
                and named[0].get('parentSnapshotId') == OLD_ID,
                'Exact accepted checkpoint is not present with L1 Off')
        previous_hash = digest(pointer_path)
        history_dir = state / 'history'
        history_dir.mkdir(parents=True, exist_ok=True)
        history_path = history_dir / (previous_hash + '.json')
        _write_exclusive(history_path, pointer_path.read_bytes())
        receipt_id = uuid.uuid4().hex
        receipt = {'schemaVersion': 2, 'contract': 'devfleet-baseline-rebind-receipt-v2',
                   'receiptId': receipt_id, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': previous_hash,
                   'previousReceiptSha256': old['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': pointer['checkpoint'],
                   'approval': {**approval, 'sourceSha256': digest(approval_path)},
                   'approvalSha256': digest(approval_path),
                   'successorPolicyId': ledger['policyId'],
                   'successorLedgerSha256': digest(ledger_path),
                   'finalL1': live['vm'], 'nativeInventorySha256': digest(live_path)}
        receipt_file = receipt_id + '.json'
        receipt_path = state / 'receipts' / receipt_file
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 2, 'contract': 'devfleet-accepted-baseline-v2',
                   'generation': 2, 'status': 'ACCEPTED',
                   'receiptFile': receipt_file, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': pointer['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


def _validate(proposal, approval, auth, live, current_tuple, ledger, auth_path):
    current_tuple = exact_tuple(current_tuple)
    require(proposal.get('schemaVersion') == 1
            and proposal.get('contract') == 'devfleet-baseline-adoption-proposal-v1',
            'Unsupported baseline proposal')
    run_id = proposal.get('runId')
    require(isinstance(run_id, str) and run_id.startswith('r2-') and len(run_id) <= 120,
            'Baseline proposal lacks an R2 run identity')
    require(proposal.get('vm') == {'name': VM_NAME, 'id': VM_ID}
            and proposal.get('predecessor') == {'name': OLD_NAME, 'id': OLD_ID},
            'Baseline proposal widens VM or predecessor scope')
    replacement = proposal.get('replacement') or {}
    try: new_id = str(uuid.UUID(replacement.get('id', '')))
    except (ValueError, TypeError, AttributeError) as exc: raise ValueError('Replacement GUID is invalid') from exc
    require(replacement == {'name': NEW_NAME, 'id': new_id, 'vmId': VM_ID,
                            'parentSnapshotId': OLD_ID} and new_id != OLD_ID,
            'Replacement must have a new exact GUID, name, VM and parent')
    require(proposal.get('candidate') == current_tuple,
            'Proposal candidate/material tuple is stale')
    require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2'
            and ledger.get('activeRunId') is None,
            'The authenticated guest source is not from a terminal R2 campaign')
    attempts = [a for a in ledger.get('attempts', []) if isinstance(a, dict)
                and a.get('runId') == run_id]
    require(len(attempts) == 1 and attempts[0].get('operation') == 'diagnostic'
            and attempts[0].get('state') == 'TERMINAL'
            and attempts[0].get('certificationCredit') is False,
            'Authenticated guest source lacks one charged terminal R2 diagnostic')
    attempt = attempts[0]
    require(type(attempt.get('exitCode')) is int and attempt['exitCode'] == 0,
            'Authenticated guest source diagnostic did not exit successfully')
    attempted_tuple = attempt.get('tuple')
    require(isinstance(attempted_tuple, dict)
            and {key: attempted_tuple.get(key) for key in TUPLE_KEYS} == current_tuple,
            'Authenticated diagnostic reservation has a different candidate/material tuple')
    require(auth.get('vm') == {'name': VM_NAME, 'id': VM_ID}
            and auth.get('candidate') == current_tuple,
            'Authenticated collector VM or candidate/material tuple differs')
    evidence_paths = attempts[0].get('evidence')
    require(isinstance(evidence_paths, list)
            and str(Path(auth_path).resolve(strict=True)) in evidence_paths,
            'Authenticated guest evidence is not retained by its terminal R2 attempt')

    require(approval.get('schemaVersion') == 1
            and approval.get('contract') == 'devfleet-baseline-adoption-approval-v1'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('vmId') == VM_ID
            and approval.get('predecessorId') == OLD_ID
            and approval.get('replacementId') == new_id
            and approval.get('runId') == run_id
            and approval.get('candidate') == current_tuple,
            'Explicit account-owner adoption approval is absent or mismatched')

    require(auth.get('scope') == 'CURRENT_RUNNING_GUEST_READ_ONLY'
            and auth.get('runId') == run_id and auth.get('connected') is True
            and auth.get('status') == 'AUTHENTICATED_CURRENT_GUEST_NOT_CLEAN_PROOF'
            and auth.get('certificationCredit') is False,
            'Authenticated current-guest evidence is absent or wrong-run')
    guest, credential, nested = (auth.get('guest') or {}, auth.get('credential') or {},
                                  auth.get('nestedL2') or {})
    require(guest.get('computerName') == 'DEVFLEET-E2E-01'
            and guest.get('principal') == 'DEVFLEET-E2E-01\\E2EAdmin'
            and guest.get('accountEnabled') is True,
            'Authenticated guest/account identity is not exact')
    auth_time = instant(auth.get('observedUtc'))
    started = instant(auth.get('startedUtc'))
    reserved = instant(attempt.get('reservedUtc'))
    terminal = instant(attempt.get('terminalUtc'))
    deadline = instant(attempt.get('deadlineUtc'))
    require(reserved <= started <= auth_time <= terminal <= deadline,
            'Authenticated collection is outside its charged diagnostic time window')
    last_set = instant(guest.get('passwordLastSetUtc'))
    expires = instant(guest.get('passwordExpiresUtc'))
    store_time = instant(credential.get('protectedStoreUpdatedUtc'))
    require(last_set <= store_time <= auth_time < expires
            and credential.get('storeUser') == 'E2EAdmin'
            and credential.get('secretValuesRecorded') is False,
            'Credential freshness or expiry metadata is incomplete/stale')
    require(nested.get('status') == 'ABSENT' and nested.get('present') is False
            and nested.get('expectedName') == L2_NAME
            and type(nested.get('exactMatchCount')) is int and nested['exactMatchCount'] == 0
            and started <= instant(nested.get('observedUtc')) <= auth_time,
            'Nested L2 absence is not positively proven')
    inventories = nested.get('backendInventories')
    require(isinstance(inventories, list) and len(inventories) == 2
            and {x.get('provider') for x in inventories if isinstance(x, dict)} == {'Hyper-V', 'VirtualBox'},
            'Complete supported in-L1 backend inventories are missing')
    for inventory in inventories:
        require(inventory.get('status') == 'PASS'
                and isinstance(inventory.get('names'), list)
                and all(isinstance(n, str) and n.strip() and n != L2_NAME
                        for n in inventory['names'])
                and isinstance(inventory.get('verification'), str)
                and inventory['verification'].strip(),
                'Nested L2 backend inventory is incomplete or present')

    require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
            and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'},
            'Final native exact L1 Off identity is absent')
    live_time = instant(live.get('observedUtc'))
    require(auth_time <= instant(attempts[0].get('terminalUtc')) <= live_time,
            'Authenticated observation is outside its terminal diagnostic lineage')
    require(auth_time <= live_time <= datetime.now(timezone.utc)
            and (live_time - auth_time).total_seconds() <= 3600
            and live_time < expires and datetime.now(timezone.utc) < expires
            and (datetime.now(timezone.utc) - live_time).total_seconds() <= 3600,
            'Native checkpoint inventory is not fresh after authenticated guest evidence')
    snapshots = live.get('snapshots')
    require(isinstance(snapshots, list) and len(snapshots) >= 2
            and all(isinstance(s, dict) for s in snapshots),
            'Native snapshot inventory is incomplete')
    old_rows = [s for s in snapshots if s.get('id') == OLD_ID or s.get('name') == OLD_NAME]
    new_rows = [s for s in snapshots if s.get('id') == new_id or s.get('name') == NEW_NAME]
    require(len(old_rows) == 1 and old_rows[0].get('name') == OLD_NAME
            and old_rows[0].get('id') == OLD_ID and old_rows[0].get('vmId') == VM_ID,
            'Predecessor checkpoint is missing or ambiguous')
    require(len(new_rows) == 1 and new_rows[0].get('name') == NEW_NAME
            and new_rows[0].get('id') == new_id and new_rows[0].get('vmId') == VM_ID
            and new_rows[0].get('parentSnapshotId') == OLD_ID,
            'Replacement checkpoint is missing, ambiguous or name-only')
    return current_tuple, expires


def adopt(root, proposal_path, approval_path, auth_path, live_path, tuple_path, ledger_path,
          *, fault=None):
    """Atomically adopt one validated replacement; never touch checkpoints or old history."""
    state = _state(root)
    with lock(state / '.adoption.lock'):
        pointer = state / 'CURRENT.json'
        receipts = state / 'receipts'
        require(not pointer.exists(), 'An accepted replacement already exists; replay rejected')
        require(not receipts.exists() or not list(receipts.iterdir()),
                'Interrupted/orphan receipt exists; old baseline remains selected')
        proposal, approval = read_json(proposal_path), read_json(approval_path)
        auth, live, current_tuple = read_json(auth_path), read_json(live_path), read_json(tuple_path)
        ledger = read_json(ledger_path)
        predecessor_evidence = proposal.get('predecessorEvidence') or {}
        predecessor_path = Path(predecessor_evidence.get('path', ''))
        expected_source_root = Path(root).resolve(strict=True) / 'audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2'
        require(predecessor_path.is_absolute() and predecessor_path.suffix.lower() == '.json'
                and predecessor_path.resolve(strict=True).is_relative_to(expected_source_root)
                and predecessor_evidence.get('sha256') == digest(predecessor_path),
                'Preserved predecessor evidence is absent, outside R2, or hash mismatched')
        predecessor_record = read_json(predecessor_path)
        require((predecessor_record.get('lab') or {}).get('l1Id') == VM_ID
                and (predecessor_record.get('lab') or {}).get('cleanId') == OLD_ID
                and (predecessor_record.get('liveGuestAuth') or {}).get('cleanRestored') is True
                and (predecessor_record.get('liveGuestAuth') or {}).get('finalL1State') == 'Off',
                'Predecessor source does not preserve the exact restored CLEAN identity')
        candidate, expires = _validate(proposal, approval, auth, live, current_tuple,
                                       ledger, auth_path)
        receipts.mkdir(parents=True, exist_ok=True)
        receipt_id = uuid.uuid4().hex
        receipt_file = receipt_id + '.json'
        receipt = {
            'schemaVersion': 1, 'contract': 'devfleet-baseline-adoption-receipt-v1',
            'receiptId': receipt_id, 'status': 'ADOPTED',
            'adoptedUtc': datetime.now(timezone.utc).isoformat(),
            'certificationCredit': False, 'secretValuesRecorded': False,
            'predecessor': proposal['predecessor'], 'replacement': proposal['replacement'],
            'candidate': candidate, 'runId': proposal['runId'],
            'passwordLastSetUtc': auth['guest']['passwordLastSetUtc'],
            'passwordExpiresUtc': auth['guest']['passwordExpiresUtc'],
            'protectedStoreUpdatedUtc': auth['credential']['protectedStoreUpdatedUtc'],
            'authenticatedGuest': {'computerName': auth['guest']['computerName'],
                                   'principal': auth['guest']['principal'],
                                   'accountEnabled': True,
                                   'sourceObservedUtc': auth['observedUtc']},
            'nestedL2': auth['nestedL2'],
            'finalL1': live['vm'],
            'liveCheckpointInventory': live['snapshots'],
            'adoptionAuthority': {'decision': approval['decision'],
                                  'approvedBy': approval['approvedBy'],
                                  'sourceSha256': digest(approval_path)},
            'sources': {'proposalSha256': digest(proposal_path),
                        'predecessorEvidenceSha256': digest(predecessor_path),
                        'approvalSha256': digest(approval_path),
                        'authenticatedGuestSha256': digest(auth_path),
                        'nativeInventorySha256': digest(live_path),
                        'currentTupleSha256': digest(tuple_path),
                        'r2LedgerSha256': digest(ledger_path)},
        }
        receipt_path = receipts / receipt_file
        _write_exclusive(receipt_path, _json_bytes(receipt))
        receipt_hash = digest(receipt_path)
        if fault == 'after_receipt':
            raise RuntimeError('Injected interruption after immutable receipt')
        pointer_value = {'schemaVersion': 1, 'contract': 'devfleet-accepted-baseline-v1',
                         'generation': 1, 'status': 'ACCEPTED',
                         'receiptFile': receipt_file, 'receiptSha256': receipt_hash,
                         'checkpoint': proposal['replacement']}
        _atomic_replace(pointer, _json_bytes(pointer_value))
        return {'receiptFile': receipt_file, 'receiptSha256': receipt_hash,
                'certificationCredit': False, 'passwordExpiresUtc': expires.isoformat()}


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    inspect = sub.add_parser('inspect')
    inspect.add_argument('--root', required=True)
    inspect.add_argument('--tuple')
    adoption = sub.add_parser('adopt')
    for flag in ('root', 'proposal', 'approval', 'auth', 'live', 'tuple', 'ledger'):
        adoption.add_argument('--' + flag, required=True)
    binding = sub.add_parser('rebind')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding.add_argument('--' + flag, required=True)
    binding3 = sub.add_parser('rebind-gen3')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding3.add_argument('--' + flag, required=True)
    binding4 = sub.add_parser('rebind-gen4')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding4.add_argument('--' + flag, required=True)
    binding5 = sub.add_parser('rebind-gen5')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding5.add_argument('--' + flag, required=True)
    args = parser.parse_args()
    if args.command == 'inspect':
        value = accepted_baseline(args.root, read_json(args.tuple) if args.tuple else None)
    elif args.command == 'adopt':
        value = adopt(args.root, args.proposal, args.approval, args.auth, args.live, args.tuple,
                      args.ledger)
    elif args.command == 'rebind':
        value = rebind(args.root, args.tuple, args.approval, args.ledger, args.live)
    elif args.command == 'rebind-gen4':
        value = rebind_gen4(args.root, args.tuple, args.approval, args.ledger, args.live)
    elif args.command == 'rebind-gen5':
        value = rebind_gen5(args.root, args.tuple, args.approval, args.ledger, args.live)
    else:
        value = rebind_gen3(args.root, args.tuple, args.approval, args.ledger, args.live)
    print(json.dumps(value, indent=2))


if __name__ == '__main__': main()

```


## FILE: tools/compute_shipping_input_identity.py

SHA256: 124fb632ac98b18e48f3b163a1568b627381c1614e93f98effce4d13d254732b | Bytes: 9809 | Git mode: 100644

```
"""Compute live and candidate shipping-input rows from the release fingerprint contract.

This is release tooling: it imports the candidate-bound ``release_fingerprint``
implementation instead of maintaining a second inclusion/mode/hash policy.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


RELEASE_ARTIFACT_NAMES = frozenset({"exe", "tar", "portable", "installerSource"})


def _fingerprint(source: Path, installer: Path, artifacts: dict[str, Path] | None = None) -> dict[str, object]:
    tools = source / "tools"
    previous_modules = {name: sys.modules.get(name) for name in ("release_fingerprint", "hook_modes")}
    for name in previous_modules:
        sys.modules.pop(name, None)
    sys.path.insert(0, str(tools))
    try:
        from release_fingerprint import build_fingerprint  # type: ignore

        return build_fingerprint(source, installer, artifacts)
    finally:
        sys.path.pop(0)
        for name in previous_modules:
            sys.modules.pop(name, None)
        for name, module in previous_modules.items():
            if module is not None:
                sys.modules[name] = module


def _git_commit_exists(workspace: Path, commit: str) -> None:
    if not commit or len(commit) != 40 or any(ch not in "0123456789abcdefABCDEF" for ch in commit):
        raise ValueError("candidate commit must be an explicit 40-character Git object ID")
    try:
        subprocess.run(["git", "-C", str(workspace), "cat-file", "-e", f"{commit}^{{commit}}"], check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(f"candidate commit does not resolve to a commit: {commit}") from exc


def _materialize_candidate(workspace: Path, commit: str, artifacts: dict[str, Path] | None = None) -> tuple[dict[str, object], Path]:
    """Materialize candidate shipping trees without changing the checkout."""
    _git_commit_exists(workspace, commit)
    try:
        archive = subprocess.check_output(["git", "-C", str(workspace), "-c", "core.autocrlf=false", "archive", "--format=tar", commit, "source", "installer-source"], stderr=subprocess.STDOUT)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(f"candidate shipping tree could not be materialized: {commit}") from exc
    staging = Path(tempfile.mkdtemp(prefix="devfleet-candidate-"))
    try:
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
            stream.extractall(staging, filter="data")
        source, installer = staging / "source", staging / "installer-source"
        if not source.is_dir() or not installer.is_dir():
            raise ValueError("candidate commit has ambiguous or incomplete shipping roots")
        return _fingerprint(source, installer, artifacts), staging
    except Exception:
        import shutil
        shutil.rmtree(staging, ignore_errors=True)
        raise


def _shipping_identity(fingerprint: dict[str, object]) -> str:
    payload = {"schemaVersion": 1, "devfleetVersion": fingerprint["devfleetVersion"], "installerVersion": fingerprint["installerVersion"], "shippingModeContract": fingerprint["shippingModeContract"], "shippingInputs": fingerprint["shippingInputs"]}
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _materialization_comparison(
    live_source: Path,
    live_installer: Path,
    candidate_source: Path,
    candidate_installer: Path,
    live: dict[str, object],
    candidate: dict[str, object],
) -> dict[str, object]:
    """Classify checkout differences without weakening Git-object authority.

    Only insertion of CR before an LF in a live Windows checkout is accepted
    as a non-substantive materialization difference.  Missing files, mode
    contract changes, versions, bare CR changes, or any other byte change are
    substantive.
    """

    def rows(value: dict[str, object]) -> dict[str, dict[str, object]]:
        return {
            f"{row['root']}/{row['path']}": row
            for row in value["shippingInputs"]  # type: ignore[index]
        }

    live_rows, candidate_rows = rows(live), rows(candidate)
    changed = sorted(
        path
        for path in set(live_rows) | set(candidate_rows)
        if live_rows.get(path) != candidate_rows.get(path)
    )
    crlf_only_paths: list[str] = []
    crlf_only = bool(changed)
    for relative in changed:
        live_row, candidate_row = live_rows.get(relative), candidate_rows.get(relative)
        if live_row is None or candidate_row is None or live_row.get("mode") != candidate_row.get("mode"):
            crlf_only = False
            continue
        root_name, path = relative.split("/", 1)
        live_root = live_source if root_name == "source" else live_installer
        candidate_root = candidate_source if root_name == "source" else candidate_installer
        live_bytes = (live_root / path).read_bytes()
        candidate_bytes = (candidate_root / path).read_bytes()
        if live_bytes != candidate_bytes and live_bytes.replace(b"\r\n", b"\n") == candidate_bytes:
            crlf_only_paths.append(relative)
        else:
            crlf_only = False
    if (
        live["shippingModeContract"] != candidate["shippingModeContract"]
        or live["devfleetVersion"] != candidate["devfleetVersion"]
        or live["installerVersion"] != candidate["installerVersion"]
    ):
        crlf_only = False
    if crlf_only and len(crlf_only_paths) != len(changed):
        crlf_only = False
    return {
        "lineEndingComparison": "CRLF_ONLY" if crlf_only else ("BYTE_EXACT" if not changed else "SUBSTANTIVE"),
        "materializedChangedPaths": changed,
        "crlfOnlyPaths": crlf_only_paths if crlf_only else [],
        "crlfOnlyMaterialization": crlf_only,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--candidate-commit")
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--installer-root", type=Path)
    parser.add_argument("--artifact", action="append", default=[], metavar="NAME=PATH")
    args = parser.parse_args()
    artifacts: dict[str, Path] = {}
    for value in args.artifact:
        name, separator, raw_path = value.partition("=")
        if not separator or not name or not raw_path:
            parser.error(f"artifact must be NAME=PATH: {value}")
        if name in artifacts:
            parser.error(f"duplicate artifact name: {name}")
        artifacts[name] = Path(raw_path).resolve()
    if artifacts:
        missing = sorted(RELEASE_ARTIFACT_NAMES - set(artifacts))
        unexpected = sorted(set(artifacts) - RELEASE_ARTIFACT_NAMES)
        if missing or unexpected:
            parser.error(f"artifact tuple must be exactly {sorted(RELEASE_ARTIFACT_NAMES)}; missing={missing}; unexpected={unexpected}")
        absent = sorted(name for name, path in artifacts.items() if not path.is_file())
        if absent:
            parser.error(f"artifact paths must be existing files: {absent}")
    if args.source_root and args.installer_root:
        fingerprint = _fingerprint(args.source_root.resolve(), args.installer_root.resolve(), artifacts)
        print(json.dumps({"shippingInputIdentity": _shipping_identity(fingerprint), "releaseFingerprintId": fingerprint["releaseFingerprintId"], "artifacts": fingerprint["artifacts"], "toolingFingerprint": fingerprint["toolingFingerprint"]}, ensure_ascii=False, separators=(",", ":")))
        return 0
    if not args.workspace or not args.candidate_commit:
        parser.error("--workspace and --candidate-commit are required unless --source-root and --installer-root are supplied")
    workspace = args.workspace.resolve()
    live = _fingerprint(workspace / "source", workspace / "installer-source", artifacts)
    candidate, staging = _materialize_candidate(workspace, args.candidate_commit, artifacts)
    try:
        comparison = _materialization_comparison(
            workspace / "source",
            workspace / "installer-source",
            staging / "source",
            staging / "installer-source",
            live,
            candidate,
        )
        candidate_fingerprint = {
            key: value for key, value in candidate.items() if key != "toolingFingerprint"
        }
        payload = {
            "liveShippingInputs": live["shippingInputs"],
            "candidateShippingInputs": candidate["shippingInputs"],
            "liveShippingModeContract": live["shippingModeContract"],
            "candidateShippingModeContract": candidate["shippingModeContract"],
            "liveVersion": live["devfleetVersion"],
            "candidateVersion": candidate["devfleetVersion"],
            "liveInstallerVersion": live["installerVersion"],
            "candidateInstallerVersion": candidate["installerVersion"],
            "liveShippingInputIdentity": _shipping_identity(live),
            "candidateShippingInputIdentity": _shipping_identity(candidate),
            "liveReleaseFingerprintId": live["releaseFingerprintId"],
            "candidateReleaseFingerprintId": candidate["releaseFingerprintId"],
            "artifacts": candidate["artifacts"],
            "candidateFingerprint": candidate_fingerprint,
            "liveToolingFingerprint": live["toolingFingerprint"],
            **comparison,
        }
    finally:
        import shutil
        shutil.rmtree(staging, ignore_errors=True)
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: tools/reconcile_osv_scanner.py

SHA256: 6cb2abed1ebcf7784767c22714f398bd68935bb74ede1b4239c0b512794ab82b | Bytes: 5548 | Git mode: 100644

```
"""Reconcile the custom dependency gate with first-party OSV-Scanner output."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdig