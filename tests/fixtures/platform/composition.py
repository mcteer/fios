"""Artifact composition contracts; fixtures cannot grant installation authority."""
from pathlib import Path
import hashlib
import json
import os
import runpy
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
API = runpy.run_path(str(ROOT/'scripts/compose-platform-candidate.py'))
REVIEW = runpy.run_path(str(ROOT/'scripts/check-platform-composition.py'))
sha = lambda data: hashlib.sha256(data).hexdigest()


class CompositionTests(unittest.TestCase):
    def fixture(self, root):
        platform = root/'platform'; platform.mkdir(mode=0o700)
        runtime = root/'runtime'; runtime.mkdir(mode=0o700)
        template = json.loads((ROOT/'platform/studio/deployment/release.json').read_bytes())
        paths = ['bin/studio-manager','bin/studio-supervisor','bin/studio-session','bin/studioctl',
                 'sandbox/runner.py','sandbox/Dockerfile','python/uv.lock',
                 'launchd/lab.fios.studio.supervisor.plist','launchd/lab.fios.studio.session.plist']
        artifacts = []
        for name in paths:
            path = platform/name; path.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
            data = struct.pack('<II',0xfeedfacf,0x0100000c)+bytes(24) if name.startswith('bin/') else b'review data'
            mode = 0o755 if name.startswith('bin/') else 0o644
            path.write_bytes(data); path.chmod(mode)
            artifacts.append(dict(path=name,sha256=sha(data),bytes=len(data),mode=mode))
        manifest = dict(template,source_revision='a'*40,source_tree_sha256='b'*64,artifacts=artifacts,package_complete=False)
        payload = (json.dumps(manifest,indent=2)+'\n').encode()
        (platform/'release.json').write_bytes(payload); (platform/'release.json').chmod(0o600)
        platform_sha = sha(payload)
        (runtime/'bin').mkdir(mode=0o700)
        sentinel = root/'must-not-execute'
        data = ('#!/bin/sh\ntouch '+str(sentinel)+'\n').encode()
        (runtime/'bin/python').write_bytes(data); (runtime/'bin/python').chmod(0o755)
        candidate = dict(version=1,purpose='python_worker_runtime_candidate',python_version='3.11.17',platform='macos/arm64',
            uv_lock_sha256=template['python']['uv_lock_sha256'],producer_sha256='c'*64,
            release_template_sha256=sha((ROOT/'platform/studio/deployment/release.json').read_bytes()),agent_sources={},distributions=[],
            files={'bin/python':dict(bytes=len(data),sha256=sha(data),mode=0o755)},bytes=len(data),console_wrappers_excluded=0,probe={},
            scope='declared_installed_runtime_bytes_not_publisher_build_or_whole_os_provenance',
            immutable_tree_enrolled=False,approved=False,activation=False)
        payload = json.dumps(candidate).encode(); (runtime/'candidate.json').write_bytes(payload)
        return platform, platform_sha, runtime, sha(payload), sentinel

    def test_combines_exact_bytes_without_executing_or_authorizing_components(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root = Path(temporary); args = self.fixture(root); output=root/'combined'
            result = API['compose'](*args[:4],output)
            self.assertFalse(args[4].exists())
            for flag in ('candidate_programs_executed','installed','activation','native_authority'):
                self.assertFalse(result[flag])
            receipt = json.loads((output/'composition.json').read_bytes())
            self.assertEqual(result['files'],13)
            self.assertEqual(receipt['platform_manifest_sha256'],args[1])
            self.assertEqual(receipt['python_candidate_sha256'],args[3])
            for flag in ('package_complete','approved','immutable_tree_enrolled','installed','activation','native_authority'):
                self.assertFalse(receipt[flag])
            planned=subprocess.run(['node',str(ROOT/'scripts/install-platform.mjs'),'plan-composition','--candidate',str(output),
                '--sha256',result['composition_sha256'],'--host','fios-edge-a.lab'],capture_output=True,timeout=10)
            self.assertEqual(planned.returncode,0,planned.stderr)
            plan=json.loads(planned.stdout);self.assertEqual(plan['state'],'blocked');self.assertEqual(plan['privileged_commands'],[])
            self.assertFalse(plan['installed']);self.assertFalse(plan['native_authority']);self.assertFalse(args[4].exists())
            self.assertEqual([item['files'] for item in plan['installation_layout']],[10,2])
            for name,record in receipt['files'].items():
                self.assertEqual(sha((output/name).read_bytes()),record['sha256'])

    def test_mixed_lock_or_template_refuses_before_output(self):
        for field in ('uv_lock_sha256','release_template_sha256'):
            with self.subTest(field=field), tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
                root=Path(temporary); platform,digest,runtime,_,sentinel=self.fixture(root)
                candidate=json.loads((runtime/'candidate.json').read_bytes());candidate[field]='0'*64
                data=json.dumps(candidate).encode();(runtime/'candidate.json').write_bytes(data)
                with self.assertRaises(ValueError):API['compose'](platform,digest,runtime,sha(data),root/'refused')
                self.assertFalse((root/'refused').exists());self.assertFalse(sentinel.exists())

    def test_existing_destination_and_sentinel_are_preserved(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'existing';output.mkdir(mode=0o700)
            (output/'sentinel').write_bytes(b'unrelated')
            with self.assertRaises(FileExistsError):API['compose'](*args[:4],output)
            self.assertEqual((output/'sentinel').read_bytes(),b'unrelated')
            self.assertEqual(set(p.name for p in output.iterdir()),{'sentinel'})

    def test_copy_failure_retains_partial_data_without_receipt_or_authority(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'partial';original=API['API']['write_data']
            def failing(fd,name,data,executable):
                if name.startswith('python-runtime/'):
                    raise OSError('finite fixture failure')
                return original(fd,name,data,executable)
            with patch.dict(API['API'],write_data=failing), self.assertRaises(OSError):
                API['compose'](*args[:4],output)
            self.assertTrue(output.exists());self.assertTrue((output/'platform').exists())
            self.assertFalse((output/'composition.json').exists());self.assertFalse(args[4].exists())

    def test_independent_review_rejects_changed_surface_and_claimed_authority(self):
        for mutation in ('none','bytes','extra-directory','approval','duplicate-key'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
                root=Path(temporary);args=self.fixture(root);output=root/'combined'
                result=API['compose'](*args[:4],output);digest=result['composition_sha256']
                if mutation=='bytes':(output/'python-runtime/bin/python').write_bytes(b'changed')
                if mutation=='extra-directory':(output/'unreviewed').mkdir(mode=0o700)
                if mutation=='approval':
                    value=json.loads((output/'composition.json').read_bytes());value['approved']=True
                    payload=json.dumps(value).encode();(output/'composition.json').write_bytes(payload);digest=sha(payload)
                if mutation=='duplicate-key':
                    payload=(output/'composition.json').read_bytes().rstrip()[:-1]+b',"approved":false}'
                    (output/'composition.json').write_bytes(payload);digest=sha(payload)
                if mutation=='none':
                    reviewed=REVIEW['review'](output,digest)
                    self.assertFalse(reviewed['candidate_programs_executed']);self.assertFalse(reviewed['native_authority'])
                else:
                    with self.assertRaises(ValueError):REVIEW['review'](output,digest)
                self.assertFalse(args[4].exists())


if __name__ == '__main__':
    unittest.main()
