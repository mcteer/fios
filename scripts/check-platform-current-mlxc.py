#!/usr/bin/env python3
"""Finite model-free existing MLX C binding compatibility check."""
from pathlib import Path
import argparse, hashlib, json, os, platform, shlex, subprocess, tempfile
p = argparse.ArgumentParser()
p.add_argument('--isolated', action='store_true', required=True)
p.add_argument('--prefix', type=Path, required=True)
p.add_argument('--mlx-sha256', required=True)
p.add_argument('--mlxc-sha256', required=True)
a = p.parse_args()
assert platform.system() == 'Darwin' and platform.machine() == 'arm64' and os.geteuid() > 0
assert a.prefix == a.prefix.resolve() and str(a.prefix).startswith('/private/tmp/')
assert a.prefix.stat().st_uid == os.geteuid() and not a.prefix.stat().st_mode & 0o022
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
root = Path(__file__).resolve().parents[1]
fixture = root / 'platform/studio/native/current_mlxc_cpu_test.c'
mlx, mlxc = [a.prefix / 'lib' / n for n in ['libmlx.dylib', 'libmlxc.dylib']]
assert sha(mlx) == a.mlx_sha256 and sha(mlxc) == a.mlxc_sha256
w = Path(tempfile.mkdtemp(prefix='fios-009-current-mlxc-check-', dir='/private/tmp'))
env = {'PATH': '/usr/bin:/bin', 'HOME': str(w), 'LANG': 'C', 'LC_ALL': 'C', 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
def output(args):
    return subprocess.check_output(args, env=env, text=True, timeout=20, stderr=subprocess.STDOUT).strip()
assert output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version']) == '27.2'
sdk = Path(output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path']))
cc = Path(output(['/usr/bin/xcrun', '--find', 'clang']))
flags = [str(cc), '-std=c11', '-UNDEBUG', '-target', 'arm64-apple-macosx26.2', '-isysroot', str(sdk), '-I', str(a.prefix / 'include')]
dependency_output = output(flags + ['-M', str(fixture)])
headers = [Path(n) for n in shlex.split(dependency_output.replace('\\\n', ' ').split(':', 1)[1])]
assert len(headers) > 10 and all(n.is_file() for n in headers)
inputs = {str(n): sha(n) for n in set(headers + [fixture, Path(__file__), cc, mlx, mlxc, sdk / 'usr/lib/libSystem.tbd'])}
r = {'scope': 'actual_MLXC_CPU_graph_error_cleanup_selected_C_headers_and_mapped_library_identity_not_native_authority', 'prefix': str(a.prefix), 'inputs': inputs, 'records': [], 'models': 0, 'inference': False, 'GPU_dispatch': False, 'installed': False, 'native_authority': False, 'whole_native_provenance': False}
def save():
    (w / 'receipt.json').write_text(json.dumps(r, indent=2) + '\n')
print(json.dumps({'directory': str(w)}), flush=True)
for mode, optimize in [('Debug', '-O0'), ('Optimized', '-O2')]:
    binary = w / mode
    argv = flags + [optimize, str(fixture), str(mlxc), str(mlx), '-Wl,-rpath,' + str(a.prefix / 'lib'), '-o', str(binary)]
    for stage, args, bound in [('compile', argv, 90), ('runtime', ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary), str(mlx), str(mlxc)], 8)]:
        try:
            result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=bound)
            status, log = result.returncode, result.stdout + result.stderr
        except subprocess.TimeoutExpired as e:
            status = 124
            log = ''.join(v.decode(errors='replace') if isinstance(v, bytes) else v or '' for v in [e.stdout, e.stderr]) + '\nFinite child deadline; no terminal authority\n'
        file = w / (mode + '-' + stage + '.log')
        file.write_text(log)
        passed = status == 0 and (stage == 'compile' or 'PASS actual MLX C CPU graph/error cleanup and mapped library identity' in log)
        r['records'].append({'mode': mode, 'stage': stage, 'arguments': args, 'status': status, 'passed': passed, 'log_sha256': sha(file)})
        save()
        assert passed, log
r['inputs_unchanged'] = all(sha(Path(n)) == h for n, h in inputs.items())
save()
assert r['inputs_unchanged']
print(json.dumps({'directory': str(w), 'receipt_sha256': sha(w / 'receipt.json'), 'stages': len(r['records']), 'models': 0, 'native_authority': False}))
