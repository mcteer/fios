#!/usr/bin/env node
// Exact current backend-fence overlay and actual protocol/tracker metadata. No models,
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
// Exact four-path parent projection, not whole-repository/native provenance.
const parents={
  "src/fios/control_protocol.zig": "fc4f3d51364af773cd4135ba12debaa624729966ef322641c8b89a82f7b84215",
  "src/fios/control_transport.zig": "15320019de0ed173dce8ba6967cff216b2f0afa554bdabec17b6683e2fd7b7e8",
  "src/host/http/server.zig": "109c977cc0afd0307ca24ba1306e176605df792b4cf5129d440c8971ed38184b",
  "src/fios/current_backend_fences.zig": null
};
const directory=mkdtempSync('/private/tmp/fios-009-current-backend-fences-check-');
const review=join(directory,'parent'),unit=join(directory,'unit');
for(const path of [review,unit])mkdirSync(path,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(program,argv,cwd=directory)=>execFileSync(program,argv,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const revision=run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim();
assert.equal(revision,'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-current-backend-fences.patch'),patch=bytes(patchPath);
const changed=[...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(match=>match[1]);
assert.deepEqual([...changed].sort(),Object.keys(parents).sort());
const declared={};
for(const name of changed){
  const data=bytes(join(source,name));declared[name]=hash(data);
  const target=join(review,name);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});
}
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});
run('/usr/bin/git',['apply','--reverse',patchCopy],review);
for(const [name,identity] of Object.entries(parents)){if(identity===null)assert(!existsSync(join(review,name)));else assert.equal(hash(bytes(join(review,name))),identity,'Unexpected parent projection');}
const oldProtocol=bytes(join(review,'src/fios/control_protocol.zig'));
run('/usr/bin/git',['apply',patchCopy],review);
for(const [name,identity] of Object.entries(declared))assert.equal(hash(bytes(join(review,name))),identity);

// Copy only the actual protocol/tracker dependency closure. Real transport/worker
// execution belongs to the separately recorded native enclosure, not this test.
const pending=['fios/request_ownership.zig','fios/control_protocol.zig','fios/current_backend_fences.zig'],copied=new Set();
while(pending.length){
  const name=pending.pop();if(copied.has(name))continue;copied.add(name);
  const path=join(source,'src',name),data=bytes(path);declared['src/'+name]=hash(data);
  const target=join(unit,name);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});
  for(const match of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
    const dependency=resolve(dirname(path),match[1]),name=relative(join(source,'src'),dependency);
    assert(!name.startsWith('..')&&!isAbsolute(name));if(existsSync(dependency))pending.push(name);
  }
}
const fixturePath=join(root,'platform/studio/native/current_backend_fences_test.zig.fixture'),fixture=bytes(fixturePath);
writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\n',{mode:0o600});
const protocolPath=join(unit,'fios/control_protocol.zig'),candidateProtocol=bytes(protocolPath);
const names=[...fixture.toString().matchAll(/^test "(fios current backend fence[^"\n]+)"/gm)].map(match=>match[1]);assert.equal(names.length,4);
const receipt={version:1,scope:'exact_current_backend_fences_overlay_actual_protocol_tracker_metadata_only',directory,source,revision,
  parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),
  models:0,inference:false,installed:false,activation:false,wire_changes:true,all_client_coverage:false,native_authority:false,whole_native_provenance:false,results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
const parentFixture=Buffer.from(`const std=@import("std");
const owners=@import("fios/request_ownership.zig");const protocol=@import("fios/control_protocol.zig");
test "parent explicitly lacks current backend version two" {
 const io=std.testing.io;var tracker:owners.Tracker=.{.primary_guard=false};try tracker.initialize(io,@splat(111));
 var request:[32]u8=@splat(0);@memcpy(request[0..4],"FIB9");request[4]=2;@memcpy(request[8..24],&@as([16]u8,@splat(111)));
 const reply=protocol.dispatchBackendFences(&tracker,io,&request,null);
 try std.testing.expectEqual(@intFromEnum(protocol.Status.invalid),reply[5]);
 try std.testing.expectEqual(@as(u8,1),reply[4]);try std.testing.expect(!@hasDecl(protocol,"dispatchCurrentBackendFences"));
}`);
writeFileSync(join(unit,'parent-control.zig'),parentFixture,{mode:0o600});receipt.parent_control_sha256=hash(parentFixture);
for(const label of ['parent_version1','candidate']){
  writeFileSync(protocolPath,label==='parent_version1'?oldProtocol:candidateProtocol,{mode:0o600});
  for(const mode of ['Debug','ReleaseSafe'])for(const name of label==='parent_version1'?['parent explicitly lacks current backend version two']:names){
    const argv=['-p','(version 1)(allow default)(deny network*)',zig,'test','-lc','-O'+mode,'--test-filter',name,'--dep','build_options','-Mroot='+join(unit,label==='parent_version1'?'parent-control.zig':'main.zig'),'-Mbuild_options='+join(unit,'options.zig')];
    const result=spawnSync('/usr/bin/sandbox-exec',argv,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
    const log=(result.stdout??'')+(result.stderr??''),key=label+'-'+mode+'-'+names.indexOf(name);
    writeFileSync(join(directory,key+'.log'),log,{mode:0o600});
    const item={label,mode,name,status:result.status,signal:result.signal,log_sha256:hash(Buffer.from(log))};
    item.expected=!result.error&&!result.signal&&(label==='parent_version1'
      ? result.status===0&&log.includes('All 2 tests passed.')&&log.includes('parent-control.test.'+name+'...OK')
      : result.status===0&&log.includes('All 2 tests passed.')&&log.includes('main.test.'+name+'...OK'));
    item.native_frames={};
    for(const frame of ['current-fences-native-frame.bin']){
      const path=join(directory,frame);if(!existsSync(path))continue;
      const data=bytes(path);assert.equal(data.length,64);assert.equal(data[4],2);
      const output=join(directory,key+'-'+frame);writeFileSync(output,data,{mode:0o600});unlinkSync(path);item.native_frames[relative(directory,output)]=hash(data);
    }
    assert.equal(Object.keys(item.native_frames).length,label==='candidate'&&names.indexOf(name)===1 ? 1:0);
    receipt.results.push(item);save();assert(item.expected,'Current backend-fence source check failed; retain '+directory);
  }
}
receipt.unchanged=Object.entries(declared).every(([name,identity])=>hash(bytes(join(source,name)))===identity)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_version2_unsupported_controls:2,candidate_named_cases_per_mode:4,models:0,native_authority:false}));
