#!/usr/bin/env python3
# Actual empty C bookkeeping binding refusal composed with current negative/source helpers.
from pathlib import Path
import sys
import tempfile,hashlib,subprocess,os,json
assert sys.platform == 'darwin' and os.getuid() > 0
assert len(sys.argv) == 5 and sys.argv[1] == '--source' and sys.argv[3] == '--zig'
s=Path(sys.argv[2]);zig=Path(sys.argv[4]);root=Path(__file__).resolve().parents[3]
assert all(str(f).startswith('/private/tmp/') and f.resolve() == f for f in [s,zig])
d=Path(tempfile.mkdtemp(prefix='fios-009-ane-bindings-root-',dir='/private/tmp'))
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
files=['src/fios/media_cleanup_host.zig','src/sdk/ane/cleanup_guard.zig','src/fios/request_ownership.zig','src/sdk/util/shared.zig','lib/ane/ane_bridge.m','lib/ane/ane_bridge.h']+['src/'+str(f.relative_to(s/'src')) for f in sorted((s/'src/fios').glob('current_*uncertainty.zig'))]
runner_hash=sha(Path(__file__))
inputs={n:sha(s/n) for n in files}
for n in files:
 f=s/n;st=f.lstat();assert f.is_file() and not f.is_symlink() and st.st_uid == os.getuid() and not st.st_mode & 0o022
 if n.startswith('src/fios/current_'):assert sha(root/'platform/studio/native'/Path(n).name)==inputs[n]
shared=subprocess.run(['/usr/bin/git','--no-replace-objects','-C',str(s),'show','4e231ceebe63308cc038117d40b9f9b64bd0372e:src/sdk/util/shared.zig'],capture_output=True,timeout=10,check=True).stdout
assert hashlib.sha256(shared).hexdigest()==inputs['src/sdk/util/shared.zig']
for n in files:
 if n.startswith('src/'):
  dest=d/n[4:];dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes((s/n).read_bytes())
fixtures={n:sha(root/n) for n in ['platform/studio/native/current_ane_bindings_probe.m.fixture','platform/studio/native/current_ane_bindings_host.zig.fixture']}
(d/'bridge.m').write_bytes((s/'lib/ane/ane_bridge.m').read_bytes()+b'\n'+(root/'platform/studio/native/current_ane_bindings_probe.m.fixture').read_bytes());(d/'ane_bridge.h').write_bytes((s/'lib/ane/ane_bridge.h').read_bytes())
(d/'host.zig').write_bytes((root/'platform/studio/native/current_ane_bindings_host.zig.fixture').read_bytes());(d/'options.zig').write_text('pub const fios_source_ane = true;\npub const fios_source_ds4 = false;\n')
env={'PATH':'/usr/bin:/bin','HOME':str(d),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
compiler=subprocess.run(['/usr/bin/xcrun','--sdk','macosx','--find','clang'],env=env,capture_output=True,text=True,timeout=10,check=True).stdout.strip();sdk=subprocess.run(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],env=env,capture_output=True,text=True,timeout=10,check=True).stdout.strip()
zig=str(zig);assert sha(Path(zig))=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
r={'directory':str(d),'runner_sha256':runner_hash,'source_scope':'declared_actual_C_bookkeeping_binding_refusal_to_current_metadata_root_not_whole_native_provenance','inputs':inputs,'fixtures':fixtures,'compiler_sha256':sha(Path(compiler)),'models':0,'native_ane_api_executed':False,'healthy_iosurface_control':True,'surface_bytes_max':32768,'native_authority':False,'installed':False,'results':[]}
for mode,opt in [('Debug','-O0'),('ReleaseSafe','-O2')]:
 obj=d/(mode+'.o');b=d/mode
 commands=[[compiler,'-std=gnu17','-fobjc-arc','-DFIOS_ANE_SOURCE=1','-isysroot',sdk,opt,'-I'+str(d),'-c',str(d/'bridge.m'),'-o',str(obj)],[zig,'build-exe','-O'+mode,str(obj),'-lc','-framework','Foundation','-framework','IOSurface','--dep','build_options','-Mroot='+str(d/'host.zig'),'-Mbuild_options='+str(d/'options.zig'),'-femit-bin='+str(b)]]
 for index,args in enumerate(commands):
  with (d/(mode+'-build-'+str(index)+'.log')).open('w') as out:subprocess.run(args,env=env,cwd=d,stdout=out,stderr=subprocess.STDOUT,timeout=120,check=True)
 digest=sha(b);object_digest=sha(obj)
 result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(b)],env=env,capture_output=True,timeout=10)
 log=result.stdout+result.stderr;(d/(mode+'.log')).write_bytes(log)
 assert result.returncode==0 and b'PASS: actual ANE C bookkeeping binding refusal preserves original lineage, models0' in log,(d,mode)
 assert sha(b)==digest and sha(obj)==object_digest;r['results'].append({'mode':mode,'binary_sha256':digest,'object_sha256':object_digest,'returncode':0})
assert sha(Path(__file__))==runner_hash
for n,h in inputs.items():assert sha(s/n)==h
for n,h in fixtures.items():assert sha(root/n)==h
(d/'receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'ok':True,'directory':str(d),'receipt_sha256':sha(d/'receipt.json'),'cases':len(r['results']),'models':0,'native_ane_api_executed':False,'healthy_iosurface_control':True,'surface_bytes_max':32768}))
