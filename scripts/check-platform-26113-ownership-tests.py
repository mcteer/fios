"""Run only reviewed model-free ownership tests from a private Zig 0.17 test binary."""
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile

TESTS = (
    'engines.mlx.runtime.load_requests.test.fios current unload worker restores original requester',
    'engines.mlx.runtime.load_requests.test.fios current queued unload preserves sender and worker origins',
    'engines.mlx.runtime.load_requests.test.fios current unload refuses callback uncertainty without releasing accounting',
    'host.registry.registry.test.fios current registry capacity planning retains known request ownership',
    'engines.mlx.scheduler.test.fios current cold load publication refusal releases original reservations',
    'engines.mlx.runtime.load_requests.test.fios current stale published target cannot evict or change a later cold claim',
    'engines.mlx.runtime.load_requests.test.fios current old victim snapshot cannot unload or refund a later ticket',
    'engines.mlx.runtime.load_requests.test.fios current attempted worker eviction retains custody while untouched siblings release',
)


def require(ok, reason):
    if not ok:
        raise RuntimeError(reason)


def packet(tag, body=b''):
    return struct.pack('<II', tag, len(body)) + body


def messages(raw):
    offset = 0
    while offset < len(raw):
        require(len(raw) - offset >= 8, 'truncated test frame header')
        tag, size = struct.unpack_from('<II', raw, offset)
        offset += 8
        require(size <= (1 << 20) and offset + size <= len(raw), 'invalid test frame size')
        yield tag, raw[offset:offset + size]
        offset += size


def main():
    if len(sys.argv) != 4 or sys.argv[1] != '--isolated':
        raise SystemExit('usage: --isolated /private/tmp/.../test REVIEWED_SHA256')
    require(sys.platform == 'darwin' and os.geteuid() != 0, 'requires unprivileged macOS')
    binary, expected = Path(sys.argv[2]), sys.argv[3]
    require(binary.is_absolute() and binary == binary.resolve(strict=True)
            and binary.is_relative_to('/private/tmp') and binary.name == 'test', 'private test path required')
    observed = binary.lstat()
    require(stat.S_ISREG(observed.st_mode) and observed.st_uid == os.geteuid()
            and observed.st_nlink == 1 and not observed.st_mode & 0o022
            and 0 < observed.st_size <= 64 * 1024 * 1024, 'unexpected test executable metadata')
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    require(digest == expected, 'test executable digest mismatch')
    root = Path(tempfile.mkdtemp(prefix='fios-26113-stock-ownership-', dir='/private/tmp'))
    print(f'Retained evidence: {root}', flush=True)
    command = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)',
               str(binary), '--listen=-']

    def call(label, request):
        home = root / str(label)
        home.mkdir(mode=0o700)
        env = {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'XDG_CACHE_HOME': str(home / 'cache'),
               'LANG': 'C', 'LC_ALL': 'C'}
        # The runner is a single process; each selected test gets a fresh
        # process so intentional process-sticky uncertainty cannot leak cases.
        result = subprocess.run(command, input=request + packet(0), capture_output=True, cwd=home,
                                env=env, timeout=8, check=False)
        (home / 'stderr.log').write_bytes(result.stderr)
        require(result.returncode == 0, f'test runner exit {result.returncode}: {label}')
        frames = list(messages(result.stdout))
        require(bool(frames) and frames[0][0] == 0 and frames[0][1].startswith(b'0.17.0'),
                'unexpected Zig test protocol version')
        return frames[1:]

    [(tag, body)] = call('metadata', packet(4))
    require(tag == 3 and len(body) >= 8, 'expected Zig test metadata')
    size, count = struct.unpack_from('<II', body)
    require(1 <= count <= 256 and 8 + 8 * count + size == len(body), 'invalid test metadata')
    strings = body[8 + 8 * count:]
    names = []
    for offset in struct.unpack_from('<' + 'I' * count, body, 8):
        end = strings.find(b'\0', offset)
        require(0 < offset < end, 'invalid test name offset')
        names.append(strings[offset:end].decode())
    require(all(names.count(name) == 1 for name in TESTS), 'missing or ambiguous reviewed test')
    (root / 'names.json').write_text(json.dumps(names, indent=2))
    results = []
    for name in TESTS:
        i = names.index(name)
        frames = call(i, packet(5, struct.pack('<I', i)))
        require([tag for tag, _ in frames] == [5, 4] and frames[0][1] == b'',
                f'missing test start/result: {name}')
        index, flags = struct.unpack('<IQ', frames[1][1])
        require(index == i, 'test result identity mismatch')
        results.append({'name': name, 'status': flags & 3, 'log_errors': (flags >> 3) & ((1 << 30) - 1),
                        'leaks': flags >> 33})
    (root / 'receipt.json').write_text(json.dumps({'binary_sha256': digest, 'listed': count, 'cases': results,
                                                  'network': 'denied', 'model_requests': 0}, indent=2))
    require(all(result['status'] == 0 and result['leaks'] == 0 and result['log_errors'] == 0
                for result in results), 'ownership case failed; see retained receipt')
    print(f'PASS: {len(results)} model-free ownership cases; separate processes; no inference')


if __name__ == '__main__':
    main()
