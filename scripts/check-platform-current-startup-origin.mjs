#!/usr/bin/env node
// Actual startup-loop prefix and original native ledger. CPU metadata only.
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
const directory=mkdtempSync('/private/tmp/fios-009-startup-origin-check-'),unit=join(directory,'unit'),review=join(directory,'review');
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
for(const name of names){const p=join(source,'src',name),b=bytes(p);assert(b.equals(readFileSync(join(review,'src',name))),'Source does not match reviewed startup patch: '+name);declared[name]=hash(b);}
const helperName='fios/current_startup_origin.zig',helper=bytes(join(root,'platform/studio/native/current_startup_origin.zig'));
assert(helper.equals(bytes(join(source,'src',helperName))));declared[helperName]=hash(helper);
const pending=[helperName,'fios/request_ownership.zig','fios/queued_request_ownership.zig'];
const copied=new Set();
while(pending.length){const name=pending.pop();if(copied.has(name))continue;copied.add(name);
 const b=bytes(join(source,'src',name));declared[name]=hash(b);const p=join(unit,name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,b,{mode:0o600});
 for(const match of b.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
  const dependency=resolve(dirname(name),match[1]);const relative=dependency.slice(resolve('.').length+1);
  assert(dependency.startsWith(resolve('.')+'/'));if(existsSync(join(source,'src',relative)))pending.push(relative);
 }
}
const fixtureFile=join(root,'platform/studio/native/current_startup_origin_test.zig.fixture'),fixture=bytes(fixtureFile).toString();
writeFileSync(join(unit,'options.zig'),'pub const fios_source_ane = false;\n',{mode:0o600});
const prefix=text=>{const a=text.indexOf('pub fn inferenceLoop(ctx: ThreadCtx) void {'),b=text.indexOf('    while (!sch.shutdown.load(.acquire))',a);assert(a>=0&&b>a);return text.slice(a,b)+'}\n';};
const receipt={version:1,scope:'actual_startup_loop_prefix_CPU_registry_loader_substitutes_not_whole_native_acceptance',directory,source,source_revision:git('rev-parse','HEAD').trim(),base,declared_inputs:declared,patch_sha256:hash(patch),helper_sha256:hash(helper),fixture_sha256:hash(Buffer.from(fixture)),runner_sha256:hash(readFileSync(import.meta.filename)),models:0,inference:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false,all_client_coverage:false,fixture_substitutions:['CPU registry and loader substitutes','spawn wrapper checks reservation and can refuse before publication','scheduler relative helper import relocated to fixture root'],results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const [label,text,baseline]of [['baseline',before['engines/mlx/runtime/loop.zig'].toString(),true],['candidate',readFileSync(join(source,'src/engines/mlx/runtime/loop.zig'),'utf8'),false]]){
 const scheduler=readFileSync(join(source,'src/engines/mlx/scheduler.zig'),'utf8');
 const publication=scheduler.slice(scheduler.indexOf('    var ctx = ThreadCtx{'),scheduler.indexOf('    // Wait until inference thread has loaded'));
 assert(publication.includes('origin.unpublished(io)'));
 writeFileSync(join(unit,'main.zig'),fixture.replace('// ACTUAL_STARTUP_PREFIX',prefix(text)).replace('// ACTUAL_STARTUP_PUBLICATION',publication.replace('std.Thread.spawn','FixtureThread.spawn').replace('../../fios/current_startup_origin.zig','fios/current_startup_origin.zig')),{mode:0o600});
 for(const mode of ['Debug','ReleaseFast']){
  const name=label+'-'+mode,binary=join(directory,name),compiled=spawnSync(zig,['build-exe','-lc','-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+binary],{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
  writeFileSync(join(directory,name+'-build.log'),(compiled.stdout??'')+(compiled.stderr??''));
  const item={label,mode,compile_status:compiled.status,compile_signal:compiled.signal};receipt.results.push(item);save();assert.equal(compiled.status,0,'Compile failed: '+directory);
  const executed=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:10000,maxBuffer:65536});
  const log=(executed.stdout??'')+(executed.stderr??'');writeFileSync(join(directory,name+'-run.log'),log);item.run_status=executed.status;item.run_signal=executed.signal;
  item.expected=baseline?executed.status===1&&log.includes('FIO_STARTUP_LOAD_WITHOUT_ORIGIN'):executed.status===0&&log.includes('PASS: actual startup prefix preserves exact model');save();assert(item.expected,'Execution failed: '+directory);
 }
}
receipt.declared_inputs_unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,'src',n)))===h)&&hash(bytes(patchFile))===receipt.patch_sha256&&hash(bytes(fixtureFile))===receipt.fixture_sha256&&hash(bytes(join(root,'platform/studio/native/current_startup_origin.zig')))===receipt.helper_sha256&&hash(readFileSync(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.declared_inputs_unchanged);console.log(JSON.stringify({directory,receipt_sha256:hash(readFileSync(join(directory,'receipt.json'))),expected_baseline_failures:2,candidate_passes:2,models:0,native_authority:false}));
