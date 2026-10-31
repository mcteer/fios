"""Filesystem-only runtime candidate contracts; no SDK/model/runtime authority."""
from pathlib import Path
import os
import runpy
import tempfile
import unittest

API = runpy.run_path(str(Path(__file__).resolve().parents[3] / 'scripts/package-platform-python.py'))


class RuntimeCandidateTests(unittest.TestCase):
    def test_installed_agent_requires_exact_source_set_and_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = root / 'source'; source.mkdir()
            installed = root / 'installed'; installed.mkdir()
            (source / 'worker.py').write_bytes(b'known')
            (installed / 'worker.py').write_bytes(b'known')
            self.assertEqual(set(API['agent_snapshot'](source, installed)), {'worker.py'})
            (installed / 'extra.py').write_bytes(b'unreviewed')
            with self.assertRaises(ValueError):
                API['agent_snapshot'](source, installed)
            (installed / 'extra.py').unlink()
            (installed / 'worker.py').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                API['agent_snapshot'](source, installed)

    def test_relative_destinations_cannot_escape(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            fd, chain = API['open_output'](root / 'new')
            try:
                for name in ('../escape', '/absolute', 'a//b', './file', 'a/../b'):
                    with self.assertRaises(ValueError):
                        API['write_data'](fd, name, b'never', False)
                self.assertFalse((root / 'escape').exists())
            finally:
                API['close_chain'](chain)

    def test_source_alias_must_stay_inside_reviewed_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = root / 'source'; source.mkdir()
            (root / 'outside').write_bytes(b'private sentinel')
            (source / 'link').symlink_to(root / 'outside')
            with self.assertRaises(ValueError):
                API['read_source'](source / 'link', source)
            (source / 'real').write_bytes(b'known')
            (source / 'safe').symlink_to('real')
            self.assertEqual(API['read_source'](source / 'safe', source)[0], b'known')

    def test_fifo_and_multiply_linked_sources_are_not_read(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            os.mkfifo(root / 'fifo', 0o600)
            with self.assertRaises(ValueError):
                API['read_source'](root / 'fifo', root)
            (root / 'original').write_bytes(b'known')
            os.link(root / 'original', root / 'alias')
            with self.assertRaises(ValueError):
                API['read_source'](root / 'original', root)

    def test_existing_leaf_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            fd, chain = API['open_output'](root / 'new')
            try:
                API['write_data'](fd, 'data', b'first', False)
                with self.assertRaises(FileExistsError):
                    API['write_data'](fd, 'data', b'replacement', False)
                self.assertEqual((root / 'new/data').read_bytes(), b'first')
            finally:
                API['close_chain'](chain)

    def test_existing_destination_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); output = root / 'existing'; output.mkdir()
            (output / 'sentinel').write_bytes(b'keep')
            with self.assertRaises(FileExistsError):
                API['open_output'](output)
            self.assertEqual((output / 'sentinel').read_bytes(), b'keep')

    def test_parent_rebind_does_not_redirect_descriptor_writes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); parent = root / 'parent'; parent.mkdir(mode=0o700)
            unrelated = root / 'unrelated'; unrelated.mkdir(mode=0o700)
            fd, chain = API['open_output'](parent / 'candidate')
            try:
                parent.rename(root / 'held'); parent.symlink_to(unrelated, target_is_directory=True)
                API['write_data'](fd, 'owned/data', b'owned', False)
                with self.assertRaises(ValueError):
                    API['verify_chain'](chain)
                self.assertFalse((unrelated / 'candidate').exists())
                self.assertEqual((root / 'held/candidate/owned/data').read_bytes(), b'owned')
            finally:
                API['close_chain'](chain)


if __name__ == '__main__':
    unittest.main()
