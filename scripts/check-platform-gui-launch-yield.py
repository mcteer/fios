#!/usr/bin/env python3
"""Denial-only GUI handover: actual prefix/decision and private-path OS readers."""
from pathlib import Path
import argparse, tempfile, subprocess, json, hashlib, shutil, os, platform
p=argparse.ArgumentParser();p.add_argument('--mock',action='store_true');p.add_argument('--isolated',action='store_true');p.add_argument('--source',type=Path);a=p.parse_args()
assert platform.system()=='Darwin' and os.geteuid()>0
assert (a.mock and not a.isolated and a.source is None) or (a.isolated and not a.mock and a.source is not None)
root=Path(__file__).resolve().parents[1];base=root/'platform/studio/native';sha=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
names=['gui_fios_launch_policy.swift.inc','gui_launch_yield_previous.inc','gui_launch_yield_scope.inc','gui_launch_yield_test.swift.fixture','gui_launch_yield_parents.json','mlx-serve-gui-launch-yield.patch'];inputs={n:sha(base/n) for n in names};runner_sha=sha(Path(__file__))
w=Path(tempfile.mkdtemp(prefix='fios-009-gui-launch-yield-check-',dir='/private/tmp'));env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C','GIT_CONFIG_GLOBAL':'/dev/null','GIT_CONFIG_NOSYSTEM':'1','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
def command(argv,timeout=15):return subprocess.check_output(argv,env=env,text=True,stderr=subprocess.STDOUT,timeout=timeout)
version=command(['/usr/bin/swiftc','--version']);sdk=command(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-version']).strip()
source_inputs={};source=None
if a.source:
 source=a.source.resolve();assert source==a.source and str(source).startswith('/private/tmp/')
 assert command(['/usr/bin/git','--no-replace-objects','-C',str(source),'rev-parse','HEAD']).strip()=='4e231ceebe63308cc038117d40b9f9b64bd0372e'
 assert sdk=='27.2'
 paths=['app/Sources/MLXServe/Services/ServerManager.swift','app/Sources/MLXServe/Services/FiosGUILaunchPolicy.swift'];source_inputs={n:sha(source/n) for n in paths};parent=w/'parent'
 for n in paths:
  target=parent/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source/n,target)
 subprocess.run(['/usr/bin/git','apply','--reverse',str(base/names[-1])],cwd=parent,env=env,check=True,capture_output=True,timeout=15)
 parents=json.loads((base/'gui_launch_yield_parents.json').read_text());assert len(parents)==1 and all(sha(parent/n)==h for n,h in parents.items());assert not (parent/paths[1]).exists()
 def fragment(text):
  start=text.index('    private func launch(args: [String], options: ServerOptions) {');end=text.index('        let binaryPath = Self.resolveBinaryPath()',start);return text[start:end]+'    }\n'
 assert fragment((parent/paths[0]).read_text())==(base/'gui_launch_yield_previous.inc').read_text()
 assert fragment((source/paths[0]).read_text())==(base/'gui_launch_yield_scope.inc').read_text()
 assert (source/paths[1]).read_bytes()==(base/'gui_fios_launch_policy.swift.inc').read_bytes()
 subprocess.run(['/usr/bin/git','apply',str(base/names[-1])],cwd=parent,env=env,check=True,capture_output=True,timeout=15);assert all(sha(parent/n)==h for n,h in source_inputs.items())
helper=(base/'gui_fios_launch_policy.swift.inc').read_text()
def replace_method(text,marker,body):
 start=text.index(marker);opening=text.index('{',start);depth=0
 for i in range(opening,len(text)):
  if text[i]=='{':depth+=1
  elif text[i]=='}':
   depth-=1
   if depth==0:return text[:opening+1]+'\n'+body+'\n    '+text[i:]
 raise AssertionError('unbalanced')
modeled=replace_method(helper,'private static func currentImage()','return Probe.image');modeled=replace_method(modeled,'private static func configurationPresence()','Probe.lookups += 1; return Probe.presence')
receipt={'scope':'GUI_launch_prefix_and_private_path_metadata_readers_not_GUI_main_or_native_authority','mode':'mock' if a.mock else 'isolated_source','source':str(source) if source else None,'source_inputs':source_inputs,'inputs':inputs,'runner_sha256':runner_sha,'swift':version,'sdk':sdk,'records':[],'GUI_main_executed':False,'model_requests':0,'OS_signals':False,'installed':False,'native_authority':False,'whole_native_provenance':False}
save=lambda:(w/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');save();print(json.dumps({'directory':str(w),'model_requests':0}),flush=True)
def compile_and_run(file,binary,opt,cases):
 argv=['/usr/bin/swiftc','-swift-version','5',opt]+([] if a.mock else ['-target','arm64-apple-macosx26.2'])+[str(file),'-o',str(binary)]
 r=subprocess.run(argv,env=env,capture_output=True,text=True,timeout=60);log=r.stdout+r.stderr;path=binary.with_suffix('.build.log');path.write_text(log);receipt['records'].append({'stage':'compile','name':binary.name,'status':r.returncode,'expected':r.returncode==0,'log_sha256':sha(path)});save();assert r.returncode==0,log
 assert not any(line.strip().endswith(' _kill') for line in command(['/usr/bin/nm','-u',str(binary)]).splitlines())
 for name,negative,marker in cases:
  argv=['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)]+([name] if name else []);r=subprocess.run(argv,env=env,capture_output=True,text=True,timeout=5);log=r.stdout+r.stderr;path=w/('run-'+str(len(receipt['records']))+'.log');path.write_text(log);expected=(r.returncode==77 and marker in log) if negative else r.returncode==0 and 'PASS' in log;receipt['records'].append({'stage':'run','name':name or binary.name,'status':r.returncode,'negative':negative,'expected':expected,'log_sha256':sha(path)});save();assert expected,log
fixture=(base/'gui_launch_yield_test.swift.fixture').read_text();assert fixture.count('@@BODY@@')==1
for label,name in [('parent','gui_launch_yield_previous.inc'),('candidate','gui_launch_yield_scope.inc')]:
 file=w/(label+'.swift');file.write_text(modeled+'\n'+fixture.replace('@@BODY@@',(base/name).read_text()))
 for mode,opt in [('Debug','-Onone'),('optimized','-O')]:
  cases=[(n,label=='parent' and n in ['managed','unavailable','unverified'],'GUI_FIOS_POLICY_') for n in ['managed','unavailable','unverified','development','ordinary','occupied']];compile_and_run(file,w/(label+'-'+mode),opt,cases)
for name in ['absent','regular','directory','symlink','unavailable','actualImage']:
 d=w/('reader-'+name);d.mkdir();target=d/'policy'
 if name=='regular':target.write_text('opaque invalid policy bytes; no content parsing')
 if name=='directory':target.mkdir()
 if name=='symlink':target.symlink_to(d/'missing')
 if name=='unavailable':(d/'parent-file').write_text('not a directory');target=d/'parent-file/policy'
 text=helper.replace('"/Library/Application Support/Fios/Studio/native-serving-launch.json"',json.dumps(str(target)))
 text+='\nextension FiosGUILaunchPolicy {static func fixtureInstalled() -> String? {refusal(image:installedImage,policy:configurationPresence)}}\n'
 text+=('guard FiosGUILaunchPolicy.refusal() == nil else {fatalError("development role unexpectedly refused")};print("PASS actual image reader")\n' if name=='actualImage' else 'guard FiosGUILaunchPolicy.fixtureInstalled() '+('== nil' if name=='absent' else '!= nil')+' else {fatalError("actual metadata lookup result incorrect")};print("PASS actual metadata reader")\n')
 file=d/'main.swift';file.write_text(text)
 for mode,opt in [('Debug','-Onone'),('optimized','-O')]:compile_and_run(file,d/mode,opt,[('',False,'')])
receipt['inputs_unchanged']=all(sha(base/n)==h for n,h in inputs.items()) and sha(Path(__file__))==runner_sha and (source is None or all(sha(source/n)==h for n,h in source_inputs.items()));save();assert receipt['inputs_unchanged'];print(json.dumps({'directory':str(w),'records':len(receipt['records']),'receipt_sha256':sha(w/'receipt.json'),'model_requests':0,'native_authority':False}))
