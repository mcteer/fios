#!/usr/bin/env node
// Disposable real supervisor/manager lock boundary. No native app operations.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {chmodSync,existsSync,linkSync,lstatSync,mkdirSync,mkdtempSync,readFileSync,rmSync,symlinkSync,writeFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(process.argv.length===3&&process.argv[2]==='--isolated','Usage: check-platform-supervisor-lock.mjs --isolated');
const root=fileURLToPath(new URL('../',import.meta.url));
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:process.env.HOME,LANG:'C',LC_ALL:'C'};
const build=spawnSync('/usr/bin/swift',['build','--package-path','platform/studio'],{cwd:root,env,encoding:'utf8',timeout:120000});
assert.equal(build.status,0,'Native source build failed');
const shown=spawnSync('/usr/bin/swift',['build','--package-path','platform/studio','--show-bin-path'],{cwd:root,env,encoding:'utf8',timeout:30000});
assert.equal(shown.status,0);const bin=shown.stdout.trim();
const temporary=mkdtempSync('/tmp/fios009-supervisor-lock-'),states=[],children=[],failures=[];
const sentinel=path.join(temporary,'sentinel');writeFileSync(sentinel,'unrelated fixture sentinel',{mode:0o600});
const before=readFileSync(sentinel),sentinelMode=lstatSync(sentinel).mode;
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function stop(child) {
 if(exited(child))return;
 child.kill('SIGTERM');const until=performance.now()+10000;
 while(!exited(child)&&performance.now()<until)await delay(25);
 assert(exited(child),'Owned supervisor teardown incomplete: retain disposable state');
}
let retain=false;
try {
 for(const mode of ['hardlink','writable','setid','symlink','fifo']) {
  const state=path.join(temporary,mode);mkdirSync(state,{mode:0o700});states.push(state);
  const lock=path.join(state,'supervisor.lock');
  if(mode==='hardlink')linkSync(sentinel,lock);
  else if(mode==='symlink')symlinkSync(sentinel,lock);
  else if(mode==='fifo') {const result=spawnSync('/usr/bin/mkfifo',['-m','600',lock],{env,stdio:'ignore',timeout:2000});assert.equal(result.status,0);}
  else {writeFileSync(lock,'metadata only',{mode:0o600});chmodSync(lock,mode==='setid'?0o4700:0o666);}
  if(mode==='setid')assert.equal(lstatSync(lock).mode&0o7777,0o4700,'Set-ID metadata was not prepared; never execute it');
  const child=spawn(path.join(bin,'studio-supervisor'),['--state',state],{env,stdio:'ignore'});children.push(child);
  const until=performance.now()+2000;
  while(!exited(child)&&performance.now()<until)await delay(25);
  if(!exited(child))failures.push('Supervisor accepted or blocked on '+mode+' lock');
  else if(child.exitCode===0)failures.push('Supervisor reported success for '+mode+' lock');
  await stop(child);
  if(existsSync(path.join(state,'state.sqlite'))) {retain=true;failures.push('Refused lock reached manager SQLite startup: '+mode);}
 }
 assert.deepEqual(readFileSync(sentinel),before);assert.equal(lstatSync(sentinel).mode,sentinelMode);
 assert.deepEqual(failures,[],'Supervisor lock trust boundary failed');
 console.log('PASS: actual supervisor rejects hardlinked/writable/set-ID/symlink/FIFO locks before manager startup; sentinel unchanged; no synthetic PID signals or native operations.');
}finally {
 for(const child of children)await stop(child);
 // A bad historical lock may have let an old manager start. Keep those DBs;
 // never delete possible writer data without the independent two-lock proof.
 if(states.some(state=>existsSync(path.join(state,'state.sqlite'))))retain=true;
 if(retain)console.log('RETAINED: disposable lock-test state (no workload content): '+temporary);
 else rmSync(temporary,{recursive:true,force:true});
}
