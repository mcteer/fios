#!/usr/bin/env node
// Exact media queue overlay and real sender/tracker/actor metadata. No models,
// service actions, wire change, enrolled admission or terminal authority.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
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
// Exact three-file parent projection, not whole-repository/native provenance.
const parents={
  "src/fios/current_queued_origins.zig": "8af860bae093b20bd3337b44ab63641016bb014691e169613123d2b5f5311eb0",
  "src/host/gpu_thread/requests.zig": "70afe0e9e08ca731f04dd16acfd1e86de2f25b72bb839f475a1407f7cd9d82b1",
  "src/engines/mlx/scheduler.zig": "e1dbce9bef08b859f217ed10ef398712cef7ca1d49de97d554a5ed5fd5f55c81"
};
const directory=mkdtempSync('/private/tmp/fios-009-media-queue-check-');
const review=join(directory,'parent'),unit=join(directory,'unit');
for(const path of [review,unit])mkdirSync(path,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(program,argv,cwd=directory)=>execFileSync(program,argv,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const revision=run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim();
assert.equal(revision,'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-current-media-queue.patch'),patch=bytes(patchPath);
const changed=[...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(match=>match[1]);
assert.deepEqual([...changed].sort(),Object.keys(parents).sort());
const declared={};
for(const name of changed){
  const data=bytes(join(source,name));declared[name]=hash(data);
  const target=join(review,name);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});
}
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});
run('/usr/bin/git',['apply','--reverse',patchCopy],review);
for(const [name,identity] of Object.entries(parents))assert.equal(hash(bytes(join(review,name))),identity,'Unexpected parent projection');
const oldBook=bytes(join(review,'src/fios/current_queued_origins.zig'));
run('/usr/bin/git',['apply',patchCopy],review);
for(const [name,identity] of Object.entries(declared))assert.equal(hash(bytes(join(review,name))),identity);

// Copy only the actual sender/tracker/actor dependency closure. Real adapter worker
// execution belongs to the separately recorded native enclosure, not this test.
const pending=['fios/request_ownership.zig','fios/current_slot_origins.zig','fios/current_queued_origins.zig'],copied=new Set();
while(pending.length){
  const name=pending.pop();if(copied.has(name))continue;copied.add(name);
  const path=join(source,'src',name),data=bytes(path);declared['src/'+name]=hash(data);
  const target=join(unit,name);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});
  for(const match of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
    const dependency=resolve(dirname(path),match[1]),name=relative(join(source,'src'),dependency);
    assert(!name.startsWith('..')&&!isAbsolute(name));if(existsSync(dependency))pending.push(name);
  }
}
const fixturePath=join(root,'platform/studio/native/current_media_queue_test.zig.fixture'),fixture=bytes(fixturePath);
writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\n',{mode:0o600});
const bookPath=join(unit,'fios/current_queued_origins.zig'),candidateBook=bytes(bookPath);
const names=[...fixture.toString().matchAll(/^test "(fios current media queued[^"\n]+)"/gm)].map(match=>match[1]);assert.equal(names.length,6);
const receipt={version:1,scope:'exact_media_queue_overlay_actual_sender_tracker_actor_metadata_only',directory,source,revision,
  parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),
  models:0,inference:false,installed:false,activation:false,wire_changes:false,all_client_coverage:false,native_authority:false,whole_native_provenance:false,results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const label of ['parent_actor','candidate']){
  writeFileSync(bookPath,label==='parent_actor'?oldBook:candidateBook,{mode:0o600});
  for(const mode of ['Debug','ReleaseSafe'])for(const name of label==='parent_actor'?names.slice(0,1):names){
    const argv=['-p','(version 1)(allow default)(deny network*)',zig,'test','-lc','-O'+mode,'--test-filter',name,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig')];
    const result=spawnSync('/usr/bin/sandbox-exec',argv,{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
    const log=(result.stdout??'')+(result.stderr??''),key=label+'-'+mode+'-'+names.indexOf(name);
    writeFileSync(join(directory,key+'.log'),log,{mode:0o600});
    const item={label,mode,name,status:result.status,signal:result.signal,log_sha256:hash(Buffer.from(log))};
    item.expected=!result.error&&!result.signal&&(label==='parent_actor'
      ? result.status===1&&log.includes('FIO_MEDIA_QUEUE_NOT_ACTIVATED')&&log.includes('1 passed; 0 skipped; 1 failed.')
      : result.status===0&&log.includes('All 2 tests passed.')&&log.includes('main.test.'+name+'...OK'));
    receipt.results.push(item);save();assert(item.expected,'Media source check failed; retain '+directory);
  }
}
receipt.unchanged=Object.entries(declared).every(([name,identity])=>hash(bytes(join(source,name)))===identity)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_actor_failures:2,candidate_named_cases_per_mode:6,models:0,native_authority:false}));
