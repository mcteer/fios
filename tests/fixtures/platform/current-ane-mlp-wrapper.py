#!/usr/bin/env python3
# CPU bookkeeping and tiny healthy IOSurface ownership only; no ANE model/API.
from pathlib import Path
import tempfile,subprocess,hashlib,json,os,sys
assert sys.platform=='darwin' and os.getuid()>0
assert len(sys.argv)==3 and sys.argv[1]=='--source'
s=Path(sys.argv[2]);assert str(s).startswith('/private/tmp/') and s.resolve()==s
d=Path(tempfile.mkdtemp(prefix='fios-009-ane-mlp-wrapper-current-',dir='/private/tmp'))
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
files=['lib/ane/ane_bridge.m','lib/ane/ane_bridge.h','lib/ane/ane_mlp.m','lib/ane/ane_mlp.h']
inputs={n:sha(s/n) for n in files}
for n in files:
 f=s/n;st=f.lstat();assert f.is_file() and not f.is_symlink() and st.st_uid==os.getuid() and not st.st_mode & 0o022
for n in files:
 (d/Path(n).name).write_bytes((s/n).read_bytes());assert sha(d/Path(n).name)==inputs[n]
root=Path(__file__).resolve().parents[3]
fixture=(root/'platform/studio/native/current_ane_mlp_wrapper.m.fixture').read_text()
(d/'probe.m').write_text(fixture)
env={'PATH':'/usr/bin:/bin','HOME':str(d),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
compiler=subprocess.check_output(['/usr/bin/xcrun','--sdk','macosx','--find','clang'],env=env,text=True,timeout=10).strip()
sdk=subprocess.check_output(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],env=env,text=True,timeout=10).strip()
r={'directory':str(d),'inputs':inputs,'runner_sha256':sha(Path(__file__)),'source_scope':'declared_actual_C_MLP_wrapper_and_raw_model_owner_cleanup_not_whole_native_provenance','compiler_sha256':sha(Path(compiler)),'fixture_sha256':sha(d/'probe.m'),'models':0,'native_ane_api_executed':False,'healthy_iosurface_control':True,'surface_bytes_max':32768,'installed':False,'native_authority':False,'results':[]}
for mode in ['O0','O2']:
 b=d/mode
 with (d/(mode+'-build.log')).open('w') as out:
  subprocess.run([compiler,'-isysroot',sdk,'-std=gnu17','-fobjc-arc','-DFIOS_ANE_SOURCE=1','-'+mode,'-framework','Foundation','-framework','IOSurface',str(d/'probe.m'),'-o',str(b)],env=env,stdout=out,stderr=subprocess.STDOUT,timeout=120,check=True)
 digest=sha(b)
 for case in ['healthy','pending']:
  result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(b)]+(['pending'] if case=='pending' else []),env=env,capture_output=True,timeout=10)
  (d/(mode+'-'+case+'.log')).write_bytes(result.stdout+result.stderr)
  expected=0
  assert sha(b)==digest
  assert result.returncode==expected,(d,mode,case,result.returncode)
  assert b'FIO_ANE_MLP_OUTER_SURFACES_DROPPED_AFTER_RAW_REFUSAL' not in result.stderr
  r['results'].append({'mode':mode,'case':case,'returncode':result.returncode,'expected_failure':False,'binary_sha256':sha(b)})
assert all(sha(s/n)==h and sha(d/Path(n).name)==h for n,h in inputs.items())
assert sha(Path(compiler))==r['compiler_sha256']
assert sha(Path(__file__))==r['runner_sha256']
assert sha(root/'platform/studio/native/current_ane_mlp_wrapper.m.fixture')==r['fixture_sha256']
(d/'receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'directory':str(d),'receipt_sha256':sha(d/'receipt.json'),'expected_failures':0,'passed':4}))
