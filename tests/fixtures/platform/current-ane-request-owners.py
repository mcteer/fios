#!/usr/bin/env python3
# Ordinary bookkeeping callbacks only; no native ANE model/API or process signal.
from pathlib import Path
import tempfile,hashlib,subprocess,os,json,sys
assert sys.platform == 'darwin' and os.getuid() > 0
assert len(sys.argv) == 3 and sys.argv[1] == '--source'
s=Path(sys.argv[2]);root=Path(__file__).resolve().parents[3];kind='current'
assert str(s).startswith('/private/tmp/') and s.resolve() == s
d=Path(tempfile.mkdtemp(prefix='fios-009-ane-request-owners-'+kind+'-',dir='/private/tmp'))
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
files=['lib/ane/ane_bridge.m','lib/ane/ane_bridge.h'];inputs={n:sha(s/n) for n in files};runner_hash=sha(Path(__file__));
for n in files:
 f=s/n;st=f.lstat();assert f.is_file() and not f.is_symlink() and st.st_uid == os.getuid() and not st.st_mode & 0o022
fixture=root/'platform/studio/native/current_ane_request_owners.m.fixture';fixture_hash=sha(fixture)
(d/'unit.m').write_bytes((s/'lib/ane/ane_bridge.m').read_bytes()+b'\n'+fixture.read_bytes());(d/'ane_bridge.h').write_bytes((s/'lib/ane/ane_bridge.h').read_bytes())
env={'PATH':'/usr/bin:/bin','HOME':str(d),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
compiler=subprocess.run(['/usr/bin/xcrun','--sdk','macosx','--find','clang'],env=env,capture_output=True,text=True,timeout=10,check=True).stdout.strip();sdk=subprocess.run(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],env=env,capture_output=True,text=True,timeout=10,check=True).stdout.strip()
r={'directory':str(d),'runner_sha256':runner_hash,'source_scope':'declared_actual_C_program_request_owners_and_tiny_healthy_IOSurface_not_native_ANE_execution','inputs':inputs,'fixture_sha256':fixture_hash,'compiler_sha256':sha(Path(compiler)),'models':0,'process_signals':0,'filesystem_mutations_by_fixture':0,'native_ane_api_executed':False,'healthy_iosurface_control':True,'surface_bytes_max':32768,'native_authority':False,'installed':False,'results':[]}
for mode in ['O0','O2']:
 label=mode;b=d/label
 args=[compiler,'-std=gnu17','-fobjc-arc','-DFIOS_ANE_SOURCE=1','-isysroot',sdk,'-'+mode,'-I'+str(d),str(d/'unit.m'),'-framework','Foundation','-framework','IOSurface','-o',str(b)]
 with (d/(label+'-build.log')).open('w') as out:subprocess.run(args,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=60,check=True)
 digest=sha(b)
 for case in ['healthy','destructor-fence','pending']:
  result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(b),case],env=env,capture_output=True,timeout=10)
  (d/(label+'-'+case+'.log')).write_bytes(result.stdout+result.stderr)
  assert result.returncode==0 and b'PASS: private ANE program request retains original surface and parent owners' in result.stdout+result.stderr,(d,mode,case)
  assert sha(b)==digest;r['results'].append({'mode':mode,'case':case,'binary_sha256':digest,'returncode':0,'expected_failure':False})
assert sha(Path(__file__))==runner_hash
for n,h in inputs.items():assert sha(s/n)==h
assert sha(fixture)==fixture_hash
(d/'receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'ok':True,'directory':str(d),'receipt_sha256':sha(d/'receipt.json'),'expected_failures':sum(x['expected_failure'] for x in r['results']),'total':len(r['results']),'models':0}))
