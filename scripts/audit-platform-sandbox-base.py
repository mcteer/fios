"""Offline content inventory for a saved OCI base. Never extracts or executes it.

This proves content binding, not publisher authenticity, reproducible build,
license/security approval, enrollment or runtime/native authority.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
import re
import stat
import tarfile
from pathlib import Path

LIMIT = 2 << 30
ROOTS = ('opt/python/', 'opt/venv/', 'usr/lib/', 'lib/')


def require(value):
    if not value:
        raise ValueError('sandbox archive review refused')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def audit(path, expected):
    require(re.fullmatch(r'sha256:[a-f0-9]{64}', expected))
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as source:
        initial = os.fstat(source.fileno())
        require(stat.S_ISREG(initial.st_mode) and 0 < initial.st_size <= LIMIT)
        archive_hash = hashlib.file_digest(source, 'sha256').hexdigest()
        source.seek(0)
        with tarfile.open(fileobj=source, mode='r:') as archive:
            members = []
            for member in archive:
                require(len(members) < 100000)
                members.append(member)
            names = [m.name for m in members]
            require(len(names) == len(set(names)))
            table = {m.name: m for m in members}

            def read(name, maximum=LIMIT):
                m = table[name]
                require(m.isfile() and 0 <= m.size <= maximum)
                return archive.extractfile(m).read()

            def blob(identifier):
                require(re.fullmatch(r'sha256:[a-f0-9]{64}', identifier))
                data = read('blobs/sha256/' + identifier[7:])
                require(digest(data) == identifier[7:])
                return data

            index = json.loads(read('index.json', 1 << 20))
            require(index['schemaVersion'] == 2)
            require(any(x['digest'] == expected for x in index['manifests']))
            manifest = json.loads(blob(expected))
            # Docker/containerd exports may address an index rather than a config.
            if 'manifests' in manifest:
                choices = [x for x in manifest['manifests'] if x.get('platform', {}).get('os') == 'linux' and x.get('platform', {}).get('architecture') == 'arm64']
                require(len(choices) == 1)
                manifest = json.loads(blob(choices[0]['digest']))
            config = json.loads(blob(manifest['config']['digest']))
            require(config['os'] == 'linux' and config['architecture'] == 'arm64')
            require(not config.get('config', {}).get('OnBuild'))
            layers = manifest['layers']
            require(0 < len(layers) <= 128 and len(layers) == len(config['rootfs']['diff_ids']))
            inventory = {}
            total = entries = 0
            for descriptor, diff in zip(layers, config['rootfs']['diff_ids']):
                data = blob(descriptor['digest'])
                require(len(data) == descriptor['size'])
                stream = gzip.GzipFile(fileobj=io.BytesIO(data)) if data[:2] == b'\x1f\x8b' else io.BytesIO(data)
                h = hashlib.sha256()
                while chunk := stream.read(1 << 20):
                    total += len(chunk)
                    require(total <= 4 * LIMIT)
                    h.update(chunk)
                require('sha256:' + h.hexdigest() == diff)
                with tarfile.open(fileobj=io.BytesIO(data), mode='r|*') as layer:
                    for member in layer:
                        entries += 1
                        require(entries <= 200000)
                        name = member.name.removeprefix('./').rstrip('/')
                        require(name and not name.startswith('/') and '..' not in name.split('/'))
                        require(not any(p.startswith('.wh.') for p in name.split('/')))
                        selected = name.startswith(ROOTS) or name in ('bin', 'lib', 'lib64', 'bin/cat', 'usr/bin/cat')
                        if not selected:
                            continue
                        # Refuse overlays requiring deletion semantics; never guess
                        # which runtime bytes survived a whiteout/opaque directory.
                        require(not any(p.startswith('.wh.') for p in name.split('/')))
                        require(member.isfile() or member.isdir() or member.issym() or member.islnk())
                        item = {'mode': member.mode, 'kind': 'directory'}
                        if member.isfile():
                            require(member.size <= 512 << 20)
                            item.update(kind='file', bytes=member.size, sha256=hashlib.file_digest(layer.extractfile(member), 'sha256').hexdigest())
                        elif member.issym() or member.islnk():
                            item.update(kind='symlink' if member.issym() else 'hardlink', target=member.linkname)
                        if not member.isdir():
                            for child in list(inventory):
                                if child.startswith(name + '/'):
                                    del inventory[child]
                        inventory[name] = item
            require(any(n.startswith('opt/python/cpython-3.11.17-linux-aarch64-gnu/') for n in inventory))
            require('opt/venv/pyvenv.cfg' in inventory and any(n in inventory for n in ('bin/cat', 'usr/bin/cat')))
            inventory_bytes = canonical(inventory)
            receipt = {'version': 1, 'purpose': 'sandbox_base_content_inventory', 'base_image': expected,
                       'archive_sha256': archive_hash, 'auditor_sha256': digest(Path(__file__).read_bytes()), 'config_sha256': manifest['config']['digest'][7:],
                       'layers': [x['digest'] for x in layers], 'inventory_sha256': digest(inventory_bytes),
                       'inventory_entries': len(inventory), 'platform': 'linux/arm64',
                       'scope': 'saved_image_copied_runtime_content_not_publisher_or_build_attestation',
                       'approved': False, 'activation': False}
        final = os.fstat(source.fileno())
        named = os.stat(path, follow_symlinks=False)
        keys = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
        require(all(getattr(initial, k) == getattr(s, k) for s in (final, named) for k in keys))
        return receipt, inventory_bytes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True)
    parser.add_argument('--image', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    receipt, inventory = audit(args.archive, args.image)
    output = Path(args.output)
    require(output.is_absolute() and output.parent.stat().st_uid == os.getuid() and stat.S_IMODE(output.parent.stat().st_mode) == 0o700)
    output.mkdir(mode=0o700)
    for name, data in [('inventory.json', inventory), ('provenance.json', canonical(receipt))]:
        with os.fdopen(os.open(output / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as target:
            target.write(data)
    print(json.dumps({'provenance_sha256': digest(canonical(receipt)), 'approved': False, 'activation': False}))


if __name__ == '__main__':
    main()
