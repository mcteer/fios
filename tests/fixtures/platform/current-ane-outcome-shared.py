#!/usr/bin/env python3
# Actual isolated host/unit metadata composition; no native ANE API is linked.
from pathlib import Path
import sys
import tempfile,hashlib,subprocess,os,json
assert sys.platform == 'darwin' and os.getuid() > 0
assert len(sys.argv) == 5 and sys.argv[1] == '--source' and sys.argv[3] == '--zig'
s=Path(sys.argv[2]);zig=Path(sys.argv[4]);root=Path(__file__).resolve().parents[3]
assert all(str(f).startswith('/private/tmp/') and f.resolve() == f for f in [s,zig])
d=Path(tempfile.mkdtemp(prefix='fios-009-ane-outcome-shared-',dir='/private/tmp'))
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
files=['fios/media_cleanup_host.zig','sdk/ane/cleanup_guard.zig','fios/request_ownership.zig','sdk/util/shared.zig']+[str(f.relative_to(s/'src')) for f in sorted((s/'src/fios').glob('current_*uncertainty.zig'))]
runner_hash=sha(Path(__file__))
inputs={n:sha(s/'src'/n) for n in files}
for n in files:
 f=s/'src'/n;st=f.lstat();assert f.is_file() and not f.is_symlink() and st.st_uid == os.getuid() and not st.st_mode & 0o022
 if n.startswith('fios/current_'):assert sha(root/'platform/studio/native'/Path(n).name)==inputs[n]
shared=subprocess.run(['/usr/bin/git','--no-replace-objects','-C',str(s),'show','4e231ceebe63308cc038117d40b9f9b64bd0372e:src/sdk/util/shared.zig'],capture_output=True,timeout=10,check=True).stdout
assert hashlib.sha256(shared).hexdigest()==inputs['sdk/util/shared.zig']
for n in files:
 f=d/n;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes((s/'src'/n).read_bytes());assert sha(f)==inputs[n]
fixtures={}
for role in ['host','unit']:
 f=root/('platform/studio/native/current_ane_run_'+role+'.zig.fixture');fixtures[str(f.relative_to(root))]=sha(f);(d/(role+'.zig')).write_bytes(f.read_bytes())
(d/'options.zig').write_text('pub const fios_source_ds4 = false;\n')
env={'PATH':'/usr/bin:/bin','HOME':str(d),'LANG':'C','LC_ALL':'C'}
zig=str(zig);assert sha(Path(zig))=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
r={'directory':str(d),'runner_sha256':runner_hash,'source_scope':'declared_current_metadata_inputs_not_whole_native_provenance','inputs':inputs,'fixtures':fixtures,'models':0,'native_backend':False,'native_authority':False,'installed':False,'results':[]}
for mode in ['Debug','ReleaseSafe']:
 obj=d/(mode+'.o');binary=d/mode
 commands=[ [zig,'build-obj','-O'+mode,'-lc','-Mroot='+str(d/'unit.zig'),'-femit-bin='+str(obj)], [zig,'build-exe','-O'+mode,str(obj),'-lc','--dep','build_options','-Mroot='+str(d/'host.zig'),'-Mbuild_options='+str(d/'options.zig'),'-femit-bin='+str(binary)] ]
 for index,args in enumerate(commands):
  with (d/(mode+'-build-'+str(index)+'.log')).open('w') as out:subprocess.run(args,env=env,cwd=d,stdout=out,stderr=subprocess.STDOUT,timeout=120,check=True)
 digest=sha(binary);object_digest=sha(obj)
 result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)],env=env,cwd=d,capture_output=True,timeout=10)
 log=result.stdout+result.stderr;(d/(mode+'.log')).write_bytes(log)
 assert result.returncode==0 and b'PASS: separate actual unit/host ANE metadata latch preserves original lineage' in log,(d,mode)
 assert sha(binary)==digest and sha(obj)==object_digest
 r['results'].append({'mode':mode,'binary_sha256':digest,'unit_object_sha256':object_digest,'returncode':0})
assert sha(Path(__file__))==runner_hash
for n in files:assert sha(s/'src'/n)==inputs[n] and sha(d/n)==inputs[n]
for n,h in fixtures.items():assert sha(root/n)==h
(d/'receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'ok':True,'directory':str(d),'receipt_sha256':sha(d/'receipt.json'),'cases':len(r['results']),'native_backend':False,'models':0}))
