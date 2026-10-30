#!/usr/bin/env node
// Actual DS4 producer/original 1KiB kernel subdomain; never device idle/authority.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,rmSync,realpathSync,lstatSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
const composed=args.at(-1)==='--composed';if(composed)args.pop();
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--developer-dir');
const source=realpathSync(args[2]),developer=realpathSync(args[4]),info=lstatSync(source);
assert(source.startsWith('/private/tmp/')&&info.uid===process.getuid()&&info.isDirectory()&&(info.mode&0o022)===0);
assert.equal(developer,'/Applications/Xcode.app/Contents/Developer');
const temporary=mkdtempSync('/private/tmp/fios-ds4-keepalive-'),env={PATH:'/usr/bin:/bin',HOME:temporary,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:30000,maxBuffer:4<<20,...options});
const git=(...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv]);
const sha=value=>createHash('sha256').update(value).digest('hex');
let passed=false;
try {
 assert.equal(git('rev-parse','HEAD').trim(),'9139e2ae58a41503968a500f36f75895c1ba63fc');
 assert.equal(git('diff','HEAD','--name-only').trim(),composed?'ds4.c\nds4.h\nds4_gpu.h\nds4_gpu_tp.h\nds4_metal.m':'ds4_metal.m');
 const patch=readFileSync(path.join(root,composed?'platform/studio/native/ds4-9139e2a-participant-retirement.patch':'platform/studio/native/ds4-9139e2a-keepalive-retirement.patch'),'utf8');
 assert.equal(git('diff','--no-ext-diff','HEAD','--',...(composed?['ds4.c','ds4.h','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m']:['ds4_metal.m'])),patch);
 const original=readFileSync(path.join(source,'ds4_metal.m'),'utf8');
 const shaderFile=readFileSync(path.join(source,'metal/dsv4_misc.metal'),'utf8');assert.equal(shaderFile,git('show','HEAD:metal/dsv4_misc.metal'));
 const kernel=/^kernel void kernel_dsv4_tp_keepalive\([\s\S]*?^\}/m.exec(shaderFile);assert(kernel);
 const shader='#include <metal_stdlib>\nusing namespace metal;\n'+kernel[0];
 function fn(name){const result=new RegExp('^static (?:id<MTLComputePipelineState>|uint64_t) '+name+'\\([^;{}]*\\)\\s*\\{[\\s\\S]*?^\\}','m').exec(original);assert(result,name);return result[0];}
 const begin=original.indexOf('static pthread_t g_queue_keepalive_thread;'),end=original.indexOf('\nint ds4_gpu_tp_failed(',begin);assert(begin>0&&end>begin);
 const participant=original.slice(begin,end);
 const verify=text=>assert(text.includes('[cb waitUntilCompleted];')&&text.includes('static int ds4_gpu_fios_keepalive_try_stop(void)')&&text.includes('g_fios_keepalive_pending = cb;'),'FIO_DS4_KEEPALIVE_UNCHECKED');
 const baseline=git('show','HEAD:ds4_metal.m');const baselineStart=baseline.indexOf('static pthread_t g_queue_keepalive_thread;');
 assert.throws(()=>verify(baseline.slice(baselineStart,baseline.indexOf('\nint ds4_gpu_tp_failed(',baselineStart))),/FIO_DS4_KEEPALIVE_UNCHECKED/);
 console.log('SOURCE RED: original producer has no checked own-buffer retirement; not a runtime/GPU red.');verify(participant);
 let instrumented=participant;
 const entry='static void *ds4_gpu_queue_keepalive_thread(void *arg) {\n    (void)arg;';assert.equal(instrumented.split(entry).length,2);
 instrumented=instrumented.replace(entry,entry+'\n    fixture_worker_checkpoint();');
 const encoder='            id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];';assert.equal(instrumented.split(encoder).length,2);
 instrumented=instrumented.replace(encoder,'            fixture_capture(cb,pipeline,scratch);\n'+encoder);
 const fixture=readFileSync(path.join(root,'platform/studio/Tests/NativeFixtures/DS4Keepalive.m.fixture'),'utf8');
 const unit=fixture.replace('// FIOS_GENUINE_KEEPALIVE_SOURCE','#define FIOS_ORIGINAL_KEEPALIVE_SHADER @'+JSON.stringify(shader)+'\n'+fn('ds4_gpu_get_pipeline')+'\n'+fn('ds4_gpu_env_u64')+'\n'+instrumented);
 assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
 const sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
 const clang=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','clang']).trim());
 run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',clang]);
 const file=path.join(temporary,'fixture.m'),binary=path.join(temporary,'fixture');
 for(const optimize of ['-O0','-O2']){
  const compile=text=>{writeFileSync(file,text);run(clang,['-isysroot',sdk,'-fobjc-arc','-std=gnu11',optimize,'-UNDEBUG',file,'-framework','Foundation','-framework','Metal','-o',binary]);};
  const execute=(mode,status=0,marker)=>{const result=spawnSync(binary,[mode],{env,encoding:'utf8',timeout:20000,maxBuffer:4096});assert(!result.error&&!result.signal,'Timeout/crash is not boundary evidence');assert.equal(result.status,status,result.stderr);if(marker)assert(result.stderr.includes(marker));};
  const positive=()=>{execute('--positive');execute('--join-error');execute('--exhausted');};
  compile(unit);positive();
  const completion='            [cb waitUntilCompleted];\n            if (cb.status != MTLCommandBufferStatusCompleted) {\n                atomic_store(&g_fios_keepalive_uncertain, 1);\n                return NULL; // Keep exact buffer/pipeline/scratch ownership.\n            }';assert.equal(unit.split(completion).length,2);
  compile(unit.replace(completion,''));execute('--positive',77,'FIO_DS4_KEEPALIVE_ACK_BEFORE_GPU_COMPLETION');
  const join='    if (pthread_join(g_queue_keepalive_thread, NULL) != 0) {\n        atomic_store(&g_fios_keepalive_uncertain, 1);\n        return 0;\n    }';assert.equal(unit.split(join).length,2);
  compile(unit.replace(join,'    (void)pthread_join(g_queue_keepalive_thread, NULL);'));execute('--join-error',77,'FIO_DS4_KEEPALIVE_JOIN_REFUSAL_CLEARED');
  const gate='    if (atomic_load(&g_fios_keepalive_sealed) || atomic_load(&g_fios_keepalive_uncertain) ||';assert.equal(unit.split(gate).length,2);
  compile(unit.replace(gate,'    if (atomic_load(&g_fios_keepalive_uncertain) ||'));execute('--positive',77,'FIO_DS4_KEEPALIVE_REARMED_SEALED_PRODUCER');
  const status='if (cb.status != MTLCommandBufferStatusCompleted) {';assert.equal(unit.split(status).length,2);
  compile(unit.replace(status,'if (cb.status != MTLCommandBufferStatusCompleted || fixture_force_error) {'));execute('--gpu-error');
  compile(unit);positive();
 }
 assert.equal(readFileSync(path.join(source,'ds4_metal.m'),'utf8'),original);
 console.log(JSON.stringify({scope:'genuine_keepalive_producer_original_kernel_fragment_only',composed_candidate:composed,source_revision:'9139e2ae58a41503968a500f36f75895c1ba63fc',patch_sha256:sha(patch),source_sha256:sha(original),shader_sha256:sha(shader),fixture_sha256:sha(fixture),native_inference:false,all_backend_terminality:false,native_authority:false,sdk:'27.2'}));
 console.log('PASS: genuine 1KiB kernel/event GPU gate, creator ownership, checked joins, exhaustion, three precise runtime omissions and injected error only after actual GPU completion. Parent/device/all-client/deadline integration remains open.');
 passed=true;
}finally{if(passed)rmSync(temporary,{recursive:true,force:true});else console.error('Failure state retained:',temporary);}
