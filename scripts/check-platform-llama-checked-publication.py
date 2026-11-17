#!/usr/bin/env python3
"""Actual pinned constructor, synthetic library ports, never model acceptance."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);a=p.parse_args();assert os.uname().sysname=='Darwin' and os.geteuid()>0
assert a.source==a.source.resolve() and str(a.source).startswith('/private/tmp/')
r=Path(__file__).resolve().parents[1];base=r/'platform/studio/native';patch=base/'mlx-serve-llama-checked-publication.patch';parents=base/'native_llama_checked_publication_parents.json';fixture=base/'llama_checked_publication.cpp.fixture';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();w=Path(tempfile.mkdtemp(prefix='fios-009-llama-publication-',dir='/private/tmp'));inputs={str(p):sha(p) for p in [patch,parents,fixture,Path(__file__)]};env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C'}
for name,digest in json.loads(parents.read_text()).items():
 src=a.source/name;assert sha(src)==digest;inputs[str(src)]=digest;dst=w/name;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(src.read_bytes())
subprocess.run(['/usr/bin/git','apply',str(patch)],cwd=w,env=env,check=True,capture_output=True,timeout=5)
def function(text):
 begin=text.index('extern "C" mlx_llama_ctx *mlx_llama_ctx_create(');at=text.index('{',begin)+1;depth=1
 while depth:
  depth+=(text[at]=='{')-(text[at]=='}');at+=1
 return text[begin:at]
records=[]
for variant,source,flags in [('parent',a.source,['-DLLAMA_FIOS_CHECKED_SYNC_V1=1','-DFIOS_EXPECT_CHECKED_PUBLICATION=1','-DFIOS_PARENT_CONTROL=1']),('checked',w,['-DLLAMA_FIOS_CHECKED_SYNC_V1=1','-DFIOS_EXPECT_CHECKED_PUBLICATION=1']),('legacy',w,[])]:
 for mode,flag in [('debug','-O0'),('optimized','-O2')]:
  cpp=w/(variant+'-'+mode+'.cpp');cpp.write_text(fixture.read_text().replace('// FIOS_ACTUAL_CONTEXT_CREATE',function((source/'lib/llama_shim/llama_shim.cpp').read_text())));binary=cpp.with_suffix('')
  result=subprocess.run(['/usr/bin/clang++','-std=c++17','-Wall','-Wextra','-Werror',flag,*flags,str(cpp),'-o',str(binary)],env=env,capture_output=True,text=True,timeout=60);log=w/(binary.name+'-compile.log');log.write_text(result.stdout+result.stderr);assert result.returncode==0,log.read_text();records.append({'name':binary.name+'-compile','status':0,'expected':0,'log_sha256':sha(log)})
  for case in ['plain-healthy','mtp-healthy','target-failure','mtp-draft-failure','invalid-status','exception']:
   result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary),case],env=env,capture_output=True,text=True,timeout=5);log=w/(binary.name+'-'+case+'.log');log.write_text(result.stdout+result.stderr);negative=variant=='parent' and case not in ['plain-healthy','mtp-healthy'];expected=3 if negative else 0
   assert result.returncode==expected and ('LLAMA_UNCHECKED_CONTEXT_PUBLICATION' in log.read_text() if negative and expected==3 else True),log.read_text();records.append({'name':binary.name+'-'+case,'status':result.returncode,'expected':expected,'log_sha256':sha(log)})
assert inputs=={n:sha(Path(n)) for n in inputs};p=w/'receipt.json';p.write_text(json.dumps({'scope':'actual_constructor_body_synthetic_library_status_ports_not_vendor_or_model_acceptance','inputs':inputs,'records':records,'models':0,'model_requests':0,'GPU_work':False,'native_authority':False,'installed':False},indent=2)+'\n');print(json.dumps({'directory':str(w),'sha256':sha(p),'records':len(records)}))
