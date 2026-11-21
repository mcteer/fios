#!/usr/bin/env python3
"""Finite normal CPU SDK request-event and private Swift client integration checks."""
import argparse, tempfile, shutil
from pathlib import Path
import hashlib, json, subprocess
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--isolated',action='store_true',required=True)
for name in ['source','zig','sdk-source','sdk-library']:
 parser.add_argument('--'+name,type=Path,required=True)
config=parser.parse_args()
for value in [config.source,config.zig,config.sdk_source,config.sdk_library]:
 assert value.is_absolute() and value.exists()
repo=Path(__file__).resolve().parents[1]
w=Path(tempfile.mkdtemp(prefix='fios-009-request-events-',dir='/private/tmp'))
source=config.source
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
patch=repo/'platform/studio/native/mlx-serve-request-event-roots.patch'
parents=json.loads((repo/'platform/studio/native/request_event_roots_parents.json').read_text())
names=[*parents,'src/fios/request_event_roots.zig']
before={name:sha(source/name) for name in names}
declared_files=[Path(__file__),patch,repo/'platform/studio/native/request_event_roots_parents.json',repo/'platform/studio/native/request_event_roots.zig',repo/'platform/studio/native/request_event_roots_sdk_test.zig.fixture',repo/'platform/studio/native/request_event_roots_live.zig.fixture',repo/'platform/studio/native/sdk_host_event_bridge_fixture.cpp',repo/'platform/studio/Tests/StudioCoreTests/NativeRequestEventsLive.swift.fixture',source/'src/fios/current_sdk_owners.cpp',config.zig,config.sdk_library]
declared_files+=sorted((repo/'platform/studio/Sources/StudioCore').glob('*.swift'))
declared_inputs={str(p):sha(p) for p in declared_files}

projection=w/'projection'
for name in names:
 target=projection/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source/name,target)
subprocess.run(['/usr/bin/patch','-R','-p1','-i',str(patch)],cwd=projection,check=True,capture_output=True)
assert all(sha(projection/name)==digest for name,digest in parents.items())
assert not (projection/'src/fios/request_event_roots.zig').exists()
subprocess.run(['/usr/bin/patch','-p1','-i',str(patch)],cwd=projection,check=True,capture_output=True)
assert all(sha(projection/name)==digest for name,digest in before.items())
assert (source/'src/fios/request_event_roots.zig').read_bytes()==(repo/'platform/studio/native/request_event_roots.zig').read_bytes()
from pathlib import Path
import os,subprocess,json,re,hashlib
root=repo;unit=w/'unit';unit.mkdir()
zig=str(config.zig)
sdkSource=config.sdk_source;library=config.sdk_library
systemSDK=Path(subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],text=True).strip());stub=systemSDK/'usr/lib/libc++.tbd'
inputs={};pending=['fios/request_ownership.zig','fios/sdk_request_ownership.zig']
while pending:
 name=pending.pop()
 if name in inputs:continue
 file=source/'src'/name;data=file.read_bytes();inputs[name]=hashlib.sha256(data).hexdigest();target=unit/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)',data.decode()):
  dependency=(file.parent/match.group(1)).resolve()
  if dependency.exists():pending.append(str(dependency.relative_to(source/'src')))
(unit/'main.zig').write_bytes((root/'platform/studio/native/request_event_roots_sdk_test.zig.fixture').read_bytes())
(unit/'options.zig').write_text('pub const fios_source_ane=false;\npub const sdk_library='+json.dumps(str(library))+';\n')
# Normal standalone root bookkeeping in both compilation modes.
for mode in ['Debug','ReleaseSafe']:
 result=subprocess.run([zig,'test',str(repo/'platform/studio/native/request_event_roots.zig'),'-O'+mode,'--cache-dir',str(w/'pure-cache'),'--global-cache-dir',str(w/'global-cache')],env={'PATH':'/usr/bin:/bin','HOME':'/var/empty'},capture_output=True,text=True,timeout=120)
 (w/('pure-'+mode+'.log')).write_text(result.stdout+result.stderr)
 assert result.returncode==0,'Normal root bookkeeping failed: '+str(w)
bridge=source/'src/fios/current_sdk_owners.cpp';cpp=root/'platform/studio/native/sdk_host_event_bridge_fixture.cpp'
records=[];env={'PATH':'/usr/bin:/bin','HOME':'/var/empty','LANG':'C','LC_ALL':'C'}
for mode,opt in [('Debug','-O0'),('ReleaseSafe','-O2')]:
 obj=w/(mode+'.o');host=w/(mode+'-bridge.o');binary=w/mode
 commands=[('BridgeCPP',['/usr/bin/clang++','-std=c++20',opt,'-DNDEBUG','-isysroot',str(systemSDK),'-I',str(sdkSource),'-c',str(bridge),'-o',str(host)]),('CPP',['/usr/bin/clang++','-std=c++20',opt,'-UNDEBUG','-isysroot',str(systemSDK),'-I',str(sdkSource),'-c',str(cpp),'-o',str(obj)]),('Zig',[zig,'test','--test-no-exec','--test-filter','normal SDK callbacks retain original managed request roots',str(obj),str(host),'-O'+mode,'-lc',str(stub),'--sysroot',str(systemSDK),str(library),'-rpath',str(library.parent),'-F/System/Library/Frameworks','-framework','Metal','-framework','Foundation','--cache-dir',str(w/'cache'),'--global-cache-dir',str(w/'global-cache'),'--dep','build_options','-Mroot='+str(unit/'main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-femit-bin='+str(binary)]),('run',['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)])]
 for stage,args in commands:
  result=subprocess.run(args,cwd=unit,env=env,text=True,capture_output=True,timeout=120 if stage!='run' else 15)
  log=w/(mode+'-'+stage+'.log');log.write_text(result.stdout+result.stderr)
  records.append({'mode':mode,'stage':stage,'status':result.returncode,'log':str(log)})
  (w/'progress.json').write_text(json.dumps({'inputs':inputs,'records':records},indent=2)+'\n')
  if result.returncode:print(json.dumps({'ok':False,'directory':str(w),'mode':mode,'stage':stage}));raise SystemExit(1)
receipt={'scope':'normal_genuine_SDK_CPU_callbacks_associated_with_original_request_roots','inputs':inputs,'records':records,'model_requests':0,'runtime_actions':0,'native_authority':False,'installed':False}
(w/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'ok':True,'directory':str(w),'records':len(records)}))

from pathlib import Path
import os,subprocess,json,re,hashlib,select,time
unit=w/'wire-unit';unit.mkdir()
zig=str(config.zig);library=config.sdk_library
systemSDK=Path(subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],text=True).strip());stub=systemSDK/'usr/lib/libc++.tbd';pending=['fios/control_transport.zig','fios/sdk_request_ownership.zig'];inputs={}
while pending:
 name=pending.pop()
 if name in inputs:continue
 file=source/'src'/name;data=file.read_bytes();inputs[name]=hashlib.sha256(data).hexdigest();target=unit/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)',data.decode()):
  dependency=(file.parent/match.group(1)).resolve()
  if dependency.exists():pending.append(str(dependency.relative_to(source/'src')))
(unit/'live.zig').write_bytes((repo/'platform/studio/native/request_event_roots_live.zig.fixture').read_bytes())
(unit/'options.zig').write_text('pub const fios_source_ane=false;\npub const sdk_library='+json.dumps(str(library))+';\n')
swiftSource=w/'WireMain.swift';swiftSource.write_bytes((repo/'platform/studio/Tests/StudioCoreTests/NativeRequestEventsLive.swift.fixture').read_bytes())
core=repo/'platform/studio/Sources/StudioCore';records=[];captured=None
baseEnv={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C','HOME':'/var/empty'}
for mode,flag in [('Debug',[]),('ReleaseSafe',['-O'])]:
 native=w/(mode+'-live');client=w/(mode+'-client')
 commands=[('NativeCompile',[zig,'build-exe',str(w/(mode+'.o')),str(w/(mode+'-bridge.o')),'-O'+mode,'-lc',str(stub),'--sysroot',str(systemSDK),str(library),'-rpath',str(library.parent),'-F/System/Library/Frameworks','-framework','Metal','-framework','Foundation','--cache-dir',str(w/'wire-cache'),'--global-cache-dir',str(w/'global-cache'),'--dep','build_options','-Mroot='+str(unit/'live.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-femit-bin='+str(native)]),('SwiftCompile',['/usr/bin/swiftc','-swift-version','6','-warnings-as-errors',*flag,'-I',str(repo/'platform/studio/Sources/CSQLite'),*[str(p) for p in sorted(core.glob('*.swift'))],str(swiftSource),'-o',str(client)])]
 for stage,args in commands:
  result=subprocess.run(args,cwd=unit,env=baseEnv,text=True,capture_output=True,timeout=180)
  log=w/(mode+'-'+stage+'.log');log.write_text(result.stdout+result.stderr);records.append({'mode':mode,'stage':stage,'status':result.returncode,'log':str(log)})
  (w/'wire-progress.json').write_text(json.dumps({'inputs':inputs,'records':records},indent=2)+'\n')
  if result.returncode:print(json.dumps({'ok':False,'directory':str(w),'mode':mode,'stage':stage}));raise SystemExit(1)
 home=w/('d-home' if mode=='Debug' else 'r-home');home.mkdir(mode=0o700,exist_ok=False)
 env=dict(baseEnv,HOME=str(home),FIOS_NATIVE_CONTROL='isolated-source-fixture')
 with (w/(mode+'-live.log')).open('w') as errorLog:
  child=subprocess.Popen([str(native)],cwd=unit,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errorLog,text=True)
  try:
   ready,_,_=select.select([child.stdout],[],[],8);assert ready,'Native fixture startup deadline';packet=json.loads(child.stdout.readline());captured=packet
   socket=home/'.fios-native-control/control.sock';assert socket.exists()
   result=subprocess.run([str(client),str(native),str(child.pid),str(socket),packet['root']],cwd=repo,env=baseEnv,text=True,capture_output=True,timeout=8)
   log=w/(mode+'-wire-run.log');log.write_text(result.stdout+result.stderr);records.append({'mode':mode,'stage':'wire','status':result.returncode,'log':str(log)})
   (w/'wire-progress.json').write_text(json.dumps({'inputs':inputs,'records':records},indent=2)+'\n')
   assert result.returncode==0,'Normal native-to-Swift event wire failed'
  finally:
   child.stdin.close();child.wait(timeout=5)
   assert child.returncode==0,'Private native fixture did not close normally'
assert captured
(w/'frames.json').write_text(json.dumps(captured,indent=2)+'\n')
receipt={'scope':'genuine_SDK_CPU_callback_original_root_to_native_Unix_wire_to_Swift_client','native_inputs':inputs,'records':records,'frames':captured,'SDK_library_sha256':hashlib.sha256(library.read_bytes()).hexdigest(),'model_requests':0,'runtime_actions':0,'native_authority':False,'installed':False}
(w/'wire-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'ok':True,'directory':str(w),'records':len(records)}))

assert all(sha(source/name)==digest for name,digest in before.items())
assert all(sha(Path(name))==digest for name,digest in declared_inputs.items())
summary={'selected_component_inputs':declared_inputs,'whole_native_provenance':False,'scope':'normal_CPU_SDK_original_request_root_observations_and_private_native_Swift_wire','source_inputs':before,'patch_sha256':sha(patch),'sdk_library_sha256':sha(library),'sdk_receipt_sha256':sha(w/'receipt.json'),'wire_receipt_sha256':sha(w/'wire-receipt.json'),'whole_native_acceptance':False,'native_authority':False,'installed':False,'model_requests':0}
(w/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({'ok':True,'directory':str(w),'summary_sha256':sha(w/'summary.json')}))
