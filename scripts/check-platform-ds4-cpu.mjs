#!/usr/bin/env node
// Actual CPU pool fragment, genuine private pthreads, no model/runtime action.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync,lstatSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===3&&args[0]==='--isolated'&&args[1]==='--source');
const source=realpathSync(args[2]),info=lstatSync(source);
assert(source.startsWith('/private/tmp/')&&info.uid===process.getuid()&&info.isDirectory()&&(info.mode&0o022)===0);
const directory=mkdtempSync('/private/tmp/fios-ds4-cpu-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const git=(...argv)=>execFileSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],{env,encoding:'utf8',timeout:5000});
const files=['ds4.c','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m'];
const patchFile=path.join(root,'platform/studio/native/ds4-9139e2a-participant-retirement.patch'),patch=readFileSync(patchFile,'utf8');
assert.equal(git('rev-parse','HEAD').trim(),'9139e2ae58a41503968a500f36f75895c1ba63fc');
assert.equal(git('diff','HEAD','--name-only').trim(),files.join('\n'));assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
const original=readFileSync(path.join(source,'ds4.c'),'utf8'),start=original.indexOf('typedef void (*ds4_parallel_fn)'),end=original.indexOf('static void cursor_error(',start);
assert(start>0&&end>start);let fragment=original.slice(start,end);
const join='pthread_join(g_pool.threads[i], NULL)';assert.equal(fragment.split(join).length,2);fragment=fragment.replace(join,'fios_join(g_pool.threads[i], NULL)');
const fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4CPU.c.fixture'),fixture=readFileSync(fixtureFile,'utf8');
const prelude=`#include <pthread.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
static int fios_join_failure;static unsigned fios_actual_joins;
static int fios_join(pthread_t t,void **v){int rc=pthread_join(t,v);if(!rc)++fios_actual_joins;return rc==0&&fios_join_failure?EIO:rc;}
static pthread_once_t iq2xxs_signed_grid_once=PTHREAD_ONCE_INIT;
static void iq2xxs_signed_grid_init(void){} // unrelated model lookup initialization
static void ds4_die(const char *message){fputs(message,stderr);abort();}
`;
console.log('CPU fixture state:',directory);
for(const optimization of ['-O0','-O3']){
 const unit=path.join(directory,'cpu.c'),binary=path.join(directory,'cpu'+optimization);
 writeFileSync(unit,prelude+fragment+fixture);
 execFileSync('/usr/bin/clang',['-std=gnu11',optimization,'-UNDEBUG','-pthread',unit,'-o',binary],{env,timeout:30000});
 const results=['--join-error','--busy-inline','--busy-parallel',null].map(mode=>{
  const r=spawnSync(binary,mode?[mode]:[],{env,encoding:'utf8',timeout:10000});
  writeFileSync(path.join(directory,optimization+(mode??'ordinary')+'-stderr.log'),r.stderr??'');return r;
 });
 for(const r of results){assert(!r.error&&!r.signal,'CPU fixture crash/deadline is not acceptance');assert.equal(r.status,0,r.stderr);console.log(r.stdout.trim());}
}
assert.equal(readFileSync(path.join(source,'ds4.c'),'utf8'),original);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);assert.equal(readFileSync(patchFile,'utf8'),patch);assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
console.log(JSON.stringify({directory,source_sha256:createHash('sha256').update(original).digest('hex'),fixture_sha256:createHash('sha256').update(fixture).digest('hex'),actual_cpu_pool_fragment:true,native_authority:false,all_writer_terminality:false}));
