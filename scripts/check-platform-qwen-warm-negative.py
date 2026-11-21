#!/usr/bin/env python3
"""Actual Qwen startWarm method and Shared negative fence; metadata worker only."""
from pathlib import Path
import argparse,tempfile,subprocess,json,hashlib,shutil,re,os,platform
parser=argparse.ArgumentParser();parser.add_argument('--shared-units',action='store_true');parser.add_argument('--isolated',action='store_true',required=True);parser.add_argument('--source',type=Path,required=True);parser.add_argument('--zig',type=Path,required=True);args=parser.parse_args()
root=Path(__file__).resolve().parents[1];source=args.source.resolve();zig=args.zig.resolve();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert platform.system()=='Darwin' and platform.machine()=='arm64' and os.geteuid()>0
assert source==args.source and zig==args.zig and str(source).startswith('/private/tmp/') and str(zig).startswith('/private/tmp/')
assert sha(zig)=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
w=Path(tempfile.mkdtemp(prefix='fios-009-qwen-warm-negative-check-',dir='/private/tmp'));parent=w/'parent';unit=w/'unit';patch=root/'platform/studio/native/mlx-serve-qwen-ngram-warm-negative.patch';support=root/'platform/studio/native/qwen_ngram_warm_support.zig.fixture';cases=root/'platform/studio/native/qwen_ngram_warm_cases.zig.fixture';parents_file=root/'platform/studio/native/qwen_ngram_warm_parents.json';parents=json.loads(parents_file.read_text());paths=re.findall(r'^\+\+\+ b/([^\r\n]+)$',patch.read_text(),re.M)
assert len(paths)==5 and set(paths)-set(parents)=={'src/sdk/util/qwen_ngram_warm_uncertainty.zig'}
inputs={name:sha(source/name) for name in paths};dependency_inputs={name:sha(source/name) for name in ['src/sdk/util/shared.zig','src/fios/current_streamed_pool_uncertainty.zig']};fixture_inputs={str(p.relative_to(root)):sha(p) for p in [patch,support,cases,parents_file,Path(__file__)]}
for name in paths:
 target=parent/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source/name,target)
subprocess.run(['git','apply','--reverse',str(patch)],cwd=parent,check=True,capture_output=True,timeout=15)
assert all(sha(parent/name)==digest for name,digest in parents.items())
subprocess.run(['git','apply',str(patch)],cwd=parent,check=True,capture_output=True,timeout=15);assert all(sha(parent/name)==digest for name,digest in inputs.items())
subprocess.run(['git','apply','--reverse',str(patch)],cwd=parent,check=True,capture_output=True,timeout=15)
(unit/'src/plugins/qwen4_exp').mkdir(parents=True)
for name in ['src/sdk/util/shared.zig','src/sdk/util/qwen_ngram_warm_uncertainty.zig','src/fios/current_backend_uncertainty.zig','src/fios/current_streamed_pool_uncertainty.zig']:
 p=unit/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source/name,p)
(unit/'options.zig').write_text('pub const mlx_stream=false;')
(unit/'src/main.zig').write_text('comptime {_ = @import("plugins/qwen4_exp/check.zig");}')
env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C','GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':'/dev/null','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
def method(text):
 start=text.index('    pub fn startWarm(');opening=text.index('{',start);depth=0
 for i in range(opening,len(text)):
  if text[i]=='{':depth+=1
  elif text[i]=='}':
   depth-=1
   if depth==0:return text[start:i+1]
 raise AssertionError('unbalanced')
actual=(source/'src/plugins/qwen4_exp/qwen4_exp.zig').read_text();decl=re.search(r'^const fios_unproven_warm = .+;$',actual,re.M).group(0);pre=support.read_text().replace('// ACTUAL_QWEN_WARM_LATCH_DECLARATION',decl)
results=[];receipt={'scope':'actual_startWarm_and_Shared_fixed_getter_metadata_worker_no_model_native_authority','inputs':inputs,'dependency_inputs':dependency_inputs,'fixture_inputs':fixture_inputs,'baseline_latch_declaration_injected_for_isolation':True,'results':results,'model_requests':0,'installed':False,'native_authority':False}
save=lambda:(w/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
save();print(json.dumps({'directory':str(w),'model_requests':0}),flush=True)
for mode in ['Debug','ReleaseSafe']:
 for old in [True,False]:
  text=((parent if old else source)/'src/plugins/qwen4_exp/qwen4_exp.zig').read_text();file=unit/'src/plugins/qwen4_exp/check.zig';file.write_text(pre+method(text)+'\n};\n'+cases.read_text())
  for index,name in enumerate(['published negative','absent region','disabled has','negative survives']):
   command=['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(zig),'test','-O'+mode,'--test-filter',name,'--dep','build_options','-Mroot='+str(unit/'src/main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-lc'];p=subprocess.run(command,cwd=unit,env=env,capture_output=True,text=True,timeout=60);log=p.stdout+p.stderr;path=w/('case-'+str(len(results))+'.log');path.write_text(log);negative=old and index in [0,3];expected=(p.returncode==1 and 'QWEN_WARM_' in log and 'FAIL (TestUnexpectedResult)' in log) if negative else p.returncode==0 and 'All 1 tests passed.' in log
   results.append({'mode':mode,'parent':old,'case':name,'status':p.returncode,'negative':negative,'expected':expected,'log_sha256':sha(path)});save();assert expected,log
if args.shared_units:
 p=unit/'src/plugins/qwen4_exp/check.zig';p.write_text(p.read_text()+'\npub fn sharedCall()bool {var table=NgramTable{};table.startWarm();if(table.warm_thread)|t|t.join();return table.observed.load(.acquire); }\n')
 (unit/'src/shared-plugin.zig').write_text('pub const mlx_serve_unit=true;\nexport fn fios_test_qwen_start()bool {return @import("plugins/qwen4_exp/check.zig").sharedCall();}\n')
 (unit/'src/shared-host.zig').write_text('const std=@import("std");const marker=@import("sdk/util/qwen_ngram_warm_uncertainty.zig");const fixed=@import("fios/current_backend_uncertainty.zig");comptime {_ = marker.storage;}\nextern fn fios_test_qwen_start()bool;\ntest "separate plugin thread publishes to original host-owned negative latch" {try std.testing.expect(!marker.known() and !fixed.known(false,false));try std.testing.expect(fios_test_qwen_start());try std.testing.expect(marker.known() and fixed.known(false,false));}\n')
 receipt['shared_results']=[]
 for mode in ['Debug','ReleaseSafe']:
  obj=unit/('qwen-'+mode+'.o');commands=[['build-obj','-O'+mode,'--dep','build_options','-Mroot='+str(unit/'src/shared-plugin.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-lc','-femit-bin='+str(obj)],['test',str(obj),'--test-filter','separate plugin thread','-O'+mode,'--dep','build_options','-Mroot='+str(unit/'src/shared-host.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-lc']]
  for stage,argv in zip(['object','host'],commands):
   result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(zig)]+argv,cwd=unit,env=env,capture_output=True,text=True,timeout=90);log=result.stdout+result.stderr;path=w/('shared-'+mode+'-'+stage+'.log');path.write_text(log);expected=result.returncode==0 and (stage=='object' or 'All 1 tests passed.' in log);receipt['shared_results'].append({'mode':mode,'stage':stage,'status':result.returncode,'expected':expected,'log_sha256':sha(path)});save();assert expected,log
assert all(sha(source/name)==digest for name,digest in dependency_inputs.items())
receipt['inputs_unchanged']=all(sha(source/name)==digest for name,digest in inputs.items());receipt['fixture_inputs_unchanged']=all(sha(root/name)==digest for name,digest in fixture_inputs.items());save();assert receipt['inputs_unchanged'] and receipt['fixture_inputs_unchanged']
print(json.dumps({'directory':str(w),'cases':len(results),'receipt_sha256':sha(w/'receipt.json'),'native_authority':False}))
