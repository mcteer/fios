#!/usr/bin/env node
// Genuine CPU pread/pthread source fragment, not a Metal/device/model receipt.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,rmSync,realpathSync,lstatSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===3&&args[0]==='--isolated'&&args[1]==='--source');
const source=realpathSync(args[2]),info=lstatSync(source);
assert(source.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);
const gitEnv={PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const git=(...argv)=>execFileSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],{env:gitEnv,encoding:'utf8',timeout:5000});
assert.equal(git('rev-parse','HEAD').trim(),'9139e2ae58a41503968a500f36f75895c1ba63fc');
assert.equal(git('diff','--name-only').trim(),'ds4_metal.m');
const patch=readFileSync(path.join(root,'platform/studio/native/ds4-9139e2a-pread-retirement.patch'),'utf8');
assert.equal(git('diff','--no-ext-diff','--','ds4_metal.m'),patch);
const original=readFileSync(path.join(source,'ds4_metal.m'),'utf8'),fixture=readFileSync(path.join(root,'platform/studio/Tests/NativeFixtures/DS4PreadPool.c.fixture'),'utf8');
const sha=v=>createHash('sha256').update(v).digest('hex');
function fn(name){const match=new RegExp('^static (?:int|double|uint32_t) '+name+'\\([^;{}]*\\)\\s*\\{[\\s\\S]*?^\\}','m').exec(original);assert(match,name);return match[0];}
const type=/typedef struct \{\s*uint64_t offset;[^{}]*\} ds4_gpu_stream_expert_pread_task;/.exec(original);assert(type);
const start=original.indexOf('static pthread_mutex_t g_stream_expert_pread_pool_mutex'),end=original.indexOf('static int ds4_gpu_stream_expert_pread_tasks(',start);
assert(start>0&&end>start);
let pool=original.slice(start,end);
assert(pool.includes('static void ds4_gpu_stream_expert_pread_pool_shutdown(void) {\n    // Legacy cleanup cannot refund a sealed checked retirement/refusal.\n    if (atomic_load_explicit(&g_fios_pread_pool_sealed, memory_order_acquire)) return;'),'Legacy cleanup must preserve sealed uncertainty before joins/record changes');
const checkpoint='            task->ok = ds4_gpu_stream_expert_pread_into(';
assert.equal(pool.split(checkpoint).length,2);
// Explicit private scheduling checkpoint; original pread/worker ABI is intact.
pool=pool.replace(checkpoint,'            fixture_checkpoint();\n'+checkpoint);
const fragment=[type[0],...['ds4_gpu_now_ms','ds4_gpu_mib','ds4_gpu_gib','ds4_gpu_stream_expert_pread_thread_limit','ds4_gpu_stream_expert_pread_into'].map(fn),pool].join('\n');
assert.equal(fixture.split('// FIOS_GENUINE_PREAD_SOURCE').length,2);
const unit=fixture.replace('// FIOS_GENUINE_PREAD_SOURCE',fragment);
const temporary=mkdtempSync('/private/tmp/fios-ds4-pread-check-'),file=path.join(temporary,'fixture.c'),binary=path.join(temporary,'fixture');
const env={PATH:'/usr/bin:/bin',HOME:temporary,LANG:'C',LC_ALL:'C'};
let passed=false;
try {
 for(const optimize of ['-O0','-O2']){
  const compile=text=>{writeFileSync(file,text);execFileSync('/usr/bin/clang',['-std=c11','-D_DARWIN_C_SOURCE',optimize,'-UNDEBUG','-pthread',file,'-o',binary],{env,timeout:30000,stdio:'pipe'});};
  const execute=(mode,status=0,marker)=>{const result=spawnSync(binary,[mode],{env,encoding:'utf8',timeout:5000,maxBuffer:4096});assert(!result.error&&!result.signal);assert.equal(result.status,status,result.stderr);if(marker)assert(result.stderr.includes(marker));};
  compile(unit);execute('--positive');execute('--join-error');execute('--exhausted');
  const refusal='else { g_fios_pread_pool_uncertain = 1; ok = 0; }';assert.equal(unit.split(refusal).length,2);
  compile(unit.replace(refusal,'else { g_fios_pread_pool_joined |= (1u << i); }'));
  execute('--join-error',77,'FIO_DS4_PREAD_JOIN_REFUSAL_CLEARED');
  const gate='    if (atomic_load_explicit(&g_fios_pread_pool_sealed, memory_order_acquire)) return 0;';assert.equal(unit.split(gate).length,2);
  compile(unit.replace(gate,''));execute('--positive',77,'FIO_DS4_PREAD_REARMED_SEALED_POOL');
  const exhausted='    if (g_stream_expert_pread_pool_generation == UINT64_MAX) {\n        g_fios_pread_pool_uncertain = 1;\n        atomic_store_explicit(&g_fios_pread_pool_sealed, 1, memory_order_release);\n        pthread_mutex_unlock(&g_stream_expert_pread_pool_mutex);\n        return 0;\n    }';assert.equal(unit.split(exhausted).length,2);
  compile(unit.replace(exhausted,''));execute('--exhausted',77,'FIO_DS4_PREAD_GENERATION_WRAPPED');
  compile(unit);execute('--positive');execute('--join-error');execute('--exhausted');
 }
 assert.equal(readFileSync(path.join(source,'ds4_metal.m'),'utf8'),original);
 console.log(JSON.stringify({source_fragment_only:true,backend:'none',model:null,native_inference:false,native_authority:false,patch_sha256:sha(patch),source_sha256:sha(original),fixture_sha256:sha(fixture)}));
 console.log('PASS: Debug/optimized actual pread/pthread fragment, busy/exhaustion refusal, exact joins, genuine self-join refusal and three precise omission witnesses. Legacy cleanup/all-writer/device integration remains open.');
 passed=true;
} finally {if(passed)rmSync(temporary,{recursive:true,force:true});else console.error('Failure state retained:',temporary);}
