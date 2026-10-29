#!/usr/bin/env node
// Finite libc-only native startup ownership fixture; no serving app/model/VM.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,existsSync,readFileSync,lstatSync,writeFileSync,linkSync,unlinkSync,symlinkSync,chmodSync,rmSync} from 'node:fs';
import {join,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
const args=process.argv.slice(2);assert.deepEqual([args[0],args[1]],['--isolated','--zig']);assert([3,4].includes(args.length));if(args.length===4)assert.equal(args[3],'--mutate-lock');assert(isAbsolute(args[2]));
assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=fileURLToPath(new URL('../',import.meta.url)),scratch=mkdtempSync('/tmp/fios009-native-startup-'),children=[];
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=5000){const end=performance.now()+timeout;while(performance.now()<end){if(check())return;await delay(20);}throw Error('Finite startup fixture deadline');}
try {
 copyFileSync(join(root,'platform/studio/native/startup_guard_fixture.zig'),join(scratch,'main.zig'));
 const guardSource=readFileSync(join(root,'platform/studio/native/startup_guard.zig'),'utf8');
 writeFileSync(join(scratch,'startup_guard.zig'),args[3]==='--mutate-lock'?guardSource.replace('c.flock(fd, c.LOCK.EX | c.LOCK.NB) != 0','false'):guardSource);
 for(const optimize of ['Debug','ReleaseSafe']) {
  const binary=join(scratch,'startup-'+optimize),home=join(scratch,optimize);mkdirSync(home,{mode:0o700});
  const build=spawnSync(args[2],['build-exe',join(scratch,'main.zig'),'-lc','-O',optimize,'-femit-bin='+binary],{encoding:'utf8',timeout:120000,maxBuffer:65536});assert.equal(build.status,0,build.stderr);
  const env={PATH:'/usr/bin:/bin',HOME:home,LANG:'C',LC_ALL:'C'},enabled={...env,FIOS_NATIVE_STARTUP:'isolated-source-fixture'};
  const disabled=spawnSync(binary,[],{env,encoding:'utf8',timeout:3000});assert.equal(disabled.status,0);assert.equal(disabled.stdout,'DISABLED\n');assert.equal(existsSync(join(home,'.fios-native-startup')),false);
  const invalid=spawnSync(binary,[],{env:{...env,FIOS_NATIVE_STARTUP:'true'},stdio:'ignore',timeout:3000});assert.notEqual(invalid.status,0);
  async function start(){const child=spawn('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env:enabled,stdio:['pipe','pipe','ignore']});children.push(child);let output='';child.stdout.on('data',x=>output+=x);await until(()=>output==='READY\n');return child;}
  const directory=join(home,'.fios-native-startup'),lock=join(directory,'server.lock');
  function refused(){const result=spawnSync(binary,[],{env:enabled,stdio:'ignore',timeout:1000});assert.equal(result.signal,null,'refusal must finish, not time out');assert.notEqual(result.status,0);}
  let owner=await start();const inode=lstatSync(lock).ino;
  const blocked=spawnSync(binary,[],{env:enabled,stdio:'ignore',timeout:1000});assert.notEqual(blocked.status,0);assert.equal(blocked.signal,null);assert.equal(exited(owner),false);assert.equal(lstatSync(lock).ino,inode);
  owner.stdin.end();await until(()=>exited(owner));assert.equal(owner.exitCode,0);
  owner=await start();owner.kill('SIGKILL');await until(()=>exited(owner));
  owner=await start();owner.stdin.end();await until(()=>exited(owner));
  chmodSync(directory,0o755);refused();chmodSync(directory,0o700);
  const alias=join(directory,'alias');linkSync(lock,alias);
  refused();unlinkSync(alias);
  chmodSync(lock,0o666);refused();chmodSync(lock,0o600);
  const acl=spawnSync('/bin/chmod',['+a','everyone allow write',lock],{encoding:'utf8',timeout:3000});assert.equal(acl.status,0,acl.stderr);
  refused();assert.equal(spawnSync('/bin/chmod',['-N',lock]).status,0);
  unlinkSync(lock);const sentinel=join(directory,'sentinel');writeFileSync(sentinel,'preserve-owned-sentinel',{mode:0o600});symlinkSync(sentinel,lock);
  refused();assert.equal(readFileSync(sentinel,'utf8'),'preserve-owned-sentinel');
 }
 console.log('PASS: actual cross-process native startup lock, immediate duplicate refusal, orderly/SIGKILL owner recovery and linked/writable/ACL/symlink refusal in Debug/ReleaseSafe; libc-only, no native terminality or serving/model activation.');
}finally {
 for(const child of children)if(!exited(child))child.kill('SIGTERM');
 await until(()=>children.every(exited),10000);
 rmSync(scratch,{recursive:true,force:true});
}
