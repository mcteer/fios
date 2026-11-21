#!/usr/bin/env python3
"""Actual CPU promotion copier custody with a finite scheduling port."""
from pathlib import Path
import argparse, hashlib, json, os, platform, re, subprocess, tempfile

p = argparse.ArgumentParser()
p.add_argument('--isolated', action='store_true', required=True)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--zig', type=Path, required=True)
a = p.parse_args()
assert platform.system() == 'Darwin' and platform.machine() == 'arm64' and os.geteuid() > 0
assert all(x == x.resolve() and str(x).startswith('/private/tmp/') for x in [a.source, a.zig])
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(a.zig) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
root = Path(__file__).resolve().parents[1]
w = Path(tempfile.mkdtemp(prefix='fios-009-stream-copy-check-', dir='/private/tmp'))
env = {'PATH': '/usr/bin:/bin', 'HOME': str(w), 'LANG': 'C', 'LC_ALL': 'C', 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
def output(args):
    return subprocess.check_output(args, env=env, text=True, timeout=20, stderr=subprocess.STDOUT).strip()
assert output(['/usr/bin/git', '--no-replace-objects', '-C', str(a.source), 'rev-parse', 'HEAD']) == '3736ed55f81c6cf0966a0f0dc7265e783655d244'
assert output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version']) == '27.2'
sdk = Path(output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path']))
stub = sdk / 'usr/lib/libc++.1.tbd'
patch = root / 'platform/studio/native/mlx-serve-stream-copy-origins.patch'
parents_file = root / 'platform/studio/native/stream_copy_origin_parents.json'
fixture = root / 'platform/studio/native/stream_copy_origins.zig.fixture'
parents = json.loads(parents_file.read_text())
name = 'src/sdk/weights/streamed/sdk_ext/expert/stream.zig'
assert set(parents) == {name}
source_file = a.source / name
candidate = source_file.read_text()
review = w / 'parent-review'
(review / name).parent.mkdir(parents=True)
(review / name).write_text(candidate)
subprocess.run(['/usr/bin/git', 'apply', '--reverse', str(patch)], cwd=review, env=env, check=True, capture_output=True, timeout=15)
assert sha(review / name) == parents[name]
parent = (review / name).read_text()
subprocess.run(['/usr/bin/git', 'apply', str(patch)], cwd=review, env=env, check=True, capture_output=True, timeout=15)
assert (review / name).read_text() == candidate
assert 'const fios_host = @import("mlx_host");' in candidate
assert 'fios_host.fios_warm_request_owners_enabled else false' in candidate
assert 'fios_host.fios_warm_request_owners else struct {}' in candidate

def block(text, needle):
    assert text.count(needle) == 1
    start = text.index(needle)
    opening = text.index('{', start)
    depth = 0
    for end in range(opening, len(text)):
        if text[end] == '{':
            depth += 1
        elif text[end] == '}':
            depth -= 1
            if depth == 0:
                return text[start:end + 1] + (';' if text[end + 1:end + 2] == ';' else '')
    raise AssertionError(needle)

inputs = {}
pending = ['fios/request_ownership.zig', 'fios/sdk_request_ownership.zig']
while pending:
    n = pending.pop()
    if n in inputs:
        continue
    file = a.source / 'src' / n
    inputs[n] = sha(file)
    for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)', file.read_text()):
        dep = (file.parent / match.group(1)).resolve()
        if dep.exists():
            pending.append(str(dep.relative_to(a.source / 'src')))
fixed = {str(x): sha(x) for x in [source_file, patch, parents_file, fixture, Path(__file__), a.zig, stub]}
receipt = {'scope': 'actual_copier_submit_loop_wait_stop_and_copy_algorithm_with_scheduling_port_real_native_custody_not_native_terminal_proof', 'source': str(a.source), 'native_unit_inputs': inputs, 'fixed_inputs': fixed, 'records': [], 'models': 0, 'inference': False, 'native_authority': False, 'installed': False, 'whole_native_provenance': False}
def save():
    (w / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'directory': str(w), 'models': 0}), flush=True)
for variant, text in [('parent', parent), ('candidate', candidate)]:
    declarations = '\n'.join(block(text, n) for n in ['const Copy = struct', 'const Batch = struct', 'const Copier = struct', 'fn submitCopies(', 'pub fn settleCopies(', 'fn stopCopier('])
    declarations += '\n' + block(text, 'fn copyParallel(').replace('fn copyParallel(', 'fn copyParallelActual(', 1)
    for enabled in [True, False]:
        for mode in ['Debug', 'ReleaseSafe']:
            out = w / (variant + '-' + str(enabled) + '-' + mode)
            unit = out / 'unit'
            unit.mkdir(parents=True)
            for n in inputs:
                target = unit / n
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((a.source / 'src' / n).read_bytes())
            (unit / 'main.zig').write_text(fixture.read_text().replace('// ACTUAL_DECLARATIONS', declarations))
            (unit / 'options.zig').write_text('pub const fios_source_ane=false;\npub const enabled=' + str(enabled).lower() + ';\n')
            binary = out / 'test'
            args = [str(a.zig), 'test', '--test-no-exec', '--test-filter', 'queued stream promotion', '-O' + mode, '-lc', str(stub), '--sysroot', str(sdk), '--dep', 'build_options', '-Mroot=' + str(unit / 'main.zig'), '-Mbuild_options=' + str(unit / 'options.zig'), '-femit-bin=' + str(binary)]
            result = subprocess.run(args, cwd=unit, env=env, capture_output=True, text=True, timeout=120)
            log = out / 'build.log'
            log.write_text(result.stdout + result.stderr)
            receipt['records'].append({'variant': variant, 'enabled': enabled, 'mode': mode, 'stage': 'compile', 'status': result.returncode, 'expected': result.returncode == 0, 'log_sha256': sha(log)})
            save()
            assert result.returncode == 0, log.read_text()
            for scenario in range(3 if enabled else 1):
                try:
                    result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary)], cwd=unit, env={**env, 'FIOS_COPY_SCENARIO': str(scenario)}, capture_output=True, text=True, timeout=8)
                    status, text_output = result.returncode, result.stdout + result.stderr
                except subprocess.TimeoutExpired as e:
                    status = 124
                    text_output = ''.join(x.decode(errors='replace') if isinstance(x, bytes) else x or '' for x in [e.stdout, e.stderr]) + '\nOwn fixture deadline; no native terminal authority\n'
                log = out / (str(scenario) + '.log')
                log.write_text(text_output)
                expected = (status == 1 and 'STREAM_COPY_' in text_output) if variant == 'parent' and enabled else (status == 0 and 'PASS promotion-copy' in text_output and 'All 2 tests passed.' in text_output)
                receipt['records'].append({'variant': variant, 'enabled': enabled, 'mode': mode, 'stage': 'runtime', 'scenario': scenario, 'status': status, 'expected': expected, 'log_sha256': sha(log)})
                save()
                assert expected, text_output
receipt['inputs_unchanged'] = all(sha(a.source / 'src' / n) == h for n, h in inputs.items()) and all(sha(Path(n)) == h for n, h in fixed.items())
save()
assert receipt['inputs_unchanged']
print(json.dumps({'directory': str(w), 'records': len(receipt['records']), 'receipt_sha256': sha(w / 'receipt.json'), 'models': 0, 'native_authority': False}))
