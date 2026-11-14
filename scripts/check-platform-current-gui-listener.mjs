#!/usr/bin/env node
// Model-free GUI launch-prefix check with modeled PID/signal/config ports.
// Never runs the GUI/server, sends an OS signal or writes native defaults.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,lstatSync,realpathSync,mkdtempSync} from 'node:fs';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url)),args=process.argv.slice(2);
const mock=args.length===1&&args[0]==='--mock';
assert(process.platform==='darwin'&&process.getuid()>0);
assert(mock||(args.length===3&&args[0]==='--isolated'&&args[1]==='--source'),
  'Use --mock | --isolated --source ABS_PINNED_GUI_SOURCE');
const directory=mkdtempSync(path.join(tmpdir(),'fios-009-gui-listener-'));
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',
  GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
function bytes(file){
  const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=2<<20);
  return readFileSync(file);
}
const names=['gui_listener_preflight_previous.inc','gui_listener_preflight_scope.inc','gui_listener_preflight_test.swift.fixture','mlx-serve-26.11.2-gui-listener-ownership.patch'];
const inputs=Object.fromEntries(names.map(name=>[name,bytes(path.join(root,'platform/studio/native',name))]));
const previous=inputs[names[0]].toString('utf8'),current=inputs[names[1]].toString('utf8'),fixture=inputs[names[2]].toString('utf8');
assert.equal(fixture.split('@@BODY@@').length,2);
function fragment(text){
  const header='    private func launch(args: [String], options: ServerOptions) {';
  const start=text.indexOf(header),end=text.indexOf('        let binaryPath = Self.resolveBinaryPath()',start);
  assert(start>=0&&end>start&&text.indexOf(header,start+1)===-1);
  let reaper='';const at=text.indexOf('    private func killOrphanedServers(');
  if(at>=0){
    let cursor=text.indexOf('{',at),depth=1;assert(cursor>=at);
    for(cursor++;depth;cursor++){assert(cursor<text.length);if(text[cursor]==='{')depth++;if(text[cursor]==='}')depth--;}
    reaper=text.slice(at,cursor)+'\n';
  }
  return text.slice(start,end)+'    }\n'+reaper;
}
const run=(program,argv)=>execFileSync(program,argv,{env,encoding:'utf8',timeout:15000,maxBuffer:2<<20});
let source,sourceFile,originalSource,observedSource,observedPatch,git;
if(!mock){
  source=args[2];assert(path.isAbsolute(source)&&realpathSync(source)===source&&source.startsWith('/private/tmp/'));
  const info=lstatSync(source);assert(info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);
  git=(...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv]);
  sourceFile='app/Sources/MLXServe/Services/ServerManager.swift';
  assert.equal(git('rev-parse','HEAD').trim(),'4e231ceebe63308cc038117d40b9f9b64bd0372e');
  assert.deepEqual(git('status','--porcelain','--untracked-files=all').trimEnd().split('\n'),[' M '+sourceFile]);
  originalSource=git('show','HEAD:'+sourceFile);observedSource=bytes(path.join(source,sourceFile));
  observedPatch=git('diff','--no-ext-diff','--no-textconv','HEAD');
  assert.equal(observedPatch,inputs[names[3]].toString('utf8'));
  assert.equal(fragment(originalSource),previous);assert.equal(fragment(observedSource.toString('utf8')),current);
}
const sdk=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim();
if(!mock)assert.equal(sdk,'27.2');
const compiler=spawnSync('/usr/bin/swiftc',['--version'],{env,encoding:'utf8',timeout:15000,maxBuffer:65536});
assert.equal(compiler.status,0);assert.equal(compiler.signal,null);
const receipt={version:1,scope:'GUI_launch_prefix_with_modeled_PID_signal_configuration_ports_not_full_GUI_or_native_acceptance',
  mode:mock?'mock':'isolated_source',source:source??null,source_revision:source?'4e231ceebe63308cc038117d40b9f9b64bd0372e':null,
  source_sha256:observedSource?sha(observedSource):null,original_source_sha256:originalSource?sha(originalSource):null,
  inputs:Object.fromEntries(names.map(name=>[name,sha(inputs[name])])),runner_sha256:sha(bytes(fileURLToPath(import.meta.url))),
  swift:(compiler.stdout??'')+(compiler.stderr??''),sdk,swift_language:'5',records:[],models:0,inference:false,
  OS_signals:false,GUI_executed:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false};
const save=()=>writeFileSync(path.join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});
save();
for(const [label,body] of [['baseline',previous],['candidate',current]]){
  const input=path.join(directory,label+'.swift');writeFileSync(input,fixture.replace('@@BODY@@',body),{mode:0o600});
  for(const [mode,optimize] of [['Debug','-Onone'],['optimized','-O']]){
    const output=path.join(directory,label+'-'+mode);
    const build=spawnSync('/usr/bin/swiftc',['-swift-version','5',optimize,...(!mock?['-target','arm64-apple-macosx26.2']:[]),input,'-o',output],
      {env,encoding:'utf8',timeout:60000,maxBuffer:1<<20});
    writeFileSync(output+'-build.log',(build.stdout??'')+(build.stderr??''),{mode:0o600});
    receipt.records.push({label,mode,operation:'compile',status:build.status,signal:build.signal});save();
    assert.equal(build.status,0,'GUI prefix compilation failed; retain '+directory);assert.equal(build.signal,null);
    // The simulated kill is a Swift function in the fixture. No direct OS
    // kill import is allowed in either compiled launch-prefix executable.
    assert(!run('/usr/bin/nm',['-u',output]).split('\n').some(line=>/\b_kill$/.test(line.trim())));
    for(const control of ['--occupied','--other','--empty']){
      const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',output,control],
        {env,encoding:'utf8',timeout:5000,maxBuffer:4096});
      const log=(result.stdout??'')+(result.stderr??'');writeFileSync(output+control+'.log',log,{mode:0o600});
      const expected=label==='baseline'&&control!=='--empty'?77:0;
      const marker=expected===0?'PASS: actual GUI launch prefix':control==='--occupied'?'GUI_PRELAUNCH_SIGNALED_UNOWNED_LISTENER':'GUI_PRELAUNCH_CHANGED_DEFAULTS_WHILE_OCCUPIED';
      receipt.records.push({label,mode,operation:control,status:result.status,signal:result.signal,expected,marker,passed:result.status===expected&&result.signal===null&&log.includes(marker)});save();
      assert(receipt.records.at(-1).passed,'GUI launch-prefix control failed; retain '+directory);
    }
  }
}
receipt.declared_inputs_unchanged=names.every(name=>bytes(path.join(root,'platform/studio/native',name)).equals(inputs[name]))&&
  sha(bytes(fileURLToPath(import.meta.url)))===receipt.runner_sha256&&
  (!source||(bytes(path.join(source,sourceFile)).equals(observedSource)&&git('diff','--no-ext-diff','--no-textconv','HEAD')===observedPatch));
save();assert(receipt.declared_inputs_unchanged);
console.log(JSON.stringify({directory,receipt_sha256:sha(readFileSync(path.join(directory,'receipt.json'))),records:receipt.records.length,models:0,inference:false,native_authority:false}));
