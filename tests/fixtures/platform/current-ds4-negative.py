#!/usr/bin/env python3
# Isolated mock metadata getters; never links a native backend or invokes a model.
from pathlib import Path
import sys
import tempfile,hashlib,subprocess,os,json
assert sys.platform == 'darwin' and os.getuid() > 0
assert len(sys.argv) == 5 and sys.argv[1] == '--source' and sys.argv[3] == '--zig'
s=Path(sys.argv[2]); zig=Path(sys.argv[4]); root=Path(__file__).resolve().parents[3]
assert all(str(f).startswith('/private/tmp/') and f.resolve() == f for f in [s, zig])
d=Path(tempfile.mkdtemp(prefix='fios-009-ds4-negative-',dir='/private/tmp'))
files=['fios/media_cleanup_host.zig','sdk/ane/cleanup_guard.zig','fios/request_ownership.zig','fios/current_backend_uncertainty.zig','fios/current_cleanup_uncertainty.zig','fios/current_locked_cleanup_uncertainty.zig','fios/current_ds4_backend_uncertainty.zig','fios/current_ds4_cleanup_uncertainty.zig','fios/current_ds4_locked_cleanup_uncertainty.zig','sdk/util/shared.zig']
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
assert sha(zig) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
files=list(dict.fromkeys(files+[str(f.relative_to(s/'src')) for f in sorted((s/'src/fios').glob('current_*uncertainty.zig'))]))
runner_hash=sha(Path(__file__))
inputs={n:sha(s/'src'/n) for n in files}
upstream=subprocess.run(['/usr/bin/git','--no-replace-objects','-C',str(s),'show','4e231ceebe63308cc038117d40b9f9b64bd0372e:src/sdk/util/shared.zig'],capture_output=True,timeout=10,check=True).stdout
assert hashlib.sha256(upstream).hexdigest() == inputs['sdk/util/shared.zig']
for n in files:
 f=s/'src'/n; st=f.lstat(); assert f.is_file() and not f.is_symlink() and st.st_uid == os.getuid() and not st.st_mode & 0o022
 if n.startswith('fios/current_'): assert sha(root/'platform/studio/native'/Path(n).name) == inputs[n]
for n in files:
 f=d/n;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes((s/'src'/n).read_bytes());assert sha(f)==inputs[n]
fixture=root/'platform/studio/native/current_ds4_negative_test.zig.fixture';(d/'test.zig').write_bytes(fixture.read_bytes());fixture_hash=sha(fixture)
(d/'options.zig').write_text('pub const fios_source_ds4 = true;\n')
env={'PATH':'/usr/bin:/bin','HOME':str(d),'LANG':'C','LC_ALL':'C'}
r={'directory':str(d),'inputs':inputs,'fixture_sha256':fixture_hash,'models':0,'runner_sha256':runner_hash,'source_scope':'declared_metadata_inputs_not_whole_native_provenance','native_backend':False,'native_authority':False,'installed':False,'results':[]}
zig=str(zig)
for mode in ['Debug','ReleaseSafe']:
 b=d/mode;args=[zig,'test','-O'+mode,'-lc','--dep','build_options','-Mroot='+str(d/'test.zig'),'-Mbuild_options='+str(d/'options.zig'),'--test-filter','fios current DS4 fixed','--test-no-exec','-femit-bin='+str(b)]
 with (d/(mode+'-build.log')).open('w') as out:subprocess.run(args,env=env,cwd=d,stdout=out,stderr=subprocess.STDOUT,timeout=120,check=True)
 h=sha(b)
 for scenario in ['healthy','host','gpu']:
  result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(b)],env={**env,'FIOS_DS4_NEGATIVE_SCENARIO':scenario},cwd=d,capture_output=True,timeout=10)
  log=result.stdout+result.stderr;(d/(mode+'-'+scenario+'.log')).write_bytes(log)
  assert result.returncode==0 and b'PASS: fixed DS4 metadata probe composition' in log and b'1/2 test.test.fios current DS4 fixed negative composition...' in log and b'2/2 fios.request_ownership.test_0...OK\nAll 2 tests passed.' in log,(d,mode,scenario)
  assert sha(b)==h;r['results'].append({'mode':mode,'scenario':scenario,'binary_sha256':h,'returncode':0})
assert sha(fixture)==fixture_hash and sha(Path(__file__))==runner_hash
for n in files:assert sha(s/'src'/n)==inputs[n] and sha(d/n)==inputs[n]
(d/'receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'ok':True,'directory':str(d),'receipt_sha256':sha(d/'receipt.json'),'cases':len(r['results']),'native_backend':False,'models':0}))
