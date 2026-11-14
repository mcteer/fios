#!/usr/bin/env node
// CPU-only source-control-flow fixture with explicitly mocked session layout.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync,lstatSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
const mutation=['--mutation-tp-busy-guard','--mutation-cpu-busy-guard'].includes(args.at(-1))?args.pop():null;const mutationMode=mutation==='--mutation-cpu-busy-guard'?'--cpu-busy':'--tp-busy';
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===3&&args[0]==='--isolated'&&args[1]==='--source');
const source=realpathSync(args[2]),info=lstatSync(source);
assert(source.startsWith('/private/tmp/')&&info.uid===process.getuid()&&info.isDirectory()&&(info.mode&0o022)===0);
const directory=mkdtempSync('/private/tmp/fios-ds4-session-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const git=(...argv)=>execFileSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],{env,encoding:'utf8',timeout:5000});
const files=['ds4.c','ds4.h','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m','ds4_tp.c'];
const patchFile=path.join(root,'platform/studio/native/ds4-9139e2a-participant-retirement.patch'),patch=readFileSync(patchFile,'utf8');
assert.equal(git('rev-parse','HEAD').trim(),'9139e2ae58a41503968a500f36f75895c1ba63fc');assert.equal(git('diff','HEAD','--name-only').trim(),files.join('\n'));assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
const original=readFileSync(path.join(source,'ds4.c'),'utf8');
let functions=[...original.matchAll(/^(?:void ds4_session_free|int ds4_session_free_checked)\(ds4_session \*s\) \{[\s\S]*?^\}/gm)].map(m=>m[0]).join('\n');assert(functions);
if(mutation){const pin=mutation==='--mutation-cpu-busy-guard'?'    if (ds4_threads_work_busy()) return 0;':'    if (ds4_gpu_tp_local_work_busy()) return 0;';assert.equal(functions.split(pin).length,2);functions=functions.replace(pin,'');}
const fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4Session.c.fixture'),fixture=readFileSync(fixtureFile,'utf8');
console.log('Session fixture state:',directory);
for(const optimization of ['-O0','-O3']){
 const unit=path.join(directory,'session.c'),binary=path.join(directory,'session'+optimization);
 writeFileSync(unit,(functions.includes('int ds4_session_free_checked(')?'#define FIOS_HAS_CHECKED_SESSION 1\n':'')+fixture.replace('/* SOURCE_FUNCTIONS */',functions));
 execFileSync('/usr/bin/clang',['-std=c11',optimization,'-UNDEBUG',unit,'-o',binary],{env,timeout:30000});
 const results=['--send-failure','--ack-failure','--failed-transport','--success','--tp-busy','--selected-busy','--cpu-busy'].map(mode=>{
  const r=spawnSync(binary,[mode],{env,encoding:'utf8',timeout:5000});writeFileSync(path.join(directory,optimization+mode+'-stderr.log'),r.stderr??'');return {...r,mode};
 });
 for(const r of results){assert(!r.error&&!r.signal,'Session fixture crash/deadline is not acceptance');assert.equal(r.status,mutation&&r.mode===mutationMode?77:0,r.stderr);if(mutation&&r.mode===mutationMode)assert(r.stderr.includes('FIO_DS4_SESSION_BUSY_GUARD_MUTATED_OWNERSHIP'));}
}
assert.equal(readFileSync(path.join(source,'ds4.c'),'utf8'),original);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);assert.equal(readFileSync(patchFile,'utf8'),patch);assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
console.log(JSON.stringify({directory,source_sha256:createHash('sha256').update(original).digest('hex'),fixture_sha256:createHash('sha256').update(fixture).digest('hex'),source_control_flow_only:true,expected_runtime_mutation:!!mutation,native_abi:false,native_authority:false}));
