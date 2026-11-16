"""Read-only combined artifact review. Never executes/enrolls candidate code."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import stat
import time

COMPOSE = runpy.run_path(str(Path(__file__).with_name('compose-platform-candidate.py')))
API, RUNTIME = COMPOSE['API'], COMPOSE['RUNTIME']
require = API['require']
sha = lambda data: hashlib.sha256(data).hexdigest()


def review(directory, expected):
    require(isinstance(expected, str) and re.fullmatch('[0-9a-f]{64}', expected))
    root = Path(directory)
    require(root.is_absolute() and root.resolve() == root and str(root).startswith(('/private/tmp/', '/tmp/')))
    chain = API['directory_chain'](root)
    began = time.monotonic()
    try:
        info = os.fstat(chain[-1][0])
        require(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700)
        named = (root/'composition.json').lstat()
        require(stat.S_ISREG(named.st_mode) and named.st_nlink == 1 and 0 < named.st_size <= 4 << 20)
        payload, identity = API['read_source'](root/'composition.json', root)
        require(sha(payload) == expected)
        value = json.loads(payload, object_pairs_hook=RUNTIME['unique_object'])
        require(set(value) == {'version','purpose','scope','platform_manifest_sha256','python_candidate_sha256',
                'release_template_sha256','uv_lock_sha256','source_revision','source_inputs','files','bytes',
                'candidate_programs_executed','package_complete','approved','immutable_tree_enrolled','installed',
                'activation','native_authority','remaining'})
        require(type(value['version']) is int and value['version'] == 1 and
                value['purpose'] == 'platform_runtime_review_composition' and
                value['scope'] == 'declared_component_bytes_not_installation_or_native_provenance')
        require(all(value[key] is False for key in ('candidate_programs_executed','package_complete','approved',
                'immutable_tree_enrolled','installed','activation','native_authority')))
        require(value['remaining'] == ['operator_release_and_host_review','protected_installation',
                'credential_configuration','native_contract_and_enrollment','installed_acceptance'])
        for key in ('platform_manifest_sha256','python_candidate_sha256','release_template_sha256','uv_lock_sha256'):
            require(isinstance(value[key], str) and re.fullmatch('[0-9a-f]{64}', value[key]))
        sources = value['source_inputs']
        require(isinstance(sources,dict) and set(sources) == {'scripts/compose-platform-candidate.py',
                'scripts/check-platform-python-candidate.py','scripts/package-platform-python.py',
                'scripts/lib/platform-release.mjs','platform/studio/deployment/release.json'} and
                all(isinstance(digest,str) and re.fullmatch('[0-9a-f]{64}',digest) for digest in sources.values()))
        # Provenance declarations are not paths to follow or approval evidence.
        platform = COMPOSE['platform_review'](root/'platform', value['platform_manifest_sha256'], root/'release-template.json')
        runtime = RUNTIME['review'](root/'python-runtime', value['python_candidate_sha256'])
        raw, _ = API['read_source'](root/'python-runtime/candidate.json',root/'python-runtime')
        candidate = json.loads(raw,object_pairs_hook=RUNTIME['unique_object'])
        require(value['source_revision'] == platform['manifest']['source_revision'] and
                value['release_template_sha256'] == platform['template_sha256'] == candidate['release_template_sha256'] and
                value['uv_lock_sha256'] == platform['manifest']['python']['uv_lock_sha256'] == candidate['uv_lock_sha256'])
        records = value['files']
        expected_files = {'platform/'+item['path'] for item in platform['manifest']['artifacts']}
        expected_files.update('python-runtime/'+name for name in candidate['files'])
        expected_files.update(['platform/release.json','python-runtime/candidate.json','release-template.json'])
        require(isinstance(records,dict) and set(records) == expected_files and len(records) <= COMPOSE['MAX_FILES'])
        folders = {str(parent) for name in records for parent in Path(name).parents if str(parent) != '.'}
        total, observed = 0, set()
        for path in root.rglob('*'):
            require(time.monotonic()-began <= 240)
            name = str(path.relative_to(root)); info = path.lstat()
            if stat.S_ISDIR(info.st_mode):
                require(name in folders and info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700)
                continue
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_uid == os.getuid())
            if name == 'composition.json':
                require(stat.S_IMODE(info.st_mode) == 0o644)
                continue
            require(name in records)
            record = records[name]
            require(isinstance(record,dict) and set(record) == {'bytes','sha256','mode'} and
                    type(record['bytes']) is int and 0 <= record['bytes'] <= API['MAX_FILE'] and
                    type(record['mode']) is int and record['mode'] in (0o644,0o755) and
                    isinstance(record['sha256'],str) and re.fullmatch('[0-9a-f]{64}',record['sha256']))
            data, current = API['read_source'](path,root)
            require(len(data) == record['bytes'] and sha(data) == record['sha256'] and
                    stat.S_IMODE(current[2]) == record['mode'])
            total += len(data); require(total <= COMPOSE['MAX_TOTAL']); observed.add(name)
        require(observed == expected_files and type(value['bytes']) is int and total == value['bytes'])
        require(API['read_source'](root/'composition.json',root) == (payload,identity))
        API['verify_chain'](chain)
        return {'composition_sha256':expected,'files':len(records),'bytes':total,
                'candidate_programs_executed':False,'installed':False,'activation':False,'native_authority':False,
                'review':'per_file_component_data_not_atomic_installed_custody'}
    finally:
        API['close_chain'](chain)


def installation_plan(directory, expected, host):
    measured = review(directory, expected)
    require(host in ('fios-edge-a.lab','fios-edge-b.lab'))
    root = Path(directory)
    raw, _ = API['read_source'](root/'composition.json',root)
    require(sha(raw) == expected)
    value = json.loads(raw,object_pairs_hook=RUNTIME['unique_object'])
    platform_files = sum(name.startswith('platform/') for name in value['files'])
    runtime_files = sum(name.startswith('python-runtime/') for name in value['files'])
    return {**measured,'version':1,'operation':'composed_platform_install_review','host':host,
            'state':'blocked','changes_made':False,'privileged_commands':[],
            'installation_layout':[
                {'source_prefix':'platform/','destination':'/Library/Application Support/Fios/Studio','files':platform_files},
                {'source_prefix':'python-runtime/','destination':'/Library/Application Support/Fios/Studio/python/runtime','files':runtime_files}],
            'service_user':'mcteer','launchd_registration':'not_proposed',
            'state_and_credentials':'separate_operator_review_not_in_bundle',
            'blockers':['development_components_not_installable_release','operator_installation_not_approved',
                        'protected_destination_and_credential_configuration_unimplemented',
                        'native_contract_and_enrollment_unproven','installed_acceptance_pending'],
            'preserves':['native_inference_uncertainty','platform_exports','unrelated_runtime_objects','fios_database','legacy_volume']}


def first_install_proposal(directory, expected, host):
    plan = installation_plan(directory, expected, host)
    root = Path(directory)
    raw, _ = API['read_source'](root/'composition.json', root)
    require(sha(raw) == expected)
    value = json.loads(raw, object_pairs_hook=RUNTIME['unique_object'])
    prefix = '/Library/Application Support/Fios/Studio'
    copies, destinations = [], set()
    for name, record in sorted(value['files'].items()):
        if name == 'release-template.json':
            continue  # Review evidence, never an installed runtime input.
        if name.startswith('platform/'):
            relative = name[len('platform/'):]
        else:
            require(name.startswith('python-runtime/'))
            relative = 'python/runtime/'+name[len('python-runtime/'):]
        require(relative and all(part not in ('', '.', '..') for part in relative.split('/')))
        destination = prefix+'/'+relative
        require(destination not in destinations)
        destinations.add(destination)
        copies.append({'source':str(root/name),'destination':destination,'sha256':record['sha256'],
                       'bytes':record['bytes'],'mode':record['mode'],
                       'program':'/usr/bin/install',
                       'argv':['-o','root','-g','wheel','-m',format(record['mode'],'04o'),str(root/name),destination]})
    folders = {str(parent) for destination in destinations for parent in Path(destination).parents
               if str(parent) == prefix or str(parent).startswith(prefix+'/')}
    create = [{'program':'/bin/mkdir','argv':['-m','0755',folder]}
              for folder in sorted(folders,key=lambda name:(len(Path(name).parts),name))]
    tool_inputs = {name:sha(API['read_source'](COMPOSE['ROOT']/name,COMPOSE['ROOT'])[0])
                   for name in ('scripts/check-platform-composition.py','scripts/install-platform.mjs')}
    return {**plan,'operation':'first_install_command_proposal','commands_authorized':False,
            'requires_operator_execution':True,'candidate_programs_executed':False,
            'proposal_tool_inputs':tool_inputs,
            'proposal_scope':'inactive_new_prefix_only_not_upgrade_or_activation',
            'proposed_files':len(copies),'proposed_directories':len(create),
            'proposed_bytes':sum(item['bytes'] for item in copies),
            'review_only_excluded':['release-template.json'],
            'mandatory_preconditions':['separate_operator_installation_approval',
                'complete_installable_release_review_not_development_receipt',
                'execute_on_exact_reviewed_studio_not_core',
                'root_wheel_operator_and_protected_no_symlink_parent',
                'destination_prefix_absent_no_overwrite',
                'no_registered_platform_jobs_or_running_platform_writers',
                'serialized_operator_transaction_and_source_hash_recheck'],
            'proposed_directory_commands':create,'proposed_file_commands':copies,
            'source_and_destination_hashes':'verify_all_before_copy_and_all_protected_copies_afterward',
            'on_failure':'stop_retain_partial_prefix_for_diagnosis_do_not_activate_or_delete',
            'launchd_registration':'not_proposed','enrollment_written':False,
            'credentials_written':False,'state_opened':False}


def uninstall_proposal(directory, expected, host):
    plan = first_install_proposal(directory, expected, host)
    files = plan.pop('proposed_file_commands')
    directories = plan.pop('proposed_directory_commands')
    # Only the exact reviewed managed artifact names. No state, enrollment,
    # credentials, launchd registration, runtime objects or unrelated paths.
    removals = [{'program':'/bin/rm','argv':[item['destination']],
                 'destination':item['destination'],'required_sha256':item['sha256'],
                 'required_bytes':item['bytes'],'required_mode':item['mode']}
                for item in files]
    empty_directories = [{'program':'/bin/rmdir','argv':[item['argv'][-1]]}
                         for item in reversed(directories)]
    return {**plan,'operation':'uninstall_command_proposal',
            'proposal_scope':'known_artifacts_only_retains_state_enrollment_and_unknown_files',
            'mandatory_preconditions':['separate_operator_uninstall_approval',
                'execute_on_exact_reviewed_studio_not_core',
                'root_wheel_operator_and_protected_no_symlink_prefix',
                'verified_stopped_state_configuration_and_program_backup',
                'platform_jobs_unregistered_and_all_writers_stopped',
                'reviewed_launchd_registration_removed_or_persistently_disabled',
                'owned_native_child_reconciled_no_unknown_native_disruption',
                'serialized_operator_transaction',
                'reverify_each_installed_artifact_owner_mode_size_and_hash_before_removal'],
            'proposed_file_removals':removals,'proposed_empty_directory_removals':empty_directories,
            'enrollment_retained':True,'credentials_retained':True,'state_and_exports_retained':True,
            'unknown_files':'retain_never_recurse_or_expand_removal_scope',
            'source_and_destination_hashes':'installed_file_must_match_exact_reviewed_artifact_before_removal',
            'on_failure':'stop_retain_remaining_data_and_uncertainty_no_recursive_cleanup'}


def python_enrollment_proposal(directory, expected, host, uid, state, review_sha256):
    plan = installation_plan(directory, expected, host)
    require(isinstance(uid,str) and re.fullmatch('[1-9][0-9]{0,9}',uid) and int(uid)<=4294967295)
    require(isinstance(state,str) and state.startswith('/Users/mcteer/') and str(Path(state))==state and
            len(state.encode())<1024 and '\0' not in state and all(part not in ('.','..') for part in Path(state).parts))
    require(isinstance(review_sha256,str) and re.fullmatch('[0-9a-f]{64}',review_sha256))
    root=Path(directory)
    raw,_=API['read_source'](root/'composition.json',root);require(sha(raw)==expected)
    composition=json.loads(raw,object_pairs_hook=RUNTIME['unique_object'])
    raw,_=API['read_source'](root/'platform/release.json',root)
    require(sha(raw)==composition['platform_manifest_sha256'])
    platform=json.loads(raw,object_pairs_hook=RUNTIME['unique_object'])
    raw,_=API['read_source'](root/'python-runtime/candidate.json',root)
    require(sha(raw)==composition['python_candidate_sha256'])
    runtime=json.loads(raw,object_pairs_hook=RUNTIME['unique_object'])
    manager=next(item for item in platform['artifacts'] if item['path']=='bin/studio-manager')
    interpreter=runtime['files'].get('bin/python')
    require(isinstance(interpreter,dict) and interpreter['mode']==0o755)
    policy={'version':1,'purpose':'reviewed_platform_python_worker','uid':int(uid),'host':host,
            'state_path':state,'review_sha256':review_sha256,'manager_sha256':manager['sha256'],
            'manifest_sha256':composition['python_candidate_sha256'],'python_sha256':interpreter['sha256'],
            'uv_lock_sha256':runtime['uv_lock_sha256'],'producer_sha256':runtime['producer_sha256'],
            'release_template_sha256':runtime['release_template_sha256'],
            'policy_sha256':platform['python']['policy_sha256'],'python_version':'3.11.17','package_version':'0.1.0'}
    require(all(isinstance(value,str) and re.fullmatch('[0-9a-f]{64}',value)
                for key,value in policy.items() if key.endswith('_sha256')))
    payload=(json.dumps(policy,indent=2)+'\n').encode();require(len(payload)<=4096)
    return {**plan,'operation':'python_enrollment_configuration_proposal','commands_authorized':False,
            'approved':False,'policy_written':False,'credentials_written':False,'state_opened':False,
            'review_identity':'supplied_correlation_not_approval_or_provenance',
            'destination':'/Library/Application Support/Fios/Studio/python-enrollment.json',
            'policy_candidate':policy,'policy_candidate_sha256':sha(payload),
            'policy_candidate_json':payload.decode('ascii'),
            'policy_encoding':'UTF8_JSON_indent2_trailing_newline',
            'configuration_scope':'declared_component_bindings_not_installed_policy_or_native_permission'}


def stage_python_enrollment(directory, expected, host, uid, state, review_sha256, output):
    proposal=python_enrollment_proposal(directory,expected,host,uid,state,review_sha256)
    output=Path(output)
    require(os.getuid()!=0 and output.is_absolute() and str(output).startswith(('/private/tmp/','/tmp/')) and
            output.parent.resolve()==output.parent and not output.is_relative_to(Path(directory)) and
            not Path(directory).is_relative_to(output))
    payload=proposal['policy_candidate_json'].encode('ascii')
    review_bytes=(json.dumps(proposal,indent=2)+'\n').encode()
    fd,chain=API['open_output'](output)
    try:
        API['write_data'](fd,'python-enrollment.json',payload,False)
        API['write_data'](fd,'review.json',review_bytes,False)
        require(API['read_source'](output/'python-enrollment.json',output)[0]==payload)
        require(API['read_source'](output/'review.json',output)[0]==review_bytes)
        review(directory,expected)  # Recheck source component bytes before success.
        API['verify_chain'](chain)
        receipt={'version':1,'operation':'private_python_enrollment_stage','composition_sha256':expected,
                 'policy_sha256':sha(payload),'review_sha256':sha(review_bytes),'private_files_written':3,
                 'source_rechecked':True,'approved':False,'installed_policy_written':False,
                 'installed':False,'activation':False,'native_authority':False,'state_opened':False}
        API['write_data'](fd,'stage-receipt.json',(json.dumps(receipt,indent=2)+'\n').encode(),False)
        require(set(os.listdir(fd))=={'python-enrollment.json','review.json','stage-receipt.json'})
        API['verify_chain'](chain)
        return receipt
    finally:
        API['close_chain'](chain)  # Retain failed/partial data; never path cleanup.


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate',required=True)
    parser.add_argument('--sha256',required=True)
    parser.add_argument('--host')
    modes=parser.add_mutually_exclusive_group()
    modes.add_argument('--first-install-proposal',action='store_true')
    modes.add_argument('--uninstall-proposal',action='store_true')
    modes.add_argument('--python-enrollment-proposal',action='store_true')
    modes.add_argument('--stage-python-enrollment',action='store_true')
    parser.add_argument('--uid')
    parser.add_argument('--state')
    parser.add_argument('--review-sha256')
    parser.add_argument('--to')
    args = parser.parse_args()
    require(not (args.first_install_proposal or args.uninstall_proposal or args.python_enrollment_proposal or args.stage_python_enrollment) or args.host is not None)
    require((args.python_enrollment_proposal or args.stage_python_enrollment) or all(value is None for value in (args.uid,args.state,args.review_sha256)))
    require(args.stage_python_enrollment or args.to is None)
    require(not args.stage_python_enrollment or args.to is not None)
    result = (stage_python_enrollment(args.candidate,args.sha256,args.host,args.uid,args.state,args.review_sha256,args.to) if args.stage_python_enrollment else
              python_enrollment_proposal(args.candidate,args.sha256,args.host,args.uid,args.state,args.review_sha256) if args.python_enrollment_proposal else
              uninstall_proposal(args.candidate,args.sha256,args.host) if args.uninstall_proposal else
              first_install_proposal(args.candidate,args.sha256,args.host) if args.first_install_proposal else
              installation_plan(args.candidate,args.sha256,args.host) if args.host else review(args.candidate,args.sha256))
    print(json.dumps(result))
