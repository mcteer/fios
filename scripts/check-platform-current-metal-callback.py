#!/usr/bin/env python3
"""CPU callback-scope controls; no Metal objects, backend/model or native authority."""
import argparse
import difflib
import hashlib
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PIN = 'c69303b00f5f61860436e832f23fa8c34b96f93a'
PATHS = ['mlx/backend/cpu/eval.cpp', 'mlx/backend/metal/device.cpp', 'mlx/backend/metal/device.h',
         'mlx/backend/metal/eval.cpp', 'mlx/scheduler.cpp', 'mlx/stream.cpp', 'mlx/stream.h']

def sha(data):
    return hashlib.sha256(data).hexdigest()

def helper(text):
    begin = text.index('template <class Work, class Cleanup>')
    return text[begin:text.index('\n\n\nconst std::string& metal_gpu_arch()', begin)]

def mock():
    assert platform.python_implementation() == 'CPython' and sys.version_info[:3] == (3, 11, 17)
    assert platform.system() == 'Darwin' and os.getuid() > 0
    directory = pathlib.Path(tempfile.mkdtemp(prefix='fios-009-metal-callback-mock-', dir='/private/tmp'))
    print(json.dumps({'directory': str(directory)}), flush=True)
    env = {'PATH': '/usr/bin:/bin', 'HOME': str(directory), 'LANG': 'C', 'LC_ALL': 'C'}
    if os.environ.get('DEVELOPER_DIR'):
        env['DEVELOPER_DIR'] = os.environ['DEVELOPER_DIR']
    cxx = subprocess.check_output(['/usr/bin/xcrun', '--find', 'clang++'], env=env, timeout=15).decode().strip()
    sdk = subprocess.check_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'], env=env, timeout=15).decode().strip()
    base = ROOT / 'platform/studio/native'
    fixture = (base / 'current_mlx_metal_callback_control.cpp.fixture').read_bytes()
    variants = {name: (base / ('current_mlx_metal_callback_' + suffix + '.inc')).read_bytes()
                for name, suffix in [('baseline', 'previous'), ('current', 'scope')]}
    results = []
    for name, body in variants.items():
        unit = fixture.decode().replace('// FIOS_GENUINE_CALLBACK_HELPER', body.decode())
        file = directory / (name + '.cpp')
        file.write_text(unit)
        for optimization in ['-O0', '-O2']:
            binary = directory / (name + optimization)
            r = subprocess.run([cxx, '-std=c++17', '-isysroot', sdk, optimization, str(file), '-o', str(binary)], env=env, capture_output=True, timeout=30)
            (directory / (name + optimization + '-build.log')).write_bytes(r.stdout + r.stderr)
            assert r.returncode == 0
            for case in ['healthy', 'work-error', 'nonstd-error', 'preexisting-error', 'cleanup-error', 'work-and-cleanup-error']:
                r = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary), case],
                                   env=env, capture_output=True, timeout=5)
                log = r.stdout + r.stderr
                (directory / (name + optimization + '-' + case + '.log')).write_bytes(log)
                expected = 77 if name == 'baseline' and case != 'healthy' else 0
                assert r.returncode == expected
                if expected:
                    assert b'FIO_METAL_' in log
                results.append({'variant': name, 'optimization': optimization, 'case': case, 'status': r.returncode, 'expected': expected})
    assert fixture == (base / 'current_mlx_metal_callback_control.cpp.fixture').read_bytes()
    assert variants['baseline'] == (base / 'current_mlx_metal_callback_previous.inc').read_bytes()
    assert variants['current'] == (base / 'current_mlx_metal_callback_scope.inc').read_bytes()
    receipt = {'scope': 'CPU_mock_callback_scope_compatibility_only_not_native_SDK_or_release_evidence',
               'helper_sha256': {n: sha(b) for n, b in variants.items()}, 'fixture_sha256': sha(fixture), 'results': results,
               'models': 0, 'native_SDK_loaded': False, 'Metal_objects': 0, 'native_authority': False, 'installed': False}
    file = directory / 'receipt.json'
    file.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'receipt': str(file), 'sha256': sha(file.read_bytes()), 'passed': True, 'models': 0}), flush=True)

def main():
    if sys.argv[1:] == ['--mock']:
        return mock()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--isolated', action='store_true', required=True)
    for name in ['baseline', 'source', 'host', 'library', 'zig']:
        parser.add_argument('--' + name, type=pathlib.Path, required=True)
    parser.add_argument('--library-sha256', required=True)
    a = parser.parse_args()
    assert platform.python_implementation() == 'CPython' and sys.version_info[:3] == (3, 11, 17)
    assert platform.system() == 'Darwin' and os.getuid() > 0
    for file in [a.baseline, a.source, a.host, a.library, a.zig]:
        assert file.is_absolute() and file.exists() and not file.is_symlink()
    assert sha(a.library.read_bytes()) == a.library_sha256
    assert sha(a.zig.read_bytes()) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
    directory = pathlib.Path(tempfile.mkdtemp(prefix='fios-009-current-metal-callback-', dir='/private/tmp'))
    print(json.dumps({'directory': str(directory)}), flush=True)
    env = {'PATH': '/usr/bin:/bin', 'HOME': str(directory), 'LANG': 'C', 'LC_ALL': 'C',
           'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
           'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_SYSTEM': '/dev/null', 'GIT_NO_REPLACE_OBJECTS': '1'}
    def query(argv):
        return subprocess.check_output(list(map(str, argv)), env=env, timeout=15).decode().strip()
    def git(source, *argv):
        return subprocess.check_output(['/usr/bin/git', '--no-replace-objects', '-C', str(source), *argv], env=env, timeout=15).decode()
    source_inputs = {}
    for source in [a.baseline, a.source]:
        assert git(source, 'rev-parse', 'HEAD').strip() == PIN
        assert git(source, 'diff', 'HEAD', '--name-only').strip().splitlines() == PATHS
        names = list(filter(None, git(source, 'ls-files', '-z').split('\0')))
        source_inputs[str(source)] = {n: sha((source / n).read_bytes()) for n in names}
    canonical = (ROOT / 'platform/studio/native/mlx-c69303b-owner-uncertainty.patch').read_text()
    assert git(a.baseline, 'diff', '--no-ext-diff', '--no-textconv', 'HEAD', '--', *PATHS) == canonical
    for name, digest in source_inputs[str(a.baseline)].items():
        if name != 'mlx/backend/metal/device.cpp':
            assert source_inputs[str(a.source)][name] == digest
    old = (a.baseline / 'mlx/backend/metal/device.cpp').read_text()
    current = (a.source / 'mlx/backend/metal/device.cpp').read_text()
    assert helper(old) == (ROOT / 'platform/studio/native/current_mlx_metal_callback_previous.inc').read_text()
    assert helper(current) == (ROOT / 'platform/studio/native/current_mlx_metal_callback_scope.inc').read_text()
    patch_file = ROOT / 'platform/studio/native/mlx-c69303b-metal-callback-fence.patch'
    patch = patch_file.read_text()
    assert ''.join(difflib.unified_diff(old.splitlines(True), current.splitlines(True), fromfile='a/mlx/backend/metal/device.cpp', tofile='b/mlx/backend/metal/device.cpp')) == patch
    files = {name: ROOT / ('platform/studio/native/current_mlx_metal_callback_' + name) for name in ['control.cpp.fixture', 'host.cpp.fixture', 'host_test.zig.fixture']}
    fixtures = {n: f.read_bytes() for n, f in files.items()}
    host = directory / 'host'
    host.mkdir(mode=0o700)
    host_inputs = {}
    for part in ['fios', 'sdk']:
        for file in sorted((a.host / 'src' / part).rglob('*.zig')):
            assert file.is_file() and not file.is_symlink()
            name = file.relative_to(a.host / 'src')
            target = host / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, target)
            host_inputs[str(name)] = sha(file.read_bytes())
    (host / 'test.zig').write_bytes(fixtures['host_test.zig.fixture'])
    (host / 'options.zig').write_text('pub const fios_source_ane=false;\npub const fios_source_sdk=true;\npub const llama_engine=false;\n')
    cxx = query(['/usr/bin/xcrun', '--find', 'clang++'])
    sdk = query(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    assert query(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version']) == '27.2'
    assert sha(pathlib.Path(cxx).read_bytes()) == 'fc5e3cbba6ad54059295cad716aacb05ace8235f5f7a6031f1d8c15d24bd6d66'
    results = []
    def run(label, argv, expected=0, extra=None, marker=None):
        r = subprocess.run(list(map(str, argv)), env={**env, **(extra or {})}, capture_output=True, timeout=45)
        log = r.stdout + r.stderr
        (directory / (label + '.log')).write_bytes(log)
        assert r.returncode == expected, (label, r.returncode)
        if marker:
            assert marker in log, label
        results.append({'label': label, 'status': r.returncode, 'expected_status': expected, 'log_sha256': sha(log)})
    for mode, optimization in [('Debug', '-O0'), ('ReleaseSafe', '-O2')]:
        binary = host / ('test-' + mode)
        run(mode + '-host-build', [a.zig, 'test', '-O' + mode, '-lc', '--dep', 'build_options', '-Mroot=' + str(host / 'test.zig'),
            '-Mbuild_options=' + str(host / 'options.zig'), '--test-filter', 'fios ordinary Metal callback actual host scope', '--test-no-exec', '-femit-bin=' + str(binary)])
        for name, text in [('baseline', old), ('current', current)]:
            generated = {}
            for kind in ['control', 'host']:
                unit = fixtures[kind + '.cpp.fixture'].decode()
                assert unit.count('// FIOS_GENUINE_CALLBACK_HELPER') == 1
                file = directory / (name + '-' + kind + '-' + mode + '.cpp')
                file.write_text(unit.replace('// FIOS_GENUINE_CALLBACK_HELPER', helper(text)))
                output = directory / (name + '-' + kind + '-' + mode + ('.dylib' if kind == 'host' else ''))
                args = [cxx, '-std=c++17', '-isysroot', sdk, optimization]
                if kind == 'host':
                    args += ['-dynamiclib', '-I' + str(a.baseline), file, a.library, '-Wl,-rpath,' + str(a.library.parent), '-o', output]
                else:
                    args += [file, '-o', output]
                run(name + '-' + kind + '-' + mode + '-build', args)
                generated[kind] = output
            for case, title in enumerate(['healthy', 'work-error', 'nonstd-error', 'preexisting-error', 'cleanup-error', 'work-and-cleanup-error']):
                expected = name == 'baseline' and case != 0
                sandbox = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)']
                run(name + '-modeled-' + mode + '-' + title, sandbox + [generated['control'], title], 77 if expected else 0,
                    marker=b'FIO_METAL_' if expected else None)
                run(name + '-actual-host-' + mode + '-' + title, sandbox + [binary], 1 if expected else 0,
                    extra={'FIOS_METAL_FIXTURE_LIBRARY': str(generated['host']), 'FIOS_METAL_CASE': str(case)},
                    marker=b'FIO_METAL_ACTUAL_OWNER_FENCE_AFTER_CAPTURE_CLEANUP' if expected else b'All 2 tests passed.')
    for source, records in source_inputs.items():
        assert records == {n: sha((pathlib.Path(source) / n).read_bytes()) for n in records}
    for name, digest in host_inputs.items():
        assert sha((a.host / 'src' / name).read_bytes()) == digest == sha((host / name).read_bytes())
    assert sha(a.library.read_bytes()) == a.library_sha256 and patch_file.read_text() == patch
    assert fixtures == {n: f.read_bytes() for n, f in files.items()}
    receipt = {'scope': 'genuine_callback_helper_actual_SDK_scope_and_host_hooks_with_modeled_capture_metadata_only',
        'python_version': platform.python_version(), 'python_executable_sha256': sha(pathlib.Path(sys.executable).resolve().read_bytes()),
        'source_inputs_before_after': source_inputs, 'host_copied_Zig_inputs': host_inputs, 'patch_sha256': sha(patch.encode()),
        'fixture_sha256': {n: sha(b) for n, b in fixtures.items()}, 'library_sha256': a.library_sha256, 'results': results,
        'models': 0, 'Metal_objects': 0, 'backend_initialized': False, 'native_authority': False, 'installed': False,
        'host_profile_scope': 'CPU_callbacks_ANE_disabled_not_full_server_profile', 'whole_native_provenance': False}
    file = directory / 'receipt.json'
    file.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'receipt': str(file), 'sha256': sha(file.read_bytes()), 'passed': True, 'models': 0}), flush=True)

if __name__ == '__main__':
    main()
