#!/usr/bin/env node
// Genuine SDK CPU queues + native ownership implementation, no model,
// fault/counter campaign, replacement SDK, native server or installed change.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,copyFileSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname} from 'node:path';
import {hostname} from 'node:os';
import {verifyMlxSourceReview} from './lib/platform-mlx-source-review.mjs';
import {verifyCurrentMlxSourceReview} from './lib/platform-current-mlx-source-review.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
const currentIndex=args.indexOf('--current-sdk'),currentSDK=currentIndex>=0;
if(currentSDK){assert.equal(args.lastIndexOf('--current-sdk'),currentIndex);args.splice(currentIndex,1);}

const errorIndex=args.indexOf('--callback-error'),callbackError=errorIndex>=0;
if(callbackError){assert.equal(args.lastIndexOf('--callback-error'),errorIndex);args.splice(errorIndex,1);}
const cleanupIndex=args.indexOf('--stream-cleanup'),streamCleanup=cleanupIndex>=0;
if(streamCleanup){assert.equal(args.lastIndexOf('--stream-cleanup'),cleanupIndex);args.splice(cleanupIndex,1);}
const abandonedIndex=args.indexOf('--abandoned-buffer'),abandonedBuffer=abandonedIndex>=0;
if(abandonedBuffer){assert.equal(args.lastIndexOf('--abandoned-buffer'),abandonedIndex);args.splice(abandonedIndex,1);}
const bufferIndex=args.indexOf('--buffer-origins'),bufferOrigins=bufferIndex>=0;
if(bufferOrigins){assert.equal(args.lastIndexOf('--buffer-origins'),bufferIndex);args.splice(bufferIndex,1);}
const metalIndex=args.indexOf('--metal'),withMetal=metalIndex>=0||bufferOrigins||abandonedBuffer;
assert(!(bufferOrigins&&abandonedBuffer));
assert(!((streamCleanup||callbackError)&&withMetal));
assert(!(streamCleanup&&callbackError));
if(metalIndex>=0){assert.equal(args.lastIndexOf('--metal'),metalIndex);args.splice(metalIndex,1);}
if(withMetal)assert.equal(hostname().split('.')[0],'fios-core');
const zipIndex=args.indexOf('--metal-cpp-zip');let metalZIP=null;
if(zipIndex>=0){assert(withMetal&&args.lastIndexOf('--metal-cpp-zip')===zipIndex&&args[zipIndex+1]?.startsWith('/'));metalZIP=realpathSync(args[zipIndex+1]);args.splice(zipIndex,2);}
assert.equal(withMetal,metalZIP!==null);
assert(!currentSDK||(!withMetal&&!callbackError&&!streamCleanup&&!abandonedBuffer),'Current SDK composition is ordinary CPU-only');
const verifySourceReview=currentSDK?verifyCurrentMlxSourceReview:verifyMlxSourceReview;
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===11&&args[0]==='--isolated');
for(const [i,key] of ['--sdk','--sha256','--source','--zig','--developer-dir'].entries())assert.equal(args[i*2+1],key);
const [document,source,zig,developer]=[2,6,8,10].map(i=>{assert(args[i].startsWith('/'));return realpathSync(args[i]);});
const proof=verifySourceReview(document,args[4],source),directory=mkdtempSync('/private/tmp/fios-009-sdk-host-owners-'),unit=join(directory,'unit');mkdirSync(unit,{mode:0o700});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const sha=file=>hash(readFileSync(file));
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const cpp=callbackError?'sdk_callback_error_owners_fixture.cpp':streamCleanup?'sdk_cleanup_owners_fixture.cpp':abandonedBuffer?'sdk_metal_abandoned_owners_fixture.cpp':withMetal?'sdk_metal_owners_fixture.cpp':'sdk_host_owners_fixture.cpp',test=callbackError?'sdk_callback_error_owners_test.zig.fixture':streamCleanup?'sdk_cleanup_owners_test.zig.fixture':abandonedBuffer?'sdk_metal_abandoned_owners_test.zig.fixture':bufferOrigins?'sdk_metal_buffer_owners_test.zig.fixture':withMetal?'sdk_metal_owners_test.zig.fixture':'sdk_host_owners_test.zig.fixture';
const names=['request_ownership.zig','sdk_request_ownership.zig',cpp,test];
const inputs=Object.fromEntries(names.map(name=>[name,sha(join(root,'platform/studio/native',name))]));
for(const name of names)copyFileSync(join(root,'platform/studio/native',name),join(unit,name.endsWith('.fixture')?'test.zig':name));
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:1<<20,...options});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),proof.sdk);
const sdk=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim();
const cxxStub=join(sdk,'usr/lib/libc++.1.tbd'),cxxStubSHA=sha(cxxStub);
let metalHeaders=null;
if(withMetal){assert.equal(sha(metalZIP),'4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4');run('/usr/bin/unzip',['-q',metalZIP,'-d',join(directory,'headers')]);metalHeaders=join(directory,'headers/metal-cpp');}
console.log(JSON.stringify({directory,models:0,native_server:false,actual_cpu_callbacks:abandonedBuffer?0:withMetal||streamCleanup||callbackError?1:2,actual_metal_buffers:withMetal?1:0,installed:false}));
for(const [mode,optimize] of [['Debug','-O0'],['ReleaseSafe','-O2']]){
 const object=join(directory,mode+'.o'),binary=join(directory,mode);
 run('/usr/bin/clang++',['-std=c++20',optimize,'-UNDEBUG','-isysroot',sdk,'-I',source,...(metalHeaders?['-I',metalHeaders]:[]),'-c',join(unit,cpp),'-o',object]);
 run(zig,['test',join(unit,'test.zig'),object,'-O'+mode,'-lc',cxxStub,'--sysroot',sdk,proof.libraries['libmlx.dylib'],'-rpath',dirname(proof.libraries['libmlx.dylib']),'-F/System/Library/Frameworks','-framework','Metal','-framework','Foundation','--test-filter',callbackError?'fios genuine SDK callback error':streamCleanup?'fios genuine SDK cleanup':abandonedBuffer?'fios genuine SDK abandoned buffer':bufferOrigins?'fios genuine SDK buffer records':withMetal?'fios genuine SDK Metal callbacks':'fios genuine SDK host callbacks','--test-no-exec','-femit-bin='+binary]);
 for(const scenario of currentSDK?['healthy']:!abandonedBuffer&&!streamCleanup&&!callbackError?['healthy','cached']:['existing']){
 const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env:{...env,FIOS_FIXTURE_SOURCE_FENCE:scenario},encoding:'utf8',timeout:20000,maxBuffer:8192});
 const log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,scenario==='existing'?mode+'-run.log':mode+'-'+scenario+'-run.log'),log,{mode:0o600});
 assert(!result.error&&!result.signal,JSON.stringify({error:result.error?.code,signal:result.signal}));assert.equal(result.status,0,log);
 assert(log.includes(callbackError?'PASS: genuine SDK callback error fences native owners before captured context destruction':streamCleanup?'PASS: genuine SDK cleanup fences native context release after actual CPU callback completion':abandonedBuffer?'PASS: genuine SDK abandoned buffer quarantines native owners before descriptor destruction':bufferOrigins?'PASS: genuine SDK unsubmitted buffer retains all distinct native encoding origins':withMetal?'PASS: genuine SDK Metal completion and captured-resource cleanup retain native owners':'PASS: genuine SDK parent and nested CPU callbacks retain native request roots'));assert(log.includes('All 1 tests passed.'));console.log(mode+'/'+scenario+': '+log.trim());
 }
}
assert.equal(sha(cxxStub),cxxStubSHA);
for(const name of names)assert.equal(sha(join(root,'platform/studio/native',name)),inputs[name]);
assert.deepEqual(verifySourceReview(document,args[4],source),proof);
const result={ok:true,directory,cxx_runtime:'sdk_system_libcxx',cxx_runtime_stub_sha256:cxxStubSHA,scope:callbackError?'declared_native_owner_implementation_and_source_SDK_CPU_callback_error_only':streamCleanup?'declared_native_owner_implementation_and_source_SDK_CPU_cleanup_only':abandonedBuffer?'declared_native_owner_implementation_and_source_SDK_reservation_abandonment_only':withMetal?'declared_native_owner_implementation_and_source_SDK_Metal_callbacks_only':'declared_native_owner_implementation_and_source_SDK_CPU_callbacks_only',inputs,sdk_receipt_sha256:proof.receipt_sha256,sdk_source_generation:currentSDK?'c69303b':'64ea011',modes:['Debug','ReleaseSafe'],actual_cpu_callbacks_per_mode:currentSDK?2:abandonedBuffer?0:streamCleanup||callbackError?1:withMetal?2:4,source_fence_scenarios:currentSDK?['healthy']:!abandonedBuffer&&!streamCleanup&&!callbackError?['healthy','cached']:[],actual_metal_buffers_per_mode:withMetal?(abandonedBuffer?1:2):0,metal_cpp_zip_sha256:metalZIP?sha(metalZIP):null,models:0,installed:false,native_authority:false,all_backend_terminality:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(result)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(result));
