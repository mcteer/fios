#!/usr/bin/env python3
"""Genuine non-model CPU graph and native custody; no native terminal authority."""
from pathlib import Path
import argparse, hashlib, json, os, platform, re, shlex, subprocess, tempfile

p = argparse.ArgumentParser()
p.add_argument('--isolated', action='store_true', required=True)
for name in ['source', 'zig', 'sdk-source', 'sdk-library']:
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--sdk-sha256', required=True)
a = p.parse_args()
assert platform.system() == 'Darwin' and platform.machine() == 'arm64' and os.geteuid() > 0
source, zig, sdk_source, library = [getattr(a, n) for n in ['source', 'zig', 'sdk_source', 'sdk_library']]
assert all(x == x.resolve() and str(x).startswith('/private/tmp/') for x in [source, zig, sdk_source, library])
def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()
assert sha(zig) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
assert a.sdk_sha256 == 'b1ab22fad4048da5837007cbdd8af55f228786373e67e2fa7d31a910ffba705b' == sha(library)
root = Path(__file__).resolve().parents[1]
cpp = root / 'platform/studio/native/sdk_cpu_graph_fixture.cpp'
fixture = root / 'platform/studio/native/sdk_cpu_graph_test.zig.fixture'
w = Path(tempfile.mkdtemp(prefix='fios-009-sdk-cpu-graph-check-', dir='/private/tmp'))
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
fixtures = {str(x.relative_to(root)): sha(x) for x in [cpp, fixture, Path(__file__)]}
receipt = {'scope': 'actual_non_model_CPU_array_graph_and_native_custody_not_native_terminal_proof', 'native_source': str(source), 'native_inputs': inputs, 'SDK_source': str(sdk_source), 'SDK_library_sha256': sha(library), 'SDK_headers': {}, 'fixture_inputs': fixtures, 'sdk': '27.2', 'CXX_stub_sha256': sha(stub), 'clang': output(['/usr/bin/clang++', '--version']), 'records': [], 'model_requests': 0, 'models': 0, 'installed': False, 'native_authority': False, 'whole_native_provenance': False}
def save():
    (w / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
save()
print(json.dumps({'directory': str(w), 'model_requests': 0}), flush=True)
for mode, opt in [('Debug', '-O0'), ('ReleaseSafe', '-O2')]:
    obj, binary, deps = w / (mode + '.o'), w / mode, w / (mode + '.d')
    commands = [('CPP', ['/usr/bin/clang++', '-std=c++20', opt, '-UNDEBUG', '-isysroot', str(sdk), '-I', str(sdk_source), '-MMD', '-MF', str(deps), '-c', str(cpp), '-o', str(obj)], 120), ('Zig', [str(zig), 'test', '--test-no-exec', '--test-filter', 'normal non-model CPU graph', str(obj), '-O' + mode, '-lc', str(stub), '--sysroot', str(sdk), str(library), '-rpath', str(library.parent), '-F/System/Library/Frameworks', '-framework', 'Metal', '-framework', 'Foundation', '--dep', 'build_options', '-Mroot=' + str(unit / 'main.zig'), '-Mbuild_options=' + str(unit / 'options.zig'), '-femit-bin=' + str(binary)], 120), ('run', ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary)], 20)]
    for stage, args, bound in commands:
        result = subprocess.run(args, cwd=unit, env=env, capture_output=True, text=True, timeout=bound)
        log = result.stdout + result.stderr
        path = w / (mode + '-' + stage + '.log')
        path.write_text(log)
        expected = result.returncode == 0 and (stage != 'run' or 'normal non-model CPU graph' in log and 'All 2 tests passed.' in log and 'contexts=0 roots=0 SDK_uncertain=false source_uncertain=false' in log)
        receipt['records'].append({'mode': mode, 'stage': stage, 'status': result.returncode, 'expected': expected, 'log_sha256': sha(path)})
        save()
        assert expected, log
        if stage == 'CPP':
            for name in shlex.split(deps.read_text().replace('\\\n', ' ').split(':', 1)[1]):
                file = Path(name).resolve()
                if file.is_relative_to(sdk_source):
                    relative = str(file.relative_to(sdk_source))
                    assert relative in headers and sha(file) == headers[relative]
                    assert sha(source / 'lib/mlx/include' / relative) == headers[relative], relative
                    receipt['SDK_headers'][relative] = headers[relative]
            assert receipt['SDK_headers']
            save()
receipt['inputs_unchanged'] = all(sha(source / 'src' / n) == h for n, h in inputs.items()) and all(sha(sdk_source / n) == h for n, h in receipt['SDK_headers'].items()) and all(sha(root / n) == h for n, h in fixtures.items()) and sha(library) == a.sdk_sha256 and sha(stub) == receipt['CXX_stub_sha256']
save()
assert receipt['inputs_unchanged']
print(json.dumps({'directory': str(w), 'records': len(receipt['records']), 'selected_SDK_headers': len(receipt['SDK_headers']), 'receipt_sha256': sha(w / 'receipt.json'), 'model_requests': 0, 'native_authority': False}))
