"""Compose reviewed platform/runtime bytes for review; no installation authority.

Never executes a candidate program, enrolls a runtime, writes protected paths,
opens state or performs service/model operations. Retains partial output.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = runpy.run_path(str(ROOT/'scripts/check-platform-python-candidate.py'))
API = RUNTIME['API']
require = API['require']
MAX_TOTAL = 1 << 30
MAX_FILES = 11000


def sha(data):
    return hashlib.sha256(data).hexdigest()


def platform_review(directory, expected, template=None):
    template = Path(template) if template is not None else ROOT/'platform/studio/deployment/release.json'
    node = shutil.which('node')
    require(node is not None)
    code = """import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const {validatePlatformRelease}=await import(process.argv[1]);
const result=validatePlatformRelease(process.argv[2],process.argv[3]);
const {source_revision,source_tree_sha256,artifacts,package_complete,...template}=result.manifest;
const bytes=readFileSync(process.argv[4]);assert.deepEqual(template,JSON.parse(bytes));
console.log(JSON.stringify({...result,template_sha256:createHash('sha256').update(bytes).digest('hex')}));"""
    result = subprocess.run([node, '--input-type=module', '-e', code,
                             (ROOT/'scripts/lib/platform-release.mjs').as_uri(), str(directory), expected, str(template)],
                            capture_output=True, timeout=30)
    require(result.returncode == 0 and not result.stderr and len(result.stdout) <= 131072)
    return json.loads(result.stdout)


def compose(platform, platform_sha, runtime, runtime_sha, output):
    require(os.getuid() != 0)
    began = time.monotonic()
    platform, runtime, output = Path(platform), Path(runtime), Path(output)
    for path in (platform, runtime, output):
        require(path.is_absolute() and str(path).startswith(('/private/tmp/', '/tmp/')))
    for path in (platform, runtime):
        require(path.resolve() == path and not output.is_relative_to(path) and not path.is_relative_to(output))
    require(platform != runtime and not platform.is_relative_to(runtime) and not runtime.is_relative_to(platform))
    before = platform_review(platform, platform_sha)
    reviewed_runtime = RUNTIME['review'](runtime, runtime_sha)
    runtime_bytes, runtime_identity = API['read_source'](runtime/'candidate.json', runtime)
    candidate = json.loads(runtime_bytes, object_pairs_hook=RUNTIME['unique_object'])
    require(candidate['uv_lock_sha256'] == before['manifest']['python']['uv_lock_sha256'] and
            candidate['release_template_sha256'] == before['template_sha256'])
    template_path = ROOT/'platform/studio/deployment/release.json'
    template_bytes, template_identity = API['read_source'](template_path, ROOT)
    require(sha(template_bytes) == before['template_sha256'])
    plan = {'release-template.json': (ROOT, 'platform/studio/deployment/release.json',
            {'bytes': len(template_bytes), 'sha256': sha(template_bytes), 'mode': stat.S_IMODE(template_identity[2])})}
    for item in before['manifest']['artifacts']:
        plan['platform/'+item['path']] = (platform, item['path'], item)
    release_bytes, release_identity = API['read_source'](platform/'release.json', platform)
    plan['platform/release.json'] = (platform, 'release.json', {'bytes': len(release_bytes), 'sha256': platform_sha, 'mode': stat.S_IMODE(release_identity[2])})
    for name, item in candidate['files'].items():
        plan['python-runtime/'+name] = (runtime, name, item)
    plan['python-runtime/candidate.json'] = (runtime, 'candidate.json', {'bytes': len(runtime_bytes), 'sha256': runtime_sha, 'mode': 0o644})
    require(0 < len(plan) <= MAX_FILES)
    total = sum(item['bytes'] for _, _, item in plan.values())
    require(0 < total <= MAX_TOTAL and shutil.disk_usage(output.parent).free >= total+(10 << 30))
    source_inputs = {name: sha((ROOT/name).read_bytes()) for name in
                     ['scripts/compose-platform-candidate.py', 'scripts/check-platform-python-candidate.py',
                      'scripts/package-platform-python.py', 'scripts/lib/platform-release.mjs',
                      'platform/studio/deployment/release.json']}
    root_fd, chain = API['open_output'](output)
    records = {}
    try:
        for name, (source_root, relative, expected) in sorted(plan.items()):
            require(time.monotonic()-began <= 240)
            data, identity = API['read_source'](source_root/relative, source_root)
            require(len(data) == expected['bytes'] and sha(data) == expected['sha256'] and
                    stat.S_IMODE(identity[2]) == expected['mode'])
            API['write_data'](root_fd, name, data, expected['mode'] == 0o755)
            # Receipts contain no credentials; copies use0644 inside the
            # private0700 tree, matching the runtime candidate convention.
            records[name] = {'bytes': len(data), 'sha256': sha(data),
                             'mode': 0o755 if expected['mode'] == 0o755 else 0o644}
        API['verify_chain'](chain)
        require(platform_review(output/'platform', platform_sha, output/'release-template.json') == before)
        require(RUNTIME['review'](output/'python-runtime', runtime_sha) == reviewed_runtime)
        require(platform_review(platform, platform_sha) == before and RUNTIME['review'](runtime, runtime_sha) == reviewed_runtime)
        require(API['read_source'](platform/'release.json', platform) == (release_bytes, release_identity))
        require(API['read_source'](runtime/'candidate.json', runtime) == (runtime_bytes, runtime_identity))
        require(API['read_source'](template_path, ROOT) == (template_bytes, template_identity))
        for name, expected in records.items():
            require(time.monotonic()-began <= 240)
            data, identity = API['read_source'](output/name, output)
            require(len(data) == expected['bytes'] and sha(data) == expected['sha256'] and stat.S_IMODE(identity[2]) == expected['mode'])
        directories = {str(parent) for name in records for parent in Path(name).parents if str(parent) != '.'}
        observed = set()
        for path in output.rglob('*'):
            info = path.lstat(); relative = str(path.relative_to(output))
            if stat.S_ISDIR(info.st_mode):
                require(relative in directories and info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700)
            else:
                require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and relative in records)
                observed.add(relative)
        require(observed == set(records))
        for name, expected in source_inputs.items():
            require(sha((ROOT/name).read_bytes()) == expected)
        API['verify_chain'](chain)
        receipt = {'version': 1, 'purpose': 'platform_runtime_review_composition',
                   'scope': 'declared_component_bytes_not_installation_or_native_provenance',
                   'platform_manifest_sha256': platform_sha, 'python_candidate_sha256': runtime_sha,
                   'release_template_sha256': before['template_sha256'], 'uv_lock_sha256': candidate['uv_lock_sha256'],
                   'source_revision': before['manifest']['source_revision'], 'source_inputs': source_inputs,
                   'files': records, 'bytes': total, 'candidate_programs_executed': False,
                   'package_complete': False, 'approved': False, 'immutable_tree_enrolled': False,
                   'installed': False, 'activation': False, 'native_authority': False,
                   'remaining': ['operator_release_and_host_review', 'protected_installation',
                                 'credential_configuration', 'native_contract_and_enrollment', 'installed_acceptance']}
        payload = (json.dumps(receipt, indent=2, sort_keys=True)+'\n').encode()
        require(len(payload) <= 4 << 20)
        API['write_data'](root_fd, 'composition.json', payload, False)
        API['verify_chain'](chain)
        return {'directory': str(output), 'composition_sha256': sha(payload), 'files': len(records), 'bytes': total,
                'candidate_programs_executed': False, 'installed': False, 'activation': False, 'native_authority': False}
    except BaseException:
        print('RETAINED private composition data; no cleanup or installation attempted', file=sys.stderr)
        raise
    finally:
        API['close_chain'](chain)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', required=True)
    parser.add_argument('--platform-sha256', required=True)
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--runtime-sha256', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    require(sys.version_info[:3] == (3, 11, 17))
    print(json.dumps(compose(args.platform, args.platform_sha256, args.runtime, args.runtime_sha256, args.output)))


if __name__ == '__main__':
    main()
