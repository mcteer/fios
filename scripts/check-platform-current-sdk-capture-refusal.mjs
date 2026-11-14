#!/usr/bin/env node
// Genuine SDK CPU publication with actual native capture/fence hooks; no models.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
const root=resolve(import.meta.dirname,'..'),a=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0&&a.length===15&&a[0]==='--isolated');
for(const[i,k]of ['--source','--zig','--sdk-source','--sdk-library','--sdk-sha256','--baseline-library','--baseline-sha256'].entries())assert.equal(a[1+i*2],k);
const pathAt=i=>{const p=a[i];assert(isAbsolute(p)&&p.startsWith('/private/tmp/')&&realpathSync(p)===p);return p;};
const [source,zig,sdkSource,library,baseline]=[2,4,6,8,12].map(pathAt),hash=b=>createHash('sha256').update(b).digest('hex');
function bytes(p,max=8<<20){const s=lstatSync(p);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<=max);return readFileSync(p);}
assert.equal(hash(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
for(const[p,h]of [[library,a[10]],[baseline,a[14]]]){assert(/^[a-f0-9]{64}$/.test(h));assert.equal(hash(bytes(p,256<<20)),h);}
const directory=mkdtempSync('/private/tmp/fios-009-sdk-capture-check-'),unit=join(directory,'unit'),review=join(directory,'review');for(const p of [unit,review])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(p,args,cwd=directory)=>execFileSync(p,args,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const git=(repo,...args)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',repo,...args]);
const pin='c69303b00f5f61860436e832f23fa8c34b96f93a';assert.equal(git(sdkSource,'rev-parse','HEAD').trim(),pin);
const sdkNames=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
for(const name of sdkNames){const p=join(review,name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,git(sdkSource,'show',pin+':'+name),{mode:0o600});}
const patches=['mlx-c69303b-owner-uncertainty.patch','mlx-c69303b-metal-callback-fence.patch','mlx-c69303b-metal-callback-status.patch','mlx-c69303b-owner-capture-refusal.patch'],patchInputs={};
for(const name of patches){const b=bytes(join(root,'platform/studio/native',name));patchInputs[name]=hash(b);const p=join(directory,name);writeFileSync(p,b,{mode:0o600});run('/usr/bin/git',['apply',p],review);}
const sdkInputs={};for(const name of sdkNames){const b=bytes(join(sdkSource,name));assert(b.equals(readFileSync(join(review,name))));sdkInputs[name]=hash(b);}
const pending=['fios/request_ownership.zig','fios/sdk_request_ownership.zig'],nativeInputs={},copied=new Set();
while(pending.length){const name=pending.pop();if(copied.has(name))continue;copied.add(name);const p=join(source,'src',name),b=bytes(p);nativeInputs[name]=hash(b);const dest=join(unit,name);mkdirSync(dirname(dest),{recursive:true,mode:0o700});writeFileSync(dest,b,{mode:0o600});for(const m of b.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){const dependency=resolve(dirname(p),m[1]),n=relative(join(source,'src'),dependency);assert(!n.startsWith('..')&&!isAbsolute(n));if(existsSync(dependency))pending.push(n);}}
const cppFile=join(root,'platform/studio/native/sdk_capture_refusal_fixture.cpp'),fixtureFile=join(root,'platform/studio/native/sdk_capture_refusal_test.zig.fixture'),cpp=bytes(cppFile),fixture=bytes(fixtureFile);
writeFileSync(join(unit,'fixture.cpp'),cpp,{mode:0o600});writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');const sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim()),stub=join(sdk,'usr/lib/libc++.1.tbd'),stubSHA=hash(readFileSync(stub));
const receipt={version:1,scope:'actual_native_hooks_and_genuine_SDK_CPU_capture_publication_not_native_authority',directory,source,native_revision:git(source,'rev-parse','HEAD').trim(),native_inputs:nativeInputs,sdk_source:sdkSource,sdk_pin:pin,sdk_inputs:sdkInputs,sdk_patches:patchInputs,sdk_library:library,sdk_library_sha256:a[10],baseline_library:baseline,baseline_library_sha256:a[14],sdk:'27.2',cxx_stub_sha256:stubSHA,cpp_sha256:hash(cpp),fixture_sha256:hash(fixture),runner_sha256:hash(readFileSync(import.meta.filename)),scenarios:['legacy_no_hooks','healthy_owned','native_already_fenced','registered_missing_context'],sdk_build_modes:'existing_library_builds_two_client_modes',negative_inputs:'ordinary_native_fence_export_or_absent_context_not_hardware_faults',actual_metal_buffers:0,models:0,inference:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false,all_backend_terminality:false,all_client_coverage:false,results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const[mode,opt]of [['Debug','-O0'],['ReleaseSafe','-O2']]){
 const object=join(directory,mode+'.o'),compiled=spawnSync('/usr/bin/clang++',['-std=c++20',opt,'-UNDEBUG','-isysroot',sdk,'-I',sdkSource,'-c',join(unit,'fixture.cpp'),'-o',object],{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});writeFileSync(join(directory,mode+'-cpp.log'),(compiled.stdout??'')+(compiled.stderr??''));assert.equal(compiled.status,0,'CPP failed: '+directory);
 for(const[label,selected]of [['baseline',baseline],['candidate',library]])for(const scenario of [0,1,2,3]){
  const name=label+'-'+mode+'-'+scenario,binary=join(directory,name);writeFileSync(join(unit,'options.zig'),`pub const fios_source_ane = false;\npub const scenario = ${scenario};\n`,{mode:0o600});
  const built=spawnSync(zig,['build-exe',object,'-O'+mode,'-lc',stub,'--sysroot',sdk,selected,'-rpath',dirname(selected),'-F/System/Library/Frameworks','-framework','Metal','-framework','Foundation','--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+binary],{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});writeFileSync(join(directory,name+'-build.log'),(built.stdout??'')+(built.stderr??''));const item={label,mode,scenario,build_status:built.status,build_signal:built.signal};receipt.results.push(item);save();assert.equal(built.status,0,'Build failed: '+directory);
  const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:20000,maxBuffer:65536}),log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,name+'-run.log'),log);item.run_status=result.status;item.run_signal=result.signal;
  const negative=label==='baseline'&&scenario>=2;item.expected=negative?result.status===1&&log.includes('FIO_SDK_PUBLISHED_WITHOUT_NATIVE_CAPTURE'):result.status===0&&log.includes('PASS: SDK capture publication respects native fence');save();assert(item.expected,'Runtime failed: '+directory);
 }
}
receipt.selected_inputs_unchanged=Object.entries(nativeInputs).every(([n,h])=>hash(bytes(join(source,'src',n)))===h)&&Object.entries(sdkInputs).every(([n,h])=>hash(bytes(join(sdkSource,n)))===h)&&Object.entries(patchInputs).every(([n,h])=>hash(bytes(join(root,'platform/studio/native',n)))===h)&&hash(bytes(library,256<<20))===receipt.sdk_library_sha256&&hash(bytes(baseline,256<<20))===receipt.baseline_library_sha256&&hash(bytes(cppFile))===receipt.cpp_sha256&&hash(bytes(fixtureFile))===receipt.fixture_sha256&&hash(readFileSync(stub))===stubSHA&&hash(readFileSync(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.selected_inputs_unchanged);console.log(JSON.stringify({directory,receipt_sha256:hash(readFileSync(join(directory,'receipt.json'))),original_failures:4,original_healthy_controls:4,candidate_passes:8,models:0,native_authority:false}));
