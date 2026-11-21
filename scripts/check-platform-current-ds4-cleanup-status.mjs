#!/usr/bin/env node
// DS4 cleanup refusal in actual current backend status frames. No models,
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
const parents={"src/fios/current_backend_fences.zig":"f4d50fca2454d563b5dbf68e55cb73d887be29f649c915fc1dea53f4cfc36c5e"};
assert.equal(hash(bytes(join(source,'src/fios/current_ds4_checked_cleanup.zig'))),'202d92c2a4897728e95038eab557e477fd618c251b3b7be15fddf07ae3c58ca6');
const directory=mkdtempSync('/private/tmp/fios-009-ds4-status-check-');
const review=join(directory,'parent'),unit=join(directory,'unit');
for(const p of [review,unit])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(program,argv,cwd=directory)=>execFileSync(program,argv,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim(),'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-current-ds4-cleanup-status.patch'),patch=bytes(patchPath);
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(m=>m[1]).sort(),Object.keys(parents));
const target=join(review,'src/fios/current_backend_fences.zig');mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,bytes(join(source,'src/fios/current_backend_fences.zig')),{mode:0o600});
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});
run('/usr/bin/git',['apply','--reverse',patchCopy],review);assert.equal(hash(bytes(target)),parents['src/fios/current_backend_fences.zig']);const parentFlags=bytes(target);
run('/usr/bin/git',['apply',patchCopy],review);assert.equal(hash(bytes(target)),hash(bytes(join(source,'src/fios/current_backend_fences.zig'))));
const declared={},pending=['fios/current_backend_fences.zig'],copied=new Set();
while(pending.length){
 const n=pending.pop();if(copied.has(n))continue;copied.add(n);
 const path=join(source,'src',n),data=bytes(path);declared['src/'+n]=hash(data);
 const dest=join(unit,n);mkdirSync(dirname(dest),{recursive:true,mode:0o700});writeFileSync(dest,data,{mode:0o600});
 for(const m of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
  const d=resolve(dirname(path),m[1]),name=relative(join(source,'src'),d);assert(!name.startsWith('..')&&!isAbsolute(name));if(existsSync(d))pending.push(name);
 }
}
const fixturePath=join(root,'platform/studio/native/current_ds4_cleanup_status_test.zig.fixture'),fixture=bytes(fixturePath);writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
const names=[...fixture.toString().matchAll(/^test "(ds4 cleanup status[^"\n]+)"/gm)].map(m=>m[1]);assert.equal(names.length,4);
const receipt={version:1,scope:'current_backend_status_actual_collector_and_protocol_with_explicit_C_substitutes_only',directory,source,parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),results:[],models:0,native_authority:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
const flagsPath=join(unit,'fios/current_backend_fences.zig'),candidate=bytes(flagsPath);
for(const mode of ['Debug','ReleaseSafe']){
 for(const parent of [true,false]){
  writeFileSync(flagsPath,parent?parentFlags:candidate,{mode:0o600});
  for(const [index,name] of names.entries()){
   const enabled=!name.endsWith('remains unavailable');
   writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ds4='+enabled+';\npub const fios_source_ane=false;\npub const llama_engine=false;\npub const mlx_stream=false;\n',{mode:0o600});
   const argv=['-p','(version 1)(allow default)(deny network*)',zig,'test','--test-filter',name,'-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-lc'];
   const result=spawnSync('/usr/bin/sandbox-exec',argv,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
   const log=(result.stdout||'')+(result.stderr||'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),log,{mode:0o600});
   const red=parent&&index===0;const expected=red?result.status===1&&log.includes('expected 8, found 0')&&!log.includes('panic:'):result.status===0&&log.includes('All 2 tests passed.');
   receipt.results.push({mode,parent,name,status:result.status,signal:result.signal,expected,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Retain failed status check '+directory);
  }
 }
}
receipt.unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,n)))===h)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_failures:2,parent_controls:6,candidate_cases:8,models:0,native_authority:false}));
