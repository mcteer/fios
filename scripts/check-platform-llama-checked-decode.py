#!/usr/bin/env python3
"""Actual pinned decode body, synthetic ports; no model or native authority."""
import argparse,hashlib,json,os,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--native-source',type=Path,required=True);a=p.parse_args()
assert os.uname().sysname=='Darwin' and os.geteuid()>0
assert a.native_source==a.native_source.resolve() and str(a.native_source).startswith('/private/tmp/')
r=Path(__file__).resolve().parents[1];base=r/'platform/studio/native';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
parents=base/'native_llama_checked_decode_parents.json';patch=base/'mlx-serve-llama-checked-decode.patch';fixture=base/'llama_checked_decode.cpp.fixture'
w=Path(tempfile.mkdtemp(prefix='fios-009-checked-decode-',dir='/private/tmp'));draft_fixture=base/'llama_checked_draft.cpp.fixture'
inputs={str(p):sha(p) for p in [parents,patch,fixture,draft_fixture,Path(__file__)]}
for name,digest in json.loads(parents.read_text()).items():
 assert not Path(name).is_absolute() and '..' not in Path(name).parts
 src=a.native_source/name;assert sha(src)==digest;inputs[str(src)]=digest
 dst=w/name;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(src.read_bytes())
env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C'}
subprocess.run(['/usr/bin/git','apply',str(patch)],cwd=w,env=env,check=True,timeout=5)
text=(w/'lib/llama_shim/llama_shim.cpp').read_text();records=[]
for kind,signature,template,marker in [('decode','static int32_t decode_rows(',fixture,'// FIOS_ACTUAL_DECODE_ROWS'),('draft','static int32_t draft(',draft_fixture,'// FIOS_ACTUAL_DRAFT')]:
 start=text.index(signature);brace=text.index('{',start);end=brace+1;depth=1
 while depth:
  depth+=(text[end]=='{')-(text[end]=='}');end+=1
 body=text[start:end]
 for mode,flag in [('debug','-O0'),('optimized','-O2')]:
  cpp=w/(kind+'-'+mode+'.cpp');cpp.write_text(template.read_text().replace(marker,body));binary=cpp.with_suffix('')
  commands=[('compile',['/usr/bin/clang++','-std=c++17','-Wall','-Wextra','-Werror','-DLLAMA_FIOS_CHECKED_SYNC_V1=1',flag,str(cpp),'-o',str(binary)])]
  commands += [(str(status),['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary),str(status)]) for status in [1,0,-1,2]]
  for name,args in commands:
   result=subprocess.run(args,cwd=w,env=env,capture_output=True,text=True,timeout=60 if name=='compile' else 5);log=w/(kind+'-'+mode+'-'+name+'.log');log.write_text(result.stdout+result.stderr)
   assert result.returncode==0,log.read_text();records.append({'name':kind+'-'+mode+'-'+name,'log_sha256':sha(log)})
parent_text=(a.native_source/'lib/llama_shim/llama_shim.cpp').read_text()
for kind,signature,template,marker in [('decode','static int32_t decode_rows(',fixture,'// FIOS_ACTUAL_DECODE_ROWS'),('draft','static int32_t draft(',draft_fixture,'// FIOS_ACTUAL_DRAFT')]:
 start=parent_text.index(signature);end=parent_text.index('{',start)+1;depth=1
 while depth:
  depth+=(parent_text[end]=='{')-(parent_text[end]=='}');end+=1
 cpp=w/('parent-'+kind+'.cpp');cpp.write_text(template.read_text().replace(marker,parent_text[start:end]));binary=cpp.with_suffix('')
 # The old body does not call the declared checked function.
 subprocess.run(['/usr/bin/clang++','-std=c++17','-O2',str(cpp),'-o',str(binary)],env=env,check=True,capture_output=True,timeout=60)
 for status in [0,-1,2]:
  result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary),str(status)],env=env,capture_output=True,text=True,timeout=5)
  assert result.returncode==3
  records.append({'name':'parent-'+kind+'-'+str(status),'expected_rejection':3,'status':result.returncode})
assert inputs=={name:sha(Path(name)) for name in inputs}
receipt=w/'receipt.json';receipt.write_text(json.dumps({'scope':'actual_decode_body_synthetic_ports','inputs':inputs,'records':records,'model_requests':0,'GPU_work':False,'native_authority':False},indent=2)+'\n')
print(json.dumps({'directory':str(w),'receipt_sha256':sha(receipt),'records':len(records)}))
