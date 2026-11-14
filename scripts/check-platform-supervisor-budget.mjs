#!/usr/bin/env node
// Private restart-budget compatibility/metadata fixture; no native operations.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {chmodSync,existsSync,linkSync,lstatSync,mkdirSync,mkdtempSync,readFileSync,rmSync,symlinkSync,writeFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(process.argv.length===3&&process.argv[2]==='--isolated','Usage: check-platform-supervisor-budget.mjs --isolated');
const root=fileURLToPath(new URL('../',import.meta.url));
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:process.env.HOME,LANG:'C',LC_ALL:'C'};
const build=spawnSync('/usr/bin/swift',['build','--package-path','platform/studio'],{cwd:root,env,encoding:'utf8',timeout:120000});
assert.equal(build.status,0,'Native source build failed');
const shown=spawnSync('/usr/bin/swift',['build','--package-path','platform/studio','--show-bin-path'],{cwd:root,env,encoding:'utf8',timeout:30000});
assert.equal(shown.status,0);const bin=shown.stdout.trim();
const temporary=mkdtempSync('/tmp/fios009-supervisor-budget-'),states=[],children=[],failures=[];
const boot=randomUUID(),valid=JSON.stringify({boot,starts:[]});
const sentinel=path.join(temporary,'sentinel');writeFileSync(sentinel,valid,{mode:0o600});
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
 for(const mode of ['unknown-field','malformed-boot','negative-start','unordered-starts','duplicate-field','writable','hardlink','symlink','fifo','directory']) {
  const state=path.join(temporary,mode);mkdirSync(state,{mode:0o700});states.push(state);
  const file=path.join(state,'restart-budget.json');
  if(mode==='hardlink')linkSync(sentinel,file);
  else if(mode==='symlink')symlinkSync(sentinel,file);
  else if(mode==='directory')mkdirSync(file,{mode:0o700});
  else if(mode==='fifo') {const result=spawnSync('/usr/bin/mkfifo',['-m','600',file],{env,stdio:'ignore',timeout:2000});assert.equal(result.status,0);}
  else {
   let payload=valid;
   if(mode==='unknown-field')payload=JSON.stringify({boot,starts:[],future_no_restart:true});
   if(mode==='malformed-boot')payload=JSON.stringify({boot:'not-a-boot-uuid',starts:[]});
   if(mode==='negative-start')payload=JSON.stringify({boot,starts:[-1]});
   if(mode==='unordered-starts')payload=JSON.stringify({boot,starts:[2,1]});
   if(mode==='duplicate-field')payload=`{"boot":"${boot}","starts":[],"starts":[]}`;
   writeFileSync(file,payload,{mode:0o600});if(mode==='writable')chmodSync(file,0o666);
  }
  const originalMetadata=lstatSync(file),originalBytes=originalMetadata.isFile()?readFileSync(file):null;
  const child=spawn(path.join(bin,'studio-supervisor'),['--state',state],{env,stdio:'ignore'});children.push(child);
  const until=performance.now()+2000;
  while(!exited(child)&&performance.now()<until)await delay(25);
  if(!exited(child))failures.push('Supervisor accepted or blocked on '+mode+' restart budget');
  else if(child.exitCode===0)failures.push('Supervisor reported success for '+mode+' budget');
  await stop(child);
  const afterMetadata=lstatSync(file);
  if(afterMetadata.ino!==originalMetadata.ino||afterMetadata.mode!==originalMetadata.mode||afterMetadata.nlink!==originalMetadata.nlink||
     (originalBytes&&!readFileSync(file).equals(originalBytes)))failures.push('Refusal rewrote restart-budget data/identity: '+mode);
  if(existsSync(path.join(state,'state.sqlite'))) {retain=true;failures.push('Invalid restart budget reached manager startup: '+mode);}
 }
 assert.deepEqual(readFileSync(sentinel),before);assert.equal(lstatSync(sentinel).mode,sentinelMode);
 assert.deepEqual(failures,[],'Supervisor restart-budget trust boundary failed');
 console.log('PASS: real supervisor refuses unknown/duplicate/malformed budget data and linked/writable/FIFO/directory metadata before manager startup; other-boot invalid histories never reset the budget; sentinel unchanged.');
}finally {
 for(const child of children)await stop(child);
 if(states.some(state=>existsSync(path.join(state,'state.sqlite'))))retain=true;
 if(retain)console.log('RETAINED: disposable budget-test state (no workload content): '+temporary);
 else rmSync(temporary,{recursive:true,force:true});
}
