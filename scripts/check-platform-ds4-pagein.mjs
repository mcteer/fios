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
const directory=mkdtempSync('/private/tmp/fios-ds4-pagein-');
const env={DEVELOPER_DIR:args[6],PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C'};
const run=(file,argv)=>execFileSync(file,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const compiler=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','clang']).trim()),sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
const receipt=JSON.parse(readFileSync(args[2],'utf8'));
assert.equal(createHash('sha256').update(readFileSync(compiler)).digest('hex'),receipt.compiler_sha256);
run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',compiler]);
const original=readFileSync(path.join(source,'ds4.c'),'utf8');
const begin=original.indexOf('typedef struct {\n    uint64_t off;\n    uint64_t size;\n} metal_graph_stream_pagein_range;');
const end=original.indexOf('\ntypedef struct {\n    metal_graph_stream_pagein_job job;',begin);assert(begin>0&&end>begin);
assert.equal(original.slice(begin,end).split('    metal_graph_stream_pagein_job *job = arg;').length,2,'Exact private worker checkpoint required');
const fragment=original.slice(begin,end).replaceAll('pthread_join(', 'fios_pagein_join(').replaceAll('pthread_create(', 'fios_pagein_create(').replace('    metal_graph_stream_pagein_job *job = arg;', '    metal_graph_stream_pagein_job *job = arg;\n    if(fios_pagein_hold){__atomic_store_n(&fios_pagein_entered,1,__ATOMIC_RELEASE);while(!__atomic_load_n(&fios_pagein_release,__ATOMIC_ACQUIRE))usleep(100);}');
const actual=original.slice(0,begin)+fragment+original.slice(end);
const prelude=`#include <pthread.h>
#include <errno.h>
static unsigned fios_pagein_hold,fios_pagein_entered,fios_pagein_release;
static unsigned fios_pagein_real_joins;
static int fios_pagein_inject_failure;
static unsigned fios_pagein_create_calls;
static unsigned fios_pagein_fail_create;
static int fios_pagein_create(pthread_t *thread,const pthread_attr_t *attr,void *(*fn)(void *),void *arg){++fios_pagein_create_calls;if(fios_pagein_create_calls==fios_pagein_fail_create)return EAGAIN;return pthread_create(thread,attr,fn,arg);}
static int fios_pagein_join(pthread_t thread,void **value){int rc=pthread_join(thread,value);if(!rc)++fios_pagein_real_joins;return !rc&&fios_pagein_inject_failure?EIO:rc;}
`;
const fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4Pagein.c.fixture'),fixture=readFileSync(fixtureFile,'utf8');
const objects=['ds4_image.o','ds4_distributed.o','ds4_tp.o','ds4_ssd.o','ds4_layer_pack.o','ds4_engram.o','ds4_gpu_args.o','ds4_help.o','ds4_metal.o'];
for(const name of objects){const value=receipt.objects[name];assert(value);const b=readFileSync(path.join(source,name));assert.equal(b.length,value.bytes);assert.equal(createHash('sha256').update(b).digest('hex'),value.sha256);}
const unit=path.join(directory,'pagein.c'),binary=path.join(directory,'pagein');
writeFileSync(unit,(original.includes('metal_graph_stream_pagein_launch(')?'#define FIOS_PAGEIN_HEAP_CUSTODY 1\n':'')+prelude+actual+'\n'+fixture);
console.log('Page-in fixture state:',directory);
run(compiler,['-isysroot',sdk,'-I',source,'-std=gnu11','-O3','-ffast-math','-g','-mcpu=native','-UNDEBUG',unit,...objects.map(name=>path.join(source,name)),'-lm','-pthread','-framework','Foundation','-framework','Metal','-o',binary]);
const results=['--selected-success','--layer-success','--selected-failure','--layer-failure','--selected-parallel-success','--layer-parallel-failure','--partial-success','--partial-failure','--capacity','--escaped-owner'].map(mode=>{
 const result=spawnSync(binary,[mode],{env,cwd:source,encoding:'utf8',timeout:10000,maxBuffer:1<<20});
 writeFileSync(path.join(directory,mode+'-stderr.log'),result.stderr??'');return result;
});
for(const result of results){assert(!result.error&&!result.signal,'Page-in crash/deadline is not acceptance');assert.equal(result.status,0,result.stderr);}
assert.deepEqual(verifyDs4SourceBuild(config),selected);assert.equal(readFileSync(path.join(source,'ds4.c'),'utf8'),original);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);
console.log(results[0].stdout.trim());console.log(JSON.stringify({directory,build_receipt_sha256:args[4],fixture_sha256:createHash('sha256').update(fixture).digest('hex'),binary_sha256:createHash('sha256').update(readFileSync(binary)).digest('hex'),actual_cpu_worker:true,empty_ranges:true,case_count:results.length,caller_stack_escape_tested:true,production_enqueue:false,local_worker_custody_only:true,software_failure_after_genuine_join:true,native_inference:false,all_backend_terminality:false,native_authority:false}));
