#!/usr/bin/env python3
"""Actual ANE C error boundary, CPU metadata only; no native device/model."""
from pathlib import Path
import argparse, hashlib, json, os, platform, re, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--isolated',action='store_true',required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--zig',type=Path,required=True);a=p.parse_args()
assert platform.system()=='Darwin' and platform.machine()=='arm64' and os.geteuid()>0
assert all(n==n.resolve() and str(n).startswith('/private/tmp/') for n in [a.source,a.zig])
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(a.zig)=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
root=Path(__file__).resolve().parents[1];native=root/'platform/studio/native';fixture=native/'ane_eval_exception.m.fixture';zig_fixture=native/'ane_eval_exception_root.zig.fixture';patch=native/'mlx-serve-ane-eval-exception.patch';parents_file=native/'ane_eval_exception_parents.json';parents=json.loads(parents_file.read_text());name='lib/ane/ane_bridge.m';assert set(parents)=={name}
w=Path(tempfile.mkdtemp(prefix='fios-009-ane-eval-exception-check-',dir='/private/tmp'));env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
def output(args):return subprocess.check_output(args,env=env,text=True,timeout=20,stderr=subprocess.STDOUT).strip()
assert output(['/usr/bin/git','--no-replace-objects','-C',str(a.source),'rev-parse','HEAD'])=='3736ed55f81c6cf0966a0f0dc7265e783655d244'
assert output(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-version'])=='27.2'
sdk=Path(output(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path']));cc=Path(output(['/usr/bin/xcrun','--find','clang']));stub=sdk/'usr/lib/libc++.1.tbd'
review=w/'parent-review';(review/name).parent.mkdir(parents=True);(review/name).write_bytes((a.source/name).read_bytes())
for direction in ['reverse','forward']:
 args=['/usr/bin/git','apply']+(['--reverse'] if direction=='reverse' else [])+[str(patch)]
 subprocess.run(args,cwd=review,env=env,capture_output=True,check=True,timeout=15)
 if direction=='reverse':assert sha(review/name)==parents[name];parent=(review/name).read_bytes()
assert (review/name).read_bytes()==(a.source/name).read_bytes()
inputs={};pending=['fios/request_ownership.zig','fios/sdk_request_ownership.zig','fios/current_ane_native_cleanup_uncertainty.zig']
while pending:
 n=pending.pop()
 if n in inputs:continue
 file=a.source/'src'/n;inputs[n]=sha(file)
 for m in re.finditer(r'@import\("([^"\n]+\.zig)"\)',file.read_text()):
  dep=(file.parent/m.group(1)).resolve()
  if dep.exists():pending.append(str(dep.relative_to(a.source/'src')))
fixed={str(n):sha(n) for n in [a.source/name,a.source/'lib/ane/ane_bridge.h',fixture,zig_fixture,patch,parents_file,Path(__file__),cc,a.zig,stub]}
r={'scope':'actual_ANE_bridge_with_CPU_ObjectiveC_metadata_and_real_native_tracker_not_native_ANE_completion_proof','source':str(a.source),'native_inputs':inputs,'fixed_inputs':fixed,'records':[],'models':0,'inference':False,'GPU_dispatch':False,'ANE_framework_loaded':False,'hardware_faults':False,'installed':False,'native_authority':False,'whole_native_provenance':False}
def save():(w/'receipt.json').write_text(json.dumps(r,indent=2)+'\n')
def run(argv,where,bound,label,expected_failure=None,env_extra=None):
 try:
  result=subprocess.run(argv,cwd=where,env={**env,**(env_extra or {})},capture_output=True,text=True,timeout=bound);status=result.returncode;log=result.stdout+result.stderr
 except subprocess.TimeoutExpired as e:
  status=124;log=''.join(v.decode(errors='replace') if isinstance(v,bytes) else v or '' for v in [e.stdout,e.stderr])+'\nFinite child deadline; no terminal authority\n'
 file=where/(label+'.log');file.write_text(log)
 expected=status==1 and expected_failure in log if expected_failure else status==0
 r['records'].append({'label':label,'arguments':argv,'status':status,'expected':expected,'log_sha256':sha(file)});save();assert expected,log
 return log
print(json.dumps({'directory':str(w)}),flush=True)
for variant,data in [('parent',parent),('candidate',(a.source/name).read_bytes())]:
 for enabled in [True,False]:
  for mode,opt in [('Debug','-O0'),('ReleaseSafe','-O2')]:
   out=w/(variant+'-'+str(enabled)+'-'+mode);out.mkdir();(out/'ane_bridge.m').write_bytes(data);(out/'ane_bridge.h').write_bytes((a.source/'lib/ane/ane_bridge.h').read_bytes());(out/'fixture.m').write_text(fixture.read_text().replace('// ACTUAL_BRIDGE_INCLUDE','#include "ane_bridge.m"'))
   flags=[str(cc),'-fobjc-arc','-fblocks','-UNDEBUG','-target','arm64-apple-macosx26.2','-isysroot',str(sdk),opt]+(['-DFIOS_ANE_SOURCE'] if enabled else [])
   run(flags+[str(out/'fixture.m'),'-framework','Foundation','-framework','IOSurface','-o',str(out/'test')],out,90,'C-compile')
   for api in ['request','model']:
    for scenario in range(5 if enabled else 3):
     expected='ANE_EVAL_EXCEPTION_ESCAPES_WITHOUT_NEGATIVE_FENCE' if variant=='parent' and enabled and scenario==1 else None
     log=run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(out/'test'),api,str(scenario)],out,8,'C-'+api+'-'+str(scenario),expected)
     assert expected or 'PASS actual ANE C evaluation error boundary' in log
   if enabled:
    unit=out/'unit';unit.mkdir()
    for n in inputs:
     target=unit/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((a.source/'src'/n).read_bytes())
    (unit/'main.zig').write_bytes(zig_fixture.read_bytes());(unit/'options.zig').write_text('pub const fios_source_ane=true;\n')
    obj=out/'fixture.o';run(flags+['-DFIOS_ZIG_CLIENT','-c',str(out/'fixture.m'),'-o',str(obj)],out,90,'C-root-object')
    binary=out/'root-test';run([str(a.zig),'test','--test-no-exec','--test-filter','ANE evaluation exception',str(obj),'-O'+mode,'-lc',str(stub),'--sysroot',str(sdk),'-F/System/Library/Frameworks','-framework','Foundation','-framework','IOSurface','--dep','build_options','-Mroot='+str(unit/'main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-femit-bin='+str(binary)],out,120,'Zig-compile')
    for api in ['request','model']:
     expected='ANE_EXCEPTION_ORIGINAL_NATIVE_FENCE_MISSING' if variant=='parent' else None
     log=run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)],out,8,'Zig-'+api,expected,{'FIOS_ANE_FIXTURE_API':api})
     assert expected or 'PASS original ANE native root remains uncertain' in log
r['inputs_unchanged']=all(sha(a.source/'src'/n)==h for n,h in inputs.items()) and all(sha(Path(n))==h for n,h in fixed.items());save();assert r['inputs_unchanged'];print(json.dumps({'directory':str(w),'records':len(r['records']),'receipt_sha256':sha(w/'receipt.json'),'models':0,'native_authority':False}))
