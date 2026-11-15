#!/usr/bin/env node
// Registry-generation-bound registry ingress metadata and actual tracker. No models,
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
// Exact one-path parent projection, not whole-repository/native provenance.
const parents={"src/fios/request_ownership.zig":"d65e3f772c5a41ff1d5f586e121665883cb5d5ed9fa2e1666b828d8b3f9adec9","src/fios/current_registry_claim.zig":"c858c1b257eed1de94a3080917e403002d76a1464343e72fd939bd7f649a309a","src/host/registry/registry.zig":"5d5f2cd024a845648c444a9124434663ea71c4ad08202864e0c446d9cbef9ad7"};
const directory=mkdtempSync('/private/tmp/fios-009-registry-ingress-check-');
const review=join(directory,'parent'),unit=join(directory,'unit');
for(const path of [review,unit])mkdirSync(path,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(program,argv,cwd=directory)=>execFileSync(program,argv,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const revision=run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim();
assert.equal(revision,'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-registry-ingress.patch'),patch=bytes(patchPath);
const changed=[...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(match=>match[1]);
assert.deepEqual([...changed].sort(),Object.keys(parents).sort());
const declared={};
for(const name of changed){
  const data=bytes(join(source,name));declared[name]=hash(data);
  const target=join(review,name);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});
}
for(const name of Object.keys(parents))run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'ast-check',join(source,name)]);
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});
run('/usr/bin/git',['apply','--reverse',patchCopy],review);
for(const [name,identity] of Object.entries(parents)){if(identity===null)assert(!existsSync(join(review,name)));else assert.equal(hash(bytes(join(review,name))),identity,'Unexpected parent projection');}
const oldTracker=bytes(join(review,'src/fios/request_ownership.zig'));
const oldRegistryHelper=bytes(join(review,'src/fios/current_registry_claim.zig'));
run('/usr/bin/git',['apply',patchCopy],review);
for(const [name,identity] of Object.entries(declared))assert.equal(hash(bytes(join(review,name))),identity);

// Copy only the actual protocol/tracker dependency closure. Real transport/worker
// execution belongs to the separately recorded native enclosure, not this test.
const pending=['fios/request_ownership.zig','fios/current_registry_claim.zig'],copied=new Set();
while(pending.length){
  const name=pending.pop();if(copied.has(name))continue;copied.add(name);
  const path=join(source,'src',name),data=bytes(path);declared['src/'+name]=hash(data);
  const target=join(unit,name);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});
  for(const match of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
    const dependency=resolve(dirname(path),match[1]),name=relative(join(source,'src'),dependency);
    assert(!name.startsWith('..')&&!isAbsolute(name));if(existsSync(dependency))pending.push(name);
  }
}
const fixturePath=join(root,'platform/studio/native/registry_ingress_test.zig.fixture'),fixture=bytes(fixturePath);
writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\n',{mode:0o600});
const trackerPath=join(unit,'fios/request_ownership.zig'),candidateTracker=bytes(trackerPath);
const registryHelperPath=join(unit,'fios/current_registry_claim.zig'),candidateRegistryHelper=bytes(registryHelperPath);
const compatibilityFixturePath=join(root,'platform/studio/native/preparation_ingress_test.zig.fixture'),compatibilityFixture=bytes(compatibilityFixturePath);
writeFileSync(join(unit,'compatibility.zig'),compatibilityFixture,{mode:0o600});
const names=[...fixture.toString().matchAll(/^test "(registry ingress[^"\n]+)"/gm)].map(match=>match[1]);assert.equal(names.length,10);
const receipt={version:1,scope:'exact_registry_generation_bound_link_actual_tracker_helper_CPU_registry_metadata_no_native_capacity_or_authority',directory,source,revision,
  parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),
  models:0,inference:false,installed:false,activation:false,wire_changes:false,all_client_coverage:false,native_authority:false,whole_native_provenance:false,results:[]};
receipt.compatibility_fixture_sha256=hash(compatibilityFixture);
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const parent of [true,false]){
 writeFileSync(trackerPath,parent?oldTracker:candidateTracker,{mode:0o600});
 writeFileSync(registryHelperPath,parent?oldRegistryHelper:candidateRegistryHelper,{mode:0o600});
 for(const mode of ['Debug','ReleaseSafe'])for(const name of names){
  if(parent&&name!=='registry ingress interface'&&!name.includes(' control '))continue;
  const argv=['-p','(version 1)(allow default)(deny network*)',zig,'test','-lc','-O'+mode,'--test-filter',name,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig')];
  const result=spawnSync('/usr/bin/sandbox-exec',argv,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
  const log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),log,{mode:0o600});
  const missing=parent&&name==='registry ingress interface';
  const expected=!result.error&&!result.signal&&(missing?result.status===1&&log.includes('MISSING_REGISTRY_GENERATION_INGRESS_LINK')&&!log.includes('panic:'):result.status===0&&log.includes('All 2 tests passed.'));
  receipt.results.push({parent,mode,name,status:result.status,signal:result.signal,expected,interface_missing_only:missing,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Preparation ingress source check failed; retain '+directory);
 }
}
// The factored tracker must preserve the preceding unsealed CPU-link API.
const compatibilityNames=[...compatibilityFixture.toString().matchAll(/^test "(preparation ingress[^"\n]+)"/gm)].map(m=>m[1]);assert.equal(compatibilityNames.length,11);
for(const mode of ['Debug','ReleaseSafe'])for(const name of compatibilityNames){
 const args=['-p','(version 1)(allow default)(deny network*)',zig,'test','-lc','-O'+mode,'--test-filter',name,'--dep','build_options','-Mroot='+join(unit,'compatibility.zig'),'-Mbuild_options='+join(unit,'options.zig')];
 const result=spawnSync('/usr/bin/sandbox-exec',args,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20}),log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),log,{mode:0o600});
 const expected=!result.error&&!result.signal&&result.status===0&&log.includes('All 2 tests passed.');receipt.results.push({compatibility:true,parent:false,mode,name,status:result.status,expected,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Retain compatibility failure '+directory);
}
receipt.unchanged=Object.entries(declared).every(([name,identity])=>hash(bytes(join(source,name)))===identity)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256&&hash(bytes(compatibilityFixturePath))===receipt.compatibility_fixture_sha256;
save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_missing_interface_cases:2,parent_controls:4,candidate_cases:20,candidate_compatibility_cases:22,models:0,native_authority:false}));
