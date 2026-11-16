#!/usr/bin/env python3
"""Actual Qwen warm methods, real private file IO and host SDK custody; no models."""
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
fixture = root / 'platform/studio/native/qwen_real_io_origins.zig.fixture'
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
declared = {str(p): sha(p) for p in [fixture, recipe, parents_file, patch, Path(__file__)]}
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
options_text=options_text.replace('pub const fios_source_sdk: bool = false;','pub const fios_source_sdk: bool = true;')
(unit / 'src/fios-prototype-options.zig').write_text(options_text)
host = (unit / 'src/plugin_host.zig').read_text()
host = host.replace('pub const fios_warm_request_owners_enabled = @import("build_options").fios_source_sdk;',
                    'pub const fios_warm_request_owners_enabled = true;')
host += '\npub const plugin_profile=false;\npub const fio_tracker=@import("fios/request_ownership.zig");\npub const fio_sdk=@import("fios/sdk_request_ownership.zig");\n'
assert host.count('pub const fios_warm_request_owners_enabled = true;') == 1
host+='\npub const fio_qwen_uncertainty=@import("sdk/util/qwen_ngram_warm_uncertainty.zig");\n'
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
receipt = {'scope': 'actual_Qwen_warm_methods_private_pread_and_original_host_custody_not_residency_or_native_proof',
           'directory': str(scratch), 'source': str(source), 'inputs': inputs,
           'fixture_inputs': declared, 'baseline_ABI_injected_for_isolation': False,
           'results': [], 'model_requests': 0, 'native_authority': False, 'installed': False}
save = lambda: (scratch / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
save()
print(json.dumps({'directory': str(scratch), 'model_requests': 0}), flush=True)


qwen_path='src/plugins/qwen4_exp/qwen4_exp.zig'
full=(source/qwen_path).read_text()
inputs[qwen_path]=sha(source/qwen_path)
qwen_patch=root/'platform/studio/native/mlx-serve-qwen-ngram-warm-origins.patch'
qwen_parents=root/'platform/studio/native/qwen_ngram_warm_origins_parents.json'
for file in [qwen_patch,qwen_parents]:declared[str(file)]=sha(file)
qparent=scratch/'qwen-parent';(qparent/Path(qwen_path).parent).mkdir(parents=True)
shutil.copyfile(source/qwen_path,qparent/qwen_path)
run(['git','apply','--reverse',str(qwen_patch)],qparent)
assert sha(qparent/qwen_path)==json.loads(qwen_parents.read_text())[qwen_path]
run(['git','apply',str(qwen_patch)],qparent)
assert sha(qparent/qwen_path)==inputs[qwen_path]
def method(name):
 start=full.index('fn '+name+'(');start=full.rfind('\n',0,start)+1;opening=full.index('{',start);depth=0
 for index in range(opening,len(full)):
  if full[index]=='{':depth+=1
  elif full[index]=='}':
   depth-=1
   if depth==0:return full[start:index+1]
 raise AssertionError(name)
field_start=full.index('    warm_thread: ?std.Thread')
fields=full[field_start:full.index('    /// Set once',field_start)]
chunk=next(line for line in full.splitlines() if 'const WARM_CHUNK:' in line)
template=fixture.read_text()
assert all(template.count(token)==1 for token in ['@@WARM_FIELDS@@','@@WARM_CHUNK@@','@@METHODS@@','@@FILE@@'])
rendered=template.replace('@@WARM_FIELDS@@',fields).replace('@@WARM_CHUNK@@',chunk).replace('@@METHODS@@','\n'.join(method(x) for x in ['warmRegion','startWarm','warmMain','close']))
libraries={str(source/'lib/mlx/lib'/name):sha(source/'lib/mlx/lib'/name) for name in ['libmlx.dylib','libmlxc.dylib']}
assert libraries[str(source/'lib/mlx/lib/libmlx.dylib')]=='4fc2c5d353b6a638d3cc4f3bdc57ddb429a71432dfc851543d6df80a67ee58ff'
assert libraries[str(source/'lib/mlx/lib/libmlxc.dylib')]=='25dfeb4fdf9f0bebbd18fe9701c939bbb66c148a00923fda2d9c905018b3e63b'
receipt['libraries']=libraries
receipt['modeled_ports']=['pool_and_embedded_resources_not_used','progress_log_suppressed','IO_gate_calls_real_libc_pread_and_close','private_allocated_map_length_not_table_format_or_model_mapping']
receipt['physical_IO_claim']='actual sparse private file descriptor reads; no physical-disk/page-residency assertion'
receipt['file_bytes_per_case']=16<<20
receipt['negative_control']='same actual methods with root source-SDK option disabled; not pristine upstream'
save()
for mode in ['Debug','ReleaseSafe']:
 for variant in ['unbound_control','normal','missing_origin','independent_uncertainty','active_close','restored_normal']:
  test=rendered.replace('@@FILE@@',str(scratch/('file-'+mode+'-'+variant+'.bin')))
  if variant=='missing_origin':test=test.replace('const missing_origin=false;','const missing_origin=true;')
  if variant=='independent_uncertainty':test=test.replace('const independent_uncertainty=false;','const independent_uncertainty=true;')
  if variant=='active_close':test=test.replace('const active_close=false;','const active_close=true;')
  (unit/'src/fios-prototype-warm-origins.zig').write_text(test)
  (unit/'src/fios-prototype-options.zig').write_text(options_text.replace('pub const fios_source_sdk: bool = true;','pub const fios_source_sdk: bool = false;') if variant=='unbound_control' else options_text)
  command=[('-O'+mode if x=='-Osafe' else x) for x in argv]
  where=next(i for i,x in enumerate(command) if x.startswith('-Mroot='));command[where:where]=['--dep','build_options']
  command[command.index('--test-filter')+1]='fios qwen real IO'
  command+=['-rpath',str(source/'lib/mlx/lib')]
  logpath=scratch/('case-'+str(len(receipt['results']))+'.log');started=time.monotonic()
  with logpath.open('w') as log:
   child=subprocess.Popen(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)']+command,cwd=unit,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
   try:status=child.wait(timeout=120)
   except subprocess.TimeoutExpired:
    os.killpg(child.pid,signal.SIGKILL);child.wait();status=124
  text=logpath.read_text()
  expected=(status==1 and 'QWEN_REAL_ORIGINAL_ROOT_NOT_HELD' in text and 'FAIL (TestUnexpectedResult)' in text if variant=='unbound_control' else status==0 and 'All 1 tests passed.' in text and 'GENUINE_QWEN_IO' in text)
  receipt['results'].append({'mode':mode,'variant':variant,'status':status,'expected':expected,'elapsed_seconds':round(time.monotonic()-started,3),'log_sha256':sha(logpath)})
  save();print(json.dumps(receipt['results'][-1]),flush=True);assert expected,str(logpath)
receipt['inputs_unchanged']=all(sha(source/name)==digest for name,digest in inputs.items())
receipt['fixture_inputs_unchanged']=all(sha(Path(name))==digest for name,digest in declared.items())
receipt['libraries_unchanged']=all(sha(Path(name))==digest for name,digest in libraries.items())
receipt['native_admission_authority']=False;receipt['native_completion_proof']=False
save()
assert receipt['inputs_unchanged'] and receipt['fixture_inputs_unchanged'] and receipt['libraries_unchanged']
print(json.dumps({'directory':str(scratch),'cases':len(receipt['results']),'receipt_sha256':sha(scratch/'receipt.json'),'native_authority':False}))
