#!/usr/bin/env python3
"""Exact current host module local-retirement metadata; no native proof."""
from pathlib import Path
import argparse, hashlib, json, os, platform, re, subprocess, tempfile
p=argparse.ArgumentParser()
p.add_argument('--isolated',action='store_true',required=True)
p.add_argument('--source',type=Path,required=True)
p.add_argument('--zig',type=Path,required=True)
p.add_argument('--expect-missing-retirement',action='store_true')
p.add_argument('--wire',action='store_true')
a=p.parse_args()
assert platform.system()=='Darwin' and platform.machine()=='arm64' and os.geteuid()>0
assert all(x==x.resolve() and str(x).startswith('/private/tmp/') for x in [a.source,a.zig])
sha=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
assert sha(a.zig)=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
root=Path(__file__).resolve().parents[1]
parents=root/'platform/studio/native/request_retirement_parents.json'
patch=root/'platform/studio/native/mlx-serve-request-retirement.patch'
fixture=root/'platform/studio/native/request_ownership_test.zig'
canonical=root/'platform/studio/native/request_ownership.zig'
wire_patch=root/'platform/studio/native/mlx-serve-request-retirement-wire.patch'
wire_parents=root/'platform/studio/native/request_retirement_wire_parents.json'
w=Path(tempfile.mkdtemp(prefix='fios-009-current-retirement-',dir='/private/tmp'))
unit=w/'unit';unit.mkdir()
env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C','GIT_CONFIG_GLOBAL':'/dev/null','GIT_CONFIG_NOSYSTEM':'1'}
revision=subprocess.check_output(['/usr/bin/git','--no-replace-objects','-C',str(a.source),'rev-parse','HEAD'],env=env,text=True,timeout=15).strip()
assert revision=='3736ed55f81c6cf0966a0f0dc7265e783655d244'
parent_hashes=json.loads(parents.read_text());assert list(parent_hashes)==['src/fios/request_ownership.zig']
assert all(sha(a.source/name)==value for name,value in parent_hashes.items())
inputs={};pending=['fios/request_ownership.zig']+(['fios/control_protocol.zig','fios/control_transport.zig'] if a.wire else [])
while pending:
    name=pending.pop()
    if name in inputs:continue
    source=a.source/'src'/name;data=source.read_bytes();inputs[name]=sha(source)
    target=unit/'src'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)',data.decode()):
        dependency=(source.parent/match.group(1)).resolve()
        if dependency.exists():pending.append(str(dependency.relative_to(a.source/'src')))
if not a.expect_missing_retirement:
    subprocess.run(['/usr/bin/git','apply','--check',str(patch)],cwd=unit,env=env,check=True,capture_output=True,timeout=15)
    subprocess.run(['/usr/bin/git','apply',str(patch)],cwd=unit,env=env,check=True,capture_output=True,timeout=15)
if a.wire:
    wire_hashes=json.loads(wire_parents.read_text())
    assert set(wire_hashes)=={'src/fios/control_protocol.zig','src/fios/control_transport.zig'}
    assert all(sha(a.source/name)==value for name,value in wire_hashes.items())
    subprocess.run(['/usr/bin/git','apply','--check',str(wire_patch)],cwd=unit,env=env,check=True,capture_output=True,timeout=15)
    subprocess.run(['/usr/bin/git','apply',str(wire_patch)],cwd=unit,env=env,check=True,capture_output=True,timeout=15)
entry=unit/'src/main.zig'
entry.write_text(fixture.read_text().replace('@import("request_ownership.zig")','@import("fios/request_ownership.zig")')+('\ntest { _ = @import("fios/control_protocol.zig"); _ = @import("fios/control_transport.zig"); }\n' if a.wire else ''))
(unit/'options.zig').write_text('pub const fios_source_ane=false;\n')
tracked={str(file.relative_to(root)):sha(file) for file in [parents,patch,fixture,canonical,Path(__file__)]+([wire_patch,wire_parents] if a.wire else [])}
r={'scope':'actual_current_host_module_local_reference_retirement_not_native_terminal_proof','source':str(a.source),'native_base':revision,'native_inputs':inputs,'fixture_inputs':tracked,'candidate_module_sha256':sha(unit/'src/fios/request_ownership.zig'),'wire':a.wire,'expect_missing_retirement':a.expect_missing_retirement,'records':[],'models':0,'inference':False,'installed':False,'native_authority':False,'whole_native_provenance':False}
def save():(w/'receipt.json').write_text(json.dumps(r,indent=2)+'\n')
save();print(json.dumps({'directory':str(w)}),flush=True)
for mode in ['Debug','ReleaseSafe']:
    binary=w/mode
    command=[str(a.zig),'test','--test-no-exec','--test-filter','retirement','-O'+mode,'-lc','--dep','build_options','-Mroot='+str(entry),'-Mbuild_options='+str(unit/'options.zig'),'-femit-bin='+str(binary)]
    result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=120)
    log=w/(mode+'-compile.log');log.write_text(result.stdout+result.stderr)
    passed=(result.returncode!=0 and "no field or member function named 'retirementSnapshot'" in log.read_text()) if a.expect_missing_retirement else result.returncode==0
    r['records'].append({'mode':mode,'stage':'compile','status':result.returncode,'expected':passed,'log_sha256':sha(log)});save();assert passed,log.read_text()
    if a.expect_missing_retirement:continue
    result=subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)],env=env,capture_output=True,text=True,timeout=30)
    log=w/(mode+'-run.log');log.write_text(result.stdout+result.stderr)
    passed=result.returncode==0 and ('All '+str(8 if a.wire else 6)+' tests passed.') in log.read_text()
    r['records'].append({'mode':mode,'stage':'runtime','status':result.returncode,'expected':passed,'log_sha256':sha(log)});save();assert passed,log.read_text()
r['inputs_unchanged']=all(sha(a.source/'src'/name)==value for name,value in inputs.items()) and all(sha(root/name)==value for name,value in tracked.items())
save();assert r['inputs_unchanged']
print(json.dumps({'directory':str(w),'receipt_sha256':sha(w/'receipt.json'),'records':len(r['records']),'native_authority':False}))
