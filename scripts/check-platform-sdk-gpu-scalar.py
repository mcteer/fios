#!/usr/bin/env python3
"""Core-only four-element GPU graph and native ledger; no model authority."""
from pathlib import Path
import argparse, hashlib, json, os, re, signal, subprocess, tempfile, time

p=argparse.ArgumentParser()
p.add_argument('--isolated',action='store_true',required=True)
for name in ['source','sdk-work','zig']:p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[1]
assert os.uname().sysname=='Darwin' and os.uname().machine=='arm64' and os.geteuid()>0
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def safe_paths(mapping):
 assert isinstance(mapping,dict) and 0<len(mapping)<=16384
 assert all(isinstance(n,str) and not Path(n).is_absolute() and not any(part in ['', '.', '..'] for part in n.split('/')) and '\\' not in n for n in mapping)

for path in [a.source,a.sdk_work,a.zig]:
 assert path==path.resolve() and str(path).startswith('/private/tmp/')
 assert path.stat().st_uid==os.geteuid() and not path.stat().st_mode&0o022
assert sha(a.zig)=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
def output(args):return subprocess.check_output(args,text=True,timeout=5).strip()
assert output(['/usr/sbin/scutil','--get','LocalHostName'])=='fios-core'
assert output(['/usr/sbin/sysctl','-n','hw.memsize'])==str(24*2**30)
assert output(['/usr/sbin/sysctl','-n','machdep.cpu.brand_string']).startswith('Apple M4')
assert output(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-version'])=='27.2'
sysroot=Path(output(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'])).resolve()
review_path=a.sdk_work/'build-receipt.json';review=json.loads(review_path.read_text())
assert review['inputs_unchanged'] and not review['native_authority'] and review['model_requests']==0
assert len(review['records'])==2 and all(x['status']==0 for x in review['records'])
source_before=a.source.parent/'source-before.json';native=json.loads(source_before.read_text())['files']
safe_paths(native)
assert all(sha(a.source/n)==h for n,h in native.items())
sdk_before=a.sdk_work/'build-before.json';sdk_inputs=json.loads(sdk_before.read_text())
assert sha(sdk_before)==review['before_sha256']
safe_paths(sdk_inputs['source'])
assert len(sdk_inputs['source'])==991 and all(sha(a.sdk_work/'sdk-source'/n)==h for n,h in sdk_inputs['source'].items())
component_path=a.sdk_work/'component-check.log';component=json.loads(component_path.read_text());component_receipt=Path(component['directory'])/'receipt.json'
assert sha(component_receipt)==component['receipt_sha256'];checked=json.loads(component_receipt.read_text())
assert checked['build_review_sha256']==sha(review_path) and checked['constructor_refusal_order_patch_checked']
assert not checked['native_authority'] and checked['models']==0 and len(checked['records'])==20 and all(x['status']==0 for x in checked['records'])
library=a.sdk_work/'review-sdk/lib/libmlx.dylib';metallib=library.parent/'mlx.metallib'
assert sha(library)==review['library_sha256']
libraries=[library,library.parent/'libjaccl.dylib',metallib]
assert all(checked['inputs'][str(path)]==sha(path) for path in libraries)
w=Path(tempfile.mkdtemp(prefix='fios-009-sdk-gpu-scalar-',dir='/private/tmp'));unit=w/'unit';unit.mkdir()
env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer','MLX_METAL_PATH':str(library.parent),'MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS':'0'}
pending=['fios/request_ownership.zig','fios/sdk_request_ownership.zig'];native_inputs={}
while pending:
 name=pending.pop()
 if name in native_inputs:continue
 source=a.source/'src'/name;data=source.read_bytes();assert len(data)<=1<<20
 native_inputs[name]=sha(source);assert len(native_inputs)<=128
 target=unit/'src'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)',data.decode()):
  dep=(source.parent/match.group(1)).resolve()
  if dep.exists():pending.append(str(dep.relative_to(a.source/'src')))
cpp=root/'platform/studio/native/sdk_gpu_scalar_fixture.cpp';fixture=root/'platform/studio/native/sdk_gpu_scalar_test.zig.fixture'
(unit/'src/main.zig').write_bytes(fixture.read_bytes());(unit/'graph.cpp').write_bytes(cpp.read_bytes())
config=a.source/'build/config.zig';helper=root/'platform/studio/native/current_system_cxx_build.zig.fixture'
assert config.read_bytes().endswith(b'\n'+helper.read_bytes());(unit/'config.zig').write_bytes(config.read_bytes())
(unit/'build.zig').write_text('''const std=@import("std");const config=@import("config.zig");
pub fn build(b:*std.Build) void {
 const target=b.standardTargetOptions(.{});const optimize=b.standardOptimizeOption(.{});
 const module=b.createModule(.{.root_source_file=b.path("src/main.zig"),.target=target,.optimize=optimize,.link_libcpp=true});
 const options=b.addOptions();options.addOption(bool,"fios_source_ane",false);options.addOption(bool,"native_host_events",true);options.addOption([]const u8,"sdk_library",'''+json.dumps(str(library))+''');module.addOptions("build_options",options);
 module.addIncludePath(.{.cwd_relative='''+json.dumps(str(a.sdk_work/'sdk-source'))+'''});
 module.addObjectFile(.{.cwd_relative='''+json.dumps(str(library))+'''});module.addRPath(.{.cwd_relative='''+json.dumps(str(library.parent))+'''});
 module.addCSourceFile(.{.file=b.path("graph.cpp"),.flags=&.{"-std=c++20"}});
 const host:config.Host=.{.frameworks='''+json.dumps(str(sysroot/'System/Library/Frameworks'))+''',.webp_prefix=null,.brew_prefix="/unused"};config.sourceSystemCxx(b,module,host);
 const test_exe=b.addTest(.{.name="gpu-scalar",.root_module=module,.filters=&.{"actual SDK GPU scalar graph"}});b.installArtifact(test_exe);
}
''')
files=[cpp,fixture,config,helper,Path(__file__),review_path,sdk_before,source_before,component_path,component_receipt,*libraries,sysroot/'usr/lib/libc++.1.tbd']
inputs={str(p):sha(p) for p in files};records=[]
receipt={'scope':'actual_Core_four_element_GPU_graph_native_request_group_and_event_ledger_only','inputs':inputs,'native_unit_inputs':native_inputs,'records':records,'models':0,'model_requests':0,'installed':False,'activation':False,'native_authority':False,'all_client_coverage':False,'whole_native_provenance':False,'system_cxx_qualification':False,'allocator_guideline_bytes':64<<20,'allocator_guideline_is_hard_GPU_quota':False,'sampled_process_limit_bytes':2<<30,'run_deadline_seconds':10,'cleanup_is_native_terminality':False}
def save():(w/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
save();print(json.dumps({'directory':str(w)}),flush=True)
for mode in ['Debug','ReleaseSafe']:
 args=[str(a.zig),'build','--sysroot',str(sysroot),'-Dcpu=apple_m1','-Doptimize='+mode,'-j2']
 with (w/(mode+'-build.log')).open('w') as log:
  compiler=subprocess.Popen(args,cwd=unit,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  try:build_status=compiler.wait(timeout=180)
  except subprocess.TimeoutExpired:
   try:os.killpg(compiler.pid,signal.SIGKILL)
   except ProcessLookupError:pass
   compiler.wait(timeout=2);build_status=124
 records.append({'mode':mode,'stage':'compile','status':build_status,'log_sha256':sha(w/(mode+'-build.log'))});save();assert build_status==0,(w/(mode+'-build.log')).read_text()
 with (w/(mode+'-run.log')).open('w') as log:
  child=subprocess.Popen(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(unit/'zig-out/bin/gpu-scalar')],cwd=unit,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  start=time.monotonic();peak=0;reason=None;missing=0
  try:
   while child.poll() is None:
    if time.monotonic()-start>10:reason='deadline';child.kill();break
    sample=subprocess.run(['/bin/ps','-o','rss=','-p',str(child.pid)],capture_output=True,text=True,timeout=1)
    if sample.returncode==0 and sample.stdout.strip().isdigit():
     missing=0;peak=max(peak,int(sample.stdout.strip())*1024)
     if peak>2<<30:reason='sampled_process_memory';child.kill();break
    elif child.poll() is None:
     missing+=1
     if missing>=3:reason='process_memory_unavailable';child.kill();break
    time.sleep(.05)
   status=child.wait(timeout=2)
  finally:
   if child.poll() is None:child.kill();child.wait(timeout=2)
 records.append({'mode':mode,'stage':'runtime','status':status,'bounded_stop':reason,'peak_sampled_process_bytes':peak,'log_sha256':sha(w/(mode+'-run.log'))});save()
 log=(w/(mode+'-run.log')).read_text()
 assert status==0 and reason is None and peak>0 and 'PASS SDK GPU scalar graph and native event ledger' in log and 'All 2 tests passed.' in log and 'fios.request_ownership.test_0...OK' in log
 match=re.search(r'metal_events=(\d+)',log);assert match and 0<int(match[1])<=64
 assert 'parent_released_before_compute=true' in log
 records[-1]['attributed_metal_events_retired']=int(match[1]);records[-1]['parent_released_before_compute']=True;save()
assert inputs=={str(p):sha(p) for p in files}
assert all(sha(a.source/'src'/n)==h for n,h in native_inputs.items())
assert all(sha(a.sdk_work/'sdk-source'/n)==h for n,h in sdk_inputs['source'].items())
assert all(sha(a.source/n)==h for n,h in native.items())
assert all(sha(a.sdk_work/'dependencies'/group/n)==h for group,values in sdk_inputs['dependencies'].items() for n,h in values.items())
receipt['inputs_unchanged']=True;save();print(json.dumps({'directory':str(w),'receipt_sha256':sha(w/'receipt.json'),'stages':len(records),'models':0,'native_authority':False}))
