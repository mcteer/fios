#!/usr/bin/env node
// Disposable real supervisor/manager only; no native service or enrollment.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(process.argv.length===3&&process.argv[2]==='--isolated','Usage: check-platform-supervisor-publication.mjs --isolated');
const root=fileURLToPath(new URL('../',import.meta.url));
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:process.env.HOME,LANG:'C',LC_ALL:'C'};
function run(file,args,timeout=120000){return spawnSync(file,args,{cwd:root,env,encoding:'utf8',timeout,maxBuffer:1<<20});}
assert.equal(run('/usr/bin/swift',['build','--package-path','platform/studio']).status,0);
const shown=run('/usr/bin/swift',['build','--package-path','platform/studio','--show-bin-path']);assert.equal(shown.status,0);
const bin=shown.stdout.trim(),state=mkdtempSync('/tmp/fios009-supervisor-publication-');
const child=spawn(path.join(bin,'studio-supervisor'),['--state',state],{env,stdio:'ignore'});
let managerPID;
const exited=()=>child.exitCode!==null||child.signalCode!==null;
try {
 let ready=false;const startup=performance.now()+15000;
 while(!ready&&performance.now()<startup){
  try {const status=JSON.parse(readFileSync(path.join(state,'supervisor.json')));const progress=JSON.parse(readFileSync(path.join(state,'progress.json')));ready=status.state==='running'&&progress.pid>1;if(ready)managerPID=progress.pid;}catch{}
  if(!ready)await delay(25);
 }
 assert(ready,'Owned manager/supervisor did not become ready');
 const publications=new Set(),until=performance.now()+2250;let last;
 while(performance.now()<until){
  const value=JSON.parse(readFileSync(path.join(state,'supervisor.json')));
  assert.equal(value.pid,child.pid);assert.equal(value.state,'running');assert.equal(value.starts,1);
  assert(Number.isSafeInteger(value.sampled_uptime_ms));
  if(last!==undefined)assert(value.sampled_uptime_ms>=last,'Publication regressed');
  last=value.sampled_uptime_ms;publications.add(last);await delay(20);
 }
 assert(publications.size>=2,'Unchanged state still needs fresh independent status');
 assert(publications.size<=4,`Unchanged supervisor durably published ${publications.size} times in 2.25s; watchdog polling must not force four fsync publications/second`);
 const result=run(path.join(bin,'studioctl'),['--state',state,'supervisor'],3000);
 assert.equal(result.status,0,'Coalescing made independently read status stale');
 console.log(`PASS: real unchanged supervisor publishes ${publications.size} fresh bounded snapshots/2.25s, not four durable writes/second; child/watchdog loops remain independent; no native action.`);
}finally {
 if(!exited())child.kill('SIGTERM');
 const deadline=performance.now()+12000;
 while(!exited()&&performance.now()<deadline)await delay(25);
 if(!exited())child.kill('SIGKILL');
 const final=performance.now()+3000;
 while(!exited()&&performance.now()<final)await delay(25);
 let managerGone=true;if(managerPID){try{process.kill(managerPID,0);managerGone=false;}catch{}}
 if(exited()&&managerGone){
  // CLI backup independently acquires BOTH writer locks before any SQLite
  // open; never delete a failed test DB merely because our handles exited.
  const proof=run(path.join(bin,'studioctl'),['--state',state,'backup','--to',path.join(state,'stopped-proof.sqlite')],5000);
  if(proof.status===0)rmSync(state,{recursive:true,force:true});
  else console.log('RETAINED: disposable publication state; stopped writer proof unavailable: '+state);
 }else console.log('RETAINED: disposable publication state; owned teardown incomplete: '+state);
}
