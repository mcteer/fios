#!/usr/bin/env python3
"""Build the existing pinned dependency as private data; no models or installation."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import signal
import subprocess
import tempfile
import time

PIN = 'd81235049384534c167caea52b85a694f6103d14'
CMAKE_SHA = '08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490'
CLANG_SHA = 'fc5e3cbba6ad54059295cad716aacb05ace8235f5f7a6031f1d8c15d24bd6d66'
ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / 'platform/studio/native/llama_source_abi_control.cpp'

def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--isolated', action='store_true', required=True)
    for name in ['source', 'cmake', 'original-library', 'headers']:
        parser.add_argument('--' + name, type=pathlib.Path, required=True)
    args = parser.parse_args()
    assert platform.system() == 'Darwin' and platform.machine() == 'arm64' and os.getuid() > 0
    for file in [args.source, args.cmake, args.original_library, args.headers]:
        assert file.is_absolute() and file.exists() and not file.is_symlink()
    assert digest(args.cmake) == CMAKE_SHA
    env = {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'LC_ALL': 'C',
           'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
    def query(argv):
        return subprocess.check_output(argv, env=env, timeout=15).decode().strip()
    assert query(['/usr/bin/git', '-C', str(args.source), 'rev-parse', 'HEAD']) == PIN
    def snapshot():
        assert not query(['/usr/bin/git', '-C', str(args.source), 'status', '--porcelain', '--untracked-files=all'])
        names = subprocess.check_output(['/usr/bin/git', '-C', str(args.source), 'ls-files', '-z'], env=env, timeout=15).split(b'\0')
        result = {}
        for raw in filter(None, names):
            name = os.fsdecode(raw)
            file = args.source / name
            assert file.is_file() and not file.is_symlink()
            result[name] = digest(file)
        return result
    before = snapshot()
    original = digest(args.original_library)
    sdk = query(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    assert query(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version']) == '27.2'
    cc = query(['/usr/bin/xcrun', '--find', 'clang'])
    cxx = query(['/usr/bin/xcrun', '--find', 'clang++'])
    assert digest(pathlib.Path(cc)) == CLANG_SHA
    # Keep clang++'s driver basename; resolving the symlink changes driver mode.
    parent = pathlib.Path(tempfile.mkdtemp(prefix='fios-009-current-llama-', dir='/private/tmp'))
    env['HOME'] = str(parent)
    print(json.dumps({'private_directory': str(parent)}), flush=True)
    commands = []
    def run(label, argv, timeout=90):
        started = time.monotonic()
        with (parent / (label + '.log')).open('wb') as log:
            process = subprocess.Popen(list(map(str, argv)), env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                status = process.wait(timeout=timeout)
            except BaseException:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                raise
        commands.append({'label': label, 'argv': list(map(str, argv)), 'status': status, 'seconds': round(time.monotonic() - started, 3)})
        assert status == 0, str(parent / (label + '.log'))
    headers = {}
    for file in sorted(args.headers.glob('*.h')):
        matches = [args.source / n for n in before if pathlib.Path(n).name == file.name and digest(args.source / n) == digest(file)]
        assert matches, file.name
        headers[file.name] = digest(file)
    assert len(headers) == 11
    build = parent / 'build'
    flags = ['CMAKE_BUILD_TYPE=Release', 'CMAKE_EXPORT_COMPILE_COMMANDS=ON',
             'CMAKE_OSX_ARCHITECTURES=arm64', 'CMAKE_OSX_DEPLOYMENT_TARGET=13.3',
             'CMAKE_OSX_SYSROOT=' + sdk, 'CMAKE_C_COMPILER=' + cc, 'CMAKE_CXX_COMPILER=' + cxx,
             'CMAKE_C_FLAGS=-mcpu=apple-m1', 'CMAKE_CXX_FLAGS=-mcpu=apple-m1', 'BUILD_SHARED_LIBS=OFF',
             'LLAMA_BUILD_NUMBER=11429', 'LLAMA_BUILD_COMMIT=' + PIN, 'LLAMA_BUILD_MTMD=ON',
             'GGML_METAL=ON', 'GGML_METAL_EMBED_LIBRARY=ON', 'GGML_BLAS_DEFAULT=ON']
    flags += [name + '=OFF' for name in ['LLAMA_BUILD_APP', 'LLAMA_BUILD_COMMON', 'LLAMA_BUILD_EXAMPLES',
              'LLAMA_BUILD_TOOLS', 'LLAMA_BUILD_TESTS', 'LLAMA_BUILD_SERVER', 'LLAMA_OPENSSL',
              'GGML_OPENMP', 'GGML_NATIVE', 'GGML_RPC', 'GGML_BACKEND_DL']]
    run('configure', [args.cmake, '-S', args.source, '-B', build, '-G', 'Unix Makefiles'] + ['-D' + f for f in flags], 180)
    run('build', [args.cmake, '--build', build, '--parallel', '2'], 1800)
    names = ['src/libllama.a', 'ggml/src/libggml.a', 'ggml/src/libggml-base.a',
             'ggml/src/libggml-cpu.a', 'ggml/src/ggml-metal/libggml-metal.a',
             'ggml/src/ggml-blas/libggml-blas.a', 'tools/mtmd/libmtmd.a', 'vendor/hash/libvendor-hash.a']
    archive = parent / 'combined.a'
    run('combine', ['/usr/bin/xcrun', 'libtool', '-static', '-o', archive] + [build / n for n in names])
    library = parent / 'libllama.dylib'
    run('link', [cxx, '-dynamiclib', '-isysroot', sdk, '-arch', 'arm64', '-mmacosx-version-min=13.3',
                 '-Wl,-force_load,' + str(archive), '-framework', 'Foundation', '-framework', 'Metal',
                 '-framework', 'Accelerate', '-install_name', '@rpath/libllama.dylib', '-o', library])
    run('sign', ['/usr/bin/codesign', '--force', '--sign', '-', library])
    deps = query(['/usr/bin/otool', '-L', str(library)])
    for line in deps.splitlines()[1:]:
        dependency = line.strip().split(' (')[0]
        assert dependency == '@rpath/libllama.dylib' or dependency.startswith(('/usr/lib/', '/System/Library/'))
    results = {}
    for name, candidate in [('original', args.original_library), ('source', library)]:
        binary = parent / ('abi-' + name)
        run('compile-' + name, [cxx, '-std=c++17', '-isysroot', sdk, '-I' + str(args.headers),
                                FIXTURE, candidate, '-Wl,-rpath,' + str(candidate.parent), '-o', binary])
        run('run-' + name, [binary], 10)
        results[name] = json.loads((parent / ('run-' + name + '.log')).read_text())
    assert results['source'] == results['original']
    assert snapshot() == before and digest(args.original_library) == original
    assert {f.name: digest(f) for f in args.headers.glob('*.h')} == headers
    receipt = {'scope': 'existing_dependency_selected_source_build_and_model_free_ABI_not_native_authority',
               'revision': PIN, 'declared_sources_before_after': before, 'headers': headers,
               'cmake_sha256': CMAKE_SHA, 'clang_sha256': CLANG_SHA, 'sdk': sdk,
               'fixture_sha256': digest(FIXTURE), 'commands': commands, 'library_sha256': digest(library),
               'static_inputs': {n: digest(build / n) for n in names},
               'cache_sha256': digest(build / 'CMakeCache.txt'),
               'compile_commands_sha256': digest(build / 'compile_commands.json'),
               'original_library_sha256': original, 'ABI': results, 'dependencies': deps,
               'models': 0, 'inference': False, 'backend_initialization': False,
               'installed': False, 'activation': False, 'native_authority': False,
               'whole_native_provenance': False, 'source_inputs_unchanged': True}
    receipt_file = parent / 'receipt.json'
    receipt_file.write_text(json.dumps(receipt, indent=2) + '\n')
    receipt_file.chmod(0o400)
    print(json.dumps({'receipt': str(receipt_file), 'sha256': digest(receipt_file),
                      'ABI_equal': True, 'models': 0, 'installed': False}), flush=True)

if __name__ == '__main__':
    main()
