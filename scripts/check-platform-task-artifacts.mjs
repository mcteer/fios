#!/usr/bin/env node
// Normal real-manager/CLI artifact downloads, without inference or runtime actions.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,readdirSync,readFileSync,writeFileSync,copyFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios009-artifacts-');
const source=join(directory,'Main.swift'),binary=join(directory,'manager'),state=join(directory,'state'),profile=join(directory,'network.sb');
copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/TaskArtifactLive.swift.fixture'),source);
writeFileSync(profile,'(version 1)\n(allow default)\n(deny network*)\n(allow network* (local unix-socket) (remote unix-socket))\n',{mode:0o600});
function command(program,args,timeout=180000){
 const result=spawnSync(program,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:2<<20});
 assert.equal(result.status,0,'Normal artifact command failed: '+(result.stderr??''));return result.stdout;
}
const core=join(root,'platform/studio/Sources/StudioCore');
command('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>join(core,n)),source,'-o',binary]);
command('swift',['build','--package-path','platform/studio','--disable-automatic-resolution','--product','studioctl','-j','2']);
const cli=join(command('swift',['build','--package-path','platform/studio','--show-bin-path']).trim(),'studioctl');
const child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'ignore'});
const exited=()=>child.exitCode!==null||child.signalCode!==null;
const sha=data=>createHash('sha256').update(data).digest('hex');
try {
 const startup=performance.now()+8000;
 while(!existsSync(join(state,'task.sock'))){assert(!exited(),'Private artifact manager exited');assert(performance.now()<startup,'Private manager startup timeout');await delay(25);}
 const fixture=JSON.parse(readFileSync(join(state,'fixture.json'),'utf8'));
 function call(payload,operation='artifact.read',expectedExit=0,owner=fixture.owner){
  const id=randomUUID();
  const result=spawnSync(cli,['--state',state,'task'],{cwd:root,encoding:'utf8',timeout:3000,input:JSON.stringify({version:1,id,operation,payload:{...payload,owner}})});
  assert.equal(result.status,expectedExit,'Normal task CLI request returned an unexpected exit code');
  const response=JSON.parse(result.stdout);assert.equal(response.ok,expectedExit===0);assert.equal(response.id,id,'Normal task reply lost its original request ID');if(!response.ok)return response;assert(response.result);return {...response.result,id};
 }
 const finished=call({job:fixture.finished_job},'job.status');assert.equal(finished.state,'removed');
 const renewal=call({job:fixture.finished_job},'job.renew',1);assert.equal(renewal.error,'job_conflict');
 const records=[];
 for(const [index,artifact] of fixture.artifacts.entries()){
  const expected=Buffer.from(index===0?'Hello, Studio 👋\n'.repeat(4096):'');
  const started=call({phase:'begin',artifact});assert.equal(started.state,'pending');assert.equal(started.stream,started.id);
  const denied=call({phase:'next',stream:started.stream},'artifact.read',1,'f'.repeat(64));
  assert.equal(denied.error,'unauthorized');
  const deadline=performance.now()+5000,parts=[];let metadata,done=false;
  while(!done){
   assert(performance.now()<deadline,'Normal artifact transfer timeout');
   const event=call({phase:'next',stream:started.stream});
   if(event.state==='pending'){await delay(10);continue;}
   if(event.type==='begin'){assert.equal(metadata,undefined);metadata=event;assert.equal(event.artifact,artifact);assert.equal(event.length,expected.length);assert.equal(event.sha256,sha(expected));}
   else if(event.type==='chunk'){assert(metadata);assert.equal(event.index,parts.length);parts.push(Buffer.from(event.data,'base64'));}
   else {assert.equal(event.type,'end');done=true;}
  }
  assert(metadata);assert.deepEqual(Buffer.concat(parts),expected);
  records.push({bytes:expected.length,chunks:parts.length,sha256:sha(expected),complete:true});
 }
 const receipt={scope:'normal_real_manager_cli_artifact_downloads',finished_job_status:true,finished_job_renewal_error_correlated:true,records,manager_sha256:sha(readFileSync(binary)),cli_sha256:sha(readFileSync(cli)),model_requests:0,runtime_actions:0,installed_service_actions:0};
 writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');
 console.log(JSON.stringify({ok:true,directory,downloads:records.length,chunks:records.map(r=>r.chunks),model_requests:0,runtime_actions:0}));
} finally {
 if(!exited())child.kill('SIGTERM');
 const deadline=performance.now()+3000;while(!exited()&&performance.now()<deadline)await delay(10);
 assert(exited(),'Private fixture manager did not exit');
}
