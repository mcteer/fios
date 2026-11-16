#!/usr/bin/env python3
"""Exact CPU reference-history closure; no native inference proof or authority."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument('--source', type=Path, required=True)
p.add_argument('--zig', type=Path, required=True)
p.add_argument('--expect-missing', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
assert os.getuid() != 0
assert a.source.resolve() == a.source and str(a.source).startswith('/private/tmp/')
sha = lambda b: hashlib.sha256(b).hexdigest()
assert sha(a.zig.read_bytes()) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
work = Path(tempfile.mkdtemp(prefix='fios-009-pristine-preparation-check-', dir='/private/tmp'))
parents_path = root/'platform/studio/native/pristine_preparation_parents.json'
patch_path = root/'platform/studio/native/mlx-serve-pristine-preparation.patch'
parents = json.loads(parents_path.read_text())
patch = patch_path.read_bytes()
inputs = {}
projection = work/'projection'
for name, expected in parents.items():
    data = (a.source/name).read_bytes()
    inputs[name] = sha(data)
    target = projection/name
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.write_bytes(data)
    if a.expect_missing:
        assert sha(data) == expected
if not a.expect_missing:
    applied = work/'source.patch'
    applied.write_bytes(patch)
    subprocess.run(['/usr/bin/git', 'apply', '--reverse', str(applied)], cwd=projection, check=True, capture_output=True)
    for name, expected in parents.items():
        assert sha((projection/name).read_bytes()) == expected
    subprocess.run(['/usr/bin/git', 'apply', str(applied)], cwd=projection, check=True, capture_output=True)
    for name in parents:
        assert sha((projection/name).read_bytes()) == inputs[name]

pending = ['fios/request_ownership.zig', 'fios/preparation_leases.zig', 'fios/preparation_protocol.zig']
while pending:
    name = pending.pop()
    key = 'src/'+name
    if (work/name).exists():
        continue
    original = a.source/'src'/name
    assert original.resolve().is_relative_to(a.source/'src')
    data = original.read_bytes()
    inputs[key] = sha(data)
    target = work/name
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.write_bytes(data)
    for match in re.findall(rb'@import\("([^"\n]+\.zig)"\)', data):
        dependency = original.parent/match.decode()
        if dependency.exists():
            pending.append(str(dependency.resolve().relative_to(a.source/'src')))
fixture_path = root/'platform/studio/native/pristine_preparation_test.zig.fixture'
fixture = fixture_path.read_bytes()
legacy_path = root/'platform/studio/native/preparation_protocol_test.zig.fixture'
legacy = legacy_path.read_bytes()
(work/'legacy_preparation_protocol.zig').write_bytes(legacy)
(work/'main.zig').write_bytes(fixture+b'\ncomptime { _ = @import("legacy_preparation_protocol.zig"); }\n')
(work/'options.zig').write_text('pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\n')
names = re.findall(r'^test "(pristine preparation[^"\n]+)"', fixture.decode(), re.M)
assert len(names) == 9
legacy_names = re.findall(r'^test "(preparation protocol[^"\n]+)"', legacy.decode(), re.M)
assert len(legacy_names) == 3
names += legacy_names
receipt = dict(scope='atomic_never_shared_CPU_preparation_close_not_native_proof',
               inputs=inputs, fixture_sha256=sha(fixture), patch_sha256=sha(patch),
               legacy_fixture_sha256=sha(legacy), parents_sha256=sha(parents_path.read_bytes()), runner_sha256=sha(Path(__file__).read_bytes()),
               models=0, inference=False, native_authority=False, all_client_coverage=False,
               expected_interface_absence=a.expect_missing, results=[])
env = dict(PATH='/usr/bin:/bin', HOME=str(work), LANG='C', LC_ALL='C')
for mode in ['Debug', 'ReleaseSafe']:
    for index, name in enumerate(names[:1] if a.expect_missing else names):
        command = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(a.zig),
                   'test', '-lc', '-O'+mode, '--test-filter', name, '--dep', 'build_options',
                   '-Mroot='+str(work/'main.zig'), '-Mbuild_options='+str(work/'options.zig')]
        result = subprocess.run(command, cwd=work, env=env, capture_output=True, timeout=120)
        output = result.stdout+result.stderr
        expected = (result.returncode != 0 and b'PRISTINE_PREPARATION_INTERFACE_ABSENT' in output) if a.expect_missing else (
            result.returncode == 0 and ('.test.'+name+'...OK').encode() in output and b'All 2 tests passed.' in output and b'SKIP' not in output)
        (work/(mode+'-'+str(index)+'.log')).write_bytes(output)
        frames = {}
        frame = work/'pristine-native-close.bin'
        if frame.exists():
            data = frame.read_bytes()
            assert len(data) == 88 and data[:7] == b'FIV9\x02\x00\x03'
            saved = work/(mode+'-pristine-native-close.bin')
            frame.rename(saved)
            saved.chmod(0o600)
            frames[saved.name] = sha(data)
        if expected and not a.expect_missing and name.endswith('enabled callback'):
            assert len(frames) == 1
        receipt['results'].append(dict(mode=mode, name=name, status=result.returncode, expected=expected, log_sha256=sha(output), native_frames=frames))
        (work/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
        if not expected:
            print(work)
            print(output.decode(errors='replace')[-3500:])
            raise SystemExit(1)
for name, expected in inputs.items():
    assert sha((a.source/name).read_bytes()) == expected
assert fixture_path.read_bytes() == fixture and legacy_path.read_bytes() == legacy and patch_path.read_bytes() == patch
assert sha(parents_path.read_bytes()) == receipt['parents_sha256']
assert sha(Path(__file__).read_bytes()) == receipt['runner_sha256']
receipt['inputs_unchanged'] = True
(work/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
print(json.dumps(dict(directory=str(work), receipt_sha256=sha((work/'receipt.json').read_bytes()), passed=len(receipt['results']), native_authority=False)))
