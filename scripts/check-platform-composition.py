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


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate',required=True)
    parser.add_argument('--sha256',required=True)
    parser.add_argument('--host')
    args = parser.parse_args()
    print(json.dumps(installation_plan(args.candidate,args.sha256,args.host) if args.host else review(args.candidate,args.sha256)))
