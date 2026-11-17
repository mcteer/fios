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
            self.assertEqual(plan['installation_layout'][1]['destination'], '/Library/Application Support/Fios/Studio/python/runtime')
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

    def test_first_install_proposal_is_inactive_fixed_layout_data_only(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'combined'
            result=API['compose'](*args[:4],output)
            planned=subprocess.run(['node',str(ROOT/'scripts/install-platform.mjs'),'propose-first-install',
                '--candidate',str(output),'--sha256',result['composition_sha256'],'--host','fios-edge-b.lab'],
                capture_output=True,timeout=10)
            self.assertEqual(planned.returncode,0,planned.stderr)
            value=json.loads(planned.stdout)
            self.assertEqual(value['state'],'blocked');self.assertEqual(value['privileged_commands'],[])
            self.assertFalse(value['commands_authorized']);self.assertTrue(value['requires_operator_execution'])
            for flag in ('installed','activation','native_authority','enrollment_written','credentials_written','state_opened'):
                self.assertFalse(value[flag])
            self.assertEqual(value['launchd_registration'],'not_proposed')
            self.assertIn('destination_prefix_absent_no_overwrite',value['mandatory_preconditions'])
            files=value['proposed_file_commands'];self.assertEqual(len(files),12)
            self.assertEqual(len({item['destination'] for item in files}),12)
            for item in files:
                self.assertEqual(item['program'],'/usr/bin/install')
                self.assertEqual(item['argv'],['-o','root','-g','wheel','-m',format(item['mode'],'04o'),item['source'],item['destination']])
                self.assertTrue(item['source'].startswith(str(output)+'/'))
                self.assertTrue(item['destination'].startswith('/Library/Application Support/Fios/Studio/'))
                self.assertEqual(sha(Path(item['source']).read_bytes()),item['sha256'])
            self.assertTrue(any(item['destination'].endswith('/python/runtime/bin/python') for item in files))
            directories=value['proposed_directory_commands']
            self.assertEqual(directories[0],{'program':'/bin/mkdir','argv':['-m','0755','/Library/Application Support/Fios/Studio']})
            self.assertTrue(all(item['program']=='/bin/mkdir' and item['argv'][:2]==['-m','0755'] for item in directories))
            self.assertFalse(args[4].exists())
            # Exercise only OS data-copy operations in a disposable redirected
            # tree. Root ownership arguments are deliberately NOT executed;
            # this is not protected installation or the proposed host action.
            prefix=Path('/Library/Application Support/Fios/Studio')
            staged=root/'operator-copy-fixture';unrelated=root/'unrelated';unrelated.write_bytes(b'retain')
            for item in directories:
                destination=staged/Path(item['argv'][-1]).relative_to(prefix)
                subprocess.run(['/bin/mkdir','-m','0755',str(destination)],check=True,timeout=2)
            for item in files:
                destination=staged/Path(item['destination']).relative_to(prefix)
                subprocess.run(['/usr/bin/install','-m',format(item['mode'],'04o'),item['source'],str(destination)],check=True,timeout=2)
                self.assertEqual(sha(destination.read_bytes()),item['sha256'])
                self.assertEqual(destination.stat().st_mode & 0o7777,item['mode'])
                self.assertEqual(destination.stat().st_uid,os.getuid())
            self.assertEqual(sum(path.is_file() for path in staged.rglob('*')),12)
            self.assertEqual(unrelated.read_bytes(),b'retain');self.assertFalse(args[4].exists())

    def test_existing_destination_and_sentinel_are_preserved(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'existing';output.mkdir(mode=0o700)
            (output/'sentinel').write_bytes(b'unrelated')
            with self.assertRaises(FileExistsError):API['compose'](*args[:4],output)
            self.assertEqual((output/'sentinel').read_bytes(),b'unrelated')
            self.assertEqual(set(p.name for p in output.iterdir()),{'sentinel'})

    def test_uninstall_proposes_only_exact_artifacts_and_retains_unknown_data(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'combined'
            result=API['compose'](*args[:4],output)
            planned=subprocess.run(['node',str(ROOT/'scripts/install-platform.mjs'),'propose-artifact-uninstall',
                '--candidate',str(output),'--sha256',result['composition_sha256'],'--host','fios-edge-a.lab'],
                capture_output=True,timeout=10)
            self.assertEqual(planned.returncode,0,planned.stderr)
            value=json.loads(planned.stdout)
            self.assertEqual(value['operation'],'uninstall_command_proposal');self.assertEqual(value['state'],'blocked')
            self.assertFalse(value['commands_authorized']);self.assertTrue(value['requires_operator_execution'])
            self.assertEqual(value['privileged_commands'],[])
            self.assertNotIn('proposed_file_commands',value);self.assertNotIn('proposed_directory_commands',value)
            for flag in ('enrollment_retained','credentials_retained','state_and_exports_retained'):
                self.assertTrue(value[flag])
            self.assertFalse(value['installed']);self.assertFalse(value['native_authority'])
            records=value['proposed_file_removals'];self.assertEqual(len(records),12)
            prefix=Path('/Library/Application Support/Fios/Studio');staged=root/'removal-fixture'
            copies=REVIEW['first_install_proposal'](output,result['composition_sha256'],'fios-edge-a.lab')
            for item in copies['proposed_file_commands']:
                path=staged/Path(item['destination']).relative_to(prefix)
                path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(Path(item['source']).read_bytes())
                path.chmod(item['mode'])
            policy=staged/'python-enrollment.json';policy.write_bytes(b'opaque retained enrollment')
            unrelated=staged/'unrelated-file';unrelated.write_bytes(b'retain')
            state=root/'independent-state';state.write_bytes(b'uncertainty and exports')
            for item in records:
                self.assertEqual(item['program'],'/bin/rm');self.assertEqual(item['argv'],[item['destination']])
                path=staged/Path(item['destination']).relative_to(prefix)
                self.assertEqual(sha(path.read_bytes()),item['required_sha256'])
                self.assertEqual(path.stat().st_size,item['required_bytes'])
                self.assertEqual(path.stat().st_mode & 0o7777,item['required_mode'])
                subprocess.run(['/bin/rm',str(path)],check=True,timeout=2)
            depths=[len(Path(item['argv'][0]).parts) for item in value['proposed_empty_directory_removals']]
            self.assertEqual(depths,sorted(depths,reverse=True))
            for item in value['proposed_empty_directory_removals']:
                self.assertEqual(item['program'],'/bin/rmdir');self.assertEqual(len(item['argv']),1)
                path=staged/Path(item['argv'][0]).relative_to(prefix)
                # ENOTEMPTY retains unknown files; never recursively remove.
                subprocess.run(['/bin/rmdir',str(path)],capture_output=True,timeout=2)
            self.assertEqual(policy.read_bytes(),b'opaque retained enrollment')
            self.assertEqual(unrelated.read_bytes(),b'retain');self.assertEqual(state.read_bytes(),b'uncertainty and exports')
            self.assertFalse(args[4].exists())

    def test_python_enrollment_proposal_binds_components_without_issuing_policy(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'combined'
            result=API['compose'](*args[:4],output)
            state='/Users/mcteer/Library/Application Support/Fios/Studio';identity='e'*64
            planned=subprocess.run(['node',str(ROOT/'scripts/install-platform.mjs'),'propose-python-enrollment',
                '--candidate',str(output),'--sha256',result['composition_sha256'],'--host','fios-edge-a.lab',
                '--uid','501','--state',state,'--review-sha256',identity],capture_output=True,timeout=10)
            self.assertEqual(planned.returncode,0,planned.stderr);value=json.loads(planned.stdout)
            self.assertEqual(value['operation'],'python_enrollment_configuration_proposal')
            self.assertEqual(value['state'],'blocked');self.assertEqual(value['privileged_commands'],[])
            for flag in ('commands_authorized','approved','policy_written','credentials_written','state_opened','installed','activation','native_authority'):
                self.assertFalse(value[flag])
            payload=value['policy_candidate_json'].encode('ascii');policy=json.loads(payload)
            self.assertEqual(policy,value['policy_candidate']);self.assertEqual(sha(payload),value['policy_candidate_sha256'])
            self.assertLessEqual(len(payload),4096)
            self.assertEqual(policy['uid'],501);self.assertEqual(policy['host'],'fios-edge-a.lab')
            self.assertEqual(policy['state_path'],state);self.assertEqual(policy['review_sha256'],identity)
            runtime=json.loads((output/'python-runtime/candidate.json').read_bytes())
            platform=json.loads((output/'platform/release.json').read_bytes())
            self.assertEqual(policy['manifest_sha256'],args[3])
            self.assertEqual(policy['python_sha256'],runtime['files']['bin/python']['sha256'])
            self.assertEqual(policy['manager_sha256'],next(item['sha256'] for item in platform['artifacts'] if item['path']=='bin/studio-manager'))
            for field in ('uv_lock_sha256','producer_sha256','release_template_sha256'):
                self.assertEqual(policy[field],runtime[field])
            self.assertEqual(policy['policy_sha256'],platform['python']['policy_sha256'])
            for uid,path,digest in [('0',state,identity),('01',state,identity),('4294967296',state,identity),
                                    ('501','relative',identity),('501',state+'/../other',identity),('501',state,'bad')]:
                with self.assertRaises(ValueError):
                    REVIEW['python_enrollment_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',uid,path,digest)
            self.assertFalse(args[4].exists());self.assertFalse((root/'python-enrollment.json').exists())

    def test_python_policy_staging_retains_partial_data_and_never_writes_installed_state(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'combined'
            result=API['compose'](*args[:4],output)
            state='/Users/mcteer/Library/Application Support/Fios/Studio';identity='e'*64;staged=root/'policy-stage'
            command=['node',str(ROOT/'scripts/install-platform.mjs'),'stage-python-enrollment',
                     '--candidate',str(output),'--sha256',result['composition_sha256'],'--host','fios-edge-a.lab',
                     '--uid','501','--state',state,'--review-sha256',identity,'--to',str(staged)]
            run=subprocess.run(command,capture_output=True,timeout=10)
            self.assertEqual(run.returncode,0,run.stderr);receipt=json.loads(run.stdout)
            self.assertEqual(receipt['operation'],'private_python_enrollment_stage')
            self.assertEqual(receipt['private_files_written'],3);self.assertTrue(receipt['source_rechecked'])
            for flag in ('approved','installed_policy_written','installed','activation','native_authority','state_opened'):
                self.assertFalse(receipt[flag])
            self.assertEqual(set(path.name for path in staged.iterdir()),{'python-enrollment.json','review.json','stage-receipt.json'})
            self.assertEqual(sha((staged/'python-enrollment.json').read_bytes()),receipt['policy_sha256'])
            self.assertEqual(sha((staged/'review.json').read_bytes()),receipt['review_sha256'])
            before={path.name:path.read_bytes() for path in staged.iterdir()}
            rerun=subprocess.run(command,capture_output=True,timeout=10);self.assertNotEqual(rerun.returncode,0)
            self.assertEqual({path.name:path.read_bytes() for path in staged.iterdir()},before)
            self.assertEqual(staged.stat().st_mode & 0o7777,0o700)
            with self.assertRaises(ValueError):
                REVIEW['stage_python_enrollment'](output,result['composition_sha256'],'fios-edge-a.lab','501',state,identity,output/'nested')
            self.assertFalse((output/'nested').exists())
            partial=root/'partial-policy';write=REVIEW['API']['write_data']
            def failing(fd,name,data,executable):
                if name=='review.json':raise OSError('finite fixture write failure')
                return write(fd,name,data,executable)
            with patch.dict(REVIEW['API'],write_data=failing):
                with self.assertRaises(OSError):
                    REVIEW['stage_python_enrollment'](output,result['composition_sha256'],'fios-edge-a.lab','501',state,identity,partial)
            self.assertTrue((partial/'python-enrollment.json').is_file())
            self.assertFalse((partial/'stage-receipt.json').exists());self.assertFalse(args[4].exists())

    def test_policy_install_review_rechecks_staged_bytes_context_and_boolean_types(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'combined'
            result=API['compose'](*args[:4],output);stage=root/'policy-stage'
            REVIEW['stage_python_enrollment'](output,result['composition_sha256'],'fios-edge-a.lab','501',
                '/Users/mcteer/Library/Application Support/Fios/Studio','e'*64,stage)
            digest=sha((stage/'stage-receipt.json').read_bytes())
            command=['node',str(ROOT/'scripts/install-platform.mjs'),'propose-python-policy-install',
                     '--candidate',str(output),'--sha256',result['composition_sha256'],'--host','fios-edge-a.lab',
                     '--bundle',str(stage),'--bundle-sha256',digest]
            run=subprocess.run(command,capture_output=True,timeout=10)
            self.assertEqual(run.returncode,0,run.stderr);value=json.loads(run.stdout)
            self.assertEqual(value['state'],'blocked');self.assertFalse(value['commands_authorized'])
            self.assertEqual(value['privileged_commands'],[]);self.assertTrue(value['staged_policy_rechecked'])
            self.assertTrue(value['requires_operator_execution']);self.assertFalse(value['policy_written'])
            self.assertFalse(value['installed']);self.assertFalse(value['native_authority'])
            self.assertEqual(len(value['proposed_file_commands']),1)
            item=value['proposed_file_commands'][0]
            self.assertEqual(item['program'],'/usr/bin/install')
            self.assertEqual(item['argv'],['-o','root','-g','wheel','-m','0644',str(stage/'python-enrollment.json'),
                '/Library/Application Support/Fios/Studio/python-enrollment.json'])
            copied=root/'private-policy-copy.json'
            subprocess.run(['/usr/bin/install','-m','0644',item['source'],str(copied)],check=True,timeout=2)
            self.assertEqual(sha(copied.read_bytes()),item['sha256'])
            removal_command=command.copy();removal_command[2]='propose-python-policy-removal'
            removal_run=subprocess.run(removal_command,capture_output=True,timeout=10)
            self.assertEqual(removal_run.returncode,0,removal_run.stderr)
            removal=json.loads(removal_run.stdout)
            self.assertEqual(removal['operation'],'python_policy_removal_command_proposal')
            self.assertEqual(removal['state'],'blocked');self.assertFalse(removal['commands_authorized'])
            self.assertFalse(removal['policy_removed']);self.assertEqual(removal['privileged_commands'],[])
            self.assertTrue(removal['state_and_exports_retained']);self.assertTrue(removal['credentials_retained'])
            self.assertNotIn('proposed_file_commands',removal)
            removed=removal['proposed_file_removals'];self.assertEqual(len(removed),1)
            self.assertEqual(removed[0]['program'],'/bin/rm');self.assertEqual(removed[0]['argv'],[item['destination']])
            self.assertEqual(removed[0]['required_sha256'],sha(copied.read_bytes()))
            self.assertEqual(removed[0]['required_uid'],0)
            independent=root/'independent-uncertainty';independent.write_bytes(b'retain')
            subprocess.run(['/bin/rm',str(copied)],check=True,timeout=2)
            self.assertFalse(copied.exists());self.assertEqual(independent.read_bytes(),b'retain')
            self.assertTrue((stage/'python-enrollment.json').exists())
            with self.assertRaises(ValueError):
                REVIEW['python_policy_install_proposal'](output,result['composition_sha256'],'fios-edge-b.lab',stage,digest)
            original=(stage/'python-enrollment.json').read_bytes()
            (stage/'python-enrollment.json').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                REVIEW['python_policy_install_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',stage,digest)
            (stage/'python-enrollment.json').write_bytes(original)
            receipt=json.loads((stage/'stage-receipt.json').read_bytes());receipt['approved']=0
            altered=json.dumps(receipt).encode();(stage/'stage-receipt.json').write_bytes(altered)
            with self.assertRaises(ValueError):
                REVIEW['python_policy_install_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',stage,sha(altered))
            self.assertFalse(args[4].exists())

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

    def test_configuration_restore_requires_root_originals_and_retains_absent_entries(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'combined'
            result=API['compose'](*args[:4],output);snapshot=root/'configuration';snapshot.mkdir(mode=0o700)
            names=['runtime-enrollment.json','session-enrollment.json','python-enrollment.json',
                   'resource-enrollment.json','native-serving-launch.json','sandbox-enrollment.json']
            rows=[{'name':name} for name in names]
            payload=b'opaque previous protected configuration'
            (snapshot/names[0]).write_bytes(payload);(snapshot/names[0]).chmod(0o600)
            rows[0].update(bytes=len(payload),sha256=sha(payload),originalUID=0,originalMode=0o640)
            manifest={'version':1,'scope':'opaque_configuration_data_only','files':rows}
            def write_manifest():
                content=json.dumps(manifest).encode();(snapshot/'manifest.json').write_bytes(content);(snapshot/'manifest.json').chmod(0o600)
                return sha(content)
            digest=write_manifest();before={p.name:p.read_bytes() for p in snapshot.iterdir()}
            for host in ['fios-edge-a.lab','fios-edge-b.lab']:
                command=['node',str(ROOT/'scripts/install-platform.mjs'),'propose-enrollment-restore',
                    '--candidate',str(output),'--sha256',result['composition_sha256'],'--host',host,
                    '--configuration',str(snapshot),'--configuration-sha256',digest]
                completed=subprocess.run(command,capture_output=True,timeout=10)
                self.assertEqual(completed.returncode,0,completed.stderr);plan=json.loads(completed.stdout)
                self.assertEqual(plan['operation'],'configuration_restore_command_proposal')
                self.assertFalse(plan['snapshot_host_binding_verified']);self.assertFalse(plan['original_group_recorded'])
                self.assertEqual(plan['state'],'blocked');self.assertFalse(plan['commands_authorized'])
                self.assertFalse(plan['configuration_restored']);self.assertFalse(plan['state_opened'])
                self.assertFalse(plan['stopped_state_backup_verified']);self.assertEqual(plan['privileged_commands'],[])
                self.assertTrue(plan['configuration_snapshot_rechecked']);self.assertTrue(plan['native_inference_uncertainty_retained'])
                self.assertNotIn('proposed_file_removals',plan)
                item=plan['proposed_file_restorations'][0]
                self.assertEqual(item['argv'],['-o','root','-g','wheel','-m','0640',str(snapshot/names[0]),'/Library/Application Support/Fios/Studio/'+names[0]])
                self.assertEqual(item['sha256'],sha(payload));self.assertTrue(item['destination_must_be_absent'])
                self.assertEqual(len(plan['proposed_file_restorations']),1)
                self.assertEqual(plan['absent_snapshot_entries'],'must_remain_absent_no_removal_proposed')
                self.assertNotIn(payload,completed.stdout)
            self.assertEqual(before,{p.name:p.read_bytes() for p in snapshot.iterdir()})
            manifest['version']=2;rows[0]['originalGID']=0;digest=write_manifest()
            plan=REVIEW['configuration_restore_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',snapshot,digest)
            self.assertTrue(plan['original_group_recorded']);self.assertEqual(plan['proposed_group'],'wheel_from_recorded_gid')
            for bad_group in [True,-1,4294967296,20]:
                rows[0]['originalGID']=bad_group;digest=write_manifest()
                with self.assertRaises(ValueError):REVIEW['configuration_restore_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',snapshot,digest)
            rows[0]['originalGID']=0
            rows[0]['originalUID']=os.getuid();digest=write_manifest()
            with self.assertRaises(ValueError):REVIEW['configuration_restore_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',snapshot,digest)
            rows[0]['originalUID']=0;digest=write_manifest();(snapshot/names[0]).write_bytes(b'changed')
            with self.assertRaises(ValueError):REVIEW['configuration_restore_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',snapshot,digest)
            (snapshot/names[0]).unlink();rows[0]={'name':names[0]};digest=write_manifest()
            plan=REVIEW['configuration_restore_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',snapshot,digest)
            self.assertEqual(plan['proposed_file_restorations'],[])
            self.assertFalse(args[4].exists())

    def test_configuration_removal_reviews_fixed_opaque_snapshot_without_deleting_data(self):
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as temporary:
            root=Path(temporary);args=self.fixture(root);output=root/'combined'
            result=API['compose'](*args[:4],output);snapshot=root/'configuration';snapshot.mkdir(mode=0o700)
            names=['runtime-enrollment.json','session-enrollment.json','python-enrollment.json',
                   'resource-enrollment.json','native-serving-launch.json','sandbox-enrollment.json']
            rows=[]
            for index,name in enumerate(names):
                if index==3:
                    rows.append({'name':name});continue
                payload=b'opaque non-policy bytes '+str(index).encode()
                (snapshot/name).write_bytes(payload);(snapshot/name).chmod(0o600)
                rows.append({'name':name,'bytes':len(payload),'sha256':sha(payload),'originalUID':os.getuid(),'originalMode':0o644})
            manifest={'version':1,'scope':'opaque_configuration_data_only','files':rows}
            payload=json.dumps(manifest).encode();(snapshot/'manifest.json').write_bytes(payload);(snapshot/'manifest.json').chmod(0o600)
            digest=sha(payload);before={p.name:p.read_bytes() for p in snapshot.iterdir()}
            command=['node',str(ROOT/'scripts/install-platform.mjs'),'propose-enrollment-removal',
                '--candidate',str(output),'--sha256',result['composition_sha256'],'--host','fios-edge-a.lab',
                '--configuration',str(snapshot),'--configuration-sha256',digest]
            completed=subprocess.run(command,capture_output=True,timeout=10)
            self.assertEqual(completed.returncode,0,completed.stderr)
            plan=json.loads(completed.stdout)
            self.assertEqual(plan['operation'],'configuration_removal_command_proposal')
            self.assertEqual(plan['state'],'blocked');self.assertFalse(plan['commands_authorized'])
            self.assertFalse(plan['configuration_removed']);self.assertFalse(plan['state_opened'])
            self.assertFalse(plan['stopped_state_backup_verified']);self.assertFalse(plan['configuration_documents_interpreted'])
            self.assertEqual(plan['privileged_commands'],[]);self.assertTrue(plan['configuration_snapshot_rechecked'])
            self.assertTrue(plan['native_inference_uncertainty_retained']);self.assertTrue(plan['credentials_retained'])
            removals=plan['proposed_file_removals'];self.assertEqual(len(removals),5)
            self.assertEqual([x['argv'] for x in removals],[['/Library/Application Support/Fios/Studio/'+x['name']] for x in rows if 'bytes' in x])
            self.assertTrue(all(x['program']=='/bin/rm' and x['required_uid']==0 for x in removals))
            self.assertNotIn(b'opaque non-policy bytes',completed.stdout)
            self.assertEqual(before,{p.name:p.read_bytes() for p in snapshot.iterdir()});self.assertFalse(args[4].exists())
            (snapshot/names[0]).write_bytes(b'changed')
            with self.assertRaises(ValueError):REVIEW['configuration_removal_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',snapshot,digest)
            (snapshot/names[0]).write_bytes(before[names[0]])
            manifest['version']=True;bad=json.dumps(manifest).encode();(snapshot/'manifest.json').write_bytes(bad)
            with self.assertRaises(ValueError):REVIEW['configuration_removal_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',snapshot,sha(bad))
            (snapshot/'manifest.json').write_bytes(before['manifest.json']);(snapshot/'unrelated').write_bytes(b'retain')
            with self.assertRaises(ValueError):REVIEW['configuration_removal_proposal'](output,result['composition_sha256'],'fios-edge-a.lab',snapshot,digest)
            self.assertEqual((snapshot/'unrelated').read_bytes(),b'retain')

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
