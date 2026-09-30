"""Verify the immutable source-parts export without revalidating changed working source.

SOURCE-PARTS.json describes the original source export. Windows Git checkouts may
expand LF in part Markdown files to CRLF; only that documented checkout transform
is normalized, and only when the normalized bytes match the recorded hash.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path, PurePosixPath


MARKER = b'<!-- BEGIN SOURCE SLICE -->\n'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_part(root, row):
    label = row['path']
    relative = PurePosixPath(label)
    require(chr(92) not in label and ':' not in label
            and not relative.is_absolute() and '..' not in relative.parts
            and relative.parts[:2] == ('ai', 'source-parts')
            and len(relative.parts) == 3,
            f'unsafe part path: {label}')
    raw = root.joinpath(*relative.parts).read_bytes()
    if sha256(raw) != row['sha256']:
        normalized = raw.replace(b'\r\n', b'\n')
        require(sha256(normalized) == row['sha256'], f'{label}: part hash mismatch')
        raw = normalized
    require(len(raw) == row['bytes'], f'{label}: part byte count mismatch')
    require(raw.count(MARKER) == 1, f'{label}: source slice marker mismatch')
    payload = raw.split(MARKER, 1)[1]
    require(sha256(payload) == row['payloadSha256'],
            f'{label}: payload hash mismatch')
    require(len(payload) == row['end'] - row['start'],
            f'{label}: payload interval mismatch')
    return payload


def verify(root):
    manifest = json.loads((root / 'ai' / 'SOURCE-PARTS.json').read_text(encoding='utf-8'))
    rows = manifest['parts']
    require(bool(rows), 'source parts missing')
    offset = 0
    payloads = []
    for number, row in enumerate(rows, 1):
        require(row['part'] == number, f"part {number}: sequence mismatch")
        require(row['start'] == offset and row['end'] > offset,
                f"{row['path']}: offset mismatch")
        payloads.append(read_part(root, row))
        offset = row['end']
    combined = b''.join(payloads)
    require(offset == manifest['fullSourceBytes'] == len(combined),
            'full-source byte count mismatch')
    require(sha256(combined) == manifest['fullSourceSha256'],
            'full-source manifest hash mismatch')
    published = (root / 'ai' / 'DEVFLEET-FULL-SOURCE.md').read_bytes()
    require(published == combined, 'full-source file differs from source parts')
    return len(rows), len(combined)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        count, size = verify(args.root.resolve())
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f'SOURCE_PARTS_FAIL: {exc}', file=sys.stderr)
        return 1
    print(f'SOURCE_PARTS_PASS: {count} parts, {size} bytes')
    return 0


if __name__ == '__main__':
    sys.exit(main())
