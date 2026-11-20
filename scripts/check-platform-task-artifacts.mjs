#!/usr/bin/env node
// Normal real-manager/CLI artifact downloads, without inference or runtime actions.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,readdirSync,readFileSync,writeFileSync,copyFileSync,existsSync,statSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
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
const launch=(...args)=>spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,...args],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'ignore'});
let child=launch();
const exited=()=>child.exitCode!==null||child.signalCode!==null;
async function stop(){
 if(!exited())child.kill('SIGTERM');
 const deadline=performance.now()+3000;while(!exited()&&performance.now()<deadline)await delay(10);
 assert(exited(),'Private fixture manager did not exit');
}
async function ready(){
 const startup=performance.now()+8000;
 while(!existsSync(join(state,'task.sock'))){assert(!exited(),'Private artifact manager exited');assert(performance.now()<startup,'Private manager startup timeout');await delay(25);}
}
const sha=data=>createHash('sha256').update(data).digest('hex');
try {
 await ready();
 const fixtureBytes=readFileSync(join(state,'fixture.json'));
 const fixture=JSON.parse(fixtureBytes);
 function call(payload,operation='artifact.read',expectedExit=0,owner=fixture.owner,id=randomUUID()){
  const result=spawnSync(cli,['--state',state,'task'],{cwd:root,encoding:'utf8',timeout:3000,input:JSON.stringify({version:1,id,operation,payload:{...payload,owner}})});
  if(expectedExit===null)assert([0,1].includes(result.status));
  else assert.equal(result.status,expectedExit,'Normal task CLI request returned an unexpected exit code');
  const response=JSON.parse(result.stdout);assert.equal(response.ok,result.status===0);assert.equal(response.id,id,'Normal task reply lost its original request ID');if(!response.ok)return response;assert(response.result);return {...response.result,id};
 }
 const finished=call({job:fixture.finished_job},'job.status');assert.equal(finished.state,'removed');
 const renewal=call({job:fixture.finished_job},'job.renew',1);assert.equal(renewal.error,'job_conflict');
 const otherOwner=randomBytes(32).toString('base64');
 for(const operation of ['job.status','job.renew']){
  assert.equal(call({job:fixture.finished_job},operation,1,otherOwner).error,'unauthorized');
 }
 // An owner who guesses a real artifact ID must see the same terminal
 // response as if it did not exist. Neither stream may publish metadata.
 for(const artifact of [fixture.artifacts[0],randomUUID()]){
  const started=call({phase:'begin',artifact},'artifact.read',0,otherOwner);
  assert.equal(started.state,'pending');assert.match(started.stream,/^[a-f0-9-]{36}$/);assert.notEqual(started.stream,started.id);
  const deadline=performance.now()+5000;
  for(;;){
   assert(performance.now()<deadline,'Unowned artifact stream did not terminate');
   const event=call({phase:'next',stream:started.stream},'artifact.read',null,otherOwner);
   if(event.ok===false){assert.equal(event.error,'invalid_request');assert.equal(event.result,undefined);break;}
   assert.equal(event.state,'pending');assert.equal(event.type,undefined);
   await delay(10);
  }
  assert.equal(call({phase:'next',stream:started.stream},'artifact.read',1,otherOwner).error,'unauthorized');
 }
 const interrupted=call({phase:'begin',artifact:fixture.artifacts[0]});
 assert.equal(interrupted.state,'pending');
 const beforeRestart=performance.now()+5000;
 for(;;){
  assert(performance.now()<beforeRestart,'Original export stream did not reach begin');
  const event=call({phase:'next',stream:interrupted.stream});
  if(event.type==='begin'){assert.equal(event.artifact,fixture.artifacts[0]);break;}
  assert.equal(event.state,'pending');await delay(10);
 }
 await stop();
 const retainedArtifactFiles=['index.json',...fixture.artifacts.map(id=>id+'.blob')];
 const retainedArchive=()=>Object.fromEntries(retainedArtifactFiles.map(name=>{
  const path=join(state,'artifacts',name),info=statSync(path,{bigint:true});
  return [name,{sha256:sha(readFileSync(path)),device:info.dev,inode:info.ino}];
 }));
 const originalArchive=retainedArchive();
 assert(!existsSync(join(state,'task.sock')),'Stopped fixture left a task socket');
 child=launch('--resume');
 await ready();
 assert.equal(call({phase:'next',stream:interrupted.stream},'artifact.read',1).error,'unauthorized');
 assert.equal(call({job:fixture.finished_job},'job.status').state,'removed');
 assert.equal(call({job:fixture.finished_job},'job.status',1,otherOwner).error,'unauthorized');
 assert.equal(call({job:fixture.finished_job},'job.renew',1,otherOwner).error,'unauthorized');
 assert.equal(call({job:fixture.finished_job},'job.renew',1).error,'job_conflict');
 for(let poll=0;poll<2;poll++){
  const finished=call({job:fixture.finished_job},'job.status');
  assert.equal(finished.state,'removed');assert.equal(finished.unresolved_managed_requests,0);
  assert.equal(finished.event,undefined,'Status replayed output for a finished job after restart');
 }
 assert.deepEqual(readFileSync(join(state,'fixture.json')),fixtureBytes,'Replacement reseeded fixture ownership');
 const records=[],beginCorrelation=randomUUID();
 let previousStream;
 for(const [index,artifact] of fixture.artifacts.entries()){
  const expected=Buffer.from(index===0?'Hello, Studio 👋\n'.repeat(4096):'');
  const started=call({phase:'begin',artifact},'artifact.read',0,fixture.owner,beginCorrelation);
  assert.equal(started.state,'pending');assert.match(started.stream,/^[a-f0-9-]{36}$/);assert.notEqual(started.stream,started.id);
  assert.notEqual(started.stream,previousStream);
  if(previousStream)assert.equal(call({phase:'next',stream:previousStream},'artifact.read',1).error,'unauthorized');
  assert.equal(call({phase:'begin',artifact},'artifact.read',1,fixture.owner,beginCorrelation).error,'resource_limit');
  const denied=call({phase:'next',stream:started.stream},'artifact.read',1,otherOwner);
  assert.equal(denied.error,'unauthorized');
  assert.equal(call({phase:'next',stream:started.stream},'artifact.read',1,otherOwner).error,'unauthorized');
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
  assert.equal(call({phase:'next',stream:started.stream},'artifact.read',1).error,'unauthorized');
  previousStream=started.stream;
  records.push({bytes:expected.length,chunks:parts.length,sha256:sha(expected),complete:true});
 }
 await stop();
 assert.deepEqual(retainedArchive(),originalArchive,'Manager replacement or downloads changed durable archive identity or bytes');
 const receipt={scope:'normal_real_manager_cli_artifact_downloads',stopped_archive_unchanged:true,finished_job_status:true,finished_job_renewal_error_correlated:true,unowned_and_missing_same_terminal_error:true,completed_stream_replay_refused:true,restarted_stream_refused_and_export_retained:true,records,manager_sha256:sha(readFileSync(binary)),cli_sha256:sha(readFileSync(cli)),model_requests:0,runtime_actions:0,installed_service_actions:0};
 writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');
 console.log(JSON.stringify({ok:true,directory,downloads:records.length,chunks:records.map(r=>r.chunks),model_requests:0,runtime_actions:0}));
} finally {
 await stop();
}
