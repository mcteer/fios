#!/usr/bin/env python3
"""Normal genuine GPU callback observations through native IPC and journal polling."""
from pathlib import Path
import argparse, hashlib, json, os, re, select, subprocess, tempfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--isolated',action='store_true',required=True)
for name in ['source','zig','sdk-source','sdk-library']:p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();repo=Path(__file__).resolve().parents[1]
for value in [a.source,a.zig,a.sdk_source,a.sdk_library]:assert value.is_absolute() and value.exists()
w=Path(tempfile.mkdtemp(prefix='fios-009-event-journal-',dir='/private/tmp'));unit=w/'unit';unit.mkdir()
sha=lambda file:hashlib.sha256(file.read_bytes()).hexdigest()
inputs={};pending=['fios/control_transport.zig','fios/sdk_request_ownership.zig']
while pending:
 name=pending.pop()
 if name in inputs:continue
 file=a.source/'src'/name;data=file.read_bytes();inputs[name]=sha(file);target=unit/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)',data.decode()):
  dependency=(file.parent/match.group(1)).resolve()
  if dependency.exists():pending.append(str(dependency.relative_to(a.source/'src')))
cpp=repo/'platform/studio/native/request_event_roots_gpu.cpp.fixture';bridge=a.source/'src/fios/current_sdk_owners.cpp'
fixture=repo/'platform/studio/native/request_event_roots_journal_live.zig.fixture';client_fixture=repo/'platform/studio/Tests/StudioCoreTests/NativeRequestEventPollingLive.swift.fixture'
(unit/'live.zig').write_bytes(fixture.read_bytes());swift=w/'Main.swift';swift.write_bytes(client_fixture.read_bytes())
(unit/'options.zig').write_text('pub const fios_source_ane=false;\npub const sdk_library='+json.dumps(str(a.sdk_library))+';\n')
core=sorted((repo/'platform/studio/Sources/StudioCore').glob('*.swift'))
selected={str(file):sha(file) for file in [Path(__file__),cpp,bridge,fixture,client_fixture,a.zig,a.sdk_library,*core]}
sdk=Path(subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],text=True).strip());stub=sdk/'usr/lib/libc++.tbd'
env={'PATH':'/usr/bin:/bin','HOME':'/var/empty','LANG':'C','LC_ALL':'C','MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS':'0'};records=[]
def run(stage,argv,mode):
 r=subprocess.run(argv,cwd=unit,env=env,capture_output=True,text=True,timeout=180)
 log=w/(mode+'-'+stage+'.log');log.write_text(r.stdout+r.stderr);records.append({'mode':mode,'stage':stage,'status':r.returncode,'log_sha256':sha(log)})
 (w/'progress.json').write_text(json.dumps(records,indent=2)+'\n');assert r.returncode==0,'Normal event/journal '+stage+' failed: '+str(w)
def packet(child):
 ready,_,_=select.select([child.stdout],[],[],10);assert ready,'Normal fixture startup deadline';line=child.stdout.readline();assert 0<len(line)<4096;return json.loads(line)
for mode,opt,swift_opt in [('Debug','-O0',[]),('ReleaseSafe','-O2',['-O'])]:
 obj=w/(mode+'.o');host=w/(mode+'-bridge.o');native=w/(mode+'-native');client=w/(mode+'-client')
 run('BridgeCPP',['/usr/bin/clang++','-std=c++20',opt,'-DNDEBUG','-DFIOS_REQUIRE_BACKGROUND_PARTICIPANT_SEAL','-isysroot',str(sdk),'-I',str(a.sdk_source),'-c',str(bridge),'-o',str(host)],mode)
 run('GraphCPP',['/usr/bin/clang++','-x','c++','-std=c++20',opt,'-UNDEBUG','-isysroot',str(sdk),'-I',str(a.sdk_source),'-c',str(cpp),'-o',str(obj)],mode)
 run('NativeCompile',[str(a.zig),'build-exe',str(obj),str(host),'-O'+mode,'-lc',str(stub),'--sysroot',str(sdk),str(a.sdk_library),'-rpath',str(a.sdk_library.parent),'-F/System/Library/Frameworks','-framework','Metal','-framework','Foundation','--cache-dir',str(w/'cache'),'--global-cache-dir',str(w/'global-cache'),'--dep','build_options','-Mroot='+str(unit/'live.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-femit-bin='+str(native)],mode)
 run('SwiftCompile',['/usr/bin/swiftc','-swift-version','6','-warnings-as-errors',*swift_opt,'-I',str(repo/'platform/studio/Sources/CSQLite'),*[str(file) for file in core],str(swift),'-o',str(client)],mode)
 home=w/(mode+'-home');home.mkdir(mode=0o700);native_env=dict(env,HOME=str(home),FIOS_NATIVE_CONTROL='isolated-source-fixture')
 with (w/(mode+'-native.log')).open('w') as native_log,(w/(mode+'-client.log')).open('w') as client_log:
  native_child=subprocess.Popen([str(native)],env=native_env,cwd=unit,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=native_log)
  swift_child=None;finished=False
  try:
   assert packet(native_child)=={'ready':True}
   socket=home/'.fios-native-control/control.sock'
   swift_child=subprocess.Popen([str(client),str(native),str(native_child.pid),str(socket),str(home/'journal')],cwd=repo,env=env,stdout=subprocess.PIPE,stderr=client_log)
   identity=packet(swift_child);native_child.stdin.write(bytes.fromhex(identity['correlation_id']));native_child.stdin.flush()
   for phase in ['queued','active']:
    assert packet(swift_child)=={'observed_operation':phase}
    native_child.stdin.write(b'1');native_child.stdin.flush()
   result=packet(swift_child);swift_child.wait(timeout=3);assert swift_child.returncode==0 and result['ok'] and result['original_root']==identity['root'] and result['unresolved_requests']==1
   assert packet(native_child)=={'graph_done':True};finished=True
   records.append({'mode':mode,'stage':'live','status':0,'result':result})
  finally:
   if swift_child is not None and swift_child.poll() is None:swift_child.terminate();swift_child.wait(timeout=3)
   native_child.stdin.close();native_child.wait(timeout=5)
   if finished:assert native_child.returncode==0
assert all(sha(a.source/'src'/name)==digest for name,digest in inputs.items())
assert all(sha(Path(name))==digest for name,digest in selected.items())
receipt={'scope':'normal_genuine_GPU_native_control_original_journal_root_polling','native_inputs':inputs,'selected_inputs':selected,'records':records,'model_requests':0,'gpu_graph_elements':4,'allocator_guideline_bytes':64<<20,'allocator_guideline_is_hard_limit':False,'installed':False,'native_authority':False,'whole_native_provenance':False}
(w/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'ok':True,'directory':str(w),'receipt_sha256':sha(w/'receipt.json')}))
