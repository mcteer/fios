#!/usr/bin/env python3
"""Finite model-free source regression; no native installation or authority."""
from pathlib import Path
import argparse,hashlib,json,os,platform,re,shutil,stat,subprocess,sys,tempfile
BASE="3736ed55f81c6cf0966a0f0dc7265e783655d244"
ZIG_SHA="1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523"
ROOT=Path(__file__).resolve().parent.parent
NAMES=['src/fios/current_backend_uncertainty.zig', 'src/mlx_stream.zig', 'src/plugins/deepseek_v41/plugin.zig', 'src/plugins/glm5_next/host.zig', 'src/plugins/glm5_next/plugin.zig', 'src/plugins/glm5_next/trunk.zig', 'src/plugins/mimo_v2/plugin.zig', 'src/plugins/qwen3_5/plugin.zig', 'src/sdk/weights/streamed.zig', 'src/sdk/weights/streamed/bank_source.zig', 'src/sdk/weights/streamed/csrc/q3_lookahead4.h', 'src/sdk/weights/streamed/csrc/q3_lookahead4_exl3.c', 'src/sdk/weights/streamed/exl3_source.zig', 'src/sdk/weights/streamed/glm5n/experts.zig', 'src/sdk/weights/streamed/glm5n_source.zig', 'src/sdk/weights/streamed/mlx_pack.zig', 'src/sdk/weights/streamed/sdk_ext/expert/io.zig', 'src/sdk/weights/streamed/sdk_ext/expert/io_stub.zig', 'src/sdk/weights/streamed/sdk_ext/expert/stream.zig']
def digest(data):return hashlib.sha256(data).hexdigest()
def checked(path):
 st=path.lstat()
 assert stat.S_ISREG(st.st_mode) and not path.is_symlink() and st.st_uid==os.geteuid() and st.st_nlink==1 and not st.st_mode&0o022 and 0<st.st_size<64<<20,str(path)
 return path.read_bytes()
def command(args,cwd,env):return subprocess.check_output(args,cwd=cwd,env=env,timeout=15)
def c_matrix(p,source,baseline,root,zig,compiler):
 s=source;fixture=root/'platform/studio/native/current_stream_pool_stop_test.c.fixture';name='src/sdk/weights/streamed/csrc/q3_lookahead4_exl3.c';sha=lambda b:hashlib.sha256(b).hexdigest()
 before=(baseline/name).read_bytes();after=(s/name).read_bytes();body=fixture.read_bytes();env={'PATH':'/usr/bin:/bin','HOME':str(p),'LANG':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
 env['SDKROOT']=subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],env=env,text=True,timeout=15).strip()
 receipt={'scope':'actual_C_pool_module_join_create_substitutes_and_real_healthy_pthreads_not_native_authority','source':str(s),'base':'3736ed55f81c6cf0966a0f0dc7265e783655d244','before_sha256':sha(before),'candidate_sha256':sha(after),'fixture_sha256':sha(body),'runner_sha256':sha(Path(__file__).read_bytes()),'clang_version':subprocess.check_output([str(compiler),'--version'],env=env,text=True),'models':0,'inference':False,'Metal':False,'hardware_faults':False,'installed':False,'native_authority':False,'results':[]}
 log=p/'c-matrix';log.mkdir(mode=0o700,exist_ok=True)
 def save():(p/'c-matrix-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 save()
 for label,data in [('baseline',before),('candidate',after)]:
  d=log/label;d.mkdir(mode=0o700,exist_ok=True);(d/'pool.c').write_bytes(data);(d/'main.c').write_bytes(body)
  for opt in ['-O0','-O3']:
   for scenario in range(9):
    key=label+'-'+opt[1:]+'-'+str(scenario);binary=log/key
    args=[str(compiler),'-std=c11',opt,'-pthread','-DFIO_CHECKED='+str(int(label=='candidate')),'-DFIO_SCENARIO='+str(scenario),str(d/'main.c'),'-o',str(binary)]
    r=subprocess.run(args,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30);(log/(key+'-build.log')).write_bytes(r.stdout)
    item={'label':label,'optimize':opt,'scenario':scenario,'build_status':r.returncode};receipt['results'].append(item);save();assert r.returncode==0,(key,r.stdout.decode()[-2000:])
    r=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=10);(log/(key+'-run.log')).write_bytes(r.stdout);item['run_status']=r.returncode;item['binary_sha256']=sha(binary.read_bytes())
    negative=scenario in [0,1,2,6,7,8]
    marker=b'FIO_STREAM_POOL_FAILED_JOIN_DISARMED_EVENT' if scenario==8 else b'FIO_STREAM_POOL_PARTIAL_START_RELEASED_STORAGE' if scenario==6 else b'FIO_STREAM_POOL_FAILED_JOIN_RELEASED_STORAGE'
    item['expected']=(r.returncode==1 and marker in r.stdout) if label=='baseline' and negative else (r.returncode==0 and b'PASS: actual C stream pool' in r.stdout)
    save();assert item['expected'],(key,r.stdout.decode())
 receipt['unchanged']=(s/name).read_bytes()==after and fixture.read_bytes()==body and sha(Path(__file__).read_bytes())==receipt['runner_sha256'];save();assert receipt['unchanged'];return {'receipt':str(p/'c-matrix-receipt.json'),'sha256':sha((p/'c-matrix-receipt.json').read_bytes()),'records':len(receipt['results']),'baseline_failures':12,'baseline_controls':6,'candidate_passes':18}


def pool_matrix(p,source,baseline,root,zig,compiler):
 s=source;old=baseline;fixture=root/'platform/studio/native/current_stream_pool_parent_test.zig.fixture';sha=lambda b:hashlib.sha256(b).hexdigest()
 env={'PATH':'/usr/bin:/bin','HOME':str(p),'LANG':'C','LC_ALL':'C'};body=fixture.read_bytes();directory=p/'pool-zig-matrix';directory.mkdir(mode=0o700,exist_ok=True)
 r={'scope':'actual_Zig_Pool_and_native_negative_bridge_C_metadata_substitutes_no_IO_threads_models','fixture_sha256':sha(body),'runner_sha256':sha(Path(__file__).read_bytes()),'models':0,'inference':False,'native_authority':False,'installed':False,'declared_inputs':{},'results':[]}
 def save():(p/'pool-zig-matrix-receipt.json').write_text(json.dumps(r,indent=2)+'\n')
 for label,source in [('baseline',old),('candidate',s)]:
  unit=directory/label;unit.mkdir(mode=0o700,exist_ok=True)
  (unit/'main.zig').write_bytes(body);(unit/'sdk.zig').write_text('pub const io_util = struct {};\n')
  for name in ['io.zig','io_stub.zig','policy.zig']:
   src=source/'src/sdk/weights/streamed/sdk_ext/expert'/name;dest=unit/'expert'/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(src.read_bytes());r['declared_inputs'][str(src)]=sha(src.read_bytes())
  pending=['fios/current_ane_native_cleanup_uncertainty.zig','fios/request_ownership.zig'];done=set()
  while pending:
   name=pending.pop()
   if name in done:continue
   done.add(name);src=source/'src'/name;b=src.read_bytes();dest=unit/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b);r['declared_inputs'][str(src)]=sha(b)
   for dep in re.findall(r'@import\("([^"\n]+\.zig)"\)',b.decode()):
    full=(src.parent/dep).resolve()
    if full.is_file():pending.append(str(full.relative_to(source/'src')))
  for mode in ['Debug','ReleaseSafe']:
   for scenario in ([0,1,2,3,4,5,7] if label=='baseline' else range(8)):
    key=label+'-'+mode+'-'+str(scenario);binary=directory/key
    (unit/'options.zig').write_text('pub const scenario='+str(scenario)+';\npub const mlx_stream=true;\npub const fios_source_ane=false;\npub const fios_source_sdk=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\n')
    args=[zig,'build-exe','-lc','-O'+mode,'--dep','build_options','--dep','sdk','-Mroot='+str(unit/'main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-Msdk='+str(unit/'sdk.zig')]
    # The actual imported modules share the root's named imports.
    args+=['-femit-bin='+str(binary)]
    built=subprocess.run(args,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);(directory/(key+'-build.log')).write_bytes(built.stdout)
    item={'label':label,'mode':mode,'scenario':scenario,'build_status':built.returncode};r['results'].append(item);save();assert built.returncode==0,(key,built.stdout.decode()[-3500:])
    executed=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=10);(directory/(key+'-run.log')).write_bytes(executed.stdout);item['status']=executed.returncode;item['binary_sha256']=sha(binary.read_bytes())
    marker=b'FIO_STREAM_POOL_PARENT_PARTIAL_START_FREED' if scenario==3 else b'FIO_STREAM_POOL_PARENT_STARTED_AFTER_REFUSAL' if scenario==5 else b'FIO_STREAM_POOL_PARENT_FREED_AFTER_REFUSAL'
    item['expected']=(executed.returncode==1 and marker in executed.stdout) if label=='baseline' and scenario in [0,1,3,5] else (executed.returncode==0 and b'PASS: actual Zig pool' in executed.stdout)
    save();assert item['expected'],(key,executed.stdout.decode())
 r['unchanged']=all(sha(Path(n).read_bytes())==h for n,h in r['declared_inputs'].items()) and fixture.read_bytes()==body and sha(Path(__file__).read_bytes())==r['runner_sha256'];save();assert r['unchanged'];return {'receipt':str(p/'pool-zig-matrix-receipt.json'),'sha256':sha((p/'pool-zig-matrix-receipt.json').read_bytes()),'records':len(r['results']),'baseline_failures':8,'baseline_controls':6,'candidate_passes':16}


def rows_matrix(p,source,baseline,root,zig,compiler):
 fixture=root/'platform/studio/native/current_stream_pool_rows_test.zig.fixture';sha=lambda b:hashlib.sha256(b).hexdigest();body=fixture.read_bytes();name='src/sdk/weights/streamed/sdk_ext/expert/stream.zig';directory=p/'rows-zig-matrix';directory.mkdir(mode=0o700,exist_ok=True);env={'PATH':'/usr/bin:/bin','HOME':str(p),'LANG':'C'}
 def method(text,marker):
  a=text.index(marker);i=text.index('{',a);level=0
  for k in range(i,len(text)):
   if text[k]=='{':level+=1
   elif text[k]=='}':
    level-=1
    if level==0:return text[a:k+1]
  raise AssertionError('Unclosed release method')
 r={'scope':'actual_complete_generic_stream_release_methods_CPU_rows_collections_pool_substitutes','fixture_sha256':sha(body),'runner_sha256':sha(Path(__file__).read_bytes()),'declared_inputs':{},'models':0,'inference':False,'native_authority':False,'installed':False,'results':[]}
 def save():(p/'rows-zig-matrix-receipt.json').write_text(json.dumps(r,indent=2)+'\n')
 for label,source in [('baseline',baseline),('candidate',source)]:
  original=(source/name).read_bytes();text=original.decode();r['declared_inputs'][str(source/name)]=sha(original)
  prepare=method(text,'pub fn prepareRelease(self: *Stream) bool') if label=='candidate' else ''
  deinit=method(text,'pub fn deinit(self: *Stream) void');unit=directory/label;unit.mkdir(mode=0o700,exist_ok=True);(unit/'main.zig').write_text(body.decode().replace('// ACTUAL_PREPARE',prepare).replace('// ACTUAL_DEINIT',deinit))
  for mode in ['Debug','ReleaseSafe']:
   for scenario in range(3):
    key=label+'-'+mode+'-'+str(scenario);binary=directory/key;(unit/'options.zig').write_text('pub const scenario='+str(scenario)+';\n')
    b=subprocess.run([zig,'build-exe','-lc','-O'+mode,'--dep','build_options','-Mroot='+str(unit/'main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-femit-bin='+str(binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);(directory/(key+'-build.log')).write_bytes(b.stdout);item={'label':label,'mode':mode,'scenario':scenario,'build_status':b.returncode};r['results'].append(item);save();assert b.returncode==0,(key,b.stdout.decode()[-2500:])
    e=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=10);(directory/(key+'-run.log')).write_bytes(e.stdout);item['run_status']=e.returncode;item['binary_sha256']=sha(binary.read_bytes());item['expected']=(e.returncode==1 and b'FIO_STREAM_POOL_ROWS_RELEASED_AFTER_REFUSAL' in e.stdout) if label=='baseline' and scenario!=2 else (e.returncode==0 and b'PASS: actual generic stream' in e.stdout);save();assert item['expected'],(key,e.stdout.decode())
 r['unchanged']=all(sha(Path(n).read_bytes())==h for n,h in r['declared_inputs'].items()) and fixture.read_bytes()==body and sha(Path(__file__).read_bytes())==r['runner_sha256'];save();assert r['unchanged'];return {'receipt':str(p/'rows-zig-matrix-receipt.json'),'sha256':sha((p/'rows-zig-matrix-receipt.json').read_bytes()),'records':len(r['results']),'baseline_failures':4,'baseline_controls':2,'candidate_passes':6}

def watchdog_matrix(directory,source,before,compiler,env):
 fixture=ROOT/"platform/studio/native/current_stream_watchdog_test.c.fixture";body=checked(fixture);name="src/sdk/weights/streamed/csrc/q3_lookahead4_exl3.c";after=checked(source/name)
 work=directory/"watchdog-matrix";work.mkdir(mode=0o700);results=[]
 for label,data in [("baseline",before),("candidate",after)]:
  unit=work/label;unit.mkdir(mode=0o700);(unit/"pool.c").write_bytes(data);(unit/"main.c").write_bytes(body)
  for opt in ["-O0","-O3"]:
   for scenario in range(4):
    key=label+"-"+opt[1:]+"-"+str(scenario);binary=work/key
    build=subprocess.run([str(compiler),"-std=c11",opt,"-pthread","-DFIO_SCENARIO="+str(scenario),str(unit/"main.c"),"-o",str(binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30);(work/(key+"-build.log")).write_bytes(build.stdout)
    assert build.returncode==0,(key,build.stdout.decode()[-2000:])
    run=subprocess.run(["/usr/bin/sandbox-exec","-p","(version 1)(allow default)(deny network*)",str(binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=10);(work/(key+"-run.log")).write_bytes(run.stdout)
    expected=(run.returncode==1 and b"FIO_STREAM_WATCHDOG_FORCED_BEFORE_NEGATIVE" in run.stdout) if label=="baseline" and scenario==0 else (run.returncode==0 and b"PASS: watchdog force preserves negative" in run.stdout)
    results.append({"label":label,"optimize":opt,"scenario":scenario,"build_status":build.returncode,"run_status":run.returncode,"binary_sha256":digest(binary.read_bytes()),"expected":expected});assert expected,(key,run.stdout.decode())
 receipt={"scope":"actual_C_watchdog_host_event_forced_gate_negative_not_native_terminal_proof","before_sha256":digest(before),"candidate_sha256":digest(after),"fixture_sha256":digest(body),"results":results,"models":0,"inference":False,"Metal":False,"hardware_faults":False,"installed":False,"native_authority":False,"substitutions":["synthetic missing/satisfied/empty gates","final parked condition wait ends local loop","unexpected Metal signal aborts"]}
 path=work/"receipt.json";path.write_text(json.dumps(receipt,indent=2)+"\n");assert checked(source/name)==after and checked(fixture)==body
 return {"receipt":str(path),"sha256":digest(path.read_bytes()),"records":16,"baseline_failures":2,"baseline_controls":6,"candidate_passes":8}

def main():
 assert sys.version_info[:3]==(3,11,17),"Use the locked CPython3.11.17"
 assert platform.system()=="Darwin" and platform.machine()=="arm64" and os.geteuid()>0
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--isolated",action="store_true",required=True);parser.add_argument("--source",type=Path,required=True);parser.add_argument("--zig",type=Path,required=True);parser.add_argument("--watchdog",action="store_true");args=parser.parse_args()
 source=args.source;zig=args.zig
 for path in [source,zig]:assert path.is_absolute() and str(path).startswith("/private/tmp/") and path.resolve()==path
 assert digest(zig.read_bytes())==ZIG_SHA
 directory=Path(tempfile.mkdtemp(prefix="fios-009-stream-pool-stop-check-",dir="/private/tmp"));os.chmod(directory,0o700)
 env={"PATH":"/usr/bin:/bin","HOME":str(directory),"LANG":"C","DEVELOPER_DIR":"/Applications/Xcode.app/Contents/Developer","GIT_CONFIG_GLOBAL":"/dev/null","GIT_CONFIG_SYSTEM":"/dev/null","GIT_CONFIG_NOSYSTEM":"1","GIT_NO_REPLACE_OBJECTS":"1"}
 git=["/usr/bin/git","--no-replace-objects","-c","core.fsmonitor=false","-C",str(source)]
 assert command(git+["rev-parse","HEAD"],directory,env).decode().strip()==BASE
 patch=ROOT/"platform/studio/native/mlx-serve-current-stream-pool-stop.patch";helper=ROOT/"platform/studio/native/current_streamed_pool_uncertainty.zig"
 artifact_paths=[patch,helper,Path(__file__).resolve()]+[ROOT/"platform/studio/native"/n for n in ["current_stream_pool_stop_test.c.fixture","current_stream_pool_parent_test.zig.fixture","current_stream_pool_rows_test.zig.fixture"]]
 if args.watchdog:artifact_paths += [ROOT/"platform/studio/native/mlx-serve-current-stream-watchdog.patch",ROOT/"platform/studio/native/current_stream_watchdog_test.c.fixture"]
 artifacts={str(f):digest(checked(f)) for f in artifact_paths};current={}
 baseline=directory/"baseline-source";review=directory/"review"
 for path in [baseline,review]:path.mkdir(mode=0o700)
 for name in NAMES:
  data=command(git+["show",BASE+":"+name],directory,env)
  for path in [baseline,review]:
   dest=path/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
  current[name]=digest(checked(source/name))
 command(["/usr/bin/git","apply",str(patch)],review,env)
 watchdog_before=(review/"src/sdk/weights/streamed/csrc/q3_lookahead4_exl3.c").read_bytes()
 if args.watchdog:command(["/usr/bin/git","apply",str(ROOT/"platform/studio/native/mlx-serve-current-stream-watchdog.patch")],review,env)
 for name in NAMES:assert (review/name).read_bytes()==checked(source/name),name
 helper_name="src/fios/current_streamed_pool_uncertainty.zig";assert checked(source/helper_name)==checked(helper);current[helper_name]=digest(checked(helper))
 # Unchanged dependencies retain current original ingress layers; only the19
 # patched files project to their parent for the baseline component tests.
 for original in (source/"src/fios").glob("*.zig"):
  name=str(original.relative_to(source))
  if name not in NAMES:
   data=checked(original);dest=baseline/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
   current[name]=digest(data)
 for name in ["src/sdk/util/shared.zig","src/sdk/weights/streamed/sdk_ext/expert/policy.zig"]:
  data=checked(source/name);dest=baseline/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data);current[name]=digest(data)
 # Materialize only the component dependency closure needed by the actual Pool
 # and source ledger, retaining original bytes for all patched baseline files.
 pending=["src/fios/request_ownership.zig","src/fios/current_ane_native_cleanup_uncertainty.zig","src/sdk/weights/streamed/sdk_ext/expert/io.zig","src/sdk/weights/streamed/sdk_ext/expert/io_stub.zig","src/sdk/weights/streamed/sdk_ext/expert/policy.zig"]
 visited=set()
 while pending:
  name=pending.pop()
  if name in visited:continue
  visited.add(name);path=baseline/name
  if not path.exists():
   data=checked(source/name);path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data);current[name]=digest(data)
  for dependency in re.findall(r'@import\("([^"\n]+\.zig)"\)',path.read_text()):
   next_path=(path.parent/dependency).resolve();next_name=str(next_path.relative_to(baseline))
   if (source/next_name).is_file():pending.append(next_name)
 compiler=Path(command(["/usr/bin/xcrun","--find","clang"],directory,env).decode().strip());assert str(compiler).startswith("/Applications/Xcode.app/Contents/Developer/")
 suites={"C":c_matrix(directory,source,baseline,ROOT,str(zig),compiler),"Pool":pool_matrix(directory,source,baseline,ROOT,str(zig),compiler),"Rows":rows_matrix(directory,source,baseline,ROOT,str(zig),compiler)}
 if args.watchdog:
  watchdog_env=env|{"SDKROOT":command(["/usr/bin/xcrun","--show-sdk-path"],directory,env).decode().strip()}
  suites["Watchdog"]=watchdog_matrix(directory,source,watchdog_before,compiler,watchdog_env)
 assert all(digest(checked(source/name))==h for name,h in current.items())
 assert all(digest(checked(Path(name)))==h for name,h in artifacts.items())
 receipt={"version":1,"watchdog_overlay":args.watchdog,"scope":"selected_actual_C_and_Zig_pool_parent_refusal_only_not_native_authority","directory":str(directory),"source":str(source),"base":BASE,"patch_sha256":artifacts[str(patch)],"artifacts":artifacts,"selected_current_inputs":current,"clang":{"path":str(compiler),"sha256":digest(compiler.read_bytes())},"zig_sha256":ZIG_SHA,"suites":suites,"inputs_unchanged":True,"models":0,"inference":False,"Metal":False,"hardware_faults":False,"installed":False,"activation":False,"native_authority":False,"all_client_coverage":False,"whole_native_provenance":False}
 path=directory/"receipt.json";path.write_text(json.dumps(receipt,indent=2)+"\n")
 print(json.dumps({"directory":str(directory),"receipt_sha256":digest(path.read_bytes()),"records":94 if args.watchdog else 78,"expected_original_failures":26 if args.watchdog else 24,"original_controls":20 if args.watchdog else 14,"candidate_passes":48 if args.watchdog else 40,"models":0,"native_authority":False}))
if __name__=="__main__":main()
