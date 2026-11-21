#!/usr/bin/env python3
"""Actual native tracker/custody ABI and Prefetch; modeled Table, no model/GPU."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile,shutil,re
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--zig',type=Path,required=True);p.add_argument('--parent-retention',action='store_true');a=p.parse_args()
assert os.uname().sysname=='Darwin' and os.geteuid()>0
for v in [a.source,a.zig]:assert v==v.resolve() and str(v).startswith('/private/tmp/')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assert sha(a.zig)=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
r=Path(__file__).resolve().parents[1];base=r/'platform/studio/native';patch=base/'mlx-serve-engram-bounded-cleanup.patch';parents=base/'engram_bounded_cleanup_parents.json';fixture=base/'engram_native_custody.zig.fixture';parent_fixture=base/'engram_native_parent.zig.fixture';w=Path(tempfile.mkdtemp(prefix='fios-009-engram-native-custody-',dir='/private/tmp'));unit=w/'unit';unit.mkdir();inputs={str(p):sha(p) for p in [patch,parents,fixture,*([parent_fixture] if a.parent_retention else []),Path(__file__)]};env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
for name in json.loads(parents.read_text()):
 src=a.source/name;inputs[str(src)]=sha(src);dst=unit/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
parent_plugin=None
for reverse in [True,False]:
 subprocess.run(['/usr/bin/git','apply',*(['--reverse'] if reverse else []),str(patch)],cwd=unit,env=env,check=True,capture_output=True,timeout=5)
 for name,digest in json.loads(parents.read_text()).items():assert sha(unit/name)==(digest if reverse else inputs[str(a.source/name)])
 if reverse:parent_plugin=(unit/'src/plugins/deepseek_v41/plugin.zig').read_text()
pending=['src/fios/request_ownership.zig','src/fios/sdk_request_ownership.zig','src/sdk/util/warm_request_origins.zig'];copied=set()
while pending:
 name=pending.pop()
 if name in copied:continue
 src=a.source/name;assert src.is_file() and not src.is_symlink() and src.stat().st_size<=1<<20
 copied.add(name);assert len(copied)<=128;inputs[str(src)]=sha(src);dst=unit/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)',src.read_text()):
  dep=(src.parent/match.group(1)).resolve();relative=dep.relative_to(a.source)
  if dep.exists():pending.append(str(relative))
text=(unit/'src/plugins/deepseek_v41/engram.zig').read_text();begin=text.index('const fios_prefetch_cleanup_failed =');end=text.index('\n};',text.index('pub const Prefetch = struct {',begin))+3
def method(text,signature):
 start=text.index(signature);at=text.index('{',start)+1;depth=1
 while depth:
  depth+=(text[at]=='{')-(text[at]=='}');at+=1
 return text[start:at]
candidate=fixture.read_text().replace('@@PREFETCH@@',text[begin:end])
if a.parent_retention:
 preflight=method((unit/'src/plugins/deepseek_v41/deepseek_v41.zig').read_text(),'pub fn fiosPreparePrefetchRelease(')
 candidate=parent_fixture.read_text().replace('@@CUSTODY_SETUP@@',fixture.read_text().split('test "native Engram healthy')[0]).replace('@@MODEL_PREFLIGHT@@',preflight).replace('@@PREFETCH@@',text[begin:end])
 candidate_unload=method((unit/'src/plugins/deepseek_v41/plugin.zig').read_text(),'fn unload(')
 parent_unload=method(parent_plugin,'fn unload(')
(unit/'src/main.zig').write_text('comptime {_ = @import("plugins/deepseek_v41/check.zig");}');(unit/'options.zig').write_text('pub const fios_source_sdk=true;pub const fios_source_ane=false;pub const llama_engine=false;');records=[]
for mode in ['Debug','ReleaseSafe']:
 for case in (['healthy-parent','blocked-parent','negative-parent'] if a.parent_retention else ['healthy release','timeout retains','CPU cleanup']):
  rendered=candidate
  if a.parent_retention:rendered=rendered.replace('@@UNLOAD@@',parent_unload if case=='negative-parent' else candidate_unload).replace('@@BLOCKED@@',str(case!='healthy-parent').lower()).replace('@@NEGATIVE@@',str(case=='negative-parent').lower())
  (unit/'src/plugins/deepseek_v41/check.zig').write_text(rendered)
  args=['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(a.zig),'test','-O'+mode,'--test-filter','parent unload retention' if a.parent_retention else case,'--dep','build_options','-Mroot='+str(unit/'src/main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-lc']
  result=subprocess.run(args,cwd=unit,env=env,capture_output=True,text=True,timeout=60);log=w/(mode+'-'+case.replace(' ','-')+'.log');log.write_text(result.stdout+result.stderr);negative=a.parent_retention and case=='negative-parent';expected=1 if negative else 0
  assert result.returncode==expected and ('ENGRAM_PARENT_PREFLIGHT_NOT_USED' in log.read_text() if negative else 'All 2 tests passed.' in log.read_text() and '.check.test.native Engram ' in log.read_text()),log.read_text();records.append({'mode':mode,'case':case,'status':result.returncode,'expected_status':expected,'log_sha256':sha(log)})
assert inputs=={n:sha(Path(n)) for n in inputs};p=w/'receipt.json';p.write_text(json.dumps({'scope':'actual_native_tracker_custody_ABI_and_prefetch_CPU_threads_modeled_table_not_model_or_device_acceptance','inputs':inputs,'records':records,'actual_parent_unload_body':a.parent_retention,'modeled_parent_resources':a.parent_retention,'real_native_custody_ABI':True,'backend_uncertainty_probe_enrolled':False,'synthetic_table_reader':True,'models':0,'model_requests':0,'GPU_work':False,'native_authority':False,'all_client_coverage':False,'installed':False},indent=2)+'\n');print(json.dumps({'directory':str(w),'sha256':sha(p)}))
