#!/usr/bin/env node
// Actual ANE seam negative fence composition with original tracker state. No models,
// service actions, enrolled admission or terminal authority.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync,unlinkSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';

const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
const [source,zig]=[args[2],args[4]].map(path=>{
  assert(isAbsolute(path)&&path.startsWith('/private/tmp/')&&realpathSync(path)===path);return path;
});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const bytes=(path,maximum=64<<20)=>{
  const info=lstatSync(path);
  assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.uid===process.getuid()&&(info.mode&0o022)===0&&info.size>0&&info.size<maximum);
  return readFileSync(path);
};
assert.equal(hash(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const parents={"src/sdk/ane/source_guard.zig":"7423ac252c4a2fa5dbcd48a80dffd8aa3bc65645e99117e46b9e7f166c53af52","src/fios/sdk_request_ownership.zig":"8c6bee0f8234e61a0f750b697c9f0cb854950303b5e68aee2e8f3a17ed299c23"};
const directory=mkdtempSync('/private/tmp/fios-009-ane-seam-check-');
const review=join(directory,'parent'),unit=join(directory,'unit');for(const p of [review,unit])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(program,argv,cwd=directory)=>execFileSync(program,argv,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim(),'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-current-ane-seam-fences.patch'),patch=bytes(patchPath);
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(m=>m[1]),Object.keys(parents));
run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'ast-check',join(source,'src/sdk/ane/source_guard.zig')]);
const candidates={},parentSources={};
for(const name of Object.keys(parents)){
 const candidate=bytes(join(source,name)),target=join(review,name);candidates[name]=candidate;
 mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,candidate,{mode:0o600});
}
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});run('/usr/bin/git',['apply','--reverse',patchCopy],review);
for(const name of Object.keys(parents)){const data=bytes(join(review,name));assert.equal(hash(data),parents[name]);parentSources[name]=data;}
run('/usr/bin/git',['apply',patchCopy],review);for(const name of Object.keys(parents))assert.equal(hash(bytes(join(review,name))),hash(candidates[name]));
const declared=Object.fromEntries(Object.entries(candidates).map(([name,data])=>[name,hash(data)])),pending=['sdk/ane/source_guard.zig','fios/sdk_request_ownership.zig','fios/request_ownership.zig','fios/current_ane_run_uncertainty.zig'],copied=new Set();
while(pending.length){
 const n=pending.pop();if(copied.has(n))continue;copied.add(n);
 const path=join(source,'src',n),data=bytes(path);declared['src/'+n]=hash(data);const dest=join(unit,n);mkdirSync(dirname(dest),{recursive:true,mode:0o700});writeFileSync(dest,data,{mode:0o600});
 for(const m of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
  const d=resolve(dirname(path),m[1]),n=relative(join(source,'src'),d);assert(!n.startsWith('..')&&!isAbsolute(n));if(existsSync(d))pending.push(n);
 }
}
const fixturePath=join(root,'platform/studio/native/current_ane_seam_fences_test.zig.fixture'),fixture=bytes(fixturePath);
const names=[...fixture.toString().matchAll(/^test "(ane seam[^"\n]+)"/gm)].map(m=>m[1]);assert.equal(names.length,6);
const markers=['ANE_SEAM_IGNORED_ORIGINAL_TRACKER_FENCE','ANE_SEAM_IGNORED_REPORTED_RUN_REFUSAL'];
const receipt={version:1,scope:'actual_full_seam_guard_and_negative_composition_actual_tracker_reported_latch_explicit_raw_flag_and_CPU_fallback_substitutes_only',directory,source,parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),results:[],models:0,native_authority:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const mode of ['Debug','ReleaseSafe'])for(const parent of [true,false]){
 writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
 for(const name of Object.keys(parents))writeFileSync(join(unit,name.slice(4)),parent?parentSources[name]:candidates[name],{mode:0o600});
 for(const [index,name]of names.entries()){
  const enabled=!name.includes('unselected');writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ane='+enabled+';\npub const fios_source_ds4=false;\npub const llama_engine=false;\npub const mlx_stream=false;\n',{mode:0o600});
  const args=['-p','(version 1)(allow default)(deny network*)',zig,'test','--test-filter',name,'-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-lc'];
  const result=spawnSync('/usr/bin/sandbox-exec',args,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20}),log=(result.stdout||'')+(result.stderr||'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),log,{mode:0o600});
  const expected=parent&&index<2?result.status===1&&log.includes(markers[index])&&!log.includes('panic:'):result.status===0&&/^All [12] tests passed\./m.test(log);
  receipt.results.push({mode,parent,name,status:result.status,signal:result.signal,expected,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Retain failed seam check '+directory);
 }
}
receipt.unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,n)))===h)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_failures:4,parent_controls:8,candidate_cases:12,models:0,native_authority:false}));
