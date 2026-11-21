"""Read-only private runtime byte review. Never executes candidate code or enrolls it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import stat
import time

API = runpy.run_path(str(Path(__file__).with_name('package-platform-python.py')))
require = API['require']


def unique_object(pairs):
    result = {}
    for name, value in pairs:
        require(name not in result)
        result[name] = value
    return result


def review(directory, expected):
    require(isinstance(expected, str) and re.fullmatch('[0-9a-f]{64}', expected))
    root = Path(directory)
    require(root.is_absolute())
    chain = API['directory_chain'](root)
    began = time.monotonic()
    try:
        info = os.fstat(chain[-1][0])
        require(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700)
        manifest_path = root / 'candidate.json'
        require(not manifest_path.is_symlink() and manifest_path.stat().st_size <= 4 << 20)
        payload, manifest_identity = API['read_source'](manifest_path, root)
        require(len(payload) <= 4 << 20 and hashlib.sha256(payload).hexdigest() == expected)
        manifest = json.loads(payload, object_pairs_hook=unique_object)
        require(set(manifest) == {'version', 'purpose', 'python_version', 'platform', 'uv_lock_sha256',
                'producer_sha256', 'release_template_sha256', 'agent_sources', 'distributions', 'files',
                'bytes', 'console_wrappers_excluded', 'probe', 'scope', 'immutable_tree_enrolled', 'approved', 'activation'})
        require(type(manifest['version']) is int and manifest['version'] == 1 and
                manifest['purpose'] == 'python_worker_runtime_candidate' and manifest['python_version'] == '3.11.17' and
                manifest['platform'] == 'macos/arm64' and manifest['scope'] == 'declared_installed_runtime_bytes_not_publisher_build_or_whole_os_provenance')
        require(all(manifest[key] is False for key in ('approved', 'activation', 'immutable_tree_enrolled')))
        records = manifest['files']
        require(isinstance(records, dict) and 0 < len(records) <= 10000)
        require(type(manifest['bytes']) is int and 0 < manifest['bytes'] <= API['MAX_TOTAL'])
        allowed_folders = set()
        for relative in records:
            require(isinstance(relative, str) and not relative.startswith('/') and '\\' not in relative and
                    '\0' not in relative and len(relative.encode()) <= 4096 and
                    all(part not in ('', '.', '..') for part in relative.split('/')))
            allowed_folders.update(str(parent) for parent in Path(relative).parents if str(parent) != '.')
        total, observed = 0, set()
        def walk_error(error):
            raise error
        for parent, folders, names in os.walk(root, followlinks=False, onerror=walk_error):
            require(time.monotonic() - began <= 120)
            for name in folders:
                path = Path(parent) / name
                info = path.lstat()
                require(str(path.relative_to(root)) in allowed_folders and stat.S_ISDIR(info.st_mode) and
                        info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700)
            for name in names:
                path = Path(parent) / name
                relative = str(path.relative_to(root))
                info = path.lstat()
                require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_nlink == 1)
                if relative == 'candidate.json':
                    require(stat.S_IMODE(info.st_mode) == 0o644)
                    continue
                require(relative in records)
                record = records[relative]
                require(isinstance(record, dict) and set(record) == {'bytes', 'sha256', 'mode'} and
                        type(record['bytes']) is int and 0 <= record['bytes'] <= API['MAX_FILE'] and
                        type(record['mode']) is int and record['mode'] == (0o755 if relative.startswith('bin/') else 0o644) and
                        isinstance(record['sha256'], str) and re.fullmatch('[0-9a-f]{64}', record['sha256']))
                data, signature = API['read_source'](path, root)
                require(len(data) == record['bytes'] and hashlib.sha256(data).hexdigest() == record['sha256'] and
                        stat.S_IMODE(signature[2]) == record['mode'])
                total += len(data); require(total <= API['MAX_TOTAL'])
                observed.add(relative)
        require(observed == set(records) and total == manifest['bytes'])
        current, current_identity = API['read_source'](manifest_path, root)
        require(current == payload and current_identity == manifest_identity)
        API['verify_chain'](chain)
        return {'candidate_sha256': expected, 'files': len(records), 'bytes': total,
                'review': 'per_file_bytes_and_named_tree_not_atomic_installed_custody',
                'candidate_executed': False, 'approved': False, 'immutable_tree_enrolled': False, 'activation': False}
    finally:
        API['close_chain'](chain)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    print(json.dumps(review(args.candidate, args.sha256), sort_keys=True))
