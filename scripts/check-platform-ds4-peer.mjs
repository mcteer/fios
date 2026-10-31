#!/usr/bin/env node
// Source control flow only; mock peer/session layouts, no native/network action.
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
const directory=mkdtempSync('/private/tmp/fios-ds4-peer-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const git=(...argv)=>execFileSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],{env,encoding:'utf8',timeout:5000});
const files=['ds4.c','ds4.h','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m','ds4_tp.c'];
const patchFile=path.join(root,'platform/studio/native/ds4-9139e2a-participant-retirement.patch'),patch=readFileSync(patchFile,'utf8');
assert.equal(git('rev-parse','HEAD').trim(),'9139e2ae58a41503968a500f36f75895c1ba63fc');assert.equal(git('diff','HEAD','--name-only').trim(),files.join('\n'));assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
const original=readFileSync(path.join(source,'ds4_tp.c'),'utf8');
const index=/^static int tp_worker_session_index\([\s\S]*?^\}/m.exec(original),remove=/^static (?:void|int) tp_worker_session_remove\([\s\S]*?^\}/m.exec(original);assert(index&&remove);
const a=original.indexOf('        if (command.type == DS4_TP_FRAME_SESSION_DESTROY) {'),b=original.indexOf('\n\n        ds4_session *session =',a);assert(a>0&&b>a);
const tpFree=/^void ds4_tp_free\(ds4_tp \*tp\) \{[\s\S]*?^\}/m.exec(original);assert(tpFree);
const finish=/^static int tp_worker_finish\([\s\S]*?^\}/m.exec(original);
const tailStart=original.indexOf('    ds4_tokens_free(&prompt);',original.indexOf('int ds4_tp_worker_run(')),tailEnd=original.indexOf('\n}',tailStart);assert(finish||tailStart>0&&tailEnd>tailStart);
const finishSource=finish?finish[0]:'static int tp_worker_finish(ds4_engine *engine,ds4_tp *tp,ds4_tp_worker_custody *custody,int rc){\n ds4_tp_worker_sessions sessions=custody->sessions;ds4_tokens prompt=custody->prompt;float *logits=custody->logits;\n'+original.slice(tailStart,tailEnd)+'\n}';
const fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4Peer.c.fixture'),fixture=readFileSync(fixtureFile,'utf8');
console.log('Peer fixture state:',directory);
for(const optimization of ['-O0','-O3']){
 const unit=path.join(directory,'peer.c'),binary=path.join(directory,'peer'+optimization);
 const macro=remove[0].startsWith('static int')?'#define FIOS_REMOVE(s,i) tp_worker_session_remove(s,i)\n':'#define FIOS_REMOVE(s,i) (tp_worker_session_remove(s,i),1)\n';
 writeFileSync(unit,macro+fixture.replace('/* SOURCE_FUNCTIONS */',index[0]+'\n'+remove[0]+'\n'+tpFree[0]).replace('/* SOURCE_FINISH */',finishSource).replace('/* SOURCE_ACK */',original.slice(a,b).replaceAll('tp_worker_session_index(sessions,','tp_worker_session_index(&sessions,').replaceAll('tp_worker_session_remove(sessions,','tp_worker_session_remove(&sessions,')));
 execFileSync('/usr/bin/clang',['-std=c11',optimization,'-UNDEBUG',unit,'-o',binary],{env,timeout:30000});
 const results=['--remove-refusal','--ack-refusal','--remove-success','--ack-success','--finish-refusal','--finish-unbind-refusal','--finish-success','--tp-free-held'].map(mode=>{
  const r=spawnSync(binary,[mode],{env,encoding:'utf8',timeout:5000});writeFileSync(path.join(directory,optimization+mode+'-stderr.log'),r.stderr??'');return r;
 });
 for(const r of results){assert(!r.error&&!r.signal,'Peer fixture crash/deadline is not acceptance');assert.equal(r.status,0,r.stderr);}
}
assert.equal(readFileSync(path.join(source,'ds4_tp.c'),'utf8'),original);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);assert.equal(readFileSync(patchFile,'utf8'),patch);assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
console.log(JSON.stringify({directory,source_sha256:createHash('sha256').update(original).digest('hex'),fixture_sha256:createHash('sha256').update(fixture).digest('hex'),source_control_flow_only:true,native_abi:false,native_authority:false}));
