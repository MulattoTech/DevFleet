import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / 'ai' / 'verify_source_parts.py'
MARKER = b'<!-- BEGIN SOURCE SLICE -->\n'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fixture(root):
    (root / 'ai' / 'source-parts').mkdir(parents=True)
    full = b'abcdef'
    (root / 'ai' / 'DEVFLEET-FULL-SOURCE.md').write_bytes(full)
    parts = []
    for number, payload in enumerate((b'abc', b'def'), 1):
        path = f'ai/source-parts/part-{number:03d}.md'
        content = f'# Part {number}\n'.encode() + MARKER + payload
        (root / path).write_bytes(content)
        parts.append({
            'part': number, 'path': path,
            'start': (number - 1) * 3, 'end': number * 3,
            'bytes': len(content), 'sha256': digest(content),
            'payloadSha256': digest(payload),
        })
    manifest = {'fullSourceBytes': len(full), 'fullSourceSha256': digest(full), 'parts': parts}
    (root / 'ai' / 'SOURCE-PARTS.json').write_text(json.dumps(manifest), encoding='utf-8')
    return manifest


def verify(root):
    return subprocess.run([sys.executable, str(SCRIPT), '--root', str(root)],
                          capture_output=True, text=True)


class SourcePartsTests(unittest.TestCase):
    def test_published_export(self):
        result = verify(REPO)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_modified_payload_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            path = root / 'ai/source-parts/part-002.md'
            path.write_bytes(path.read_bytes()[:-1] + b'X')
            result = verify(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('part-002', result.stderr)

    def test_gap_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = fixture(root)
            manifest['parts'][1]['start'] = 4
            (root / 'ai/SOURCE-PARTS.json').write_text(json.dumps(manifest), encoding='utf-8')
            result = verify(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('offset', result.stderr)

    def test_windows_path_escape_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = fixture(root)
            manifest['parts'][0]['path'] = 'ai/source-parts/..\\..\\outside.md'
            (root / 'ai/SOURCE-PARTS.json').write_text(json.dumps(manifest), encoding='utf-8')
            result = verify(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('path', result.stderr)

    def test_path_escape_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = fixture(root)
            manifest['parts'][0]['path'] = '../outside.md'
            (root / 'ai/SOURCE-PARTS.json').write_text(json.dumps(manifest), encoding='utf-8')
            result = verify(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('path', result.stderr)


if __name__ == '__main__':
    unittest.main()
