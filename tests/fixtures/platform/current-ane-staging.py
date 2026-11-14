#!/usr/bin/env python3
# Disposable fixture-owned files only; no process signal, ANE API or model.
from pathlib import Path
import tempfile,hashlib,subprocess,os,json,sys
assert sys.platform == 'darwin' and os.getuid() > 0
assert len(sys.argv) == 3 and sys.argv[1] == '--source'
s=Path(sys.argv[2]);root=Path(__file__).resolve().parents[3];kind='current'
assert str(s).startswith('/private/tmp/') and s.resolve() == s
d=Path(tempfile.mkdtemp(prefix='fios-009-ane-staging-'+kind+'-',dir='/private/tmp'))
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
files=['lib/ane/ane_bridge.m','lib/ane/ane_bridge.h'];inputs={n:sha(s/n) for n in files};runner_hash=sha(Path(__file__));
for n in files:
 f=s/n;st=f.lstat();assert f.is_file() and not f.is_symlink() and st.st_uid == os.getuid() and not st.st_mode & 0o022
fixture=root/'platform/studio/native/current_ane_staging.m.fixture';fixture_hash=sha(fixture)
(d/'unit.m').write_bytes((s/'lib/ane/ane_bridge.m').read_bytes()+b'\n'+fixture.read_bytes());(d/'ane_bridge.h').write_bytes((s/'lib/ane/ane_bridge.h').read_bytes())
env={'PATH':'/usr/bin:/bin','HOME':str(d),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
compiler=subprocess.run(['/usr/bin/xcrun','--sdk','macosx','--find','clang'],env=env,capture_output=True,text=True,timeout=10,check=True).stdout.strip();sdk=subprocess.run(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],env=env,capture_output=True,text=True,timeout=10,check=True).stdout.strip()
r={'directory':str(d),'runner_sha256':runner_hash,'source_scope':'declared_actual_C_staging_filesystem_not_native_execution','inputs':inputs,'fixture_sha256':fixture_hash,'compiler_sha256':sha(Path(compiler)),'models':0,'process_signals':0,'filesystem_scope':'only_disposable_fixture_owned_paths','native_ane_api_executed':False,'native_authority':False,'installed':False,'results':[]}
for mode in ['O0','O2']:
 for enabled in [False,True]:
  label=mode+('-private' if enabled else '-legacy');b=d/label;args=[compiler,'-std=gnu17','-fobjc-arc','-isysroot',sdk,'-'+mode,'-I'+str(d),str(d/'unit.m'),'-framework','Foundation','-framework','IOSurface','-o',str(b)]
  if enabled:args.insert(1,'-DFIOS_ANE_SOURCE=1')
  with (d/(label+'-build.log')).open('w') as out:subprocess.run(args,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=60,check=True)
  (d/(label+'-files')).mkdir();digest=sha(b);result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(b),str(d/(label+'-files'))],env=env,capture_output=True,timeout=10);log=result.stdout+result.stderr;(d/(label+'.log')).write_bytes(log)
  expected_failure=kind=='baseline' and enabled
  assert result.returncode==(1 if expected_failure else 0),(d,label,result.returncode)
  assert (b'FIO_CURRENT_ANE_REPLACED_EXISTING_STAGING' if expected_failure else b'PASS: private staging refuses existing destination; legacy control preserved') in log,(d,label)
  assert sha(b)==digest;r['results'].append({'mode':mode,'private':enabled,'binary_sha256':digest,'returncode':result.returncode,'expected_failure':expected_failure})
assert sha(Path(__file__))==runner_hash
for n,h in inputs.items():assert sha(s/n)==h
assert sha(fixture)==fixture_hash
(d/'receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'ok':True,'directory':str(d),'receipt_sha256':sha(d/'receipt.json'),'expected_failures':sum(x['expected_failure'] for x in r['results']),'total':len(r['results']),'models':0}))
