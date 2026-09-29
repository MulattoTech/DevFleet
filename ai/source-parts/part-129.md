# DevFleet source part 129

Full-source UTF-8 byte interval [5952000, 5998500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: e962a30687683363383e12928dcb59e52e8b79125c310e425807572713d976de

<!-- BEGIN SOURCE SLICE -->
ENT-PROOF.json",
    "evidence/FULLRELEASE-SUMMARY.json", "audit/CURRENT-HANDOFF.json",
    "release-tooling/proof-entrypoints/run-exact-candidate-proof.ps1",
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _safe_extract(bundle: zipfile.ZipFile, destination: Path) -> set[str]:
    names: set[str] = set()
    for info in bundle.infolist():
        normalized = PurePosixPath(info.filename.replace("\\", "/"))
        if normalized.is_absolute() or ".." in normalized.parts:
            raise ValueError(f"unsafe archive member: {info.filename}")
        name = normalized.as_posix()
        if name in names:
            raise ValueError(f"duplicate archive member: {name}")
        file_type = (info.external_attr >> 16) & stat.S_IFMT(0o170000)
        if file_type in (stat.S_IFLNK, stat.S_IFCHR, stat.S_IFBLK, stat.S_IFIFO):
            raise ValueError(f"unsupported special archive member: {name}")
        names.add(name)
        target = (destination / Path(*normalized.parts)).resolve()
        if destination.resolve() not in target.parents and target != destination.resolve():
            raise ValueError(f"archive member escapes extraction root: {info.filename}")
        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(info, "r") as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
    return names


def _proof_identity(value: object, *keys: str) -> str:
    if isinstance(value, dict):
        for key in keys:
            if value.get(key):
                return str(value[key])
        for child in value.values():
            found = _proof_identity(child, *keys)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _proof_identity(child, *keys)
            if found:
                return found
    return ""


def _validate_repair3_signed_output_receipt(receipt: dict, candidate: dict) -> None:
    """Check the non-certifying signed-output receipt bound to REPAIR-3."""
    rows = receipt.get('artifacts')
    names = [row.get('name') for row in rows or [] if isinstance(row, dict)]
    exe_rows = [row for row in rows or []
                if isinstance(row, dict) and row.get('name') == 'exe']
    if (receipt.get('schemaVersion') != 1
            or receipt.get('contract') != 'devfleet-signed-build-output-inspection-v1'
            or receipt.get('status') != 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION'
            or receipt.get('certificationCredit') is not False
            or receipt.get('repositoryHead') != candidate['candidateBuildCommit']
            or receipt.get('shippingInputIdentity') != candidate['shippingInputIdentity']
            or receipt.get('signatureStatus') != 'Valid'
            or receipt.get('publicPromotionAllowed') is not False
            or receipt.get('publicPublisherTrust') is not False
            or len(names) != 4
            or set(names) != {'exe', 'tar', 'portable', 'installerSource'}
            or any(not re.fullmatch(r'[0-9a-f]{64}', str(row.get('sha256', '')).lower())
                   for row in rows or [] if isinstance(row, dict)
                   )
            or len(exe_rows) != 1
            or exe_rows[0].get('sha256') != candidate['candidateSha256']):
        raise ValueError('generation-4 signed-output receipt contents are invalid')


def _load_packaged_repair3_receipt(sources: Path, artifact_hash: str) -> dict:
    """Load REPAIR-3 receipt only from the packaged hash-addressed source."""
    if not re.fullmatch(r'[0-9a-f]{64}', artifact_hash):
        raise ValueError('generation-4 signed-output receipt is absent or unbound')
    path = sources / (artifact_hash + '.json')
    if (not path.is_file() or path.is_symlink() or sha(path) != artifact_hash):
        raise ValueError('generation-4 signed-output receipt is absent or hash-mismatched')
    return json.loads(path.read_text(encoding='utf-8-sig'))


def _validate_repair3_receipt_hash_binding(binding: dict, artifact_hash: str) -> None:
    if binding.get('artifactReceiptSha256') != artifact_hash:
        raise ValueError('generation-4 baseline and signed-output receipt hashes differ')


def _validate_repair3_attempts(attempts: object, candidate: dict) -> None:
    if (not isinstance(attempts, list) or len(attempts) != 1
            or len([a for a in attempts if a.get('operation') == 'build-sign']) != 0
            or len({a.get('operation') for a in attempts}) != len(attempts)
            or attempts[0].get('operation') != 'standard-token'
            or attempts[0].get('state') != 'TERMINAL'
            or attempts[0].get('exitCode') != 0
            or attempts[0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
            or attempts[0].get('tuple') != candidate
            or attempts[0].get('certificationCredit') is not False
            or not isinstance(attempts[0].get('evidence'), list)
            or not attempts[0]['evidence']):
        raise ValueError('generation-4 qualification source lacks exact REPAIR-3 standard token')


def load_accepted_baseline(root: Path, expected: dict[str, str], artifacts: dict[str, str],
                           _pointer: dict | None = None) -> dict[str, str | None]:
    """Resolve only the original CLEAN or a packaged, immutable adoption receipt."""
    def strict_baseline_json(path: Path) -> dict:
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 4_000_000:
            raise ValueError("accepted baseline evidence is absent, linked, or oversized")
        def pairs(items):
            result = {}
            for key, value in items:
                if key in result:
                    raise ValueError("accepted baseline JSON has duplicate keys")
                result[key] = value
            return result
        value = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite baseline JSON")))
        if not isinstance(value, dict):
            raise ValueError("accepted baseline JSON root is invalid")
        return value
    old_id = "19865b76-4c3a-44f7-ba39-841e9d3c40c9"
    pointer_path = root / "evidence/baselines/CURRENT.json"
    if not pointer_path.exists():
        return {"id": old_id, "name": "DevFleet-E2E-CLEAN", "receiptSha256": None}
    pointer = _pointer if _pointer is not None else strict_baseline_json(pointer_path)
    if pointer.get('generation') == 5:
        if (pointer.get('schemaVersion') != 5
                or pointer.get('contract') != 'devfleet-accepted-baseline-v5'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('generation-5 baseline pointer contract is invalid')
        old_hash, name = pointer.get('previousPointerSha256', ''), pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('generation-5 baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or history_path.is_symlink() or sha(history_path) != old_hash
                or not receipt_path.is_file() or receipt_path.is_symlink()
                or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('generation-5 baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 4:
            raise ValueError('generation-5 predecessor is not generation 4')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        prior_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                          'candidateCommit': old_tuple.get('candidateBuildCommit'),
                          'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                          'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                          'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, prior_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        if (binding.get('schemaVersion') != 5
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v5'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or 'artifactReceiptSha256' in binding
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != prior['receiptSha256']
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')
                or new_tuple != actual
                or old_tuple.get('repositoryHead') == new_tuple.get('repositoryHead')
                or old_tuple.get('toolingFingerprintId') == new_tuple.get('toolingFingerprintId')
                or any(old_tuple.get(key) != new_tuple.get(key) for key in
                       ('candidateBuildCommit', 'shippingInputIdentity',
                        'releaseFingerprintId', 'candidateSha256'))):
            raise ValueError('generation-5 receipt or signed material tuple differs')
        approval = binding.get('approval') or {}
        final_l1 = {'name': 'DevFleet-E2E-Win11-01',
                    'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'state': 'Off'}
        if (approval.get('schemaVersion') != 4
                or approval.get('contract') != 'devfleet-baseline-rebind-approval-v4'
                or approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('shippingChangeApproved') is not False
                or approval.get('previousCandidate') != old_tuple
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('approvalSha256', '')))
                or binding.get('finalL1') != final_l1
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('nativeInventorySha256', '')))):
            raise ValueError('generation-5 authorization or terminal lab differs')
        sources = root / 'evidence/baselines/sources'
        ledger_hash, inventory_hash = binding['successorLedgerSha256'], binding['nativeInventorySha256']
        ledger_path, inventory_path = sources / (ledger_hash + '.json'), sources / (inventory_hash + '.json')
        if (not ledger_path.is_file() or ledger_path.is_symlink() or sha(ledger_path) != ledger_hash
                or not inventory_path.is_file() or inventory_path.is_symlink()
                or sha(inventory_path) != inventory_hash):
            raise ValueError('generation-5 qualification or inventory source is absent or altered')
        ledger, inventory = strict_baseline_json(ledger_path), strict_baseline_json(inventory_path)
        attempts = ledger.get('attempts')
        limits = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                  'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
        if (ledger.get('policyId') != binding['successorPolicyId']
                or ledger.get('limits') != limits
                or ledger.get('activeRunId') is not None
                or not isinstance(attempts, list) or len(attempts) != 1
                or attempts[0].get('operation') != 'standard-token'
                or attempts[0].get('state') != 'TERMINAL'
                or attempts[0].get('exitCode') != 0
                or attempts[0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
                or attempts[0].get('tuple') != new_tuple
                or attempts[0].get('certificationCredit') is not False
                or not isinstance(attempts[0].get('evidence'), list)
                or not attempts[0]['evidence']):
            raise ValueError('generation-5 qualification source lacks exact standard token')
        snapshots = inventory.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict)
                 and row.get('name') == 'DevFleet-E2E-CLEAN-R2'] if isinstance(snapshots, list) else []
        if (inventory.get('scope') != 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                or inventory.get('vm') != final_l1
                or len(exact) != 1 or exact[0].get('id') != pointer['checkpoint']['id']
                or exact[0].get('vmId') != final_l1['id']
                or exact[0].get('parentSnapshotId') != '19865b76-4c3a-44f7-ba39-841e9d3c40c9'):
            raise ValueError('generation-5 inventory does not prove accepted checkpoint and L1 Off')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    if pointer.get('generation') == 4:
        if (pointer.get('schemaVersion') != 4
                or pointer.get('contract') != 'devfleet-accepted-baseline-v4'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('generation-4 baseline pointer contract is invalid')
        old_hash, name = pointer.get('previousPointerSha256', ''), pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('generation-4 baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or history_path.is_symlink() or sha(history_path) != old_hash
                or not receipt_path.is_file() or receipt_path.is_symlink()
                or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('generation-4 baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 3:
            raise ValueError('generation-4 predecessor is not generation 3')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        prior_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                          'candidateCommit': old_tuple.get('candidateBuildCommit'),
                          'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                          'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                          'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, prior_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        tuple_keys = ('repositoryHead', 'candidateBuildCommit', 'shippingInputIdentity',
                      'releaseFingerprintId', 'toolingFingerprintId', 'candidateSha256')
        if (binding.get('schemaVersion') != 4
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v4'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != prior['receiptSha256']
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')
                or new_tuple != actual
                or any(old_tuple.get(key) == new_tuple.get(key) for key in tuple_keys)):
            raise ValueError('generation-4 receipt or signed material tuple differs')
        approval = binding.get('approval') or {}
        final_l1 = {'name': 'DevFleet-E2E-Win11-01',
                    'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'state': 'Off'}
        if (approval.get('schemaVersion') != 3
                or approval.get('contract') != 'devfleet-baseline-rebind-approval-v3'
                or approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('shippingChangeApproved') is not True
                or approval.get('previousCandidate') != old_tuple
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('approvalSha256', '')))
                or binding.get('finalL1') != final_l1
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-3'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('nativeInventorySha256', '')))):
            raise ValueError('generation-4 authorization or terminal lab differs')
        sources = root / 'evidence/baselines/sources'
        ledger_hash, inventory_hash = binding['successorLedgerSha256'], binding['nativeInventorySha256']
        ledger_path, inventory_path = sources / (ledger_hash + '.json'), sources / (inventory_hash + '.json')
        if (not ledger_path.is_file() or ledger_path.is_symlink() or sha(ledger_path) != ledger_hash
                or not inventory_path.is_file() or inventory_path.is_symlink()
                or sha(inventory_path) != inventory_hash):
            raise ValueError('generation-4 qualification or inventory source is absent or altered')
        ledger, inventory = strict_baseline_json(ledger_path), strict_baseline_json(inventory_path)
        attempts = ledger.get('attempts')
        limits = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                  'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
        artifact_binding = ledger.get('artifactReceipt') or {}
        artifact_hash = str(artifact_binding.get('sha256', '')).lower()
        _validate_repair3_receipt_hash_binding(binding, artifact_hash)
        artifact_receipt = _load_packaged_repair3_receipt(sources, artifact_hash)
        _validate_repair3_signed_output_receipt(artifact_receipt, new_tuple)
        if (ledger.get('policyId') != binding['successorPolicyId']
                or ledger.get('limits') != limits
                or ledger.get('activeRunId') is not None):
            raise ValueError('generation-4 qualification source lacks exact REPAIR-3 standard token')
        _validate_repair3_attempts(attempts, new_tuple)
        snapshots = inventory.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict)
                 and row.get('name') == 'DevFleet-E2E-CLEAN-R2'] if isinstance(snapshots, list) else []
        if (inventory.get('scope') != 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                or inventory.get('vm') != final_l1
                or len(exact) != 1 or exact[0].get('id') != pointer['checkpoint']['id']
                or exact[0].get('vmId') != final_l1['id']
                or exact[0].get('parentSnapshotId') != '19865b76-4c3a-44f7-ba39-841e9d3c40c9'):
            raise ValueError('generation-4 inventory does not prove accepted checkpoint and L1 Off')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    if pointer.get('generation') == 3:
        if (pointer.get('schemaVersion') != 3
                or pointer.get('contract') != 'devfleet-accepted-baseline-v3'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('generation-3 baseline pointer contract is invalid')
        old_hash = pointer.get('previousPointerSha256', '')
        name = pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('generation-3 baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or sha(history_path) != old_hash
                or not receipt_path.is_file() or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('generation-3 baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 2:
            raise ValueError('generation-3 predecessor is not generation 2')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        old_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                        'candidateCommit': old_tuple.get('candidateBuildCommit'),
                        'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                        'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                        'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, old_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        if (binding.get('schemaVersion') != 3
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v3'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != prior['receiptSha256']
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')
                or new_tuple != actual
                or old_tuple.get('repositoryHead') == new_tuple.get('repositoryHead')
                or old_tuple.get('toolingFingerprintId') == new_tuple.get('toolingFingerprintId')
                or any(old_tuple.get(key) != new_tuple.get(key) for key in
                       ('candidateBuildCommit', 'shippingInputIdentity',
                        'releaseFingerprintId', 'candidateSha256'))):
            raise ValueError('generation-3 receipt or material tuple differs')
        approval = binding.get('approval') or {}
        if (approval.get('schemaVersion') != 2
                or approval.get('contract') != 'devfleet-baseline-rebind-approval-v2'
                or approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not isinstance(binding.get('approvalSha256'), str)
                or not re.fullmatch(r'[0-9a-f]{64}', binding['approvalSha256'])
                or binding.get('finalL1') != {'name': 'DevFleet-E2E-Win11-01',
                                             'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2',
                                             'state': 'Off'}
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-1'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('nativeInventorySha256', '')))):
            raise ValueError('generation-3 authorization or terminal lab differs')
        source_dir = root / 'evidence/baselines/sources'
        ledger_hash = binding['successorLedgerSha256']
        inventory_hash = binding['nativeInventorySha256']
        ledger_path = source_dir / (ledger_hash + '.json')
        inventory_path = source_dir / (inventory_hash + '.json')
        if (not ledger_path.is_file() or ledger_path.is_symlink()
                or not inventory_path.is_file() or inventory_path.is_symlink()
                or sha(ledger_path) != ledger_hash or sha(inventory_path) != inventory_hash):
            raise ValueError('generation-3 qualification or inventory source is absent or altered')
        ledger = strict_baseline_json(ledger_path)
        inventory = strict_baseline_json(inventory_path)
        attempts = ledger.get('attempts')
        required_remaining = {'standard-token': 1, 'diagnostic': 1,
                              'laptop-proof': 1, 'desktop-proof': 1,
                              'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
        if (ledger.get('policyId') != binding['successorPolicyId']
                or ledger.get('limits') != required_remaining
                or ledger.get('activeRunId') is not None
                or not isinstance(attempts, list) or len(attempts) != 1
                or attempts[0].get('operation') != 'standard-token'
                or attempts[0].get('state') != 'TERMINAL'
                or attempts[0].get('exitCode') != 0
                or attempts[0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
                or attempts[0].get('tuple') != new_tuple
                or attempts[0].get('certificationCredit') is not False
                or not isinstance(attempts[0].get('evidence'), list)
                or not attempts[0]['evidence']):
            raise ValueError('generation-3 qualification source does not prove terminal standard token')
        snapshots = inventory.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict)
                 and row.get('name') == 'DevFleet-E2E-CLEAN-R2'] if isinstance(snapshots, list) else []
        if (inventory.get('scope') != 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                or inventory.get('vm') != binding['finalL1']
                or len(exact) != 1 or exact[0].get('id') != pointer['checkpoint']['id']
                or exact[0].get('vmId') != binding['finalL1']['id']
                or exact[0].get('parentSnapshotId') != '19865b76-4c3a-44f7-ba39-841e9d3c40c9'):
            raise ValueError('generation-3 inventory source does not prove accepted checkpoint and L1 Off')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    if pointer.get('generation') == 2:
        if (pointer.get('schemaVersion') != 2
                or pointer.get('contract') != 'devfleet-accepted-baseline-v2'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('rebound baseline pointer contract is invalid')
        old_hash = pointer.get('previousPointerSha256', '')
        name = pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('rebound baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or sha(history_path) != old_hash
                or not receipt_path.is_file() or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('rebound baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 1:
            raise ValueError('rebound baseline predecessor is not generation 1')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        if (binding.get('schemaVersion') != 2
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v2'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != previous.get('receiptSha256')
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')):
            raise ValueError('rebound baseline receipt lineage is invalid')
        old_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                        'candidateCommit': old_tuple.get('candidateBuildCommit'),
                        'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                        'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                        'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, old_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        if (new_tuple != actual or binding['previousReceiptSha256'] != prior['receiptSha256']
                or old_tuple.get('repositoryHead') == new_tuple.get('repositoryHead')
                or old_tuple.get('toolingFingerprintId') == new_tuple.get('toolingFingerprintId')
                or any(old_tuple.get(k) != new_tuple.get(k) for k in
                       ('candidateBuildCommit', 'shippingInputIdentity',
                        'releaseFingerprintId', 'candidateSha256'))):
            raise ValueError('rebound baseline tuple differs')
        approval = binding.get('approval') or {}
        if (approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not isinstance(binding.get('approvalSha256'), str)
                or not re.fullmatch(r'[0-9a-f]{64}', binding['approvalSha256'])
                or binding.get('finalL1') != {'name': 'DevFleet-E2E-Win11-01',
                                             'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2',
                                             'state': 'Off'}
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260926-R2-D1'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))):
            raise ValueError('rebound baseline authorization or terminal lab differs')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    name = pointer.get("receiptFile", "")
    if (pointer.get("schemaVersion") != 1
            or pointer.get("contract") != "devfleet-accepted-baseline-v1" or pointer.get("generation") != 1
            or pointer.get("status") != "ACCEPTED" or not re.fullmatch(r"[0-9a-f]{32}\.json", name)):
        raise ValueError("accepted baseline pointer contract is invalid")
    receipt_path = root / "evidence/baselines/receipts" / name
    if not receipt_path.is_file() or pointer.get("receiptSha256") != sha(receipt_path):
        raise ValueError("accepted baseline receipt is missing or hash mismatched")
    receipt = strict_baseline_json(receipt_path)
    new = receipt.get("replacement", {})
    old = receipt.get("predecessor", {})
    if (receipt.get("schemaVersion") != 1
            or receipt.get("contract") != "devfleet-baseline-adoption-receipt-v1"
            or receipt.get("status") != "ADOPTED" or receipt.get("certificationCredit") is not False
            or receipt.get("secretValuesRecorded") is not False
            or not isinstance(receipt.get("receiptId"), str)
            or receipt["receiptId"] + ".json" != name
            or old != {"name": "DevFleet-E2E-CLEAN", "id": old_id}
            or new.get("name") != "DevFleet-E2E-CLEAN-R2"
            or new.get("vmId") != "84b7d8b8-ee6c-4085-aa29-4b0adc316de2"
            or new.get("parentSnapshotId") != old_id or new.get("id") == old_id
            or pointer.get("checkpoint") != new):
        raise ValueError("accepted baseline receipt lineage is invalid")
    try:
        if str(uuid.UUID(new["id"])) != new["id"]:
            raise ValueError("replacement GUID is not canonical")
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("replacement GUID is invalid") from exc
    tuple_expected = {"repositoryHead": expected["repositoryHead"],
                      "candidateBuildCommit": expected["candidateCommit"],
                      "shippingInputIdentity": expected["shippingInputIdentity"],
                      "releaseFingerprintId": expected["releaseFingerprintId"],
                      "toolingFingerprintId": expected["toolingFingerprintId"],
                      "candidateSha256": artifacts["exe"]}
    if receipt.get("candidate") != tuple_expected:
        raise ValueError("accepted baseline material tuple differs")
    def utc_baseline(value):
        moment = datetime.fromisoformat(str(value or "").replace("Z", "+00:00"))
        if moment.tzinfo is None or moment.utcoffset().total_seconds() != 0:
            raise ValueError("accepted baseline credential instant is not UTC")
        return moment
    expiry = utc_baseline(receipt.get("passwordExpiresUtc"))
    last_set = utc_baseline(receipt.get("passwordLastSetUtc"))
    store_updated = utc_baseline(receipt.get("protectedStoreUpdatedUtc"))
    auth_observed = utc_baseline(receipt.get("authenticatedGuest", {}).get("sourceObservedUtc"))
    if expiry <= datetime.now(timezone.utc) or not last_set <= store_updated <= auth_observed < expiry:
        raise ValueError("accepted baseline account expiry is unknown or elapsed")
    nested = receipt.get("nestedL2", {})
    inventories = nested.get("backendInventories")
    sources = receipt.get("sources") or {}
    if (receipt.get("adoptionAuthority", {}).get("decision") != "APPROVE"
            or receipt.get("adoptionAuthority", {}).get("approvedBy") != "ACCOUNT_OWNER"
            or receipt.get("adoptionAuthority", {}).get("sourceSha256") != sources.get("approvalSha256")
            or receipt.get("authenticatedGuest", {}).get("computerName") != "DEVFLEET-E2E-01"
            or receipt.get("authenticatedGuest", {}).get("principal") != "DEVFLEET-E2E-01\\E2EAdmin"
            or receipt.get("authenticatedGuest", {}).get("accountEnabled") is not True
            or nested.get("status") != "ABSENT" or nested.get("present") is not False
            or nested.get("expectedName") != "DevFleet-E2E-Linux-01"
            or type(nested.get("exactMatchCount")) is not int or nested.get("exactMatchCount") != 0
            or not isinstance(inventories, list) or len(inventories) != 2
            or not all(isinstance(row, dict) for row in inventories)
            or {row.get("provider") for row in inventories} != {"Hyper-V", "VirtualBox"}
            or any(row.get("status") != "PASS" or not isinstance(row.get("names"), list)
                   or any(not isinstance(n, str) or not n.strip() or n == "DevFleet-E2E-Linux-01"
                          for n in row["names"])
                   or not isinstance(row.get("verification"), str)
                   or not row["verification"].strip() for row in inventories)
            or receipt.get("finalL1") != {"name": "DevFleet-E2E-Win11-01",
                                           "id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2",
                                           "state": "Off"}):
        raise ValueError("accepted baseline guest, nested inventory, approval, or L1 terminal state is invalid")
    for key in ("proposalSha256", "predecessorEvidenceSha256", "approvalSha256",
                "authenticatedGuestSha256", "nativeInventorySha256",
                "currentTupleSha256", "r2LedgerSha256"):
        if not isinstance(sources.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", sources[key]):
            raise ValueError(f"accepted baseline source hash missing: {key}")
    return {"id": new["id"], "name": new["name"], "receiptSha256": pointer["receiptSha256"]}


def validate_native_proof(run: Path, config_path: Path, sources: dict[str, Path], expected: dict[str, str], artifacts: dict[str, str], baseline: dict[str, str | None] | None = None) -> tuple[str, str, str]:
    """Validate immutable start provenance against terminal native product evidence."""
    start, final = read_json(run / "proof-start.json"), read_json(run / "proof-final.json")
    provenance = start.get("provenance", {})
    if start.get("runId") != run.name or final.get("runId") != run.name:
        raise ValueError("proof RunId disagreement")
    if final.get("status") != "PASS" or final.get("outcome") != "PASS":
        raise ValueError("proof terminal status/outcome disagreement")
    if provenance.get("diagnosticOnly") is not False or provenance.get("certificationEligible") is not True or final.get("diagnosticOnly") is not False or final.get("certificationEligible") is not True:
        raise ValueError("diagnostic or ineligible proof cannot receive release credit")
    if final.get("proofStartSha256") != sha(run / "proof-start.json") or final.get("provenance") != provenance:
        raise ValueError("proof terminal provenance does not bind its immutable start")
    for key, value in expected.items():
        if provenance.get(key) != value:
            raise ValueError(f"proof tuple mismatch: {key}")
    for key, source in sources.items():
        if provenance.get(key) != sha(source):
            raise ValueError(f"proof source hash missing or mismatched: {key}")
    if final.get("candidate") != start.get("candidate"):
        raise ValueError("proof start/final artifact tuple disagreement")
    for name, field in (("exe", "candidate"), ("tar", "tar"), ("portable", "portable"), ("installerSource", "installerSource")):
        if not re.fullmatch(r"[0-9a-f]{64}", artifacts.get(name, "")) or final.get("candidate", {}).get(field, {}).get("sha256") != artifacts[name]:
            raise ValueError(f"proof artifact differs from current candidate: {name}")
    for key, field in (("repositoryHead", "repositoryHead"), ("candidateCommit", "gitCommit"), ("shippingInputIdentity", "shippingInputIdentity"), ("releaseFingerprint", "releaseFingerprintId"), ("toolingFingerprint", "toolingFingerprintId")):
        if final.get("candidate", {}).get(field) != expected[key]:
            raise ValueError(f"proof terminal candidate tuple mismatch: {field}")
    binding = final.get("proofBinding", {})
    tx, lineage, role = binding.get("transactionId", ""), binding.get("checkpointLineageId", ""), binding.get("role", "")
    if not re.fullmatch(r"[0-9a-f]{32}", tx) or not re.fullmatch(r"[0-9a-f]{32}", lineage):
        raise ValueError("proof lacks native transaction or invocation lineage")
    if final.get("transactionId") != tx or final.get("checkpointLineageId") != lineage or final.get("role") != role or provenance.get("role") != role:
        raise ValueError("proof terminal identity disagreement")
    phases = {"Primary / Desktop": "REBOOT-RESUME", "Laptop / Surrogate": "SURROGATE-DISPOSABLE"}
    if role not in phases or binding.get("phaseId") != phases[role] or provenance.get("phaseId") != phases[role]:
        raise ValueError("proof role/phase disagreement")
    if baseline is None:
        baseline = {"id": "19865b76-4c3a-44f7-ba39-841e9d3c40c9", "name": "DevFleet-E2E-CLEAN", "receiptSha256": None}
    if provenance.get("cleanCheckpointId") != baseline["id"]:
        raise ValueError("proof does not bind accepted CLEAN checkpoint identity")
    if baseline["receiptSha256"] is not None:
        if (provenance.get("cleanCheckpointName") != baseline["name"]
                or provenance.get("baselineReceiptSha256") != baseline["receiptSha256"]
                or final.get("cleanCheckpoint", {}).get("id") != baseline["id"]
                or final.get("cleanCheckpoint", {}).get("name") != baseline["name"]):
            raise ValueError("proof does not bind the immutable accepted baseline receipt")
    elif provenance.get("baselineReceiptSha256") not in (None, ""):
        raise ValueError("original CLEAN proof cannot claim an adoption receipt")
    payload = start["candidate"]["tar"]["sha256"]
    if binding.get("payloadSha256") != payload:
        raise ValueError("proof payload differs from the signed candidate")
    records = binding.get("evidence", [])
    files = [record.get("file", "") for record in records]
    if len(files) != len(set(files)) or files.count("product-lifecycle-completion-authority.json") != 1:
        raise ValueError("proof native evidence missing or duplicated")
    for record in records:
        name = record.get("file", "")
        if not re.fullmatch(r"product-lifecycle-(?:completion-authority|generation-[1-3])\.json", name) or record.get("sha256") != sha(run / name):
            raise ValueError("proof native evidence path/hash mismatch")
    authority = read_json(run / "product-lifecycle-completion-authority.json")
    if authority.get("status") != "REAL E2E PASS" or authority.get("contract") != "product-lifecycle-completion-authority" or authority.get("completionVerified") is not True or authority.get("authenticatedHealth") is not True:
        raise ValueError("proof native completion authority is incomplete")
    if (authority.get("transactionId"), authority.get("invocationId"), authority.get("role"), authority.get("payloadSha256")) != (tx, lineage, role, payload):
        raise ValueError("proof native completion identity disagreement")
    guest = authority.get("guest", {})
    if guest.get("completionVerified") is not True or guest.get("transactionId") != tx or guest.get("role") != role:
        raise ValueError("proof native guest completion disagreement")
    role_evidence = guest.get("roleEvidence", {})
    if role_evidence != binding.get("roleEvidence") or role_evidence.get("configSha256") != sha(config_path):
        raise ValueError("proof role evidence is not candidate-config bound")
    config = read_json(config_path)
    targets = [(config["Primary"]["InstanceName"], "primary")] if role == "Primary / Desktop" else [(config["Failover"]["InstanceName"], "surrogate"), (config["Vault"]["InstanceName"], "vault")]
    required = [(entry.get("instanceName"), entry.get("nodeRole")) for entry in role_evidence.get("requiredTargets", [])]
    markers = role_evidence.get("markers", [])
    observed = [(entry.get("instanceName"), entry.get("nodeRole")) for entry in markers]
    if sorted(required) 