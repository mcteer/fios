#!/usr/bin/env python3
"""Current warm-worker CPU trace and real host custody ABI; no model/GPU work."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--isolated', action='store_true', required=True)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--zig', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source, zig = args.source.resolve(), args.zig.resolve()
assert platform.system() == 'Darwin' and platform.machine() == 'arm64' and os.geteuid() > 0
assert source == args.source and zig == args.zig
assert str(source).startswith('/private/tmp/') and str(zig).startswith('/private/tmp/')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(zig) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
scratch = Path(tempfile.mkdtemp(prefix='fios-009-current-warm-origins-check-', dir='/private/tmp'))
env = {'PATH': '/usr/bin:/bin', 'HOME': str(scratch), 'LANG': 'C', 'LC_ALL': 'C',
       'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
       'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_SYSTEM': '/dev/null',
       'GIT_CONFIG_NOSYSTEM': '1'}

def run(argv, cwd=scratch, timeout=30):
    return subprocess.check_output(argv, cwd=cwd, env=env, text=True, timeout=timeout,
                                   stderr=subprocess.STDOUT)

assert run(['git', '--no-replace-objects', '-c', 'core.fsmonitor=false', '-C', str(source),
            'rev-parse', 'HEAD']).strip() == '3736ed55f81c6cf0966a0f0dc7265e783655d244'
assert run(['xcrun', '--sdk', 'macosx', '--show-sdk-version']).strip() == '27.2'
frameworks = run(['xcrun', '--sdk', 'macosx', '--show-sdk-path']).strip() + '/System/Library/Frameworks'
fixture = root / 'platform/studio/native/current_streamed_warm_origins.zig.fixture'
recipe = root / 'platform/studio/native/current_streamed_warm_compile_args.json'
parents_file = root / 'platform/studio/native/current_streamed_warm_parents.json'
patch = root / 'platform/studio/native/mlx-serve-current-streamed-warm-origins.patch'
parents = json.loads(parents_file.read_text())
paths = re.findall(r'^\+\+\+ b/([^\r\n]+)$', patch.read_text(), re.M)
assert len(paths) == 10 and set(parents) < set(paths)
assert set(paths) - set(parents) == {'src/sdk/util/warm_request_origins.zig'}
for name in paths:
    stat = (source / name).lstat()
    assert (source / name).is_file() and not (source / name).is_symlink()
    assert stat.st_uid == os.geteuid() and stat.st_nlink == 1 and stat.st_mode & 0o022 == 0
inputs = {name: sha(source / name) for name in paths}
declared = {str(p.relative_to(root)): sha(p) for p in [fixture, recipe, parents_file, patch, Path(__file__)]}
unit = scratch / 'unit'
shutil.copytree(source / 'src', unit / 'src')
run(['git', 'apply', '--reverse', str(patch)], unit)
assert all(sha(unit / name) == digest for name, digest in parents.items())
baseline = (unit / 'src/sdk/weights/streamed/mimo/gpu_warm.zig').read_bytes()
run(['git', 'apply', str(patch)], unit)
assert all(sha(unit / name) == digest for name, digest in inputs.items())
candidate = (unit / 'src/sdk/weights/streamed/mimo/gpu_warm.zig').read_bytes()
options = next(p for p in (source / '.zig-cache/o').glob('*/options.zig')
               if 'fios_source_sdk' in p.read_text())
options_text = options.read_text()
for flag in ['fios_source_ane', 'fios_source_sdk', 'fios_source_ds4']:
    options_text = re.sub(r'(pub const ' + flag + r': bool = )true;', r'\g<1>false;', options_text)
(unit / 'src/fios-prototype-options.zig').write_text(options_text)
host = (unit / 'src/plugin_host.zig').read_text()
host = host.replace('pub const fios_warm_request_owners_enabled = @import("build_options").fios_source_sdk;',
                    'pub const fios_warm_request_owners_enabled = true;')
host += '\npub const plugin_profile=false;\npub const fio_tracker=@import("fios/request_ownership.zig");\npub const fio_sdk=@import("fios/sdk_request_ownership.zig");\n'
assert host.count('pub const fios_warm_request_owners_enabled = true;') == 1
(unit / 'src/fios-prototype-warm-host.zig').write_text(host)
legacy = '\n'.join(line for line in host.splitlines()
                   if not line.startswith('pub const fios_warm_request_owners')) + '\n'
(unit / 'src/fios-prototype-warm-legacy-host.zig').write_text(legacy)
(unit / 'src/fios-prototype-warm-origins.zig').write_bytes(fixture.read_bytes())
mapping = {'$SOURCE': str(source), '$ZIG_LIB': str(zig.parent / 'lib') + '/',
           '$ZIG': str(zig), '$CACHE': str(scratch / 'cache'), '$FRAMEWORKS': frameworks}
argv = json.loads(recipe.read_text())
for key, value in mapping.items():
    argv = [entry.replace(key, value) for entry in argv]
assert not any('$' in entry for entry in argv)
target = unit / 'src/sdk/weights/streamed/mimo/gpu_warm.zig'
receipt = {'scope': 'actual_current_warm_CPU_trace_host_ABI_and_SDK_bindings_not_native_proof',
           'directory': str(scratch), 'source': str(source), 'inputs': inputs,
           'fixture_inputs': declared, 'baseline_ABI_injected_for_isolation': True,
           'results': [], 'model_requests': 0, 'native_authority': False, 'installed': False}
save = lambda: (scratch / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
save()
print(json.dumps({'directory': str(scratch), 'model_requests': 0}), flush=True)
cases = [('original roots survive caller release', 'WARM_SOURCE_ORIGINS_DROPPED'),
         ('missing original refuses before CPU backend', 'WARM_SOURCE_MISSING_ORIGIN_SUBMITTED'),
         ('independent uncertainty survives local retirement', 'WARM_UNKNOWN_ROOT_LOST'),
         ('legacy CPU trace remains unchanged', None)]
try:
    for mode in ['Debug', 'ReleaseSafe']:
        for parent in [True, False]:
            target.write_bytes(baseline if parent else candidate)
            for suffix, marker in cases:
                command = [('-O' + mode if entry == '-Osafe' else entry) for entry in argv]
                command[command.index('--test-filter') + 1] = 'fios prototype warm ' + suffix
                if marker is None:
                    command = [entry.replace('-Mmlx_host=src/fios-prototype-warm-host.zig',
                                             '-Mmlx_host=src/fios-prototype-warm-legacy-host.zig')
                               for entry in command]
                path = scratch / ('case-' + str(len(receipt['results'])) + '.log')
                start = time.monotonic()
                with path.open('w') as log:
                    child = subprocess.Popen(['/usr/bin/sandbox-exec', '-p',
                                              '(version 1)(allow default)(deny network*)'] + command,
                                             cwd=unit, env=env, stdout=log, stderr=subprocess.STDOUT,
                                             start_new_session=True)
                    try:
                        status = child.wait(timeout=120)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
                        status = 124
                text = path.read_text()
                negative = parent and marker is not None
                expected = (status == 1 and marker in text and 'FAIL (TestUnexpectedResult)' in text
                            and re.search(r'^[0-9]+ passed; 0 skipped; 1 failed\.$', text, re.M)
                            if negative else status == 0 and 'All 1 tests passed.' in text)
                receipt['results'].append({'mode': mode, 'parent': parent, 'case': suffix,
                                           'status': status, 'negative': negative, 'expected': bool(expected),
                                           'elapsed_seconds': round(time.monotonic()-start, 3),
                                           'log_sha256': sha(path)})
                save()
                assert expected, str(path)
finally:
    target.write_bytes(candidate)
receipt['inputs_unchanged'] = all(sha(source/name) == digest for name, digest in inputs.items())
receipt['fixture_inputs_unchanged'] = all(sha(root/name) == digest for name, digest in declared.items())
save()
assert receipt['inputs_unchanged'] and receipt['fixture_inputs_unchanged']
print(json.dumps({'directory': str(scratch), 'cases': len(receipt['results']),
                  'receipt_sha256': sha(scratch/'receipt.json'), 'native_authority': False}))
