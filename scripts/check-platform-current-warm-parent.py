#!/usr/bin/env python3
# Actual parent cleanup methods with metadata-only resource spies; no model/native authority.
from pathlib import Path
import subprocess,json,hashlib
import argparse,tempfile,shutil,os
parser=argparse.ArgumentParser();parser.add_argument('--isolated',action='store_true',required=True);parser.add_argument('--source',type=Path,required=True);parser.add_argument('--zig',type=Path,required=True);args=parser.parse_args()
root=Path(__file__).resolve().parents[1];s=args.source.resolve();zig=str(args.zig.resolve());assert s==args.source and str(s).startswith('/private/tmp/');assert hashlib.sha256(Path(zig).read_bytes()).hexdigest()=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
w=Path(tempfile.mkdtemp(prefix='fios-009-current-warm-parent-check-',dir='/private/tmp'));parent=w/'parent';out=w/'unit';out.mkdir(mode=0o700);patch=root/'platform/studio/native/mlx-serve-current-streamed-warm-origins.patch';parents=json.loads((root/'platform/studio/native/current_streamed_warm_parents.json').read_text());names=[]
import re
names=re.findall(r'^\+\+\+ b/([^\r\n]+)$',patch.read_text(),re.M)
for name in names:
 target=parent/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(s/name,target)
subprocess.run(['git','apply','--reverse',str(patch)],cwd=parent,check=True,capture_output=True,timeout=15)
assert all(hashlib.sha256((parent/name).read_bytes()).hexdigest()==digest for name,digest in parents.items())
inputs={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [patch,root/'platform/studio/native/current_streamed_warm_parents.json',root/'platform/studio/native/current_streamed_warm_parent_support.zig.fixture',root/'platform/studio/native/current_streamed_warm_parent_cases.zig.fixture',s/'src/sdk/weights/streamed/glm5n/experts.zig',s/'src/sdk/weights/streamed/glm5n_source.zig']}
print(json.dumps({'directory':str(w),'models':0}),flush=True)

def method(text,name):
 marker='fn '+name+'(';start=text.index(marker);line=text.rfind('\n',0,start)+1;opening=text.index('{',start);depth=0
 for i in range(opening,len(text)):
  if text[i]=='{':depth+=1
  elif text[i]=='}':
   depth-=1
   if depth==0:return text[line:i+1]
 raise AssertionError('unbalanced')
pre=(root/'platform/studio/native/current_streamed_warm_parent_support.zig.fixture').read_text()
results=[]
for mode in ['Debug','ReleaseSafe']:
 for old in [True,False]:
  text=((parent if old else s)/'src/sdk/weights/streamed/glm5n/experts.zig').read_text();helpers='' if old else method(text,'cleanupUncertain')+'\n';parts=[method(text,n) for n in (['prepareRelease','deinit'] if old else ['retireWarm','cleanupAllowed','prepareRelease','deinit'])];body=pre+helpers+'\nconst Source=struct {const Self=@This();warm:?*Warm=null,sdk_stream:Stream=.{},g:Leaf=.{},ex:Ex=.{},combine_kernel:Leaf=.{},sdk_bank:Leaf=.{},bank:Leaf=.{},allocator:Alloc=.{},own_gates:[0]u8=.{},rows:[0]u8=.{},decode_rows:[0]u8=.{},\n'+'\n'.join(parts)+'\n};\n';body+=(root/'platform/studio/native/current_streamed_warm_parent_cases.zig.fixture').read_text()
  file=out/'parent.zig';file.write_text(body)
  for index,name in enumerate(['warm parent refuses','warm parent healthy','warm parent cached']):
   result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',zig,'test',str(file),'-O'+mode,'--test-filter',name,'-lc'],capture_output=True,text=True,timeout=60,cwd=out);log=result.stdout+result.stderr;(out/('case-'+str(len(results))+'.log')).write_text(log);negative=old and index==0;expected=(result.returncode==1 and 'WARM_PARENT_FREED_ON_REFUSAL' in log and 'FAIL (TestUnexpectedResult)' in log) if negative else result.returncode==0
   results.append({'mode':mode,'parent':old,'case':name,'status':result.returncode,'negative':negative,'expected':expected});(w/'parent-metadata-receipt.json').write_text(json.dumps({'scope':'actual_expert_prepare_deinit_methods_metadata_resources_only','results':results,'models':0,'native_authority':False},indent=2)+'\n');assert expected,log
# Exercise the actual outer wrapper after an inner cleanup discovers uncertainty.
for mode in ['Debug','ReleaseSafe']:
 for old in [True,False]:
  text=((parent if old else s)/'src/sdk/weights/streamed/glm5n_source.zig').read_text()
  body=pre+"\nconst Inner=struct {fn prepareRelease(_: *@This())bool{return true;}fn deinit(_: *@This())void {live.warm_live=false;if(live.fail_stop)live.warm_unknown=true;}};\nconst Source=struct {inner:Inner=.{},a:Alloc=.{},\n"+method(text,'prepareRelease')+'\n'+method(text,'deinit')+'\n};\n'
  body+='test "outer warm wrapper" {var trace=Trace{.fail_stop=true};live=&trace;var source=Source{};source.deinit();if(trace.frees!=0 or !trace.warm_unknown){std.debug.print("WARM_WRAPPER_FREED_ON_LATE_REFUSAL\\n",.{});return error.TestUnexpectedResult;}}\n'
  file=out/'wrapper.zig';file.write_text(body)
  result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',zig,'test',str(file),'-O'+mode,'--test-filter','outer warm wrapper','-lc'],capture_output=True,text=True,timeout=60,cwd=out)
  log=result.stdout+result.stderr;(out/('case-'+str(len(results))+'.log')).write_text(log)
  expected=(result.returncode==1 and 'WARM_WRAPPER_FREED_ON_LATE_REFUSAL' in log and 'FAIL (TestUnexpectedResult)' in log) if old else result.returncode==0
  results.append({'mode':mode,'parent':old,'case':'outer wrapper late refusal','status':result.returncode,'negative':old,'expected':expected})
  (w/'parent-metadata-receipt.json').write_text(json.dumps({'scope':'actual_expert_and_wrapper_cleanup_methods_metadata_resources_only','input_sha256':inputs,'results':results,'models':0,'native_authority':False},indent=2)+'\n');assert expected,log
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==digest for p,digest in inputs.items())
print(json.dumps({'directory':str(w),'cases':len(results),'all_expected':all(x['expected'] for x in results),'receipt_sha256':hashlib.sha256((w/'parent-metadata-receipt.json').read_bytes()).hexdigest()}))
