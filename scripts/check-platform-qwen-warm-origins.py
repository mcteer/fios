#!/usr/bin/env python3
"""Actual Qwen warm methods and fields, real threads, modeled IO/custody ports; no native proof."""
from pathlib import Path
import argparse, hashlib, json, os, platform, re, shutil, subprocess, tempfile

p = argparse.ArgumentParser()
p.add_argument('--isolated', action='store_true', required=True)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--zig', type=Path, required=True)
a = p.parse_args()
assert platform.system() == 'Darwin' and platform.machine() == 'arm64' and os.geteuid() > 0
source, zig = a.source.resolve(), a.zig.resolve()
assert source == a.source and zig == a.zig
assert all(str(x).startswith('/private/tmp/') for x in [source, zig])
sha = lambda x: hashlib.sha256(x.read_bytes()).hexdigest()
assert sha(zig) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
root = Path(__file__).resolve().parents[1]
base = root / 'platform/studio/native'
patch = base / 'mlx-serve-qwen-ngram-warm-origins.patch'
fixture = base / 'qwen_ngram_warm_origins.zig.fixture'
parents_file = base / 'qwen_ngram_warm_origins_parents.json'
parents = json.loads(parents_file.read_text())
paths = re.findall(r'^\+\+\+ b/([^\r\n]+)$', patch.read_text(), re.M)
assert paths == ['src/plugins/qwen4_exp/qwen4_exp.zig'] and set(parents) == set(paths)
w = Path(tempfile.mkdtemp(prefix='fios-009-qwen-warm-origins-check-', dir='/private/tmp'))
parent, unit = w / 'parent', w / 'unit'
inputs = {n: sha(source / n) for n in paths}
dependencies = {n: sha(source / n) for n in ['src/sdk/util/shared.zig', 'src/sdk/util/qwen_ngram_warm_uncertainty.zig', 'src/sdk/util/warm_request_origins.zig']}
fixtures = {str(x.relative_to(root)): sha(x) for x in [patch, fixture, parents_file, Path(__file__)]}
env = {'PATH': '/usr/bin:/bin', 'HOME': str(w), 'LANG': 'C', 'LC_ALL': 'C', 'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_NOSYSTEM': '1', 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
assert subprocess.check_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version'], env=env, text=True, timeout=15).strip() == '27.2'
assert subprocess.check_output(['/usr/bin/git', '--no-replace-objects', '-C', str(source), 'rev-parse', 'HEAD'], env=env, text=True).strip() == '3736ed55f81c6cf0966a0f0dc7265e783655d244'
for n in paths:
    target = parent / n
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / n, target)
for reverse in [True, False, True]:
    subprocess.run(['/usr/bin/git', 'apply'] + (['--reverse'] if reverse else []) + [str(patch)], cwd=parent, env=env, check=True, capture_output=True, timeout=15)
    assert all(sha(parent / n) == h for n, h in (parents if reverse else inputs).items())
for n in dependencies:
    target = unit / n
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / n, target)
(unit / 'src/plugins/qwen4_exp').mkdir(parents=True)
(unit / 'src/main.zig').write_text('comptime {_ = @import("plugins/qwen4_exp/check.zig");}')
text = fixture.read_text()
assert all(text.count(marker) == 1 for marker in ['@@WARM_FIELDS@@', '@@WARM_CHUNK@@', '@@METHODS@@'])
def method(full, name):
    start = full.index('fn ' + name + '(')
    start = full.rfind('\n', 0, start) + 1
    opening, depth = full.index('{', start), 0
    for index in range(opening, len(full)):
        if full[index] == '{':
            depth += 1
        elif full[index] == '}':
            depth -= 1
            if depth == 0:
                return full[start:index + 1]
    raise AssertionError('unbalanced method')
def render(selected, template):
    full = (selected / paths[0]).read_text()
    start = full.index('    warm_thread: ?std.Thread')
    end = full.index('    /// Set once', start)
    chunk = next(line for line in full.splitlines() if 'const WARM_CHUNK:' in line)
    return template.replace('@@WARM_FIELDS@@', full[start:end]).replace('@@WARM_CHUNK@@', chunk).replace('@@METHODS@@', '\n'.join(method(full, name) for name in ['warmRegion', 'startWarm', 'warmMain', 'close']))

receipt = {'scope': 'actual_Qwen_warm_fields_and_methods_real_threads_modeled_IO_custody_and_resource_ports_not_native_proof', 'source': str(source), 'inputs': inputs, 'dependency_inputs': dependencies, 'fixture_inputs': fixtures, 'records': [], 'model_requests': 0, 'installed': False, 'native_authority': False}
def save():
    (w / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
save()
print(json.dumps({'directory': str(w), 'model_requests': 0}), flush=True)
for old in [True, False]:
    selected = parent if old else source
    (unit / 'src/plugins/qwen4_exp/check.zig').write_text(render(selected, text))
    for mode in ['Debug', 'ReleaseSafe']:
        for owned, name in [(True, 'original group'), (True, 'missing original'), (True, 'entry refusal'), (True, 'restoration refusal'), (True, 'absent region'), (True, 'disabled warm'), (False, 'legacy warm'), (False, 'repeat warm')]:
            (unit / 'options.zig').write_text('pub const fios_source_sdk=' + str(owned).lower() + ';')
            argv = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(zig), 'test', '-O' + mode, '--test-filter', name, '--dep', 'build_options', '-Mroot=' + str(unit / 'src/main.zig'), '-Mbuild_options=' + str(unit / 'options.zig'), '-lc']
            result = subprocess.run(argv, env=env, cwd=unit, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            path = w / ('case-' + str(len(receipt['records'])) + '.log')
            path.write_text(log)
            negative = old and name in ['original group', 'missing original', 'entry refusal', 'restoration refusal']
            expected = (result.returncode == 1 and 'QWEN_' in log and 'FAIL (TestUnexpectedResult)' in log) if negative else result.returncode == 0 and 'All 1 tests passed.' in log
            receipt['records'].append({'parent': old, 'mode': mode, 'owned': owned, 'case': name, 'status': result.returncode, 'negative': negative, 'expected': expected, 'log_sha256': sha(path)})
            save()
            assert expected, log
# Compile the candidate again without modeled C exports. Legacy objects must
# have no native custody dependency; the opted-in object must bind the exact
# genuine host ABI names, rather than copying host ownership globals.
assert text.count('// MODELED_HOST_ABI_BEGIN') == text.count('// MODELED_HOST_ABI_END') == 1
without = text.split('// MODELED_HOST_ABI_BEGIN')[0] + text.split('// MODELED_HOST_ABI_END')[1]
without = render(source, without)
without += '\nexport fn fios_fixture_qwen_warm_object() void {var table=NgramTable{.map=&bytes};table.startWarm();table.close();}\n'
(unit / 'src/plugins/qwen4_exp/check.zig').write_text(without)
for mode in ['Debug', 'ReleaseSafe']:
    for owned in [False, True]:
        (unit / 'options.zig').write_text('pub const fios_source_sdk=' + str(owned).lower() + ';')
        obj = w / (mode + '-' + str(owned) + '.o')
        argv = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(zig), 'build-obj', '-O' + mode, '--dep', 'build_options', '-Mroot=' + str(unit / 'src/main.zig'), '-Mbuild_options=' + str(unit / 'options.zig'), '-lc', '-femit-bin=' + str(obj)]
        result = subprocess.run(argv, env=env, cwd=unit, capture_output=True, text=True, timeout=60)
        log = result.stdout + result.stderr
        path = w / ('object-' + mode + '-' + str(owned) + '.log')
        path.write_text(log)
        assert result.returncode == 0, log
        symbols = subprocess.check_output(['/usr/bin/nm', '-u', str(obj)], env=env, text=True, timeout=15)
        selected = sorted(line.split()[-1] for line in symbols.splitlines() if line.split() and line.split()[-1].startswith('_fios_native_request_owners_'))
        expected = sorted('_fios_native_request_owners_' + n for n in ['capture', 'enter', 'leave', 'release', 'uncertain']) if owned else []
        assert selected == expected, selected
        receipt['records'].append({'stage': 'unbound_object', 'mode': mode, 'owned': owned, 'status': 0, 'expected': True, 'symbols': selected, 'object_sha256': sha(obj), 'log_sha256': sha(path)})
        save()
receipt['inputs_unchanged'] = all(sha(source / n) == h for n, h in {**inputs, **dependencies}.items()) and all(sha(root / n) == h for n, h in fixtures.items())
save()
assert receipt['inputs_unchanged']
print(json.dumps({'directory': str(w), 'records': len(receipt['records']), 'receipt_sha256': sha(w / 'receipt.json'), 'native_authority': False}))
