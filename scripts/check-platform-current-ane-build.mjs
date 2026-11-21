#!/usr/bin/env node
// Original ownership in actual ANE build constructor and worker methods. No models,
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
const parents={"src/engines/ane/lm.zig":"da0df465ab2347caf768e0e6860948a59260bbc6831bc5122cf8cdac13b87627"};
const directory=mkdtempSync('/private/tmp/fios-009-ane-build-check-');
const review=join(directory,'parent'),unit=join(directory,'unit');for(const p of [review,unit])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(program,argv,cwd=directory)=>execFileSync(program,argv,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim(),'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-current-ane-build-origins.patch'),patch=bytes(patchPath);
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(m=>m[1]),Object.keys(parents));
run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'ast-check',join(source,'src/engines/ane/lm.zig')]);
const name='src/engines/ane/lm.zig',candidate=bytes(join(source,name)),target=join(review,name);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,candidate,{mode:0o600});
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});run('/usr/bin/git',['apply','--reverse',patchCopy],review);assert.equal(hash(bytes(target)),parents[name]);const parentSource=bytes(target);run('/usr/bin/git',['apply',patchCopy],review);assert.equal(hash(bytes(target)),hash(candidate));
assert(candidate.toString().includes('try build.captureOrigin();'));assert(candidate.toString().includes('const build = try a.create(Build);'));assert(candidate.toString().includes('if (!build.finishOrigin() and build.failed == null)'));assert(candidate.toString().indexOf('try build.captureOrigin();')<candidate.toString().indexOf('std.Thread.spawn(.{}, Build.run,'));
const declared={[name]:hash(candidate)},pending=['fios/request_ownership.zig','fios/queued_request_ownership.zig'],copied=new Set();
while(pending.length){
 const n=pending.pop();if(copied.has(n))continue;copied.add(n);
 const path=join(source,'src',n),data=bytes(path);declared['src/'+n]=hash(data);const dest=join(unit,n);mkdirSync(dirname(dest),{recursive:true,mode:0o700});writeFileSync(dest,data,{mode:0o600});
 for(const m of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
  const d=resolve(dirname(path),m[1]),n=relative(join(source,'src'),d);assert(!n.startsWith('..')&&!isAbsolute(n));if(existsSync(d))pending.push(n);
 }
}
const fixturePath=join(root,'platform/studio/native/current_ane_build_origins_test.zig.fixture'),fixture=bytes(fixturePath);
function actualMethods(input){
 const text=input.toString(),hasOrigin=text.includes('        // One original group');
 const start=hasOrigin?text.indexOf('        // One original group'):text.indexOf('        fn run(b: *Build) void {');
 const end=text.indexOf('        fn one(b: *Build, i: usize) !void {',start),ctor=text.indexOf('        const B = Build{'),ctorEnd=text.indexOf('        errdefer if (!rt.cleanupUnknown()) {',ctor);
 assert(start>0&&end>start&&ctor>0&&ctorEnd>ctor&&ctorEnd<start);
 const original=text.slice(ctor,ctorEnd);assert.equal([...original.matchAll(/std\.Thread\.spawn\(\.\{\}, Build\.run,/g)].length,1);
 const constructor=original.replace('std.Thread.spawn(.{}, Build.run,','spawnCompiler(.{}, Build.run,');
 return fixture.toString().replace('// ACTUAL_BUILD_RUN',text.slice(start,end)).replace('// ACTUAL_CONSTRUCTOR_PREFIX',constructor).replace('FIXTURE_SOURCE_VARIANT',String(hasOrigin));
}
const names=[...fixture.toString().matchAll(/^test "(ane build original[^"\n]+)"/gm)].map(m=>m[1]);assert.equal(names.length,6);
const markers=['ANE_BUILD_WORKER_LOST_ORIGINAL_SCOPE','ANE_BUILD_ORIGIN_NOT_RETAINED_BEFORE_PUBLICATION','ANE_BUILD_COMPILED_WITHOUT_REQUIRED_ORIGIN','ANE_BUILD_PARTIAL_SPAWN_LOST_ORIGINAL_SCOPE','ANE_BUILD_ERASED_ORIGINAL_UNCERTAINTY'];
const receipt={version:1,scope:'actual_build_constructor_prefix_and_worker_methods_actual_tracker_scope_explicit_CPU_compilation_and_thread_spawn_substitutes_only',directory,source,parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),results:[],models:0,native_authority:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const mode of ['Debug','ReleaseSafe'])for(const parent of [true,false]){
 writeFileSync(join(unit,'main.zig'),actualMethods(parent?parentSource:candidate),{mode:0o600});
 for(const [index,name]of names.entries()){
  const enabled=!name.includes('unselected');writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ane='+enabled+';\npub const fios_source_ds4=false;\npub const llama_engine=false;\npub const mlx_stream=false;\n',{mode:0o600});
  const args=['-p','(version 1)(allow default)(deny network*)',zig,'test','--test-filter',name,'-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-lc'];
  const result=spawnSync('/usr/bin/sandbox-exec',args,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20}),log=(result.stdout||'')+(result.stderr||'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),log,{mode:0o600});
  const expected=parent&&index<5?result.status===1&&log.includes(markers[index])&&!log.includes('panic:'):result.status===0&&log.includes('All 2 tests passed.');
  receipt.results.push({mode,parent,name,status:result.status,signal:result.signal,expected,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Retain failed lane check '+directory);
 }
}
receipt.unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,n)))===h)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_failures:10,parent_controls:2,candidate_cases:12,models:0,native_authority:false}));
