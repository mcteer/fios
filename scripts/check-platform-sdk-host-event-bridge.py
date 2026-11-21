#!/usr/bin/env python3
"""Actual optional native constructor bridge; no native terminal authority."""
from pathlib import Path
import argparse, hashlib, json, os, platform, re, shlex, subprocess, tempfile

p = argparse.ArgumentParser()
p.add_argument('--isolated', action='store_true', required=True)
for name in ['source', 'zig', 'sdk-source', 'sdk-library', 'sdk-stage']:
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--sdk-sha256', required=True)
p.add_argument('--expect-missing-bridge', action='store_true')
p.add_argument('--legacy-sdk-source', type=Path)
a = p.parse_args()
assert platform.system() == 'Darwin' and platform.machine() == 'arm64' and os.geteuid() > 0
source, zig, sdk_source, library = [getattr(a, n) for n in ['source', 'zig', 'sdk_source', 'sdk_library']]
assert all(x == x.resolve() and str(x).startswith('/private/tmp/') for x in [source, zig, sdk_source, library])
def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()
assert sha(zig) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
assert re.fullmatch('[a-f0-9]{64}', a.sdk_sha256) and a.sdk_sha256 == sha(library)
assert a.sdk_stage == a.sdk_stage.resolve() and str(a.sdk_stage).startswith('/private/tmp/')
root = Path(__file__).resolve().parents[1]
cpp = root / 'platform/studio/native/sdk_host_event_bridge_fixture.cpp'
fixture = root / 'platform/studio/native/sdk_host_event_bridge_test.zig.fixture'
w = Path(tempfile.mkdtemp(prefix='fios-009-sdk-host-event-bridge-check-', dir='/private/tmp'))
unit = w / 'unit'
unit.mkdir()
env = {'PATH': '/usr/bin:/bin', 'HOME': str(w), 'LANG': 'C', 'LC_ALL': 'C', 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer', 'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_NOSYSTEM': '1'}
def output(args):
    return subprocess.check_output(args, env=env, text=True, timeout=15, stderr=subprocess.STDOUT).strip()
assert output(['/usr/bin/git', '--no-replace-objects', '-C', str(source), 'rev-parse', 'HEAD']) == '3736ed55f81c6cf0966a0f0dc7265e783655d244'
assert output(['/usr/bin/git', '--no-replace-objects', '-C', str(sdk_source), 'rev-parse', 'HEAD']) == 'c69303b00f5f61860436e832f23fa8c34b96f93a'
assert output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version']) == '27.2'
sdk = Path(output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path']))
stub = sdk / 'usr/lib/libc++.1.tbd'
headers = {str(x.relative_to(sdk_source)): sha(x) for x in (sdk_source / 'mlx').rglob('*.h') if x.is_file()}
inputs = {}
pending = ['fios/request_ownership.zig', 'fios/sdk_request_ownership.zig']
while pending:
    name = pending.pop()
    if name in inputs:
        continue
    file = source / 'src' / name
    data = file.read_bytes()
    inputs[name] = hashlib.sha256(data).hexdigest()
    target = unit / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)', data.decode()):
        dependency = (file.parent / match.group(1)).resolve()
        relative = dependency.relative_to(source / 'src')
        if dependency.exists():
            pending.append(str(relative))
(unit / 'main.zig').write_bytes(fixture.read_bytes())
(unit / 'options.zig').write_text('pub const fios_source_ane=false;\npub const sdk_library=' + json.dumps(str(library)) + ';\n')
patch = root / 'platform/studio/native/mlx-c69303b-host-request-events.patch'
parents_file = root / 'platform/studio/native/sdk_host_event_parents.json'
parents = json.loads(parents_file.read_text())
assert set(parents) == {'mlx/stream.h', 'mlx/stream.cpp', 'mlx/scheduler.cpp', 'mlx/backend/metal/event.cpp'}
projection = {n: sha(sdk_source / n) for n in parents}
review = w / 'source-review'
for n in parents:
    dest = review / n
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes((sdk_source / n).read_bytes())
for reverse in [True, False]:
    subprocess.run(['/usr/bin/git', 'apply'] + (['--reverse'] if reverse else []) + [str(patch)], cwd=review, env=env, check=True, capture_output=True, timeout=15)
    assert all(sha(review / n) == h for n, h in (parents if reverse else projection).items())
native_patches = [root / 'platform/studio/native' / name for name in ['mlx-serve-sdk-host-event-ledger.patch', 'mlx-serve-sdk-host-event-bridge.patch']]
native_parents = [root / 'platform/studio/native' / name for name in ['sdk_host_event_ledger_parents.json', 'sdk_host_event_bridge_parents.json']]
for index, (native_patch, parent_file) in enumerate(zip(native_patches, native_parents)):
    parent_hashes = json.loads(parent_file.read_text())
    expected_name = 'src/fios/' + ('sdk_request_ownership.zig' if index == 0 else 'current_sdk_owners.cpp')
    assert set(parent_hashes) == {expected_name}
    selected = source / expected_name
    if index == 1 and a.expect_missing_bridge:
        assert sha(selected) == parent_hashes[expected_name]
        continue
    review = w / ('native-review-' + str(index))
    destination = review / expected_name
    destination.parent.mkdir(parents=True)
    destination.write_bytes(selected.read_bytes())
    for reverse in [True, False]:
        subprocess.run(['/usr/bin/git', 'apply'] + (['--reverse'] if reverse else []) + [str(native_patch)], cwd=review, env=env, check=True, capture_output=True, timeout=15)
        assert sha(destination) == (parent_hashes[expected_name] if reverse else sha(selected))
bridge = source / 'src/fios/current_sdk_owners.cpp'
inputs['fios/current_sdk_owners.cpp'] = sha(bridge)
(unit / 'source-bridge.cpp').write_bytes(bridge.read_bytes())
fixtures = {str(x.relative_to(root)): sha(x) for x in [cpp, fixture, patch, parents_file, Path(__file__), *native_patches, *native_parents]}
receipt = {'scope': 'actual_optional_native_constructor_to_SDK_CPU_event_receiver_not_native_terminal_proof', 'native_source': str(source), 'native_inputs': inputs, 'SDK_source': str(sdk_source), 'SDK_library_sha256': sha(library), 'SDK_headers': {}, 'SDK_projection': projection, 'fixture_inputs': fixtures, 'sdk': '27.2', 'CXX_stub_sha256': sha(stub), 'clang': output(['/usr/bin/clang++', '--version']), 'records': [], 'expect_missing_bridge': a.expect_missing_bridge, 'model_requests': 0, 'models': 0, 'installed': False, 'native_authority': False, 'whole_native_provenance': False}
def save():
    (w / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
save()
print(json.dumps({'directory': str(w), 'model_requests': 0}), flush=True)
for mode, opt in [('Debug', '-O0'), ('ReleaseSafe', '-O2')]:
    obj, binary, deps = w / (mode + '.o'), w / mode, w / (mode + '.d')
    host_obj = w / (mode + '-bridge.o')
    commands = [('CPP', ['/usr/bin/clang++', '-std=c++20', opt, '-UNDEBUG', '-isysroot', str(sdk), '-I', str(sdk_source), '-MMD', '-MF', str(deps), '-c', str(cpp), '-o', str(obj)], 120), ('Zig', [str(zig), 'test', '--test-no-exec', '--test-filter', 'actual SDK constructor bridge', str(obj), str(host_obj), '-O' + mode, '-lc', str(stub), '--sysroot', str(sdk), str(library), '-rpath', str(library.parent), '-F/System/Library/Frameworks', '-framework', 'Metal', '-framework', 'Foundation', '--dep', 'build_options', '-Mroot=' + str(unit / 'main.zig'), '-Mbuild_options=' + str(unit / 'options.zig'), '-femit-bin=' + str(binary)], 120), ('run', ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary)], 20)]
    commands.insert(0, ('BridgeCPP', ['/usr/bin/clang++', '-std=c++20', opt, '-DNDEBUG', '-isysroot', str(sdk), '-I', str(sdk_source), '-c', str(unit / 'source-bridge.cpp'), '-o', str(host_obj)], 120))
    for stage, args, bound in commands[:3]:
        result = subprocess.run(args, cwd=unit, env=env, capture_output=True, text=True, timeout=bound)
        log = result.stdout + result.stderr
        path = w / (mode + '-' + stage + '.log')
        path.write_text(log)
        expected = result.returncode == 0
        receipt['records'].append({'mode': mode, 'stage': stage, 'status': result.returncode, 'expected': expected, 'log_sha256': sha(path)})
        save()
        assert expected, log
        if stage == 'CPP':
            for name in shlex.split(deps.read_text().replace('\\\n', ' ').split(':', 1)[1]):
                file = Path(name).resolve()
                if file.is_relative_to(sdk_source):
                    relative = str(file.relative_to(sdk_source))
                    assert relative in headers and sha(file) == headers[relative]
                    assert sha(a.sdk_stage / 'include' / relative) == headers[relative], relative
                    receipt['SDK_headers'][relative] = headers[relative]
            assert receipt['SDK_headers']
            save()
    for scenario in range(1):
        try:
            result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary)], cwd=unit, env={**env, 'FIOS_FIXTURE_HOST_EVENT_SCENARIO': str(scenario)}, capture_output=True, text=True, timeout=20)
            status, log = result.returncode, result.stdout + result.stderr
        except subprocess.TimeoutExpired as failure:
            status = 124
            log = ''.join(value.decode(errors='replace') if isinstance(value, bytes) else value or '' for value in [failure.stdout, failure.stderr]) + '\nFixture runtime deadline exceeded\n'
        path = w / (mode + '-scenario-' + str(scenario) + '.log')
        path.write_text(log)
        expected = (status != 0 and status != 124 and 'SDK_HOST_EVENT_BRIDGE_MISSING' in log) if a.expect_missing_bridge else (status == 0 and 'All 2 tests passed.' in log and 'PASS actual SDK constructor' in log)
        receipt['records'].append({'mode': mode, 'stage': 'run', 'scenario': scenario, 'status': status, 'expected': expected, 'log_sha256': sha(path)})
        save()
        assert expected, log
if a.legacy_sdk_source:
    legacy = a.legacy_sdk_source
    assert legacy == legacy.resolve() and str(legacy).startswith('/private/tmp/')
    assert output(['/usr/bin/git', '--no-replace-objects', '-C', str(legacy), 'rev-parse', 'HEAD']) == 'c69303b00f5f61860436e832f23fa8c34b96f93a'
    legacy_header = legacy / 'mlx/stream.h'
    legacy_hash = sha(legacy_header)
    assert legacy_hash == parents['mlx/stream.h']
    for mode, opt in [('Debug', '-O0'), ('ReleaseSafe', '-O2')]:
        obj = w / (mode + '-legacy.o')
        command = ['/usr/bin/clang++', '-std=c++20', opt, '-DNDEBUG', '-isysroot', str(sdk), '-I', str(legacy), '-c', str(unit / 'source-bridge.cpp'), '-o', str(obj)]
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
        log = w / (mode + '-legacy.log')
        log.write_text(result.stdout + result.stderr)
        expected = result.returncode == 0
        undefined = output(['/usr/bin/nm', '-u', str(obj)]) if expected else ''
        expected = expected and '_fios_native_host_request_event_observe' not in undefined
        for name in ['capture', 'enter', 'leave', 'release', 'merge', 'covers_current', 'uncertain']:
            expected = expected and ('_fios_native_request_owners_' + name) in undefined
        receipt['records'].append({'mode': mode, 'stage': 'LegacyBridgeCPP', 'status': result.returncode, 'expected': expected, 'undefined': undefined, 'log_sha256': sha(log)})
        save()
        assert expected and sha(legacy_header) == legacy_hash, log.read_text()
    receipt['legacy_header_sha256'] = legacy_hash
receipt['inputs_unchanged'] = all(sha(source / 'src' / n) == h for n, h in inputs.items()) and all(sha(sdk_source / n) == h for n, h in receipt['SDK_headers'].items()) and all(sha(root / n) == h for n, h in fixtures.items()) and all(sha(sdk_source / n) == h for n, h in projection.items()) and sha(library) == a.sdk_sha256 and sha(stub) == receipt['CXX_stub_sha256']
save()
assert receipt['inputs_unchanged']
print(json.dumps({'directory': str(w), 'records': len(receipt['records']), 'selected_SDK_headers': len(receipt['SDK_headers']), 'receipt_sha256': sha(w / 'receipt.json'), 'model_requests': 0, 'native_authority': False}))
