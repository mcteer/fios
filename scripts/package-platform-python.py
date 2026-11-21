"""Private worker-runtime candidate producer. Data and import probe only.

No installation, enrollment, model request, service action or native authority.
The snapshot binds installed bytes; it is not publisher/build/whole-OS provenance.
"""
import argparse
import base64
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import stat
import subprocess
import sys
import sysconfig
import time

MAX_FILE = 128 << 20
MAX_TOTAL = 512 << 20


def require(value):
    if not value:
        raise ValueError('Python runtime candidate refused')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def identity(info):
    return tuple(getattr(info, key) for key in ('st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_gid', 'st_nlink', 'st_size', 'st_mtime_ns', 'st_ctime_ns'))


def close_chain(chain):
    for fd, _, _ in reversed(chain):
        os.close(fd)


def directory_chain(path):
    path = Path(path)
    require(path.is_absolute() and all(p not in ('', '.', '..') for p in path.parts[1:]))
    chain = [(os.open('/', os.O_RDONLY | os.O_DIRECTORY), None, None)]
    try:
        for name in path.parts[1:]:
            parent = chain[-1][0]
            fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            chain.append((fd, parent, name))
        return chain
    except BaseException:
        close_chain(chain)
        raise


def verify_chain(chain):
    for fd, parent, name in chain:
        current = os.fstat(fd)
        require(stat.S_ISDIR(current.st_mode))
        if parent is not None:
            named = os.stat(name, dir_fd=parent, follow_symlinks=False)
            require((current.st_dev, current.st_ino, current.st_mode, current.st_uid) ==
                    (named.st_dev, named.st_ino, named.st_mode, named.st_uid))


def open_output(path):
    path = Path(path)
    require(path.is_absolute() and path.name not in ('', '.', '..'))
    chain = directory_chain(path.parent)
    try:
        parent = chain[-1][0]
        info = os.fstat(parent)
        require(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700)
        os.mkdir(path.name, mode=0o700, dir_fd=parent)
        fd = os.open(path.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        chain.append((fd, parent, path.name))
        verify_chain(chain)
        return fd, chain
    except BaseException:
        close_chain(chain)
        raise


def write_data(root_fd, relative, data, executable):
    require(isinstance(relative, str) and not relative.startswith('/') and '\0' not in relative and '\\' not in relative)
    parts = relative.split('/')
    require(all(p not in ('', '.', '..') for p in parts) and len(relative.encode()) <= 4096 and len(data) <= MAX_FILE)
    parent, opened = root_fd, []
    try:
        for name in parts[:-1]:
            try:
                os.mkdir(name, mode=0o700, dir_fd=parent)
            except FileExistsError:
                pass
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            opened.append(child); parent = child
        fd = os.open(parts[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o755 if executable else 0o644, dir_fd=parent)
        try:
            offset = 0
            while offset < len(data):
                count = os.write(fd, data[offset:offset + (1 << 20)])
                require(count > 0); offset += count
            os.fchmod(fd, 0o755 if executable else 0o644)
            os.fsync(fd)
        finally:
            os.close(fd)
        for directory in reversed(opened):
            os.fsync(directory)
        os.fsync(root_fd)
    finally:
        for directory in reversed(opened):
            os.close(directory)


def read_source(path, root):
    root = Path(root).resolve(strict=True)
    path = Path(path).resolve(strict=True)
    require(path.is_relative_to(root))
    chain = directory_chain(path.parent)
    try:
        before = os.stat(path.name, dir_fd=chain[-1][0], follow_symlinks=False)
        require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1 and before.st_uid in (0, os.getuid()) and
                not before.st_mode & 0o6022 and 0 <= before.st_size <= MAX_FILE)
        fd = os.open(path.name, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW, dir_fd=chain[-1][0])
        try:
            require(identity(before) == identity(os.fstat(fd)))
            chunks, count = [], 0
            while chunk := os.read(fd, min(1 << 20, MAX_FILE + 1 - count)):
                count += len(chunk); require(count <= MAX_FILE); chunks.append(chunk)
            require(count == before.st_size and identity(before) == identity(os.fstat(fd)) and
                    identity(before) == identity(os.stat(path.name, dir_fd=chain[-1][0], follow_symlinks=False)))
            verify_chain(chain)
            return b''.join(chunks), identity(before)
        finally:
            os.close(fd)
    finally:
        close_chain(chain)


def gather(base, site):
    plan, distributions, skipped = {}, [], 0
    for source in (base / 'lib').rglob('*'):
        relative = source.relative_to(base)
        if 'site-packages' in relative.parts or '__pycache__' in relative.parts:
            continue
        if source.is_symlink() and source.is_dir():
            raise ValueError('Directory aliases require separate runtime review')
        if source.is_file():
            plan[str(relative)] = (source, base, None, None)
    interpreter = base / 'bin/python3.11'
    for name in ('bin/python', 'bin/python3.11'):
        plan[name] = (interpreter, base, None, None)
    for distribution in importlib.metadata.distributions(path=[str(site)]):
        direct = distribution.read_text('direct_url.json')
        require(not direct or not json.loads(direct).get('dir_info', {}).get('editable'))
        require(distribution.files is not None)
        distributions.append({'name': distribution.metadata['Name'], 'version': distribution.version})
        for item in distribution.files:
            source = site / item
            resolved = source.resolve(strict=True)
            if not resolved.is_relative_to(site):
                skipped += 1; continue  # Console wrappers are not worker entry points.
            relative = source.relative_to(site)
            if '__pycache__' in relative.parts or source.suffix == '.pyc':
                continue
            require(not source.is_symlink() and source.is_file())
            destination = 'lib/python3.11/site-packages/' + str(relative)
            require(destination not in plan)
            expected = None
            if item.hash:
                require(item.hash.mode == 'sha256')
                expected = item.hash.value
            plan[destination] = (source, site, expected, item.size)
    require(0 < len(plan) <= 10000 and len(distributions) <= 128)
    require(any(d['name'].lower().replace('_', '-') == 'fios-agent' and d['version'] == '0.1.0' for d in distributions))
    return plan, sorted(distributions, key=lambda d: d['name'].lower()), skipped


def agent_snapshot(source_root, installed_root):
    source_paths = {p.relative_to(source_root) for p in source_root.rglob('*.py')}
    installed_paths = {p.relative_to(installed_root) for p in installed_root.rglob('*.py')}
    require(source_paths and source_paths == installed_paths)
    result = {}
    for relative in sorted(source_paths):
        source, source_identity = read_source(source_root / relative, source_root)
        packaged, packaged_identity = read_source(installed_root / relative, installed_root)
        require(source == packaged)
        result[str(relative)] = (sha(source), source_identity, packaged_identity)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    require(sys.platform == 'darwin' and platform.machine() == 'arm64' and os.getuid() != 0 and sys.version_info[:3] == (3, 11, 17))
    began = time.monotonic()
    output = Path(args.output)
    base, site = Path(sys.base_prefix).resolve(), Path(sysconfig.get_path('purelib')).resolve()
    project = Path(__file__).resolve().parent.parent
    lock, lock_identity = read_source(project / 'uv.lock', project)
    producer, producer_identity = read_source(Path(__file__), project)
    template_bytes, template_identity = read_source(project / 'platform/studio/deployment/release.json', project)
    template = json.loads(template_bytes)
    require(sha(lock) == template['python']['uv_lock_sha256'])
    plan, distributions, skipped = gather(base, site)
    installed = site / 'fios_agent'
    agent_state = agent_snapshot(project / 'src/agent/fios_agent', installed)
    agent_sources = {name: record[0] for name, record in agent_state.items()}
    root_fd, chain = open_output(output)
    total, files, originals = 0, {}, []
    try:
        for relative, (source, source_root, expected, size) in sorted(plan.items()):
            require(time.monotonic() - began <= 120)
            data, signature = read_source(source, source_root)
            if expected:
                require(base64.urlsafe_b64encode(hashlib.sha256(data).digest()).decode().rstrip('=') == expected)
            require(size is None or size == len(data))
            total += len(data); require(total <= MAX_TOTAL)
            executable = relative.startswith('bin/')
            write_data(root_fd, relative, data, executable)
            files[relative] = {'bytes': len(data), 'sha256': sha(data), 'mode': 0o755 if executable else 0o644}
            originals.append((source, source_root, signature, sha(data)))
        verify_chain(chain)
        for relative, record in files.items():
            copied, signature = read_source(output / relative, output)
            require(sha(copied) == record['sha256'] and len(copied) == record['bytes'] and
                    stat.S_IMODE(signature[2]) == record['mode'])
        require({str(p.relative_to(output)) for p in output.rglob('*') if p.is_file()} == set(files))
        verify_chain(chain)
        probe = """import sys,ssl,ctypes,json,socket,errno,importlib.metadata as m
import _ssl,_ctypes,_socket
import pydantic_core
from pydantic_core import _pydantic_core
import fios_agent.platform_worker as worker
from pathlib import Path
prefix=Path(sys.argv[1])
assert sys.version_info[:3]==(3,11,17) and Path(sys.prefix)==prefix
assert all(Path(module.__file__).is_relative_to(prefix) for module in (ssl,ctypes,pydantic_core,_pydantic_core,worker))
assert all(module.__spec__.origin=='built-in' and module.__name__ in sys.builtin_module_names
           or Path(module.__file__).is_relative_to(prefix) for module in (_ssl,_ctypes,_socket))
assert m.version('fios-agent')=='0.1.0'
try:
    connection=socket.socket()
    connection.connect(('127.0.0.1',1))
except OSError as error:
    assert error.errno==errno.EPERM
else:
    raise AssertionError('network connect was not denied')
print(json.dumps({'python':sys.version.split()[0],'package':m.version('fios-agent'),'private_prefix':True,'worker_imported':True,'network_denial_observed':True}))
"""
        result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(output / 'bin/python'), '-I', '-B', '-c', probe, str(output)],
                                capture_output=True, timeout=30, env={'PATH': '/usr/bin:/bin', 'HOME': '/var/empty', 'LANG': 'C', 'LC_ALL': 'C', 'PYDANTIC_AI_NO_BANNER': '1'})
        require(result.returncode == 0 and not result.stderr and len(result.stdout) <= 4096)
        measured = json.loads(result.stdout)
        require(measured.get('private_prefix') is True and measured.get('worker_imported') is True and measured.get('network_denial_observed') is True)
        for source, source_root, signature, expected in originals:
            require(time.monotonic() - began <= 120)
            data, current = read_source(source, source_root)
            require(current == signature and sha(data) == expected)
        require(set(gather(base, site)[0]) == set(plan))
        require(agent_snapshot(project / 'src/agent/fios_agent', installed) == agent_state)
        for path, data, signature in ((project / 'uv.lock', lock, lock_identity),
                                      (Path(__file__), producer, producer_identity),
                                      (project / 'platform/studio/deployment/release.json', template_bytes, template_identity)):
            current, current_identity = read_source(path, project)
            require(current == data and current_identity == signature)
        for relative, record in files.items():
            copied, signature = read_source(output / relative, output)
            require(sha(copied) == record['sha256'] and len(copied) == record['bytes'] and
                    stat.S_IMODE(signature[2]) == record['mode'])
        require({str(p.relative_to(output)) for p in output.rglob('*') if p.is_file()} == set(files))
        verify_chain(chain)
        candidate = {'version': 1, 'purpose': 'python_worker_runtime_candidate', 'python_version': '3.11.17', 'platform': 'macos/arm64',
                     'uv_lock_sha256': sha(lock), 'producer_sha256': sha(producer), 'release_template_sha256': sha(template_bytes), 'agent_sources': agent_sources,
                     'distributions': distributions, 'files': files, 'bytes': total, 'console_wrappers_excluded': skipped,
                     'probe': measured, 'scope': 'declared_installed_runtime_bytes_not_publisher_build_or_whole_os_provenance',
                     'immutable_tree_enrolled': False, 'approved': False, 'activation': False}
        payload = (json.dumps(candidate, indent=2, sort_keys=True) + '\n').encode()
        write_data(root_fd, 'candidate.json', payload, False)
        verify_chain(chain)
        print(json.dumps({'directory': str(output), 'candidate_sha256': sha(payload), 'files': len(files), 'bytes': total,
                          'immutable_tree_enrolled': False, 'approved': False, 'activation': False}))
    except BaseException:
        print('RETAINED: private runtime candidate data; no cleanup or enrollment attempted', file=sys.stderr)
        raise
    finally:
        close_chain(chain)


if __name__ == '__main__':
    main()
