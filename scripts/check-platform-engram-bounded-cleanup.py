#!/usr/bin/env python3
"""Actual Prefetch methods and real CPU threads; synthetic host ports, no model."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile,shutil
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--zig',type=Path,required=True);a=p.parse_args()
assert os.uname().sysname=='Darwin' and os.geteuid()>0
for value in [a.source,a.zig]:assert value==value.resolve() and str(value).startswith('/private/tmp/')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(a.zig)=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
r=Path(__file__).resolve().parents[1];base=r/'platform/studio/native';patch=base/'mlx-serve-engram-bounded-cleanup.patch';parents=base/'engram_bounded_cleanup_parents.json';fixture=base/'engram_bounded_cleanup.zig.fixture'
w=Path(tempfile.mkdtemp(prefix='fios-009-engram-bounded-',dir='/private/tmp'));parent_fixture=base/'engram_bounded_parent.zig.fixture';shared_fixtures=[base/'engram_cleanup_shared_host.zig.fixture',base/'engram_cleanup_shared_unit.zig.fixture'];inputs={str(p):sha(p) for p in [patch,parents,fixture,parent_fixture,*shared_fixtures,Path(__file__)]};unit=w/'unit';unit.mkdir()
for name,digest in json.loads(parents.read_text()).items():
 src=a.source/name;assert sha(src)==digest;inputs[str(src)]=digest;dst=unit/name;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(src.read_bytes())
env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['/usr/bin/git','apply',str(patch)],cwd=unit,env=env,check=True,capture_output=True,timeout=5)
for name in ['src/sdk/util/shared.zig','src/sdk/util/warm_request_origins.zig','src/sdk/util/engram_prefetch_uncertainty.zig']:
 src=a.source/name;inputs[str(src)]=sha(src);dst=unit/name;dst.parent.mkdir(parents=True,exist_ok=True)
 if name not in json.loads(parents.read_text()):shutil.copyfile(src,dst)
full=(unit/'src/plugins/deepseek_v41/engram.zig').read_text();start=full.index('const fios_prefetch_cleanup_failed =');end=full.index('\n};',full.index('pub const Prefetch = struct {',start))+3
model=(unit/'src/plugins/deepseek_v41/deepseek_v41.zig').read_text();begin=model.index('    pub fn fiosPreparePrefetchRelease(');at=model.index('{',begin)+1;depth=1
while depth:
 depth+=(model[at]=='{')-(model[at]=='}');at+=1
model_method=model[begin:at]
(unit/'src/plugins/deepseek_v41/check.zig').write_text(fixture.read_text().replace('@@PREFETCH@@',full[start:end]).replace('@@MODEL_PREFLIGHT@@',model_method));(unit/'src/main.zig').write_text('comptime {_ = @import("plugins/deepseek_v41/check.zig");}')
records=[]
for mode in ['Debug','ReleaseSafe']:
 for case,owned in [('model preflight',True),('healthy join',True),('timeout retains',True),('restoration failure',True),('entry refusal',True),('legacy finish',False)]:
  (unit/'options.zig').write_text('pub const fios_source_sdk='+str(owned).lower()+';')
  args=['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(a.zig),'test','-O'+mode,'--test-filter',case,'--dep','build_options','-Mroot='+str(unit/'src/main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-lc']
  result=subprocess.run(args,cwd=unit,env=env,capture_output=True,text=True,timeout=60);log=w/(mode+'-'+case.replace(' ','-')+'.log');log.write_text(result.stdout+result.stderr);assert result.returncode==0 and 'All 1 tests passed.' in log.read_text(),log.read_text();records.append({'mode':mode,'case':case,'status':0,'log_sha256':sha(log)})
prefix=fixture.read_text().split('fn start()!*Prefetch')[0]
for parent in [True,False]:
 selected=(a.source if parent else unit)/'src/plugins/deepseek_v41/engram.zig';text=selected.read_text()
 begin=text.index('pub const Prefetch = struct {') if parent else text.index('const fios_prefetch_cleanup_failed =')
 end=text.index('\n};',text.index('pub const Prefetch = struct {',begin))+3
 (unit/'src/plugins/deepseek_v41/check.zig').write_text(prefix+parent_fixture.read_text().replace('@@PREFETCH@@',text[begin:end]))
 (unit/'options.zig').write_text('pub const fios_source_sdk=true;')
 for mode in ['Debug','ReleaseSafe']:
  args=['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(a.zig),'test','-O'+mode,'--test-filter','parent control','--dep','build_options','-Mroot='+str(unit/'src/main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-lc']
  result=subprocess.run(args,cwd=unit,env=env,capture_output=True,text=True,timeout=60);log=w/('parent-control-'+str(parent)+'-'+mode+'.log');log.write_text(result.stdout+result.stderr)
  expected=1 if parent else 0;assert result.returncode==expected and ('ENGRAM_UNBOUNDED_PARENT_FINISH' in log.read_text() if parent else 'All 1 tests passed.' in log.read_text()),log.read_text();records.append({'mode':mode,'case':'parent-unbounded-control','parent':parent,'status':result.returncode,'expected_status':expected,'log_sha256':sha(log)})
for file,name in zip(shared_fixtures,['host-main.zig','unit-main.zig']):(unit/'src'/name).write_bytes(file.read_bytes())
for mode in ['Debug','ReleaseSafe']:
 obj=w/('shared-unit-'+mode+'.o');binary=w/('shared-host-'+mode)
 for stage,args in [('object',[str(a.zig),'build-obj','-O'+mode,'-Mroot='+str(unit/'src/unit-main.zig'),'-femit-bin='+str(obj)]),('link',[str(a.zig),'build-exe','-O'+mode,str(obj),'-Mroot='+str(unit/'src/host-main.zig'),'-lc','-femit-bin='+str(binary)]),('runtime',['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)])]:
  result=subprocess.run(args,cwd=unit,env=env,capture_output=True,text=True,timeout=60 if stage!='runtime' else 5);log=w/('shared-'+mode+'-'+stage+'.log');log.write_text(result.stdout+result.stderr);assert result.returncode==0 and (stage!='runtime' or 'PASS: actual Shared cleanup latch' in log.read_text()),log.read_text();records.append({'mode':mode,'case':'actual-host-plugin-shared-binding','stage':stage,'status':0,'log_sha256':sha(log)})
assert inputs=={n:sha(Path(n)) for n in inputs};p=w/'receipt.json';p.write_text(json.dumps({'scope':'actual_prefetch_methods_real_CPU_threads_synthetic_table_and_host_ports_not_model_or_parent_native_acceptance','inputs':inputs,'records':records,'models':0,'model_requests':0,'native_authority':False,'installed':False},indent=2)+'\n');print(json.dumps({'directory':str(w),'sha256':sha(p)}))
