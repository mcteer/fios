#!/usr/bin/env python3
"""Finite actual-tracker lease tests; no installed service or model execution."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--zig', type=Path, required=True)
parser.add_argument('--review-only', action='store_true')
parser.add_argument('--protocol', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
assert os.getuid() != 0
assert str(args.source).startswith('/private/tmp/') and args.source.resolve() == args.source
assert args.zig.is_file()
sha = lambda data: hashlib.sha256(data).hexdigest()
assert sha(args.zig.read_bytes()) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
work = Path(tempfile.mkdtemp(prefix='fios-009-preparation-leases-', dir='/private/tmp'))
inputs = {}
# Reverse/reapply only the two declared files; this is a parent projection,
# never whole-native provenance or installed enrollment.
parents = json.loads((root/'platform/studio/native/preparation_leases_parents.json').read_text())
review = work/'review'
review.mkdir(mode=0o700)
for name in parents:
    data = (args.source/name).read_bytes()
    target = review/name
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.write_bytes(data)
    inputs[name] = sha(data)
patch = (root/'platform/studio/native/mlx-serve-preparation-leases.patch').read_bytes()
(work/'source.patch').write_bytes(patch)
subprocess.run(['/usr/bin/git', 'apply', '--reverse', str(work/'source.patch')], cwd=review, check=True, capture_output=True)
for name, expected in parents.items():
    assert not (review/name).exists() if expected is None else sha((review/name).read_bytes()) == expected
subprocess.run(['/usr/bin/git', 'apply', str(work/'source.patch')], cwd=review, check=True, capture_output=True)
for name in parents:
    assert sha((review/name).read_bytes()) == inputs[name]
assert (args.source/'src/fios/preparation_leases.zig').read_bytes() == (root/'platform/studio/native/preparation_leases.zig').read_bytes()
inputs['patch'] = sha(patch)
pending = ['fios/request_ownership.zig', 'fios/current_registry_claim.zig']
if args.protocol:
    pending.append('fios/control_protocol.zig')
while pending:
    name = pending.pop()
    if name in inputs:
        continue
    source = args.source / 'src' / name
    assert source.resolve().is_relative_to(args.source / 'src')
    data = source.read_bytes()
    inputs[name] = sha(data)
    target = work / name
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.write_bytes(data)
    for relative in re.findall(rb'@import\("([^"\n]+\.zig)"\)', data):
        dependency = source.parent / relative.decode()
        if dependency.exists():
            pending.append(str(dependency.resolve().relative_to(args.source / 'src')))
files = [('preparation_leases.zig', 'fios/preparation_leases.zig')]
if args.protocol:
    files += [('preparation_protocol.zig', 'fios/preparation_protocol.zig'), ('preparation_protocol_test.zig.fixture', 'main.zig')]
else:
    files += [('preparation_leases_test.zig.fixture', 'main.zig')]
for name, destination in files:
    data = (root / 'platform/studio/native' / name).read_bytes()
    inputs[name] = sha(data)
    (work / destination).write_bytes(data)
(work / 'options.zig').write_text('pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\n')
receipt = dict(scope='actual_tracker_registry_helper_with_fixture_registry_and_proposed_codec_no_native_authority' if args.protocol else 'actual_tracker_registry_helper_with_fixture_registry_no_native_authority', inputs=inputs,
               runner_sha256=sha(Path(__file__).read_bytes()), models=0, installed=False, activation=False, all_client_coverage=False, results=[])
prefix = 'preparation protocol' if args.protocol else 'preparation lease'
names = re.findall(r'^test "('+prefix+r'[^"\n]+)"', (work/'main.zig').read_text(), re.M)
assert len(names) == (3 if args.protocol else 6)
if args.review_only:
    (work/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(work)
    print('PASS declared two-file projection only; compiler tests not run')
    raise SystemExit(0)
for mode, name in [(mode, name) for mode in ['Debug', 'ReleaseSafe'] for name in names]:
    command = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(args.zig), 'test', '-lc', '-O'+mode, '--test-filter', name,
               '--dep', 'build_options', '-Mroot='+str(work/'main.zig'), '-Mbuild_options='+str(work/'options.zig')]
    result = subprocess.run(command, cwd=work, capture_output=True, timeout=120)
    output = result.stdout + result.stderr
    (work / (mode+'-'+str(names.index(name))+'.log')).write_bytes(output)
    expected = result.returncode == 0 and ('main.test.'+name+'...OK').encode() in output and b'All 2 tests passed.' in output and b'SKIP' not in output
    receipt['results'].append(dict(mode=mode, name=name, status=result.returncode, expected=expected, log_sha256=sha(output)))
    (work/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    if not expected:
        print(work)
        print(output.decode(errors='replace')[-4000:])
        raise SystemExit(1)
print(work)
print('PASS Debug/ReleaseSafe preparation '+('protocol' if args.protocol else 'lease')+' tests; no native authority')
