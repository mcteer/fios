#!/usr/bin/env node
// No model, installed app, real daemon or public/LAN endpoint is selected.
import assert from 'node:assert/strict';
import {spawnSync,execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,symlinkSync,rmSync} from 'node:fs';
import path from 'node:path';
import {createServer} from 'node:net';
import {fileURLToPath} from 'node:url';
assert(process.platform==='darwin'&&process.getuid()>0&&process.argv.slice(2).join(' ')==='--isolated');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),scratch=mkdtempSync('/private/tmp/f9-review-kernel-'),env={PATH:'/usr/bin:/bin',HOME:scratch,LANG:'C',LC_ALL:'C'};
const original=readFileSync(path.join(root,'tests/fixtures/platform/native-model-review.sb'),'utf8');
let server;
try {
 const binary=path.join(scratch,'probe'),witness=path.join(scratch,'witness');
 execFileSync('/usr/bin/clang',['-x','c',path.join(root,'platform/studio/Tests/NativeFixtures/ReviewKernel.c.fixture'),'-O2','-o',binary],{env,timeout:30000});
 const unit=path.join(scratch,'witness.c');writeFileSync(unit,'#include <stdio.h>\nint main(void){puts("FIO_REVIEW_EXEC_ESCAPE");return 44;}\n');execFileSync('/usr/bin/clang',[unit,'-O2','-o',witness],{env,timeout:30000});
 const socket=path.join(scratch,'unrelated.sock');let connections=0;server=createServer(s=>{connections++;s.end();});await new Promise((ok,no)=>{server.once('error',no);server.listen(socket,ok);});
 for(const variant of ['positive','write','network','fork','exec']) {
  const directory=path.join(scratch,variant),home=path.join(directory,'home');mkdirSync(directory,{mode:0o700});mkdirSync(home,{mode:0o700});
  const protectedFile=path.join(directory,'protected'),alias=path.join(home,'alias');writeFileSync(protectedFile,'unchanged',{mode:0o600});symlinkSync(protectedFile,alias);
  const omission={write:'(deny file-write*)',network:'(deny network*)',fork:'(deny process-fork)',exec:'(deny process-exec)'}[variant];
  if(omission)assert.equal(original.split(omission).length,2);const profile=path.join(directory,'profile.sb');writeFileSync(profile,omission?original.replace(omission,'; private exact omission'):original);
  const result=spawnSync('/usr/bin/sandbox-exec',['-D','FIOS_REVIEW_ENDPOINT=localhost:54321','-D','FIOS_REVIEW_STATE='+home,'-D','FIOS_REVIEW_BINARY='+binary,'-f',profile,binary,alias,path.join(home,'allowed'),socket,witness],{env,encoding:'utf8',timeout:5000,maxBuffer:4096});
  assert(!result.error&&!result.signal,'Kernel witness did not exit normally');
  const expected={positive:[0,'FIO_REVIEW_KERNEL_PASS'],write:[41,'FIO_REVIEW_SHARED_WRITE'],network:[42,'FIO_REVIEW_SOCKET_ESCAPE'],fork:[43,'FIO_REVIEW_FORK_ESCAPE'],exec:[44,'FIO_REVIEW_EXEC_ESCAPE']}[variant];
  assert.equal(result.status,expected[0],result.stderr);assert(result.stdout.includes(expected[1]));
  if(variant!=='write')assert.equal(readFileSync(protectedFile,'utf8'),'unchanged');
  await new Promise(ok=>setImmediate(ok));
  console.log('PASS: '+variant+' exact file/Unix/fork/exec kernel witness; owned synthetic resources only.');
 }
 await new Promise(ok=>server.close(ok));server=null;
 assert.equal(connections,1,'Only the private network omission may reach the unrelated sentinel');
 console.log('PASS: model-review kernel restrictions and four precise runtime omissions; zero inference/real daemon contact.');
} finally {if(server)await new Promise(ok=>server.close(ok));rmSync(scratch,{recursive:true,force:true});}
