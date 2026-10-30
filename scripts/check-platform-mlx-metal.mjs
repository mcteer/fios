#!/usr/bin/env node
// Genuine original Metal pipeline and empty-GPU subdomain fixtures only.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync,mkdtempSync,mkdirSync,copyFileSync,chmodSync,existsSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url)),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()!==0);
let reviewOutput;
const reviewIndex=args.indexOf('--review-output');
if(reviewIndex!==-1){
 assert.equal(reviewIndex,args.length-2);assert(path.isAbsolute(args[reviewIndex+1]??''));
 reviewOutput=args[reviewIndex+1];args.splice(reviewIndex,2);
 const parent=realpathSync(path.dirname(reviewOutput)),info=lstatSync(parent);
 assert.equal(path.dirname(reviewOutput),parent);
 assert(parent.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o077)===0);
 assert(/^[A-Za-z0-9_-]+$/.test(path.basename(reviewOutput))&&!existsSync(reviewOutput));
}
const privateGPU=args.length===14&&args[13]==='--static-backend-clear';
const diagnostics=args.length===14&&args[13]==='--uncertainty-diagnostics';
const sharedEvents=args.length===14&&(args[13]==='--shared-events'||diagnostics);
assert((args.length===13||privateGPU||sharedEvents)&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--cmake'&&args[5]==='--json-source'&&args[7]==='--fmt-source'&&args[9]==='--metal-cpp-zip'&&args[11]==='--developer-dir'&&[2,4,6,8,10,12].every(i=>path.isAbsolute(args[i])),
 'Use --isolated --source ABS --cmake ABS --json-source ABS --fmt-source ABS --metal-cpp-zip ABS --developer-dir ABS [--static-backend-clear|--shared-events|--uncertainty-diagnostics] [--review-output ABS_NEW_PRIVATE_DIRECTORY]');
assert(!reviewOutput||sharedEvents,'Retained source dependency requires the cumulative shared-event candidate');
const [source,cmake,json,fmt,metalZIP,developer]=[2,4,6,8,10,12].map(i=>realpathSync(args[i]));
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:os.homedir(),LC_ALL:'C',DEVELOPER_DIR:developer,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1',...(privateGPU?{ZERO_AR_DATE:'1'}:{})};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:900000,maxBuffer:16<<20,...options});
const git=(directory,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',directory,...argv]);
const sha=file=>{const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink());return createHash('sha256').update(readFileSync(file)).digest('hex');};
for(const directory of [source,json,fmt]){const info=lstatSync(directory);assert(directory.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);}
const pins={mlx:'64ea011cb65f14d9ce2737e60db9a4ae91ed7441',json:'9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03',fmt:'407c905e45ad75fc29bf0f9bb7c5c2fd3475976f'};
const clean=(directory,pin)=>{assert.equal(git(directory,'rev-parse','HEAD').trim(),pin);assert.equal(git(directory,'status','--porcelain','--untracked-files=all','--ignored=matching').trim(),'');};
clean(json,pins.json);clean(fmt,pins.fmt);assert.equal(git(source,'rev-parse','HEAD').trim(),pins.mlx);
assert.equal(sha(cmake),'08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490');
assert.equal(sha(metalZIP),'4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4');
const metal=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','metal']).trim());
run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',metal]);
const metalVersion=run('/usr/bin/xcrun',['--sdk','macosx','metal','--version']);
const sdk=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim();
const metalVersions={'27.0':'32023.921','27.2':'32023.922'};assert(metalVersions[sdk]&&metalVersion.startsWith('Apple metal version '+metalVersions[sdk]+' '),'Unreviewed SDK/Metal compiler pairing');
const paths=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
const patchFile=path.join(root,`platform/studio/native/mlx-64ea011-${diagnostics?'uncertainty-diagnostics.patch':sharedEvents?'shared-event-custody.patch':'metal-buffer-custody.patch'}`),patch=readFileSync(patchFile,'utf8'),patchSHA=sha(patchFile);
assert.equal(git(source,'diff','--no-ext-diff','--no-textconv','HEAD','--',...paths),patch);assert.deepEqual(git(source,'diff','HEAD','--name-only').trim().split('\n').sort(),paths);
const fixture=path.join(root,'platform/studio/native/mlx_metal_buffer_custody_test.cpp'),fixtureSHA=sha(fixture);
const eventFixture=path.join(root,'platform/studio/native/mlx_shared_event_custody_test.cpp'),eventSHA=sharedEvents?sha(eventFixture):null;
const temporary=mkdtempSync(path.join(os.tmpdir(),'fios-009-metal-custody-'));env.TMPDIR=temporary;
const checkout=path.join(temporary,'source'),build=path.join(temporary,'build'),binary=path.join(temporary,'fixture'),eventBinary=path.join(temporary,'event-fixture');
try{
 run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',source,checkout]);git(checkout,'checkout','--quiet','--detach',pins.mlx);git(checkout,'apply','--check',patchFile);git(checkout,'apply',patchFile);
 run('/usr/bin/unzip',['-q',metalZIP,'-d',path.join(temporary,'headers')]);
 const headers=path.join(temporary,'headers/metal-cpp');
 console.log(run(cmake,['-S',checkout,'-B',build,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_C_COMPILER=/usr/bin/clang','-DCMAKE_CXX_COMPILER=/usr/bin/clang++','-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET=27.0',`-DBUILD_SHARED_LIBS=${privateGPU?'OFF':'ON'}`,'-DMLX_BUILD_CPU=ON','-DMLX_BUILD_METAL=ON','-DMLX_BUILD_CUDA=OFF','-DMLX_BUILD_TESTS=OFF','-DMLX_BUILD_EXAMPLES=OFF','-DMLX_BUILD_BENCHMARKS=OFF','-DMLX_BUILD_PYTHON_BINDINGS=OFF','-DMLX_BUILD_GGUF=OFF',`-DMLX_BUILD_SAFETENSORS=${reviewOutput?'ON':'OFF'}`,'-DMLX_USE_CCACHE=OFF','-DMLX_METAL_JIT=ON','-DFETCHCONTENT_FULLY_DISCONNECTED=ON',`-DFETCHCONTENT_SOURCE_DIR_JSON=${json}`,`-DFETCHCONTENT_SOURCE_DIR_FMT=${fmt}`,`-DFETCHCONTENT_SOURCE_DIR_METAL_CPP=${headers}`,'-DJSON_BuildTests=OFF','-DJSON_Install=OFF','-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF']));
 const library=path.join(build,privateGPU?'libmlx.a':'libmlx.dylib');
 const linkOne=(input,output,withPrivate)=>run('/usr/bin/clang++',['-std=c++20','-O2','-UNDEBUG',...(withPrivate?['-DFIOS_METAL_PRIVATE_FIXTURE']:[]),'-I',checkout,'-I',headers,input,library,...(privateGPU?['-framework','Accelerate','-framework','MetalPerformanceShaders','-framework','MetalPerformancePrimitives','-framework','QuartzCore']:[`-Wl,-rpath,${build}`]),'-framework','Metal','-framework','Foundation','-o',output]);
 const link=()=>{linkOne(fixture,binary,privateGPU);if(sharedEvents)linkOne(eventFixture,eventBinary,false);};
 const compile=()=>{for(const file of ['stream','backend/metal/device','backend/metal/eval'])rmSync(path.join(build,`CMakeFiles/mlx.dir/mlx/${file}.cpp.o`),{force:true});console.log(run(cmake,['--build',build,'--target','mlx','--parallel','2']));link();};
 compile();
 const loaderFixture=path.join(root,'platform/studio/native/mlx_safetensors_source_test.cpp');
 const loaderSHA=reviewOutput?sha(loaderFixture):null;
 if(reviewOutput){
  const loader=path.join(temporary,'safetensors-fixture');linkOne(loaderFixture,loader,false);
  const roundtrip=path.join(temporary,'scalar.safetensors');
  const log=run(loader,[roundtrip],{timeout:20000,maxBuffer:4096});assert(log.includes('PASS: genuine CPU scalar safetensors roundtrip'));
  assert(lstatSync(roundtrip).size<65536);console.log(log);
 }
 const execute=(mode,expected=0,event=false)=>{const result=spawnSync(event?eventBinary:binary,[mode],{env,encoding:'utf8',timeout:20000,maxBuffer:1<<20});assert.equal(result.error,undefined);assert.equal(result.signal,null);const log=(result.stdout??'')+(result.stderr??'');assert.equal(result.status,expected,mode+': '+log);console.log(mode+': '+log);return log;};
 const ordinary=()=>{for(const mode of ['--callback','--payload','--capture','--uncommitted','--exact-gate','--foreign','--owner-exit','--raw-alias',...(privateGPU?['--backend-clear-held','--backend-clear-unheld']:[])])execute(mode);if(sharedEvents)for(const mode of ['--wait','--signal','--held-signal'])execute(mode,0,true);};
 if(diagnostics){
  const input=path.join(root,'platform/studio/native/mlx_uncertainty_source_test.cpp'),output=path.join(temporary,'uncertainty-fixture');
  linkOne(input,output,false);
  const log=run(output,[],{timeout:20000,maxBuffer:4096});assert(log.includes('PASS: genuine exported first-uncertainty accessor'));console.log(log);
  const budgetInput=path.join(root,'platform/studio/native/mlx_capture_budget_source_test.cpp'),budgetOutput=path.join(temporary,'capture-budget-fixture');
  linkOne(budgetInput,budgetOutput,false);
  for(const mode of ['--per-buffer','--global']){const budgetLog=run(budgetOutput,[mode],{timeout:20000,maxBuffer:4096});assert(budgetLog.includes('PASS: exact finite capture budget'));console.log(mode+': '+budgetLog);}
 }
 ordinary();const librarySHA=sha(library);
 const deviceFile=path.join(checkout,'mlx/backend/metal/device.cpp'),deviceOriginal=readFileSync(deviceFile,'utf8');
 const variant=(file,original,oldText,newText,mode,marker,event=false)=>{assert.equal(original.split(oldText).length,2);writeFileSync(file,original.replace(oldText,newText));compile();assert(execute(mode,77,event).includes(marker));writeFileSync(file,original);compile();ordinary();};
 const callback='        if (completion) {\n          completion();\n        }';
 variant(deviceFile,deviceOriginal,callback,'        fios_metal_completed(fios_custody, false);\n'+callback,'--callback','EARLY_METAL_CALLBACK_OR_PAYLOAD_RETIREMENT');
 const payload='          completion = nullptr;wait_events.clear();signal_events.clear();\n          fios_metal_completed(fios_custody, has_error);';
 variant(deviceFile,deviceOriginal,payload,'          fios_metal_completed(fios_custody, has_error);\n          completion = nullptr;wait_events.clear();signal_events.clear();','--payload','EARLY_METAL_CALLBACK_OR_PAYLOAD_RETIREMENT');
 const capture='      function = nullptr;\n      fios_metal_capture_end(capture, cbuf->status() == MTL::CommandBufferStatusError);';
 variant(deviceFile,deviceOriginal,capture,'      fios_metal_capture_end(capture, cbuf->status() == MTL::CommandBufferStatusError);\n      function = nullptr;','--capture','EARLY_METAL_CAPTURE_PAYLOAD_RETIREMENT');
 const streamFile=path.join(checkout,'mlx/stream.cpp'),streamOriginal=readFileSync(streamFile,'utf8');
 const gate='  if (fios_registry.enabled && fios_registry.metal_held)\n    throw std::runtime_error("Metal buffers held");\n';
 variant(streamFile,streamOriginal,gate,'','--exact-gate','METAL_GATE_ALLOWED_SUBMISSION');
 if(sharedEvents){
  const retain='  add_completed_handler([retained = NS::RetainPtr(event)](MTL::CommandBuffer*) { (void)retained; });';
  variant(deviceFile,deviceOriginal,retain,'','--wait','METAL_SHARED_EVENT_RESERVATION_OR_CAPTURE_BOUNDARY',true);
  const ordered='  fios_reserve_buffer();\n  end_encoding();\n  // Retain the actual SDK object in the existing exact capture receipt.\n  // Its owning callable is destroyed before capture retirement, outside locks.\n'+retain+'\n  if (wait) buffer_->encodeWait(event, value);\n  else buffer_->encodeSignalEvent(event, value);';
  const escaped='  if (wait) buffer_->encodeWait(event, value);\n  else buffer_->encodeSignalEvent(event, value);\n  fios_reserve_buffer();\n  end_encoding();\n'+retain;
  variant(deviceFile,deviceOriginal,ordered,escaped,'--held-signal','METAL_SHARED_EVENT_RESERVATION_OR_CAPTURE_BOUNDARY',true);
 }
 if(privateGPU){
  const file=path.join(checkout,'mlx/backend/metal/eval.cpp'),original=readFileSync(file,'utf8');
  variant(file,original,'void clear_streams() {\n  fios_before_clear_streams();\n','void clear_streams() {\n','--backend-clear-held','GPU_BACKEND_CLEAR_ALLOWED_WITH_CREATION_HOST_HELD');
 }
 const release='  if (!fios_bump()) return false;\n  fios_registry.metal_held = fios_registry.metal_owner = 0;\n  fios_registry.host_held = fios_registry.host_owner = fios_registry.host_creation = 0;\n  fios_registry.held = fios_registry.held_owner = 0;\n  return true;';
 const boundary='  fios_registry.epoch = std::numeric_limits<uint64_t>::max(); // Private boundary injector.\n';
 const cleared='  fios_registry.metal_held = fios_registry.metal_owner = 0;\n  fios_registry.host_held = fios_registry.host_owner = fios_registry.host_creation = 0;\n  fios_registry.held = fios_registry.held_owner = 0;\n  return fios_bump();';
 assert.equal(streamOriginal.split(release).length,2);writeFileSync(streamFile,streamOriginal.replace(release,boundary+cleared));compile();assert(execute('--exhausted-release',77).includes('METAL_RELEASE_CLEARED_ON_EXHAUSTION'));
 writeFileSync(streamFile,streamOriginal.replace(release,boundary+release));compile();execute('--exhausted-release');
 writeFileSync(streamFile,streamOriginal);compile();ordinary();
 assert.equal(sha(library),librarySHA);assert.equal(git(checkout,'diff','--no-ext-diff','--no-textconv','HEAD','--',...paths),patch);assert.equal(sha(patchFile),patchSHA);assert.equal(sha(fixture),fixtureSHA);if(sharedEvents)assert.equal(sha(eventFixture),eventSHA);clean(json,pins.json);clean(fmt,pins.fmt);
 let dependencyReview=null;
 if(reviewOutput){
  // Data-only copies of this restored genuine build, never host installation.
  mkdirSync(reviewOutput,{mode:0o700});
  const files={};
  for(const [name,input]of [['libmlx.dylib',library],['mlx.metallib',path.join(build,'mlx/backend/metal/kernels/mlx.metallib')],['libjaccl.dylib',path.join(build,'jaccl/libjaccl.dylib')]]){
   const before=lstatSync(input),digest=sha(input);assert(before.isFile()&&before.nlink===1&&before.size>0&&before.size<256<<20);
   const output=path.join(reviewOutput,name);copyFileSync(input,output);chmodSync(output,0o400);
   assert.equal(sha(output),digest);assert.equal(sha(input),digest);
   files[name]={bytes:before.size,sha256:digest};
  }
  assert.equal(sha(loaderFixture),loaderSHA);
  assert(readFileSync(path.join(build,'CMakeCache.txt'),'utf8').includes('MLX_BUILD_SAFETENSORS:BOOL=ON'));
  const declared=Object.fromEntries(paths.map(file=>[file,sha(path.join(checkout,file))]));
  const receipt={version:1,purpose:'private_mlx_source_dependency_review',activation:false,installed:false,native_authority:false,all_backend_terminality:false,native_inference:false,
   scope:'reviewed_patch_and_declared_dependencies_not_whole_native_provenance',features:{safetensors:true,gguf:false,cpu:true,metal:true,metal_jit:true},loader_fixture_sha256:loaderSHA,pins,patch_sha256:patchSHA,declared_sources:declared,cmake_sha256:sha(cmake),metal_cpp_zip_sha256:sha(metalZIP),metal_driver_sha256:sha(metal),metal_version:metalVersion.trim(),sdk,files};
  const bytes=Buffer.from(JSON.stringify(receipt)+'\n');writeFileSync(path.join(reviewOutput,'candidate.json'),bytes,{mode:0o400,flag:'wx'});
  dependencyReview={directory:reviewOutput,receipt_sha256:createHash('sha256').update(bytes).digest('hex')};
 }
 console.log(JSON.stringify({scope:sharedEvents?'genuine_metal_buffers_callbacks_shared_event_resources_only':'genuine_empty_metal_buffers_callbacks_and_payloads_only',shared_events:sharedEvents,safetensors_roundtrip:!!reviewOutput,event_fixture_sha256:eventSHA,all_backend_terminality:false,activation:false,private_backend_clear:privateGPU,pins,patch_sha256:patchSHA,fixture_sha256:fixtureSHA,library_sha256:librarySHA,metal_executable_sha256:sha(metal),metal_version:metalVersion.trim(),sdk,dependency_review:dependencyReview}));
 console.log(`PASS: ${sharedEvents?'eleven':privateGPU?'ten':'eight'} genuine empty-Metal cases/${sharedEvents?'seven':privateGPU?'six':'five'} actual optimized causal mutations, exact source/library restoration; ${reviewOutput?'one genuine CPU scalar safetensors roundtrip; no models/inference':'no arrays/kernels/models/inference'}/all-context/lifecycle authority. Owner/exhaustion cases deliberately exit without destructor submissions, not retirement proof.`);
}finally{rmSync(temporary,{recursive:true,force:true});}
