#!/usr/bin/env node
// Real disposable manager with synthetic prerequisite observations only.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,copyFileSync,readdirSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {fileURLToPath} from 'node:url';
assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
assert.deepEqual(process.argv.slice(2),['--isolated']);
const root=fileURLToPath(new URL('../',import.meta.url));
const temporary=mkdtempSync('/tmp/fios009-boot-state-'),children=[];
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,limit=5000){const end=performance.now()+limit;while(performance.now()<end){const value=check();if(value)return value;await delay(25);}throw Error('Finite boot-state fixture deadline');}
function run(program,args,timeout=5000){const result=spawnSync(program,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:65536});assert.equal(result.status,0,'Boot fixture command failed');return result.stdout.trim();}
try {
 const core=join(root,'platform/studio/Sources/StudioCore');
 const sources=readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name));
 const fixture=join(temporary,'BootState.swift'),binary=join(temporary,'boot-state');
 copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/BootState.swift.fixture'),fixture);
 run('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,fixture,'-o',binary],120000);
 const bin=run('swift',['build','--package-path','platform/studio','--show-bin-path']);
 const cli=join(bin,'studioctl');
 for(const [scenario,expected] of [['session','waiting_session'],['credentials','waiting_credentials'],['absent','stopped'],['unknown','unknown']]) {
  const state=join(temporary,scenario);
  const child=spawn('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))',binary,state,scenario],{stdio:'ignore'});children.push(child);
  const status=await until(()=>{
   const result=spawnSync(cli,['--state',state,'status'],{encoding:'utf8',timeout:1000,maxBuffer:65536});
   if(result.status!==0)return null;return JSON.parse(result.stdout);
  });
  assert.equal(status.state,'ready');assert.equal(status.session.state,'waiting_session');
  for(const service of ['mlx','orbstack'])assert.equal(status.services[service].observed,expected);
  assert.equal(status.native_activity,'unsupported');assert.equal(status.unresolved_requests,0);
  assert.equal(status.sandbox_admission,'disabled');
  child.kill('SIGTERM');await until(()=>exited(child));
  // Both writer locks must be available before this private state is deleted.
  run(cli,['--state',state,'backup','--to',join(temporary,scenario+'-stopped.sqlite')]);
 }
 console.log('PASS: real network-denied manager reports waiting_session/waiting_credentials/proven-absent/unknown from synthetic trusted observations; no native service/keychain/inference actions.');
}finally {
 for(const child of children)if(!exited(child))child.kill('SIGTERM');
 await until(()=>children.every(exited),10000);
 rmSync(temporary,{recursive:true,force:true});
}
