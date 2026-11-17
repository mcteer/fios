#!/usr/bin/env python3
"""Pinned source control flow with synthetic CPU ports, never native proof."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--isolated',action='store_true',required=True)
for name in ['vendor-source','native-source']:p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[1]
assert os.uname().sysname=='Darwin' and os.geteuid()>0
for value in [a.vendor_source,a.native_source]:assert value==value.resolve() and str(value).startswith('/private/tmp/')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
w=Path(tempfile.mkdtemp(prefix='fios-009-llama-checked-sync-',dir='/private/tmp'));env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C'}
inputs={};candidates={}
for kind,source,patch_name,parent_name in [('vendor',a.vendor_source,'llama-b11429-checked-sync.patch','llama_checked_sync_parents.json'),('native',a.native_source,'mlx-serve-llama-checked-sync.patch','native_llama_checked_sync_parents.json')]:
 patch=root/'platform/studio/native'/patch_name;parent=root/'platform/studio/native'/parent_name
 inputs[str(patch)]=sha(patch);inputs[str(parent)]=sha(parent);parents=json.loads(parent.read_text());unit=w/kind;unit.mkdir()
 for name,digest in parents.items():
  assert not Path(name).is_absolute() and '..' not in Path(name).parts
  original=source/name;assert sha(original)==digest;inputs[str(original)]=digest
  target=unit/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(original.read_bytes())
 result=subprocess.run(['/usr/bin/git','apply',str(patch)],cwd=unit,env=env,capture_output=True,text=True,timeout=5)
 (w/(kind+'-apply.log')).write_text(result.stdout+result.stderr);assert result.returncode==0
 candidates[kind]=unit
fixtures=[root/'platform/studio/native'/n for n in ['llama_checked_sync_method.cpp.fixture','native_llama_checked_sync.cpp.fixture','llama_backend_checked_sync.cpp.fixture']]
for file in [*fixtures,Path(__file__)]:inputs[str(file)]=sha(file)
def function(text,signature):
 start=text.index(signature);brace=text.index('{',start);depth=1;at=brace+1
 while depth:
  if text[at]=='{':depth+=1
  elif text[at]=='}':depth-=1
  at+=1
 return text[start:at]
method=function((candidates['vendor']/'src/llama-context.cpp').read_text(),'int32_t llama_context::fios_synchronize_checked()')
signature='extern "C" int32_t mlx_llama_ctx_try_free('
parent_function=function((a.native_source/'lib/llama_shim/llama_shim.cpp').read_text(),signature)
new_function=function((candidates['native']/'lib/llama_shim/llama_shim.cpp').read_text(),signature)
records=[]
def run(name,args,expected=0,marker=None):
 result=subprocess.run(args,cwd=w,env=env,capture_output=True,text=True,timeout=60 if name.endswith('compile') else 5)
 log=w/(name+'.log');log.write_text(result.stdout+result.stderr)
 assert result.returncode==expected and (marker is None or marker in log.read_text()),log.read_text()
 records.append({'name':name,'status':result.returncode,'expected':expected,'log_sha256':sha(log)})
for mode,flag in [('debug','-O0'),('optimized','-O2')]:
 cpp=w/('method-'+mode+'.cpp');cpp.write_text(fixtures[0].read_text().replace('// FIOS_ACTUAL_CHECKED_METHOD',method));binary=cpp.with_suffix('')
 run('method-'+mode+'-compile',['/usr/bin/clang++','-std=c++17','-Wall','-Wextra','-Werror',flag,str(cpp),'-o',str(binary)])
 for scenario in ['cpu','healthy','empty','null-backend','unsupported','no-device','no-registry','failure','invalid-status','exception','sync-exception','limit']:
  run('method-'+mode+'-'+scenario,['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary),scenario],marker='PASS: actual source context checked synchronization')
 backend_body=fixtures[2].read_text()
 for marker,name,signature in [
  ('// FIOS_ACTUAL_METAL_STATUS','ggml/src/ggml-metal/ggml-metal-context.m','int32_t ggml_metal_fios_synchronize_checked_v1('),
  ('// FIOS_ACTUAL_METAL_BRIDGE','ggml/src/ggml-metal/ggml-metal.cpp','static int32_t ggml_backend_metal_fios_synchronize_checked_v1('),
  ('// FIOS_ACTUAL_BLAS_STATUS','ggml/src/ggml-blas/ggml-blas.cpp','static int32_t ggml_backend_blas_fios_synchronize_checked_v1(')]:
  backend_body=backend_body.replace(marker,function((candidates['vendor']/name).read_text(),signature))
 cpp=w/('backend-'+mode+'.cpp');cpp.write_text(backend_body);binary=cpp.with_suffix('')
 run('backend-'+mode+'-compile',['/usr/bin/clang++','-std=c++17','-Wall','-Wextra','-Werror',flag,str(cpp),'-o',str(binary)])
 for scenario in ['metal-null','metal-no-context','metal-failure','metal-latched','metal-healthy','blas-pending','blas-wrong','blas-healthy']:
  run('backend-'+mode+'-'+scenario,['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary),scenario],marker='PASS: actual backend source checked status helpers')
 for variant,body,flags in [('parent',parent_function,['-DFIOS_EXPECT_CHECKED=1','-DLLAMA_FIOS_CHECKED_SYNC_V1=1']),('checked',new_function,['-DFIOS_EXPECT_CHECKED=1','-DLLAMA_FIOS_CHECKED_SYNC_V1=1']),('legacy',new_function,[])]:
  cpp=w/('shim-'+variant+'-'+mode+'.cpp');cpp.write_text(fixtures[1].read_text().replace('// FIOS_ACTUAL_SHIM_CLEANUP',body));binary=cpp.with_suffix('')
  run('shim-'+variant+'-'+mode+'-compile',['/usr/bin/clang++','-std=c++17','-Wall','-Wextra','-Werror',flag,*flags,str(cpp),'-o',str(binary)])
  for scenario in ['healthy','empty','target-failure','draft-failure','unsupported','invalid-status','exception']:
   failure=variant=='parent' and scenario not in ['healthy','empty'];run('shim-'+variant+'-'+mode+'-'+scenario,['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary),scenario],expected=3 if failure else 0,marker='LLAMA_SYNC_UNCHECKED_RETIREMENT' if failure else 'PASS: actual shim source cleanup/status control')
assert inputs=={n:sha(Path(n)) for n in inputs}
r={'scope':'actual_pinned_source_methods_and_shim_cleanup_synthetic_ports_only_not_vendor_backend_or_native_acceptance','inputs':inputs,'records':records,'models':0,'model_requests':0,'GPU_work':False,'hardware_fault_injection':False,'vendor_library_built':False,'native_authority':False,'all_client_coverage':False,'installed':False,'inputs_unchanged':True}
p=w/'receipt.json';p.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'directory':str(w),'receipt_sha256':sha(p),'records':len(records),'native_authority':False}))
