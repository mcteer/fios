#!/usr/bin/env node
// Actual idle producer + native hooks + genuine SDK CPU callbacks, no models.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
const root=resolve(import.meta.dirname,'..'),a=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0&&a.length===11&&a[0]==='--isolated');
for(const[i,k]of ['--source','--zig','--sdk-source','--sdk-library','--sdk-sha256'].entries())assert.equal(a[1+i*2],k);
const pathAt=i=>{const p=a[i];assert(isAbsolute(p)&&p.startsWith('/private/tmp/')&&realpathSync(p)===p);return p;};
const[source,zig,sdkSource,library]=[2,4,6,8].map(pathAt),hash=b=>createHash('sha256').update(b).digest('hex');
function bytes(p,max=8<<20){const s=lstatSync(p);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<=max);return readFileSync(p);}
assert.equal(hash(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert(/^[a-f0-9]{64}$/.test(a[10]));assert.equal(hash(bytes(library,256<<20)),a[10]);
const directory=mkdtempSync('/private/tmp/fios-009-idle-unload-sdk-check-'),unit=join(directory,'unit'),review=join(directory,'review'),nativeReview=join(directory,'native-review');for(const p of [unit,review,nativeReview])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(p,args,cwd=directory)=>execFileSync(p,args,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});const git=(repo,...args)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',repo,...args]);
const pin='c69303b00f5f61860436e832f23fa8c34b96f93a';assert.equal(git(sdkSource,'rev-parse','HEAD').trim(),pin);
const sdkNames=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
for(const name of sdkNames){const p=join(review,name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,git(sdkSource,'show',pin+':'+name),{mode:0o600});}
const patchInputs={};
for(const name of ['mlx-c69303b-owner-uncertainty.patch','mlx-c69303b-metal-callback-fence.patch','mlx-c69303b-metal-callback-status.patch','mlx-c69303b-owner-capture-refusal.patch']){const b=bytes(join(root,'platform/studio/native',name));patchInputs[name]=hash(b);const p=join(directory,name);writeFileSync(p,b,{mode:0o600});run('/usr/bin/git',['apply',p],review);}
const sdkInputs={};for(const name of sdkNames){const b=bytes(join(sdkSource,name));assert(b.equals(readFileSync(join(review,name))));sdkInputs[name]=hash(b);}
const base='3736ed55f81c6cf0966a0f0dc7265e783655d244',nativeNames=['fios/request_ownership.zig','engines/mlx/scheduler.zig'],before={},nativePatches={};
for(const name of [...nativeNames,'fios/queued_request_ownership.zig','engines/mlx/runtime/load_requests.zig','engines/mlx/runtime/thread.zig','engines/mlx/runtime/loop.zig']){const p=join(nativeReview,'src',name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,git(source,'show',base+':src/'+name),{mode:0o600});}
for(const name of ['mlx-serve-current-startup-origin.patch','mlx-serve-current-required-queued-origin.patch','mlx-serve-current-idle-unload-origin.patch']){
 if(name==='mlx-serve-current-idle-unload-origin.patch')for(const n of nativeNames)before[n]=readFileSync(join(nativeReview,'src',n));
 const b=bytes(join(root,'platform/studio/native',name)),p=join(directory,name);nativePatches[name]=hash(b);writeFileSync(p,b,{mode:0o600});run('/usr/bin/git',['apply',p],nativeReview);
}
for(const name of [...nativeNames,'fios/queued_request_ownership.zig'])assert(bytes(join(source,'src',name)).equals(readFileSync(join(nativeReview,'src',name))));
const pending=['fios/request_ownership.zig','fios/queued_request_ownership.zig','fios/sdk_request_ownership.zig'],nativeInputs={},copied=new Set();
while(pending.length){const name=pending.pop();if(copied.has(name))continue;copied.add(name);const p=join(source,'src',name),b=bytes(p);nativeInputs[name]=hash(b);const dest=join(unit,name);mkdirSync(dirname(dest),{recursive:true,mode:0o700});writeFileSync(dest,b,{mode:0o600});for(const m of b.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){const dependency=resolve(dirname(p),m[1]),n=relative(join(source,'src'),dependency);assert(!n.startsWith('..')&&!isAbsolute(n));if(existsSync(dependency))pending.push(n);}}
const producer=bytes(join(source,'src',nativeNames[1]));nativeInputs[nativeNames[1]]=hash(producer);
const cppFile=join(root,'platform/studio/native/sdk_startup_origin_fixture.cpp'),helperFile=join(root,'platform/studio/native/sdk_host_owners_fixture.cpp'),fixtureFile=join(root,'platform/studio/native/current_idle_unload_sdk_test.zig.fixture'),cpp=bytes(cppFile),helper=bytes(helperFile),fixture=bytes(fixtureFile).toString();
writeFileSync(join(unit,'fixture.cpp'),cpp,{mode:0o600});writeFileSync(join(unit,'sdk_host_owners_fixture.cpp'),helper,{mode:0o600});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');const sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim()),stub=join(sdk,'usr/lib/libc++.1.tbd'),stubSHA=hash(readFileSync(stub));
const receipt={version:1,scope:'actual_idle_producer_native_hooks_and_genuine_SDK_CPU_callbacks_not_native_authority',directory,source,native_revision:git(source,'rev-parse','HEAD').trim(),native_base:base,native_inputs:nativeInputs,native_patches:nativePatches,baseline_native_inputs:Object.fromEntries(Object.entries(before).map(([n,b])=>[n,hash(b)])),sdk_source:sdkSource,sdk_pin:pin,sdk_inputs:sdkInputs,sdk_patches:patchInputs,sdk_library:library,sdk_library_sha256:a[10],sdk:'27.2',cxx_stub_sha256:stubSHA,cpp_sha256:hash(cpp),cpp_helper_sha256:hash(helper),fixture_sha256:hash(Buffer.from(fixture)),runner_sha256:hash(readFileSync(import.meta.filename)),sdk_build_modes:'one_existing_library_build_two_client_modes',fixture_substitutions:['CPU registry/queue/completion records','queue clones worker scope synchronously before genuine SDK publication'],actual_metal_buffers:0,models:0,inference:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false,all_client_coverage:false,results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const[mode,opt]of [['Debug','-O0'],['ReleaseSafe','-O2']]){
 const object=join(directory,mode+'.o'),compiled=spawnSync('/usr/bin/clang++',['-std=c++20',opt,'-UNDEBUG','-isysroot',sdk,'-I',sdkSource,'-c',join(unit,'fixture.cpp'),'-o',object],{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});writeFileSync(join(directory,mode+'-cpp.log'),(compiled.stdout??'')+(compiled.stderr??''));assert.equal(compiled.status,0,'CPP failed: '+directory);
 for(const label of ['baseline','candidate']){
  writeFileSync(join(unit,nativeNames[0]),label==='baseline'?before[nativeNames[0]]:bytes(join(source,'src',nativeNames[0])),{mode:0o600});
  const text=label==='baseline'?before[nativeNames[1]].toString():producer.toString(),start=text.indexOf('pub fn unloadModelIfIdle('),stop=text.indexOf('\n/// The least recently used',start);assert(start>=0&&stop>start);
  writeFileSync(join(unit,'main.zig'),fixture.replace('// ACTUAL_PRODUCER',text.slice(start,stop)),{mode:0o600});writeFileSync(join(unit,'options.zig'),`pub const fios_source_ane=false;\npub const scenario=0;\npub const sdk_library=${JSON.stringify(library)};\n`,{mode:0o600});
  const name=label+'-'+mode,binary=join(directory,name),built=spawnSync(zig,['build-exe',object,'-O'+mode,'-lc',stub,'--sysroot',sdk,library,'-rpath',dirname(library),'-F/System/Library/Frameworks','-framework','Metal','-framework','Foundation','--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+binary],{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
  writeFileSync(join(directory,name+'-build.log'),(built.stdout??'')+(built.stderr??''));const item={label,mode,build_status:built.status,build_signal:built.signal};receipt.results.push(item);save();assert.equal(built.status,0,'Build failed: '+directory);
  const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:20000,maxBuffer:65536}),log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,name+'-run.log'),log);item.run_status=result.status;item.run_signal=result.signal;item.actual_cpu_callbacks=null;
  item.expected=label==='baseline'?result.status===1&&log.includes('FIO_IDLE_UNLOAD_WITHOUT_PUBLISHED_ORIGINS'):result.status===0&&log.includes('PASS: actual idle-unload producer retains exact model through genuine SDK');if(item.expected)item.actual_cpu_callbacks=label==='candidate'?2:0;save();assert(item.expected,'Runtime failed: '+directory);
 }
}
receipt.selected_inputs_unchanged=Object.entries(nativeInputs).every(([n,h])=>hash(bytes(join(source,'src',n)))===h)&&Object.entries(sdkInputs).every(([n,h])=>hash(bytes(join(sdkSource,n)))===h)&&Object.entries({...patchInputs,...nativePatches}).every(([n,h])=>hash(bytes(join(root,'platform/studio/native',n)))===h)&&hash(bytes(library,256<<20))===receipt.sdk_library_sha256&&hash(bytes(cppFile))===receipt.cpp_sha256&&hash(bytes(helperFile))===receipt.cpp_helper_sha256&&hash(bytes(fixtureFile))===receipt.fixture_sha256&&hash(readFileSync(stub))===stubSHA&&hash(readFileSync(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.selected_inputs_unchanged);console.log(JSON.stringify({directory,receipt_sha256:hash(readFileSync(join(directory,'receipt.json'))),expected_baseline_failures:2,candidate_passes:2,models:0,native_authority:false}));
