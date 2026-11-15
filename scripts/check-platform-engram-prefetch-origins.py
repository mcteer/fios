#!/usr/bin/env python3
"""Actual Prefetch methods, real threads, modeled host custody ABI; no native proof."""
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
patch = base / 'mlx-serve-engram-prefetch-origins.patch'
fixture = base / 'engram_prefetch_origins.zig.fixture'
parents_file = base / 'engram_prefetch_origins_parents.json'
parents = json.loads(parents_file.read_text())
paths = re.findall(r'^\+\+\+ b/([^\r\n]+)$', patch.read_text(), re.M)
assert paths == ['src/plugins/deepseek_v41/engram.zig'] and set(parents) == set(paths)
w = Path(tempfile.mkdtemp(prefix='fios-009-engram-origins-check-', dir='/private/tmp'))
parent, unit = w / 'parent', w / 'unit'
inputs = {n: sha(source / n) for n in paths}
dependencies = {n: sha(source / n) for n in ['src/sdk/util/shared.zig', 'src/sdk/util/engram_prefetch_uncertainty.zig', 'src/sdk/util/warm_request_origins.zig']}
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
(unit / 'src/plugins/deepseek_v41').mkdir(parents=True)
(unit / 'src/main.zig').write_text('comptime {_ = @import("plugins/deepseek_v41/check.zig");}')
text = fixture.read_text()
assert text.count('@@PREFETCH@@') == 1
receipt = {'scope': 'actual_Prefetch_methods_real_threads_allocators_and_modeled_host_custody_ABI_not_native_proof', 'source': str(source), 'inputs': inputs, 'dependency_inputs': dependencies, 'fixture_inputs': fixtures, 'records': [], 'model_requests': 0, 'installed': False, 'native_authority': False}
def save():
    (w / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
save()
print(json.dumps({'directory': str(w), 'model_requests': 0}), flush=True)
for old in [True, False]:
    selected = parent if old else source
    full = (selected / paths[0]).read_text()
    start = full.index('pub const Prefetch = struct {')
    end = full.index('\n};', start) + 3
    (unit / 'src/plugins/deepseek_v41/check.zig').write_text(text.replace('@@PREFETCH@@', full[start:end]))
    for mode in ['Debug', 'ReleaseSafe']:
        for owned, name in [(True, 'original request'), (True, 'missing original'), (True, 'entry refusal'), (True, 'restoration refusal'), (True, 'allocation failure'), (False, 'legacy behavior')]:
            (unit / 'options.zig').write_text('pub const fios_source_sdk=' + str(owned).lower() + ';')
            argv = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(zig), 'test', '-O' + mode, '--test-filter', name, '--dep', 'build_options', '-Mroot=' + str(unit / 'src/main.zig'), '-Mbuild_options=' + str(unit / 'options.zig'), '-lc']
            result = subprocess.run(argv, env=env, cwd=unit, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            path = w / ('case-' + str(len(receipt['records'])) + '.log')
            path.write_text(log)
            negative = old and owned and name != 'allocation failure'
            expected = (result.returncode == 1 and 'ENGRAM_' in log and 'FAIL (TestUnexpectedResult)' in log) if negative else result.returncode == 0 and 'All 1 tests passed.' in log
            receipt['records'].append({'parent': old, 'mode': mode, 'owned': owned, 'case': name, 'status': result.returncode, 'negative': negative, 'expected': expected, 'log_sha256': sha(path)})
            save()
            assert expected, log
# Compile the candidate again without modeled C exports. Legacy objects must
# have no native custody dependency; the opted-in object must bind the exact
# genuine host ABI names, rather than copying host ownership globals.
full = (source / paths[0]).read_text()
start = full.index('pub const Prefetch = struct {')
end = full.index('\n};', start) + 3
assert text.count('// MODELED_HOST_ABI_BEGIN') == text.count('// MODELED_HOST_ABI_END') == 1
without = text.split('// MODELED_HOST_ABI_BEGIN')[0] + text.split('// MODELED_HOST_ABI_END')[1]
without = without.replace('@@PREFETCH@@', full[start:end])
without += '\nexport fn fios_fixture_prefetch_object() void {const t=struct{var value=Table{};};const p=Prefetch.start(std.heap.c_allocator,&.{&t.value},&.{.{.at=0,.len=1,.ids=&.{7}}},1,1) catch return;p.finish();}\n'
(unit / 'src/plugins/deepseek_v41/check.zig').write_text(without)
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
