#!/usr/bin/env python3
"""CPU-only original TP service callback and modeled request metadata controls."""
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
BASE_SHA = '24411877c26d2f13a18dfbf9be1315c3dcc2b1022f01827e48b5a87ad70b1237'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--isolated', action='store_true', required=True)
    parser.add_argument('--baseline', type=pathlib.Path, required=True)
    parser.add_argument('--source', type=pathlib.Path, required=True)
    parser.add_argument('--host', type=pathlib.Path)
    parser.add_argument('--zig', type=pathlib.Path)
    args = parser.parse_args()
    assert platform.python_implementation() == 'CPython' and sys.version_info[:3] == (3, 11, 17), 'Use locked CPython 3.11.17'
    assert bool(args.host) == bool(args.zig)
    assert platform.system() == 'Darwin' and os.getuid() > 0
    for source in [args.baseline, args.source]:
        assert source.is_absolute() and source.is_dir() and not source.is_symlink()
    directory = pathlib.Path(tempfile.mkdtemp(prefix='fios-009-ds4-tp-origins-', dir='/private/tmp'))
    print(json.dumps({'directory': str(directory)}), flush=True)
    env = {'PATH': '/usr/bin:/bin', 'HOME': str(directory), 'LANG': 'C', 'LC_ALL': 'C',
           'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
           'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_SYSTEM': '/dev/null', 'GIT_NO_REPLACE_OBJECTS': '1'}
    def query(argv):
        return subprocess.check_output(list(map(str, argv)), env=env, timeout=15).decode().strip()
    for source in [args.baseline, args.source]:
        assert query(['/usr/bin/git', '--no-replace-objects', '-C', source, 'rev-parse', 'HEAD']) == '9139e2ae58a41503968a500f36f75895c1ba63fc'
    reviewed_paths = ['ds4.c', 'ds4.h', 'ds4_gpu.h', 'ds4_gpu_tp.h', 'ds4_metal.m', 'ds4_tp.c']
    def diff(source, *options):
        return subprocess.check_output(['/usr/bin/git', '--no-replace-objects', '-C', str(source), 'diff', '--no-ext-diff', '--no-textconv', 'HEAD', *options], env=env, timeout=15).decode()
    assert diff(args.baseline, '--', *reviewed_paths) == (ROOT / 'platform/studio/native/ds4-9139e2a-request-origins.patch').read_text()
    for source in [args.baseline, args.source]:
        assert diff(source, '--name-only').strip().splitlines() == reviewed_paths
    for name in reviewed_paths:
        if name != 'ds4_metal.m':
            assert (args.baseline / name).read_bytes() == (args.source / name).read_bytes()
    names = subprocess.check_output(['/usr/bin/git', '-C', str(args.source), 'ls-files', '-z'], env=env, timeout=15).decode().split('\0')
    names = sorted(n for n in names if n == 'Makefile' or pathlib.Path(n).suffix in ['.c', '.m', '.h', '.inc', '.metal'])
    assert len(names) == 154
    selected_sources = {n: sha((args.source / n).read_bytes()) for n in names}
    baseline = (args.baseline / 'ds4_metal.m').read_text()
    current = (args.source / 'ds4_metal.m').read_text()
    assert sha(baseline.encode()) == BASE_SHA
    patch_file = ROOT / 'platform/studio/native/ds4-9139e2a-tp-request-origins.patch'
    patch = patch_file.read_text()
    assert ''.join(difflib.unified_diff(baseline.splitlines(True), current.splitlines(True), fromfile='a/ds4_metal.m', tofile='b/ds4_metal.m')) == patch
    fixture_file = ROOT / 'platform/studio/Tests/NativeFixtures/DS4TPRequestOrigins.m.fixture'
    fixture = fixture_file.read_text()
    clang = query(['/usr/bin/xcrun', '--find', 'clang'])
    sdk = query(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    assert query(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version']) == '27.2'
    results = []
    def run(label, argv, expected=0, extra=None):
        result = subprocess.run(list(map(str, argv)), env={**env, **(extra or {})}, capture_output=True, timeout=30)
        log = result.stdout + result.stderr
        (directory / (label + '.log')).write_bytes(log)
        assert result.returncode == expected, label
        if expected == 77:
            assert b'FIO_DS4_TP_CALLBACK_LOST_ORIGINAL_CONTEXT' in log
        results.append({'label': label, 'status': result.returncode, 'expected_status': expected, 'log_sha256': sha(log)})
    # Compile the entire actual modified file without executing backend code.
    run('full-source-syntax', [clang, '-isysroot', sdk, '-fsyntax-only', '-fobjc-arc', '-std=gnu11', '-I', args.source, args.source / 'ds4_metal.m'])
    for name, source in [('baseline', baseline), ('current', current)]:
        end = source.index('} ds4_gpu_tp_request;') + len('} ds4_gpu_tp_request;')
        begin = source.rfind('typedef struct {', 0, end)
        request = source[begin:end]
        begin = source.index('static void *ds4_gpu_tp_service_thread(void *arg) {')
        service = source[begin:source.index('\nint ds4_gpu_tp_init(', begin)]
        helpers = ''
        if name == 'current':
            begin = source.index('static void *g_fios_tp_active_origins;')
            helpers = source[begin:source.index('// Same non-wrapping per-thread', begin)]
        unit = fixture
        for marker, value in [('FIOS_TP_REQUEST_TYPE', request), ('FIOS_TP_ORIGIN_HELPERS', helpers), ('FIOS_TP_SERVICE_SOURCE', service)]:
            assert unit.count('// ' + marker) == 1
            unit = unit.replace('// ' + marker, value)
        for mode in ['-O0', '-O2']:
            stem = name + mode
            file = directory / (stem + '.m')
            binary = directory / stem
            file.write_text(unit)
            run(stem + '-compile', [clang, '-isysroot', sdk, '-fobjc-arc', '-std=gnu11', mode, '-UNDEBUG'] +
                (['-DFIOS_TP_REQUEST_ORIGINS=1'] if name == 'current' else []) + [file, '-framework', 'Foundation', '-o', binary])
            run(stem + '-healthy', ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', binary], 77 if name == 'baseline' else 0)
            if name == 'current':
                for scenario in ['FIOS_TP_UNCERTAIN', 'FIOS_TP_LEAVE_REFUSE', 'FIOS_TP_CALLBACK_REFUSE', 'FIOS_TP_MISSING', 'FIOS_TP_STANDALONE', 'FIOS_TP_SOURCE_UNCERTAIN']:
                    run(stem + '-' + scenario.lower(), ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', binary], extra={scenario: '1'})
    host_inputs = None
    if args.host:
        assert args.host.is_absolute() and args.host.is_dir() and args.zig.is_absolute()
        assert sha(args.zig.read_bytes()) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
        host = directory / 'host'
        host.mkdir(mode=0o700)
        host_inputs = {}
        for part in ['fios', 'sdk']:
            for original in sorted((args.host / 'src' / part).rglob('*.zig')):
                assert original.is_file() and not original.is_symlink()
                relative = original.relative_to(args.host / 'src')
                target = host / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(original, target)
                host_inputs[str(relative)] = sha(original.read_bytes())
        actual_fixture_file = ROOT / 'platform/studio/Tests/NativeFixtures/DS4TPHostOrigins.m.fixture'
        actual_test_file = ROOT / 'platform/studio/native/current_ds4_tp_origins_test.zig.fixture'
        actual_fixture = actual_fixture_file.read_text()
        actual_test = actual_test_file.read_bytes()
        (host / 'test.zig').write_bytes(actual_test)
        (host / 'options.zig').write_text('pub const fios_source_ane=false;\npub const fios_source_sdk=true;\npub const llama_engine=false;\n')
        for name, source in [('baseline', baseline), ('current', current)]:
            end = source.index('} ds4_gpu_tp_request;') + len('} ds4_gpu_tp_request;')
            begin = source.rfind('typedef struct {', 0, end)
            request = source[begin:end]
            begin = source.index('static void *ds4_gpu_tp_service_thread(void *arg) {')
            service = source[begin:source.index('\nint ds4_gpu_tp_init(', begin)]
            helpers = 'static void *fixture_original;'
            if name == 'current':
                begin = source.index('static void *g_fios_tp_active_origins;')
                helpers = source[begin:source.index('// Same non-wrapping per-thread', begin)]
            unit = actual_fixture
            for marker, value in [('FIOS_TP_REQUEST_TYPE', request), ('FIOS_TP_ORIGIN_HELPERS', helpers), ('FIOS_TP_SERVICE_SOURCE', service)]:
                assert unit.count('// ' + marker) == 1
                unit = unit.replace('// ' + marker, value)
            for mode, optimization in [('Debug', '-O0'), ('ReleaseSafe', '-O2')]:
                stem = 'host-' + name + '-' + mode
                file = host / (stem + '.m')
                object_file = host / (stem + '.o')
                binary = host / stem
                file.write_text(unit)
                run(stem + '-compile', [clang, '-isysroot', sdk, '-fobjc-arc', '-std=gnu11', optimization] +
                    (['-DFIOS_TP_REQUEST_ORIGINS=1'] if name == 'current' else []) + ['-c', file, '-o', object_file])
                run(stem + '-host-build', [args.zig, 'test', object_file, '-O' + mode, '-lc', '--sysroot', sdk,
                    '-F/System/Library/Frameworks', '-framework', 'Foundation', '--dep', 'build_options',
                    '-Mroot=' + str(host / 'test.zig'), '-Mbuild_options=' + str(host / 'options.zig'),
                    '--test-filter', 'fios ordinary TP actual host origins', '--test-no-exec', '-femit-bin=' + str(binary)])
                if name == 'baseline':
                    result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary)], env=env, capture_output=True, timeout=15)
                    log = result.stdout + result.stderr
                    (directory / (stem + '-expected-context-failure.log')).write_bytes(log)
                    assert result.returncode == 1 and b'FIO_TP_ACTUAL_HOST_CONTEXT_MISSING' in log and b'1 passed; 0 skipped; 1 failed.' in log
                    results.append({'label': stem, 'expected_missing_context_assertion': True, 'status': 1, 'log_sha256': sha(log)})
                else:
                    for scenario, extra in [('healthy', {}), ('cached', {'FIOS_TP_CACHED': '1'})]:
                        run(stem + '-' + scenario, ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', binary], extra=extra)
                        assert b'All 2 tests passed.' in (directory / (stem + '-' + scenario + '.log')).read_bytes()
        for relative, digest in host_inputs.items():
            assert sha((args.host / 'src' / relative).read_bytes()) == digest
            assert sha((host / relative).read_bytes()) == digest
        assert actual_fixture_file.read_text() == actual_fixture and actual_test_file.read_bytes() == actual_test
    assert (args.baseline / 'ds4_metal.m').read_text() == baseline
    assert (args.source / 'ds4_metal.m').read_text() == current
    assert fixture_file.read_text() == fixture and patch_file.read_text() == patch
    assert selected_sources == {n: sha((args.source / n).read_bytes()) for n in names}
    receipt = {'scope': 'actual_CPU_TP_service_fragment_with_modeled_metadata_hooks_only',
               'python_version': platform.python_version(), 'python_executable_sha256': sha(pathlib.Path(sys.executable).resolve().read_bytes()),
               'baseline_source_sha256': BASE_SHA, 'current_source_sha256': sha(current.encode()),
               'patch_sha256': sha(patch.encode()), 'fixture_sha256': sha(fixture.encode()), 'selected_DS4_sources_before_after': selected_sources, 'results': results,
               'models': 0, 'GPU_objects': 0, 'RDMA': False, 'transport_exchange': False,
               'actual_host_request_hook_composition': bool(args.host), 'host_copied_zig_inputs': host_inputs,
               'host_profile_scope': 'CPU_callbacks_only_ANE_disabled_not_full_server_profile', 'all_client_coverage': False,
               'installed': False, 'native_authority': False, 'whole_native_provenance': False}
    file = directory / 'receipt.json'
    file.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'receipt': str(file), 'sha256': sha(file.read_bytes()), 'passed': True, 'models': 0}), flush=True)

if __name__ == '__main__':
    main()
