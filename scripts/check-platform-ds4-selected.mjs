#!/usr/bin/env node
// Whole real C module, genuine private worker, empty payload/private checkpoint.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyDs4SourceBuild} from './lib/platform-ds4-source-review.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
assert(args.length===7&&args[0]==='--isolated'&&args[1]==='--build'&&args[3]==='--sha256'&&args[5]==='--developer-dir'&&args[6]==='/Applications/Xcode.app/Contents/Developer');
const config={document:args[2],expected:args[4],root},selected=verifyDs4SourceBuild(config),source=selected.source;
const directory=mkdtempSync('/private/tmp/fios-ds4-selected-');
const env={DEVELOPER_DIR:args[6],PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C'};
const run=(file,argv)=>execFileSync(file,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const compiler=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','clang']).trim()),sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
const receipt=JSON.parse(readFileSync(args[2],'utf8'));
assert.equal(createHash('sha256').update(readFileSync(compiler)).digest('hex'),receipt.compiler_sha256);
run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',compiler]);
const original=readFileSync(path.join(source,'ds4.c'),'utf8'),pin='        metal_graph_selected_async_load_run(&job);';assert.equal(original.split(pin).length,2);
let actual=original.replace(pin,`        __atomic_store_n(&fios_selected_entered,1,__ATOMIC_RELEASE);
        while(!__atomic_load_n(&fios_selected_release,__ATOMIC_ACQUIRE))usleep(100);
${pin}`);
// Preserve the actual finishing implementation; hold only its caller frame
// immediately after it releases the mailbox mutex, before consuming the result.
const finishStart=actual.indexOf('static bool metal_graph_selected_async_load_finish('),finishEnd=actual.indexOf('\n#ifdef DS4_ROCM_BUILD',finishStart);
assert(finishStart>0&&finishEnd>finishStart);
let finish=actual.slice(finishStart,finishEnd);
const activePin='    job->active = false;';assert.equal(finish.split(activePin).length,2);
finish=finish.replace(activePin,`    if(__atomic_load_n(&fios_selected_finish_hold,__ATOMIC_ACQUIRE)){
        __atomic_store_n(&fios_selected_finish_entered,1,__ATOMIC_RELEASE);
        while(!__atomic_load_n(&fios_selected_finish_release,__ATOMIC_ACQUIRE))usleep(100);
    }
${activePin}`);
actual=actual.slice(0,finishStart)+finish+actual.slice(finishEnd);
const startPin='    if (!metal_graph_selected_async_load_ensure_worker())';assert.equal(actual.split(startPin).length,2);
actual=actual.replace(startPin,`    if(__atomic_load_n(&fios_selected_start_hold,__ATOMIC_ACQUIRE)){
        __atomic_store_n(&fios_selected_start_entered,1,__ATOMIC_RELEASE);
        while(!__atomic_load_n(&fios_selected_start_release,__ATOMIC_ACQUIRE))usleep(100);
    }
${startPin}`);
const createPin='const int rc = pthread_create(&g_metal_graph_selected_async_load_thread,';assert.equal(actual.split(createPin).length,2);
// Explicit software refusal before that one worker-creation syscall; no
// phantom worker or successful join is manufactured by this fault case.
actual=actual.replace(createPin,'const int rc = __atomic_load_n(&fios_selected_create_refused,__ATOMIC_ACQUIRE) ? EAGAIN : pthread_create(&g_metal_graph_selected_async_load_thread,');
// Missing-interface baseline only. The actual parent-source fixture separately
// reproduces destructive cleanup without the busy guard before implementation.
if(!original.includes('static bool metal_graph_selected_async_load_idle(void)'))actual+='\nstatic bool metal_graph_selected_async_load_idle(void){return true;}\n';
const fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4Selected.c.fixture'),fixture=readFileSync(fixtureFile,'utf8');
const objects=['ds4_image.o','ds4_distributed.o','ds4_tp.o','ds4_ssd.o','ds4_layer_pack.o','ds4_engram.o','ds4_gpu_args.o','ds4_help.o','ds4_metal.o'];
for(const name of objects){const value=receipt.objects[name];assert(value);const b=readFileSync(path.join(source,name));assert.equal(b.length,value.bytes);assert.equal(createHash('sha256').update(b).digest('hex'),value.sha256);}
const unit=path.join(directory,'selected.c'),binary=path.join(directory,'selected');
writeFileSync(unit,'static unsigned fios_selected_entered,fios_selected_release,fios_selected_finish_hold,fios_selected_finish_entered,fios_selected_finish_release,fios_selected_start_hold,fios_selected_start_entered,fios_selected_start_release,fios_selected_create_refused;\n'+actual+'\n'+fixture);
console.log('Selected-loader fixture state:',directory);
run(compiler,['-isysroot',sdk,'-I',source,'-std=gnu11','-O3','-ffast-math','-g','-mcpu=native','-UNDEBUG',unit,...objects.map(name=>path.join(source,name)),'-lm','-pthread','-framework','Foundation','-framework','Metal','-o',binary]);
for(const mode of [[],['--finish-held'],['--enqueue-held'],['--enqueue-start-failure']]){
 const result=spawnSync(binary,mode,{env,cwd:source,encoding:'utf8',timeout:10000,maxBuffer:1<<20});
 writeFileSync(path.join(directory,mode.length?mode[0]+'-stderr.log':'stderr.log'),result.stderr??'');assert(!result.error&&!result.signal,'Selected-loader crash/deadline is not acceptance');assert.equal(result.status,0,result.stderr);
 console.log(result.stdout.trim());
}
assert.deepEqual(verifyDs4SourceBuild(config),selected);assert.equal(readFileSync(path.join(source,'ds4.c'),'utf8'),original);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);
console.log(JSON.stringify({directory,build_receipt_sha256:args[4],fixture_sha256:createHash('sha256').update(fixture).digest('hex'),binary_sha256:createHash('sha256').update(readFileSync(binary)).digest('hex'),actual_cpu_worker:true,empty_payload:true,production_enqueue:true,genuine_tensor_and_event:true,empty_invalid_model_payload:true,worker_retirement_tested:false,native_inference:false,native_authority:false}));
