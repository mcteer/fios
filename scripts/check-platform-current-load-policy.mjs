#!/usr/bin/env node
// Actual load tail/ANE worker/ready helper + native custody, CPU substitutes.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
const [source,zig]=[args[2],args[4]].map(p=>{assert(isAbsolute(p)&&p.startsWith('/private/tmp/')&&realpathSync(p)===p);return p;});
const hash=b=>createHash('sha256').update(b).digest('hex');
const bytes=p=>{const s=lstatSync(p);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<(64<<20));return readFileSync(p);};
assert.equal(hash(readFileSync(zig)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const directory=mkdtempSync('/private/tmp/fios-009-load-policy-check-'),unit=join(directory,'unit'),review=join(directory,'review');
for(const p of [unit,review])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(p,a,cwd=directory)=>execFileSync(p,a,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const git=(...a)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...a]);
const base='3736ed55f81c6cf0966a0f0dc7265e783655d244',names=['fios/queued_request_ownership.zig','engines/mlx/runtime/load_requests.zig'],before={},declared={};
for(const name of names){const b=Buffer.from(git('show',base+':src/'+name));before[name]=b;const p=join(review,'src',name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,b,{mode:0o600});}
const requiredFile=join(root,'platform/studio/native/mlx-serve-current-required-queued-origin.patch'),required=bytes(requiredFile);
writeFileSync(join(directory,'required.patch'),required,{mode:0o600});run('/usr/bin/git',['apply',join(directory,'required.patch')],review);
const unloadFile=join(root,'platform/studio/native/mlx-serve-current-unload-policy.patch'),unload=bytes(unloadFile);
writeFileSync(join(directory,'unload.patch'),unload,{mode:0o600});run('/usr/bin/git',['apply',join(directory,'unload.patch')],review);
for(const name of names)before[name]=readFileSync(join(review,'src',name));
const patchFile=join(root,'platform/studio/native/mlx-serve-current-load-policy.patch'),patch=bytes(patchFile);
writeFileSync(join(directory,'source.patch'),patch,{mode:0o600});run('/usr/bin/git',['apply',join(directory,'source.patch')],review);
for(const name of names){const b=bytes(join(source,'src',name));assert(b.equals(readFileSync(join(review,'src',name))));declared[name]=hash(b);}
const pending=['fios/request_ownership.zig','fios/queued_request_ownership.zig'],copied=new Set();
while(pending.length){const name=pending.pop();if(copied.has(name))continue;copied.add(name);const p=join(source,'src',name),b=bytes(p);declared[name]=hash(b);const dest=join(unit,name);mkdirSync(dirname(dest),{recursive:true,mode:0o700});writeFileSync(dest,b,{mode:0o600});for(const m of b.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){const dependency=resolve(dirname(p),m[1]),n=relative(join(source,'src'),dependency);assert(!n.startsWith('..')&&!isAbsolute(n));if(existsSync(dependency))pending.push(n);}}
const fixtureFile=join(root,'platform/studio/native/current_load_policy_test.zig.fixture'),fixture=bytes(fixtureFile).toString();
const receipt={version:1,scope:'actual_load_tail_ANE_ready_native_custody_CPU_substitutes_not_native_authority',directory,source,source_revision:git('rev-parse','HEAD').trim(),base,declared_inputs:declared,patch_sha256:hash(patch),required_queued_origin_patch_sha256:hash(required),unload_policy_patch_sha256:hash(unload),fixture_sha256:hash(Buffer.from(fixture)),runner_sha256:hash(readFileSync(import.meta.filename)),models:0,inference:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false,all_client_coverage:false,fixture_substitutions:['scheduler/request/entry/queue metadata','load/ANE/wired-policy effects and sender completion callbacks','loader substitute preserves actual pre-existing-uncertainty refusal','ordinary independent source fences at return/control-flow edges, not hardware faults'],results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const label of ['baseline','candidate']){
 const native=label==='baseline'?before[names[1]].toString():bytes(join(source,'src',names[1])).toString();
 let start=native.indexOf('    // Step 2: the actual load.'),stop=native.indexOf('\n/// A cold Neural Engine',start);assert(start>=0&&stop>start);
 const tail='fn runLoadTail(sch:*Scheduler,req:*LoadRequest)void {\n'+native.slice(start,stop);
 start=native.indexOf('fn aneBuildThread(');stop=native.indexOf('\nfn readyLoadRequest(',start);assert(start>=0&&stop>start);const ane=native.slice(start,stop);
 start=stop+1;stop=native.indexOf('\n/// Mark the entry',start);assert(stop>start);const ready=native.slice(start,stop);
 writeFileSync(join(unit,'main.zig'),fixture.replace('// ACTUAL_LOAD_TAIL',tail).replace('// ACTUAL_ANE_WORKER',ane).replace('// ACTUAL_READY',ready),{mode:0o600});
 for(const mode of ['Debug','ReleaseSafe'])for(const scenario of [0,1,2,3,4,5,6,7,8]){
  writeFileSync(join(unit,'options.zig'),`pub const fios_source_ane=false;\npub const scenario=${scenario};\n`,{mode:0o600});
  const key=label+'-'+mode+'-'+scenario,binary=join(directory,key),built=spawnSync(zig,['build-exe','-lc','-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+binary],{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
  writeFileSync(join(directory,key+'-build.log'),(built.stdout??'')+(built.stderr??''));const item={label,mode,scenario,build_status:built.status,build_signal:built.signal};receipt.results.push(item);save();assert.equal(built.status,0,'Compile failed: '+directory);
  const executed=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:10000,maxBuffer:65536}),log=(executed.stdout??'')+(executed.stderr??'');writeFileSync(join(directory,key+'-run.log'),log);item.run_status=executed.status;item.run_signal=executed.signal;
  item.expected=label==='baseline'&&[1,2,4,5,6].includes(scenario)?executed.status===1&&log.includes('FIO_LOAD_READY_AFTER_KNOWN_UNCERTAINTY'):executed.status===0&&log.includes('PASS: actual load completion');save();assert(item.expected,'Execution failed: '+directory);
 }
}
receipt.declared_inputs_unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,'src',n)))===h)&&hash(bytes(patchFile))===receipt.patch_sha256&&hash(bytes(requiredFile))===receipt.required_queued_origin_patch_sha256&&hash(bytes(unloadFile))===receipt.unload_policy_patch_sha256&&hash(bytes(fixtureFile))===receipt.fixture_sha256&&hash(readFileSync(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.declared_inputs_unchanged);console.log(JSON.stringify({directory,receipt_sha256:hash(readFileSync(join(directory,'receipt.json'))),expected_baseline_failures:10,baseline_controls:8,candidate_passes:18,models:0,native_authority:false}));
