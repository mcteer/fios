"""Tiny synthetic OCI archives test content refusal, never artifact approval."""
import hashlib
import io
import json
from pathlib import Path
import runpy
import tarfile
import tempfile
import unittest

AUDIT = runpy.run_path(str(Path(__file__).resolve().parents[3] / 'scripts/audit-platform-sandbox-base.py'))['audit']


def tar(entries, sparse=False):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w') as archive:
        for name, content in entries:
            member = tarfile.TarInfo(name)
            member.size = len(content)
            if name == '.':
                member.type = tarfile.DIRTYPE
            if sparse and name == 'opt/venv/sparse.py':
                member.pax_headers = {'GNU.sparse.map': '0,1', 'GNU.sparse.size': '100'}
            archive.addfile(member, io.BytesIO(content))
    return data.getvalue()


def fixture(*, damage=False, diff=False, extra=None, duplicate=False, sparse=False, root_directory=False):
    content = [('opt/python/cpython-3.11.17-linux-aarch64-gnu/bin/python', b'not an executable'), ('opt/venv/pyvenv.cfg', b'fixture'), ('usr/bin/cat', b'fixture')]
    if extra:
        content.append((extra, b'fixture'))
    if root_directory:
        content.insert(0, ('.', b''))
    if sparse:
        content.append(('opt/venv/sparse.py', b'x'))
    layer = tar(content, sparse=sparse)
    blobs = []

    def blob(data):
        if isinstance(data, dict):
            data = json.dumps(data).encode()
        sha = hashlib.sha256(data).hexdigest()
        blobs.append(('blobs/sha256/' + sha, data))
        return {'digest': 'sha256:' + sha, 'size': len(data)}

    layer_ref = blob(layer)
    config = blob({'os': 'linux', 'architecture': 'arm64', 'rootfs': {'diff_ids': ['sha256:' + ('0' * 64 if diff else hashlib.sha256(layer).hexdigest())]}, 'config': {}})
    manifest = blob({'schemaVersion': 2, 'config': config, 'layers': [layer_ref]})
    if damage:
        blobs[0] = (blobs[0][0], b'damaged')
    if duplicate:
        blobs.append(blobs[0])
    return tar([('index.json', json.dumps({'schemaVersion': 2, 'manifests': [manifest]}).encode()), *blobs]), manifest['digest']


class ArchiveTests(unittest.TestCase):
    def review(self, **options):
        data, image = fixture(**options)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'base.tar'
            path.write_bytes(data)
            return AUDIT(path, image)

    def test_actual_content_receipt_has_no_approval(self):
        receipt, inventory = self.review()
        self.assertFalse(receipt['approved'])
        self.assertFalse(receipt['activation'])
        self.assertEqual(receipt['inventory_sha256'], hashlib.sha256(inventory).hexdigest())
        self.assertEqual(receipt['inventory_entries'], 3)

    def test_conventional_root_directory_does_not_hide_runtime_content(self):
        receipt, inventory = self.review(root_directory=True)
        self.assertEqual(receipt['inventory_entries'], 3)
        self.assertEqual(receipt['inventory_sha256'], hashlib.sha256(inventory).hexdigest())

    def test_blob_substitution(self):
        with self.assertRaises(ValueError):
            self.review(damage=True)

    def test_uncompressed_layer_substitution(self):
        with self.assertRaises(ValueError):
            self.review(diff=True)

    def test_whiteout_is_not_ignored(self):
        with self.assertRaises(ValueError):
            self.review(extra='opt/venv/.wh.pyvenv.cfg')

    def test_traversal(self):
        with self.assertRaises(ValueError):
            self.review(extra='opt/venv/../../escape')

    def test_repeated_separator_cannot_hide_selected_runtime_file(self):
        with self.assertRaises(ValueError):
            self.review(extra='opt//venv/unlisted.py')

    def test_dot_alias_cannot_hide_selected_runtime_file(self):
        with self.assertRaises(ValueError):
            self.review(extra='././opt/venv/unlisted.py')

    def test_sparse_runtime_file_is_not_a_layer_expansion_bypass(self):
        with self.assertRaises(ValueError):
            self.review(sparse=True)

    def test_duplicate_blob(self):
        with self.assertRaises(ValueError):
            self.review(duplicate=True)


if __name__ == '__main__':
    unittest.main()
