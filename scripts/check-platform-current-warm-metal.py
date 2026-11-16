#!/usr/bin/env python3
"""Current actual warm worker, tiny real Metal chunks and original custody; no models."""
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
fixture = root / 'platform/studio/native/current_warm_metal_origins.zig.fixture'
helper = root / 'platform/studio/native/mimo_warm_metal_fixture_helpers.inc'
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
for name in ['mimo_gpu_warm.inc','mlx_alloc_shim.cpp','mlx_event_shim.cpp','q3_event_shim.mm']:
    relative='src/sdk/weights/streamed/csrc/'+name
    inputs[relative]=sha(source/relative)
declared = {str(p.relative_to(root)): sha(p) for p in [fixture, helper, recipe, parents_file, patch, Path(__file__)]}
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
receipt = {'scope': 'actual_current_warm_Metal_physical_retirement_original_roots_not_all_client_or_native_admission',
           'directory': str(scratch), 'source': str(source), 'inputs': inputs,
           'fixture_inputs': declared, 'baseline_ABI_injected_for_isolation': False,
           'results': [], 'model_requests': 0, 'native_authority': False, 'installed': False}
save = lambda: (scratch / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
save()
print(json.dumps({'directory': str(scratch), 'model_requests': 0}), flush=True)
cppfile=unit/'src/sdk/weights/streamed/csrc/mimo_gpu_warm.inc'
cpp=cppfile.read_text()
original_kernel=re.search(r'const char\* const kSource = R"MSL\((.*?)\)MSL";',cpp,re.S).group(1)
def replace(text,before,after):
    assert text.count(before)==1,before
    return text.replace(before,after)
cpp=replace(cpp,'#include <string>','#include <string>\n#include <atomic>')
cpp=replace(cpp,'namespace mimo_warm {','namespace mimo_warm {\nstatic std::atomic<uint64_t> fixture_retire_calls{0}, fixture_destroy_calls{0};')
cpp=replace(cpp,'struct Warm {','struct Warm {\n  MTL::SharedEvent* fixture_second = nullptr;\n  uint64_t fixture_commits = 0;\n  std::atomic<MTL::CommandBuffer*> fixture_last{nullptr};')
cpp=replace(cpp,'  if (w == nullptr) return;','  if (w == nullptr) return;\n  ++fixture_destroy_calls;\n  if(auto* last=w->fixture_last.load())last->release();')
cpp=replace(cpp,'  MTL::CommandBuffer* buf = w->queue->commandBufferWithUnretainedReferences();','  ++w->fixture_commits;\n  if(w->fixture_commits==2&&w->fixture_second){auto* gate=w->queue->commandBuffer();gate->encodeWait(w->fixture_second,1);gate->commit();}\n  MTL::CommandBuffer* buf = w->queue->commandBufferWithUnretainedReferences();')
cpp=replace(cpp,'  buf->commit();\n  *cb = buf;','  buf->commit();\n  if(w->fixture_commits==2){buf->retain();w->fixture_last.store(buf);}\n  *cb = buf;')
cpp=replace(cpp,'  buf->waitUntilCompleted();','  ++fixture_retire_calls;\n  buf->waitUntilCompleted();')
cpp+='\n'+helper.read_text()
assert re.search(r'const char\* const kSource = R"MSL\((.*?)\)MSL";',cpp,re.S).group(1)==original_kernel
cppfile.write_text(cpp)

original_fixture=fixture.read_text()
original_cpp=cppfile.read_bytes()
libraries={str(source/'lib/mlx/lib'/name):sha(source/'lib/mlx/lib'/name) for name in ['libmlx.dylib','libmlxc.dylib']}
assert libraries[str(source/'lib/mlx/lib/libmlx.dylib')]=='4fc2c5d353b6a638d3cc4f3bdc57ddb429a71432dfc851543d6df80a67ee58ff'
assert libraries[str(source/'lib/mlx/lib/libmlxc.dylib')]=='25dfeb4fdf9f0bebbd18fe9701c939bbb66c148a00923fda2d9c905018b3e63b'
receipt['libraries']=libraries
receipt['fixture_instrumentation']='two shared-event gates, counters, retained-status buffer and5s emergency release; existing kernel unchanged'
receipt['warm_cpp_original_sha256']=sha(source/'src/sdk/weights/streamed/csrc/mimo_gpu_warm.inc')
receipt['required_physical_chunks']=2
receipt['original_kernel_sha256']=hashlib.sha256(original_kernel.encode()).hexdigest()
receipt['kernel_unchanged']=True
receipt['negative_control']='same current worker with ownership disabled in test host; not pristine upstream baseline'
save()
try:
 for mode in ['Debug','ReleaseSafe']:
  for variant in ['unbound_control','normal','retire_api_error','independent_uncertainty','restored_normal']:
   target.write_bytes(candidate)
   cppfile.write_text(cpp)
   test=original_fixture
   if variant=='retire_api_error':
    cppfile.write_text(replace(cpp,'  if (st != MTL::CommandBufferStatusCompleted) return fail("a warm chunk completed with an error");','  if (st != MTL::CommandBufferStatusCompleted) return fail("a warm chunk completed with an error");\n  return fail("FIOS injected API error AFTER genuine GPU completion/release");'))
    test=replace(test,'const injected_retire_failure = false;','const injected_retire_failure = true;')
   if variant=='independent_uncertainty':
    test=replace(test,'const independent_uncertainty = false;','const independent_uncertainty = true;')
   (unit/'src/fios-prototype-warm-origins.zig').write_text(test)
   command=[('-O'+mode if x=='-Osafe' else x) for x in argv]
   command=[part for value in command for part in (['-DFIOS_GENUINE_WARM_ENGINE_FIXTURE=1',value] if value=='-std=c++20' else [value])]
   command[command.index('--test-filter')+1]='fios real metal:'
   command+=['-rpath',str(source/'lib/mlx/lib')]
   if variant=='unbound_control':command=[value.replace('-Mmlx_host=src/fios-prototype-warm-host.zig','-Mmlx_host=src/fios-prototype-warm-legacy-host.zig') for value in command]
   logpath=scratch/('case-'+str(len(receipt['results']))+'.log')
   started=time.monotonic()
   with logpath.open('w') as log:
    child=subprocess.Popen(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)']+command,cwd=unit,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    try:status=child.wait(timeout=120)
    except subprocess.TimeoutExpired:
     os.killpg(child.pid,signal.SIGKILL);child.wait();status=124
   text=logpath.read_text()
   expected=(status==1 and 'CURRENT_WARM_METAL_ROOT_DROPPED' in text and 'FAIL (TestUnexpectedResult)' in text if variant=='unbound_control' else status==0 and 'All 1 tests passed.' in text and 'GENUINE_MIMO_METAL chunks=2' in text)
   receipt['results'].append({'mode':mode,'variant':variant,'status':status,'expected':expected,'elapsed_seconds':round(time.monotonic()-started,3),'log_sha256':sha(logpath)})
   save();print(json.dumps(receipt['results'][-1]),flush=True)
   assert expected,str(logpath)
finally:
 target.write_bytes(candidate);cppfile.write_bytes(original_cpp)
receipt['inputs_unchanged']=all(sha(source/name)==digest for name,digest in inputs.items())
receipt['fixture_inputs_unchanged']=all(sha(root/name)==digest for name,digest in declared.items())
receipt['libraries_unchanged']=all(sha(Path(name))==digest for name,digest in libraries.items())
receipt['native_admission_authority']=False
receipt['native_completion_proof']=False
save()
assert receipt['inputs_unchanged'] and receipt['fixture_inputs_unchanged'] and receipt['libraries_unchanged']
print(json.dumps({'directory':str(scratch),'cases':len(receipt['results']),'receipt_sha256':sha(scratch/'receipt.json'),'native_authority':False}))
