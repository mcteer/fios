#!/usr/bin/env node
// Disposable boot-prerequisite simulation, NOT FileVault/reboot/login or
// launchd/native service acceptance. Never changes real volume/session policy.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {chmodSync,existsSync,mkdirSync,mkdtempSync,rmSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(process.argv.length===3&&process.argv[2]==='--isolated','Usage: check-platform-boot.mjs --isolated');
const root=fileURLToPath(new URL('../',import.meta.url));
const build=spawnSync('swift',['build','--package-path','platform/studio'],{cwd:root,encoding:'utf8',timeout:120000});
assert.equal(build.status,0,'Source package build failed');
const shown=spawnSync('swift',['build','--package-path','platform/studio','--show-bin-path'],{cwd:root,encoding:'utf8',timeout:30000});
assert.equal(shown.status,0);const bin=shown.stdout.trim();
const temporary=mkdtempSync('/tmp/fios009-boot-'),volume=path.join(temporary,'unavailable-volume'),state=path.join(volume,'state');
mkdirSync(volume,{mode:0o700});const children=[];
function start() {const child=spawn(path.join(bin,'studio-supervisor'),['--state',state],{stdio:'ignore'});children.push(child);return child;}
function status() {
 const child=spawnSync(path.join(bin,'studioctl'),['--state',state,'status'],{encoding:'utf8',timeout:2500});
 if(child.status!==0)return null;
 try{return JSON.parse(child.stdout);}catch{return null;}
}
async function until(check,limit=30000) {
 const end=performance.now()+limit;
 while(performance.now()<end) {const value=check();if(value)return value;await delay(50);}
 throw Error('Isolated boot fixture deadline');
}
try {
 // Permissions model an unavailable backing path, not actual encryption.
 chmodSync(volume,0);
 const denied=start();await until(()=>denied.exitCode!==null,5000);
 assert.notEqual(denied.exitCode,0);assert.equal(existsSync(state),false,'Unavailable storage must not claim a ready manager');
 chmodSync(volume,0o700);
 assert.equal(existsSync(state),false,'Unavailable storage did not leave hidden state to adopt');
 const began=performance.now(),supervisor=start();
 const first=await until(()=>{const value=status();return value?.state==='ready'?value:null;},60000);
 assert(performance.now()-began<60000);
 assert.equal(first.session?.state,'waiting_session','Storage access must not fabricate a GUI helper/session');
 assert.equal(existsSync(path.join(state,'session.json')),false);
 assert.equal(first.services?.mlx?.observed,'unknown');assert.equal(first.services?.orbstack?.observed,'unknown');
 const duplicate=start();await until(()=>duplicate.exitCode!==null,5000);assert.notEqual(duplicate.exitCode,0);
 assert.equal(status()?.epoch,first.epoch,'A duplicate supervisor must not replace the serialized manager');
 for(const [service,value]of [['mlx','maintenance'],['orbstack','stopped']]) {
  const command=spawnSync(path.join(bin,'studioctl'),['--state',state,'service',service,value],{encoding:'utf8',timeout:3000});
  assert.equal(command.status,0,'Fixed operator desired-state CLI missing');
  const result=JSON.parse(command.stdout);assert.equal(result.ok,true);assert.equal(result.applied,false);
 }
 for(const args of [['service','foreign','running'],['service','mlx','shell'],['service','mlx','force','confirm','not-a-token','not-a-digest']]) {
  const command=spawnSync(path.join(bin,'studioctl'),['--state',state,...args],{encoding:'utf8',timeout:3000});
  assert.equal(command.status,2,'Malformed lifecycle command must fail locally');assert.equal(command.stdout,'');
 }
 for(const args of [['service','mlx','drain'],['service','orbstack','force','prepare']]) {
  const command=spawnSync(path.join(bin,'studioctl'),['--state',state,...args],{encoding:'utf8',timeout:3000});
  assert.equal(command.status,1,'Unenrolled lifecycle authority must remain closed');
  const result=JSON.parse(command.stdout);assert.equal(result.error,'native_unsupported');
 }
 // Stop only our spawned supervisor handle. Its own verified-child teardown
 // reaps the manager; never signal an inferred/foreign manager PID directly.
 supervisor.kill('SIGTERM');await until(()=>supervisor.exitCode!==null,10000);
 const restarted=start();
 const second=await until(()=>{const value=status();return value?.epoch&&value.epoch!==first.epoch?value:null;},30000);
 assert.equal(second.session?.state,'waiting_session');
 assert.equal(second.services?.mlx?.desired,'maintenance');assert.equal(second.services?.orbstack?.desired,'stopped');
 assert.equal(second.services?.mlx?.observed,'unknown');
 restarted.kill('SIGTERM');await until(()=>restarted.exitCode!==null,10000);
 console.log('PASS: simulated unavailable storage vs missing GUI helper, unlocked-source visibility<60s, singleton, new restart epoch and preserved unapplied desired state. NOT physical FileVault/login/reboot/native acceptance.');
}finally {
 chmodSync(volume,0o700);
 for(const child of children)if(child.exitCode===null)child.kill('SIGTERM');
 const exited=child=>child.exitCode!==null||child.signalCode!==null;
 await Promise.race([Promise.all(children.map(child=>exited(child)?Promise.resolve():new Promise(resolve=>child.once('exit',resolve)))),delay(10000)]);
 assert(children.every(exited),'Cleanup incomplete: retaining disposable state rather than deleting possible live-writer data');
 if(existsSync(state)) {
  // The existing offline path acquires BOTH writer locks before SQLite open.
  // If shutdown/reaping failed, leave state intact instead of deleting a DB.
  const proof=spawnSync(path.join(bin,'studioctl'),['--state',state,'backup','--to',path.join(temporary,'cleanup-proof.sqlite')],{encoding:'utf8',timeout:5000});
  assert.equal(proof.status,0,'Cleanup writer-lock proof failed; disposable state retained');
 }
 rmSync(temporary,{recursive:true,force:true});
}
