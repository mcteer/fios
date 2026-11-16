#!/usr/bin/env python3
"""Exact registry claimability overlay and actual tracker/registry metadata checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--zig', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
assert sys.platform == 'darwin' and os.getuid() > 0
assert str(args.source).startswith('/private/tmp/') and args.source.resolve() == args.source
sha = lambda data: hashlib.sha256(data).hexdigest()
assert sha(args.zig.read_bytes()) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
work = Path(tempfile.mkdtemp(prefix='fios-009-claimability-', dir='/private/tmp'))
review = work/'review'
review.mkdir(mode=0o700)
parents = json.loads((root/'platform/studio/native/registry_claimability_parents.json').read_text())
inputs = {}
for name in parents:
    data = (args.source/name).read_bytes()
    target = review/name
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.write_bytes(data)
    inputs[name] = sha(data)
patch = (root/'platform/studio/native/mlx-serve-registry-claimability.patch').read_bytes()
(work/'source.patch').write_bytes(patch)
subprocess.run(['/usr/bin/git', 'apply', '--reverse', str(work/'source.patch')], cwd=review, capture_output=True, check=True)
for name, expected in parents.items():
    assert not (review/name).exists() if expected is None else sha((review/name).read_bytes()) == expected
subprocess.run(['/usr/bin/git', 'apply', str(work/'source.patch')], cwd=review, capture_output=True, check=True)
for name in parents:
    assert sha((review/name).read_bytes()) == inputs[name]
unit = work/'unit'
unit.mkdir(mode=0o700)
pending = ['fios/control_protocol.zig', 'fios/current_registry_activity.zig', 'fios/current_registry_claim.zig']
copied = set()
while pending:
    name = pending.pop()
    if name in copied:
        continue
    copied.add(name)
    source = args.source/'src'/name
    assert source.resolve().is_relative_to(args.source/'src')
    data = source.read_bytes()
    inputs['src/'+name] = sha(data)
    target = unit/name
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.write_bytes(data)
    for relative in re.findall(rb'@import\("([^"\n]+\.zig)"\)', data):
        dependency = source.parent/relative.decode()
        if dependency.exists():
            pending.append(str(dependency.resolve().relative_to(args.source/'src')))
fixture = (root/'platform/studio/native/registry_claimability_test.zig.fixture').read_bytes()
(unit/'main.zig').write_bytes(fixture)
(unit/'options.zig').write_text('pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\n')
names = re.findall(r'^test "(fios registry claimability[^"\n]+)"', fixture.decode(), re.M)
assert len(names) == 3
receipt = dict(scope='exact_registry_claimability_overlay_actual_tracker_registry_shaped_metadata_no_native_authority',
               inputs=inputs, parent_projection=parents, patch_sha256=sha(patch), fixture_sha256=sha(fixture),
               runner_sha256=sha(Path(__file__).read_bytes()), models=0, installed=False, activation=False,
               all_client_coverage=False, results=[])
for mode in ['Debug', 'ReleaseSafe']:
    for index, name in enumerate(names):
        home = work/(mode[0]+str(index))
        home.mkdir(mode=0o700)
        env = {'PATH':'/usr/bin:/bin', 'HOME':str(home), 
               'ZIG_GLOBAL_CACHE_DIR':str(work/'cache'), 'DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer',
               'LANG':'C', 'LC_ALL':'C'}
        command = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)',
                   str(args.zig), 'test', '-lc', '-O'+mode, '--test-filter', name, '--dep', 'build_options',
                   '-Mroot='+str(unit/'main.zig'), '-Mbuild_options='+str(unit/'options.zig')]
        result = subprocess.run(command, cwd=work, env=env, capture_output=True, timeout=120)
        output = result.stdout+result.stderr
        (work/(mode+'-'+str(index)+'.log')).write_bytes(output)
        expected = result.returncode == 0 and ('main.test.'+name+'...OK').encode() in output and b'SKIP' not in output
        frames = {}
        for frame_name in ['claimability-native-frame.bin']:
            frame = work/frame_name
            if not frame.exists():
                continue
            data = frame.read_bytes()
            assert len(data) == 67168 and data[:4] == b'FIT9' and data[4] == 4
            saved = work/(mode+'-'+str(index)+'-'+frame_name)
            frame.rename(saved)
            saved.chmod(0o600)
            frames[saved.name] = sha(data)
        if expected and index == 0:
            assert len(frames) == 1
        receipt['results'].append(dict(mode=mode, name=name, status=result.returncode, expected=expected, log_sha256=sha(output), native_frames=frames))
        (work/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
        if not expected:
            print(work)
            print(output.decode(errors='replace')[-4000:])
            raise SystemExit(1)
print(work)
print('PASS six actual tracker/registry claimability stages; no native authority')
