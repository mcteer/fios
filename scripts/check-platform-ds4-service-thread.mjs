#!/usr/bin/env node
// Genuine CPU/pthread fragment from the Metal source; no SDK/model substitution.
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
const directory=mkdtempSync('/private/tmp/fios-ds4-service-thread-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const git=(...argv)=>execFileSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],{env,encoding:'utf8',timeout:5000});
const files=['ds4.c','ds4.h','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m','ds4_tp.c'];
const patchFile=path.join(root,'platform/studio/native/ds4-9139e2a-participant-retirement.patch'),patch=readFileSync(patchFile,'utf8');
assert.equal(git('rev-parse','HEAD').trim(),'9139e2ae58a41503968a500f36f75895c1ba63fc');
assert.equal(git('diff','HEAD','--name-only').trim(),files.join('\n'));assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
const original=readFileSync(path.join(source,'ds4_metal.m'),'utf8');
const start=original.indexOf('static pthread_t g_stream_expert_service_thread;')>=0?original.indexOf('static pthread_t g_stream_expert_service_thread;'):original.indexOf('static _Thread_local int g_stream_expert_service_thread_set;');
const end=original.indexOf('static NSUInteger g_flash_attn_mask_bytes;',start);assert(start>0&&end>start);
const fragment=original.slice(start,end),fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4ServiceThread.c.fixture'),fixture=readFileSync(fixtureFile,'utf8');
assert.equal(fixture.split('// FIOS_GENUINE_SERVICE_THREAD_SOURCE').length,2);
console.log('Service-thread fixture state:',directory);
for(const optimization of ['-O0','-O3']){
 const unit=path.join(directory,'service.c'),binary=path.join(directory,'service'+optimization);
 writeFileSync(unit,fixture.replace('// FIOS_GENUINE_SERVICE_THREAD_SOURCE',fragment));
 execFileSync('/usr/bin/clang',['-std=c11',optimization,'-UNDEBUG','-pthread',unit,'-o',binary],{env,timeout:30000});
 const result=spawnSync(binary,[],{env,encoding:'utf8',timeout:10000,maxBuffer:4096});
 writeFileSync(path.join(directory,optimization+'-stderr.log'),result.stderr??'');
 assert(!result.error&&!result.signal,'Crash/deadline or unobserved reuse is not acceptance');assert.equal(result.status,0,result.stderr);console.log(result.stdout.trim());
}
assert.equal(readFileSync(path.join(source,'ds4_metal.m'),'utf8'),original);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
const sha=value=>createHash('sha256').update(value).digest('hex');
console.log(JSON.stringify({directory,source_sha256:sha(original),fixture_sha256:sha(fixture),pthread_handle_representation_reuse_observed:true,source_fragment_only:true,gpu_completion:false,native_inference:false,native_authority:false}));
