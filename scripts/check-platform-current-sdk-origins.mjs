#!/usr/bin/env node
// Actual native origins + native hooks + genuine selected SDK CPU queues.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
let mode='startup';
for(const [flag,value]of [['--slot-origins','slot_origins'],['--queued-batch','queued_batch']]){
 const index=args.indexOf(flag);if(index<0)continue;assert.equal(mode,'startup');assert.equal(args.lastIndexOf(flag),index);args.splice(index,1);mode=value;
}
const auxIndex=args.indexOf('--auxiliary-components'),auxiliaryComponents=auxIndex>=0;
if(auxiliaryComponents){assert(mode!=='startup'&&args.lastIndexOf('--auxiliary-components')===auxIndex);args.splice(auxIndex,1);}
const refusalIndex=args.indexOf('--owner-capture-refusal'),captureRefusal=refusalIndex>=0;
if(captureRefusal){assert.equal(args.lastIndexOf('--owner-capture-refusal'),refusalIndex);args.splice(refusalIndex,1);}
assert.equal(args.length,11);assert.equal(args[0],'--isolated');
for(const [i,key]of ['--source','--zig','--sdk-source','--sdk-library','--sdk-sha256'].entries())assert.equal(args[1+i*2],key);
const [source,zig,sdkSource,library]=[2,4,6,8].map(i=>{const p=args[i];assert(isAbsolute(p)&&p.startsWith('/private/tmp/')&&realpathSync(p)===p);return p;});
const hash=b=>createHash('sha256').update(b).digest('hex');
const bytes=(p,max=8<<20)=>{const s=lstatSync(p);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<=max);return readFileSync(p);};
assert.equal(hash(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert(/^[a-f0-9]{64}$/.test(args[10]));assert.equal(hash(bytes(library,256<<20)),args[10]);
const directory=mkdtempSync('/private/tmp/fios-009-startup-sdk-check-'),unit=join(directory,'unit'),review=join(directory,'review');
for(const p of [unit,review])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(p,a,cwd=directory)=>execFileSync(p,a,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const git=(repo,...a)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',repo,...a]);
const base='3736ed55f81c6cf0966a0f0dc7265e783655d244',names=['engines/mlx/scheduler.zig','engines/mlx/runtime/thread.zig','engines/mlx/runtime/loop.zig'];
const nativeInputs={},original={};
for(const name of names){const b=Buffer.from(git(source,'show',base+':src/'+name));original[name]=b;const p=join(review,'src',name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,b,{mode:0o600});nativeInputs[name]=hash(bytes(join(source,'src',name)));}
const patchFile=join(root,'platform/studio/native/mlx-serve-current-startup-origin.patch'),patch=bytes(patchFile);
writeFileSync(join(directory,'startup.patch'),patch,{mode:0o600});run('/usr/bin/git',['apply',join(directory,'startup.patch')],review);
const prefix=text=>{const a=text.indexOf('pub fn inferenceLoop(ctx: ThreadCtx) void {'),b=text.indexOf('    while (!sch.shutdown.load(.acquire))',a);assert(a>=0&&b>a);return text.slice(a,b)+'}\n';};
for(const name of names.slice(0,2))assert(bytes(join(source,'src',name)).equals(readFileSync(join(review,'src',name))));
const candidatePrefix=prefix(readFileSync(join(source,'src',names[2]),'utf8'));assert.equal(candidatePrefix,prefix(readFileSync(join(review,'src',names[2]),'utf8')),'Actual startup prefix differs from reviewed patch');
const helper=bytes(join(root,'platform/studio/native/current_startup_origin.zig'));assert(helper.equals(bytes(join(source,'src/fios/current_startup_origin.zig'))));
const helperNames=mode==='startup'?[]:['current_slot_origins.zig',...(mode==='queued_batch'?['current_queued_origins.zig']:[])];
for(const name of helperNames)assert(bytes(join(root,'platform/studio/native',name)).equals(bytes(join(source,'src/fios',name))));
const pending=['fios/request_ownership.zig','fios/sdk_request_ownership.zig','fios/queued_request_ownership.zig','fios/current_startup_origin.zig',...helperNames.map(n=>'fios/'+n)],copied=new Set();
while(pending.length){const name=pending.pop();if(copied.has(name))continue;copied.add(name);const p=join(source,'src',name),b=bytes(p);nativeInputs[name]=hash(b);const dest=join(unit,name);mkdirSync(dirname(dest),{recursive:true,mode:0o700});writeFileSync(dest,b,{mode:0o600});
 for(const m of b.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){const dependency=resolve(dirname(p),m[1]),n=relative(join(source,'src'),dependency);assert(!n.startsWith('..')&&!isAbsolute(n));if(existsSync(dependency))pending.push(n);}}
const sdkPin='c69303b00f5f61860436e832f23fa8c34b96f93a';assert.equal(git(sdkSource,'rev-parse','HEAD').trim(),sdkPin);
const sdkNames=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
const sdkPatchFile=join(root,'platform/studio/native/mlx-c69303b-owner-uncertainty.patch'),sdkPatch=bytes(sdkPatchFile);
const sdkOverlays={};
if(captureRefusal){
 const sdkReview=join(directory,'sdk-review');mkdirSync(sdkReview,{mode:0o700});
 for(const name of sdkNames){const p=join(sdkReview,name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,git(sdkSource,'show',sdkPin+':'+name),{mode:0o600});}
 for(const name of ['mlx-c69303b-owner-uncertainty.patch','mlx-c69303b-metal-callback-fence.patch','mlx-c69303b-metal-callback-status.patch','mlx-c69303b-owner-capture-refusal.patch']){
  const data=bytes(join(root,'platform/studio/native',name));sdkOverlays[name]=hash(data);const p=join(directory,name);writeFileSync(p,data,{mode:0o600});run('/usr/bin/git',['apply',p],sdkReview);
 }
 for(const name of sdkNames)assert(bytes(join(sdkSource,name)).equals(readFileSync(join(sdkReview,name))));
}else assert.equal(git(sdkSource,'diff','--no-ext-diff','--no-textconv','HEAD','--',...sdkNames),sdkPatch.toString(),'Only the explicit canonical SDK overlay is selected');
const sdkInputs=Object.fromEntries(sdkNames.map(n=>[n,hash(bytes(join(sdkSource,n)))]));
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');const sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim()),stub=join(sdk,'usr/lib/libc++.1.tbd'),stubSHA=hash(readFileSync(stub));
const fixtureName=mode==='startup'?'sdk_startup_origin_test.zig.fixture':mode==='slot_origins'?'sdk_slot_origins_test.zig.fixture':'sdk_queued_batch_origins_test.zig.fixture';
const fixtureFile=join(root,'platform/studio/native',fixtureName),fixture=bytes(fixtureFile).toString(),cppNames=['sdk_host_owners_fixture.cpp','sdk_startup_origin_fixture.cpp'];
let fixtureProgram=mode==='startup'?fixture:fixture.replace('const std = @import("std");','const std = @import("std");\nextern fn fios_startup_sdk_library_is_selected(expected: [*:0]const u8) c_int;').replace('    const io = std.testing.io;','    const io = std.testing.io;\n    try std.testing.expectEqual(@as(c_int,1),fios_startup_sdk_library_is_selected(@import("build_options").sdk_library));');
if(auxiliaryComponents){
 const binding='    try owners.shared().bind(io, second, "fixture/slot-origin");';
 assert.equal(fixtureProgram.split(binding).length,2);
 fixtureProgram=fixtureProgram.replace(binding,binding+'\n    try owners.shared().bindAuxiliary(io, first, "fixture/auxiliary-a");\n    try owners.shared().bindAuxiliary(io, second, "fixture/auxiliary-b");');
 fixtureProgram+='\nfn checkAuxiliaryComponents(io: std.Io) !void {\n    const observed = owners.shared().snapshot(io);\n    try std.testing.expectEqual(@as(usize,3),observed.model_count);\n    for ([_][]const u8{"fixture/slot-origin","fixture/auxiliary-a","fixture/auxiliary-b"}) |id| {\n        var found = false;\n        for (observed.models[0..observed.model_count]) |model| if (std.mem.eql(u8,model.id[0..model.len],id)) { found = true; };\n        try std.testing.expect(found);\n    }\n}\n';
 const held='    try std.testing.expectEqual(@as(usize, 2), owners.shared().snapshot(io).owned);';
 assert.equal(fixtureProgram.split(held).length,3);fixtureProgram=fixtureProgram.replaceAll(held,held+'\n    try checkAuxiliaryComponents(io);');
 const retired='    try std.testing.expectEqual(@as(usize, 0), owners.shared().snapshot(io).owned);';
 assert.equal(fixtureProgram.split(retired).length,2);fixtureProgram=fixtureProgram.replace(retired,retired+'\n    try std.testing.expectEqual(@as(usize,0),owners.shared().snapshot(io).model_count);');
}
const testFilter=mode==='slot_origins'?'fios genuine slot origin union':'fios genuine queued batch origin union';
const successMarker=mode==='startup'?'PASS: actual startup prefix retains exact model':mode==='slot_origins'?'PASS: genuine SDK callbacks retain both slot origins after actor exit':'PASS: genuine SDK callbacks retain both queued batch origins after actor exit';
const cppInputs=Object.fromEntries(cppNames.map(n=>[n,hash(bytes(join(root,'platform/studio/native',n)))]));
for(const name of cppNames)writeFileSync(join(unit,name),bytes(join(root,'platform/studio/native',name)),{mode:0o600});
writeFileSync(join(unit,'options.zig'),'pub const fios_source_ane = false;\npub const sdk_library = '+JSON.stringify(library)+';\n',{mode:0o600});
const receipt={version:1,scope:'actual_native_origins_hooks_genuine_SDK_CPU_callbacks_selected_inputs_only',mode,owner_capture_refusal:captureRefusal,sdk_overlay_patches:sdkOverlays,auxiliary_components:auxiliaryComponents,auxiliary_model_ids:auxiliaryComponents?['fixture/auxiliary-a','fixture/auxiliary-b']:[],directory,source,native_revision:git(source,'rev-parse','HEAD').trim(),base,native_inputs:nativeInputs,startup_prefix_sha256:hash(Buffer.from(candidatePrefix)),startup_patch_sha256:hash(patch),helper_sha256:hash(helper),sdk_source:sdkSource,sdk_pin:sdkPin,sdk_inputs:sdkInputs,sdk_patch_sha256:hash(sdkPatch),sdk_library:library,sdk_library_sha256:args[10],sdk:'27.2',cxx_stub_sha256:stubSHA,cpp_inputs:cppInputs,fixture_sha256:hash(Buffer.from(fixture)),runner_sha256:hash(readFileSync(import.meta.filename)),fixture_substitutions:mode==='startup'?['CPU registry and loader shell','loader enqueues genuine SDK CPU callback chain instead of a model','native startup prefix extracted; later loop/cleanup is outside fixture']:['slot/batch-shaped CPU metadata; actual native helper and SDK hooks','mapped-library assertion inserted into copied fixture; no full scheduler or model'],sdk_build_modes:'existing_selected_library_client_modes_only',expected_tests_per_execution:mode==='startup'?0:2,anonymous_native_import_test:mode!=='startup',mapped_library_identity_checked:true,actual_cpu_callbacks_per_execution:2,actual_metal_buffers:0,models:0,inference:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false,all_backend_terminality:false,all_client_coverage:false,results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
const controls=mode==='startup'&&!captureRefusal?[['baseline',prefix(original[names[2]].toString()),true],['candidate',candidatePrefix,false]]:[['candidate',mode==='startup'?candidatePrefix:null,false]];
for(const [label,body,baseline]of controls){
 writeFileSync(join(unit,'main.zig'),mode==='startup'?fixtureProgram.replace('// ACTUAL_STARTUP_PREFIX',body):fixtureProgram,{mode:0o600});
 for(const [clientMode,opt]of [['Debug','-O0'],['ReleaseSafe','-O2']]){
  const name=label+'-'+clientMode,object=join(directory,name+'.o'),binary=join(directory,name);
  const compile=(tool,argv,step)=>{const r=spawnSync(tool,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});writeFileSync(join(directory,name+'-'+step+'.log'),(r.stdout??'')+(r.stderr??''));return r;};
  const cpp=compile('/usr/bin/clang++',['-std=c++20',opt,'-UNDEBUG','-isysroot',sdk,'-I',sdkSource,'-c',join(unit,'sdk_startup_origin_fixture.cpp'),'-o',object],'cpp');
  const item={label,mode:clientMode,cpp_status:cpp.status,cpp_signal:cpp.signal};receipt.results.push(item);save();assert.equal(cpp.status,0,'CPP failed: '+directory);
  const built=compile(zig,[mode==='startup'?'build-exe':'test',...(mode==='startup'?[]:['--test-no-exec','--test-filter',testFilter]),object,'-O'+clientMode,'-lc',stub,'--sysroot',sdk,library,'-rpath',dirname(library),'-F/System/Library/Frameworks','-framework','Metal','-framework','Foundation','--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+binary],'build');
  item.build_status=built.status;item.build_signal=built.signal;save();assert.equal(built.status,0,'Zig failed: '+directory);
  const executed=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:20000,maxBuffer:65536}),log=(executed.stdout??'')+(executed.stderr??'');writeFileSync(join(directory,name+'-run.log'),log);item.run_status=executed.status;item.run_signal=executed.signal;
  item.expected=baseline?executed.status===1&&log.includes('FIO_STARTUP_SDK_CALLBACK_WITHOUT_ORIGIN'):executed.status===0&&log.includes(successMarker)&&(mode==='startup'||(log.includes('All 2 tests passed.')&&log.includes('fios.request_ownership.test_0...OK')));save();assert(item.expected,'Execution failed: '+directory);
 }
}
receipt.selected_inputs_unchanged=Object.entries(nativeInputs).every(([n,h])=>hash(bytes(join(source,'src',n)))===h)&&Object.entries(sdkInputs).every(([n,h])=>hash(bytes(join(sdkSource,n)))===h)&&hash(bytes(library,256<<20))===receipt.sdk_library_sha256&&Object.entries(cppInputs).every(([n,h])=>hash(bytes(join(root,'platform/studio/native',n)))===h)&&hash(bytes(fixtureFile))===receipt.fixture_sha256&&hash(bytes(patchFile))===receipt.startup_patch_sha256&&hash(bytes(sdkPatchFile))===receipt.sdk_patch_sha256&&Object.entries(sdkOverlays).every(([n,h])=>hash(bytes(join(root,'platform/studio/native',n)))===h)&&hash(bytes(join(root,'platform/studio/native/current_startup_origin.zig')))===receipt.helper_sha256&&helperNames.every(n=>hash(bytes(join(root,'platform/studio/native',n)))===nativeInputs['fios/'+n])&&hash(readFileSync(stub))===stubSHA&&hash(readFileSync(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.selected_inputs_unchanged);console.log(JSON.stringify({directory,receipt_sha256:hash(readFileSync(join(directory,'receipt.json'))),mode,owner_capture_refusal:captureRefusal,auxiliary_components:auxiliaryComponents,expected_baseline_failures:mode==='startup'&&!captureRefusal?2:0,candidate_passes:2,actual_cpu_callbacks_per_execution:2,actual_metal_buffers:0,models:0,native_authority:false}));
