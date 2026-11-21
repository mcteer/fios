#!/usr/bin/env node
// Actual shutdown close function. CPU-only registry/close substitutes.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,isAbsolute} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
const [source,zig]=[args[2],args[4]].map(p=>{assert(isAbsolute(p)&&p.startsWith('/private/tmp/')&&realpathSync(p)===p);return p;});
const hash=b=>createHash('sha256').update(b).digest('hex');
const bytes=p=>{const s=lstatSync(p);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<(64<<20));return readFileSync(p);};
assert.equal(hash(readFileSync(zig)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const directory=mkdtempSync('/private/tmp/fios-009-shutdown-cleanup-check-'),unit=join(directory,'unit'),review=join(directory,'review');
mkdirSync(unit,{mode:0o700});mkdirSync(review,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(p,a,cwd=directory)=>execFileSync(p,a,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const git=(...a)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...a]);
const base='3736ed55f81c6cf0966a0f0dc7265e783655d244';
const names=['engines/mlx/scheduler.zig','engines/mlx/runtime/thread.zig','engines/mlx/runtime/loop.zig'];
const declared={},before={};
for(const name of names){const b=Buffer.from(git('show',base+':src/'+name));before[name]=b;const p=join(review,'src',name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,b,{mode:0o600});}
const patchFile=join(root,'platform/studio/native/mlx-serve-current-startup-origin.patch'),patch=bytes(patchFile);
writeFileSync(join(directory,'source.patch'),patch,{mode:0o600});
run('/usr/bin/git',['apply','--unsafe-paths','--directory='+review,join(directory,'source.patch')]);
const shutdownPatchFile=join(root,'platform/studio/native/mlx-serve-current-shutdown-cleanup.patch');
const shutdownPatch=bytes(shutdownPatchFile);
writeFileSync(join(directory,'shutdown.patch'),shutdownPatch,{mode:0o600});
run('/usr/bin/git',['apply','--unsafe-paths','--directory='+review,join(directory,'shutdown.patch')]);
for(const name of names){const b=bytes(join(source,'src',name));assert(b.equals(readFileSync(join(review,'src',name))));declared[name]=hash(b);}
const fixtureFile=join(root,'platform/studio/native/current_shutdown_cleanup_test.zig.fixture'),fixture=bytes(fixtureFile).toString();
const closeFunction=text=>{const a=text.indexOf('fn closeGlmModels(sch: *Scheduler) void {'),b=text.indexOf('\n/// Cleanup, vision',a);assert(a>=0&&b>a);return text.slice(a,b);};
const receipt={version:1,scope:'actual_shutdown_close_CPU_substitutes_negative_evidence_only',directory,source,source_revision:git('rev-parse','HEAD').trim(),base,declared_inputs:declared,patch_sha256:hash(patch),shutdown_patch_sha256:hash(shutdownPatch),fixture_sha256:hash(Buffer.from(fixture)),runner_sha256:hash(readFileSync(import.meta.filename)),models:0,inference:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false,all_client_coverage:false,fixture_substitutions:['CPU registry and stream-close substitutes','fixed negative-evidence getters use per-process scenario state'],results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const [label,text,baseline]of [['baseline',before['engines/mlx/runtime/loop.zig'].toString(),true],['candidate',readFileSync(join(source,'src/engines/mlx/runtime/loop.zig'),'utf8'),false]]){
 writeFileSync(join(unit,'main.zig'),fixture.replace('// ACTUAL_SHUTDOWN_CLOSE',closeFunction(text)),{mode:0o600});
 for(const mode of ['Debug','ReleaseFast'])for(const scenario of [0,1,2]){
  writeFileSync(join(unit,'options.zig'),`pub const scenario = ${scenario};\n`,{mode:0o600});
  const name=label+'-'+mode+'-'+scenario,binary=join(directory,name),compiled=spawnSync(zig,['build-exe','-lc','-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+binary],{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
  writeFileSync(join(directory,name+'-build.log'),(compiled.stdout??'')+(compiled.stderr??''));
  const item={label,mode,scenario,compile_status:compiled.status,compile_signal:compiled.signal};receipt.results.push(item);save();assert.equal(compiled.status,0,'Compile failed: '+directory);
  const executed=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:10000,maxBuffer:65536});
  const log=(executed.stdout??'')+(executed.stderr??'');writeFileSync(join(directory,name+'-run.log'),log);item.run_status=executed.status;item.run_signal=executed.signal;
  item.expected=baseline&&scenario!==0?executed.status===1&&log.includes('FIO_SHUTDOWN_UNCERTAIN_CLOSE_OR_HANDLE_CLEAR'):executed.status===0&&log.includes('PASS: actual shutdown close respects negative evidence');save();assert(item.expected,'Execution failed: '+directory);
 }
}
receipt.declared_inputs_unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,'src',n)))===h)&&hash(bytes(patchFile))===receipt.patch_sha256&&hash(bytes(fixtureFile))===receipt.fixture_sha256&&hash(bytes(shutdownPatchFile))===receipt.shutdown_patch_sha256&&hash(readFileSync(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.declared_inputs_unchanged);console.log(JSON.stringify({directory,receipt_sha256:hash(readFileSync(join(directory,'receipt.json'))),expected_baseline_failures:4,baseline_healthy_passes:2,candidate_passes:6,models:0,native_authority:false}));
