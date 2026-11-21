#!/usr/bin/env node
// Disposable unprivileged helper observation only: no app operations, login,
// launchd, runtime or model access. Never installs the GUI helper.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {chmodSync,existsSync,linkSync,mkdirSync,mkdtempSync,readFileSync,rmSync,symlinkSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(process.argv.length===3&&process.argv[2]==='--isolated');
const build=spawnSync('swift',['build','--package-path','platform/studio'],{encoding:'utf8',timeout:120000});assert.equal(build.status,0);
const shown=spawnSync('swift',['build','--package-path','platform/studio','--show-bin-path'],{encoding:'utf8',timeout:30000});assert.equal(shown.status,0);
const binary=join(shown.stdout.trim(),'studio-session'),root=mkdtempSync('/tmp/fios009-session-'),state=join(root,'state'),children=[];
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,limit=10000){const end=performance.now()+limit;while(performance.now()<end){const result=check();if(result)return result;await delay(50);}throw Error('Finite session fixture deadline');}
function start(directory,once=false){const child=spawn(binary,['--state',directory,...(once?['--once']:[])],{stdio:'ignore'});children.push(child);return child;}
try {
 const first=start(state);
 await until(()=>{try{return JSON.parse(readFileSync(join(state,'session.json'))).pid===first.pid;}catch{return false;}});
 const metadata=JSON.parse(readFileSync(join(state,'session.json')));assert.equal(metadata.lifecycle_enabled,false);assert.equal(metadata.uid,process.getuid());
 const duplicate=start(state,true);await until(()=>exited(duplicate));
 assert.equal(duplicate.exitCode,1,'Duplicate session helper was allowed to overwrite the live helper record');
 assert.equal(JSON.parse(readFileSync(join(state,'session.json'))).pid,first.pid);
 first.kill('SIGTERM');await until(()=>exited(first),5000);
 const replacement=start(state,true);await until(()=>exited(replacement));assert.equal(replacement.exitCode,0);
 assert.equal(JSON.parse(readFileSync(join(state,'session.json'))).pid,replacement.pid);
 for(const kind of ['symlink','hardlink','writable']) {
  const directory=join(root,kind);mkdirSync(directory,{mode:0o700});const target=join(directory,'sentinel');writeFileSync(target,'unchanged-session-lock-sentinel',{mode:0o600});
  const lock=join(directory,'session.lock');
  if(kind==='symlink')symlinkSync(target,lock);else if(kind==='hardlink')linkSync(target,lock);else{writeFileSync(lock,'',{mode:0o600});chmodSync(lock,0o666);}
  const refused=start(directory,true);await until(()=>exited(refused));assert.equal(refused.exitCode,1,'Unsafe session lock adopted');
  assert.equal(readFileSync(target,'utf8'),'unchanged-session-lock-sentinel');assert.equal(existsSync(join(directory,'session.json')),false);
 }
 console.log('PASS: real disposable GUI helper singleton/release, linked/writable-lock refusal and observation-only metadata; no login/native actions.');
}finally {
 for(const child of children)if(!exited(child))child.kill('SIGTERM');
 await until(()=>children.every(exited),10000);
 rmSync(root,{recursive:true,force:true});
}
