#!/usr/bin/env node
// Checked DS4 destruction and actual Zig wrapper allocation retention. No models,
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
const parents={"src/engines/ds4/bridge.zig": "be051975afaa607d141280e833ae42a98d908ac5592919c3a69c4488de0c479b", "src/engines/ds4/ffi.zig": "fb1bfe5ca6e1225f84ccc24f1521036bc3adeaaa226b5ceba019e199a7715dcf", "src/fios/current_ds4_backend_uncertainty.zig": "81685a87b0dc23b49efd6356da8c7f77804866b179d2150b5a2ef04fc51e124d", "src/fios/current_ds4_checked_cleanup.zig": null};
const directory=mkdtempSync('/private/tmp/fios-009-ds4-cleanup-check-');
const review=join(directory,'parent'),unit=join(directory,'unit');
for(const p of [review,unit])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(program,argv,cwd=directory)=>execFileSync(program,argv,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim(),'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-current-ds4-checked-cleanup.patch'),patch=bytes(patchPath);
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(m=>m[1]).sort(),Object.keys(parents).sort());
const declared={};
for(const n of Object.keys(parents)){
 const data=bytes(join(source,n));declared[n]=hash(data);
 const target=join(review,n);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});
}
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});
run('/usr/bin/git',['apply','--reverse',patchCopy],review);
for(const [n,h] of Object.entries(parents)){if(h===null)assert(!existsSync(join(review,n)));else assert.equal(hash(bytes(join(review,n))),h);}
const parentBridge=bytes(join(review,'src/engines/ds4/bridge.zig'));
run('/usr/bin/git',['apply',patchCopy],review);
for(const [n,h] of Object.entries(declared))assert.equal(hash(bytes(join(review,n))),h);
// Unmodified Zig dependency closure. Inactive model/Metal functions are never called.
const pending=['engines/ds4/bridge.zig','fios/current_ds4_checked_cleanup.zig','fios/current_ds4_backend_uncertainty.zig'],copied=new Set();
while(pending.length){
 const n=pending.pop();if(copied.has(n))continue;copied.add(n);
 const path=join(source,'src',n),data=bytes(path);declared['src/'+n]=hash(data);
 const target=join(unit,n);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});
 for(const m of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
  const d=resolve(dirname(path),m[1]),name=relative(join(source,'src'),d);assert(!name.startsWith('..')&&!isAbsolute(name));if(existsSync(d))pending.push(name);
 }
}
const fixturePath=join(root,'platform/studio/native/current_ds4_checked_cleanup_test.zig.fixture'),fixture=bytes(fixturePath);
writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
// Metal module is deliberately inert: kernel extraction/open never executes.
writeFileSync(join(unit,'metal.zig'),'// no Metal execution\n',{mode:0o600});
const names=[...fixture.toString().matchAll(/^test "(ds4 cleanup[^"\n]+)"/gm)].map(m=>m[1]);assert.equal(names.length,7);
const receipt={version:1,scope:'actual_ds4_zig_wrappers_with_allocator_counters_and_explicit_c_cleanup_substitutes',directory,source,parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),results:[],models:0,native_authority:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
const bridgePath=join(unit,'engines/ds4/bridge.zig'),candidateBridge=bytes(bridgePath);
for(const mode of ['Debug','ReleaseSafe']){
 for(const parent of [true,false]){
  writeFileSync(bridgePath,parent?parentBridge:candidateBridge,{mode:0o600});
  const selected=parent?names.slice(0,2):names;
  for(const name of selected){
   const enabled=!name.endsWith('legacy ABI');
   writeFileSync(join(unit,'options.zig'),'pub const fios_source_ds4='+enabled+';\n',{mode:0o600});
   const argv=['-p','(version 1)(allow default)(deny network*)',zig,'test','--test-filter',name,'-O'+mode,'--dep','build_options','--dep','ds4_metal_sources','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-Mds4_metal_sources='+join(unit,'metal.zig'),'-lc'];
   if(name.endsWith('share refusal latch')){
    writeFileSync(join(unit,'unit.zig'),'pub const mlx_serve_unit=true;\nconst cleanup=@import("fios/current_ds4_checked_cleanup.zig");\nexport fn fios_fixture_unit_refuse() c_int { return if(cleanup.session(@ptrFromInt(8192))) 1 else 0; }\n',{mode:0o600});
    const helperPath=join(unit,'fios/current_ds4_checked_cleanup.zig'),actualHelper=bytes(helperPath);
    const sharedDeclaration='const uncertain = @import("../sdk/util/shared.zig").Shared(std.atomic.Value(bool), "fios_ds4_checked_cleanup_uncertain", .init(false));';
    assert(actualHelper.toString().includes(sharedDeclaration));
    const splitHelper=actualHelper.toString().replace(sharedDeclaration,'var uncertain = std.atomic.Value(bool).init(false);').replaceAll('uncertain.get().','uncertain.');
    writeFileSync(helperPath,splitHelper,{mode:0o600});
    run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'build-obj','-O'+mode,'--dep','build_options','-Mroot='+join(unit,'unit.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+join(directory,'split-unit.o')]);
    const split=spawnSync('/usr/bin/sandbox-exec',[...argv,join(directory,'split-unit.o')],{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
    const splitLog=(split.stdout||'')+(split.stderr||'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),splitLog,{mode:0o600});
    const splitExpected=split.status===1&&splitLog.includes('FAIL (TestUnexpectedResult)')&&!splitLog.includes('panic:');
    receipt.results.push({mode,parent:false,split_unit_control:true,name,status:split.status,signal:split.signal,expected:splitExpected,log_sha256:hash(Buffer.from(splitLog))});save();assert(splitExpected,'Retain split-unit control '+directory);
    writeFileSync(helperPath,actualHelper,{mode:0o600});
    run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'build-obj','-O'+mode,'--dep','build_options','-Mroot='+join(unit,'unit.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+join(directory,'unit.o')]);
    argv.push(join(directory,'unit.o'));
   }
   const result=spawnSync('/usr/bin/sandbox-exec',argv,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
   const log=(result.stdout||'')+(result.stderr||'');const logPath=join(directory,'case-'+receipt.results.length+'.log');writeFileSync(logPath,log,{mode:0o600});
   const expected=parent?result.status===1&&log.includes('expected 0, found')&&!log.includes('panic:'):result.status===0&&log.includes('All 1 tests passed.');
   receipt.results.push({mode,parent,name,status:result.status,signal:result.signal,expected,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Retain failed check '+directory);
  }
 }
}
receipt.unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,n)))===h)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_failures:4,unit_split_controls:2,candidate_cases:14,models:0,native_authority:false}));
