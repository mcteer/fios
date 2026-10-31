#!/usr/bin/env node
// Real installed worker/private mock transport. No model or service access.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import path from 'node:path';
const args=process.argv.slice(2),root=path.resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.getuid()>0&&args[0]==='--isolated'&&(args.length===1||(args.length===2&&args[1]==='--expect-expired')));
const expired=args.length===2,base='http://127.0.0.1:1/v1',job=randomUUID(),epoch=randomUUID();
const child=spawn('/usr/bin/sandbox-exec',['-D','FIOS_MOCK_ENDPOINT=localhost:1','-f',path.join(root,'tests/fixtures/platform/mock-network.sb'),path.join(root,'.venv/bin/python'),'-I','-B',path.join(root,'tests/fixtures/platform/mock-worker.py')],{cwd:root,env:{PATH:'/usr/bin:/bin',HOME:'/var/empty',LANG:'C',LC_ALL:'C',MLX_BASE_URL:base,FIOS_WEB_SEARCH:'off',PYDANTIC_AI_NO_BANNER:'1',...(expired?{FIOS_PLATFORM_FIXTURE_HEALTH_DELAY:'1.25'}:{FIOS_PLATFORM_FIXTURE_POST_DELAY:'1.25'}),FIOS_PLATFORM_FIXTURE_READY:'1'},stdio:['pipe','pipe','pipe']});
let output=Buffer.alloc(0),diagnostic='',sent=false,expiry=0;
const deadline=setTimeout(()=>child.kill('SIGKILL'),15000);
try {
 child.stdout.on('data',chunk=>{output=Buffer.concat([output,chunk]);if(output.length>1<<20)child.kill('SIGKILL');});
 child.stderr.on('data',chunk=>{
  diagnostic+=chunk.toString();if(diagnostic.length>8192)child.kill('SIGKILL');
  if(!sent&&diagnostic.includes('FIXTURE_IMPORTS_READY\n')){
   sent=true;expiry=Date.now()+1000;
   const data=Buffer.from(JSON.stringify({v:1,type:'run',job_id:job,attempt:0,epoch,model:'fixture/model',endpoint_hash:createHash('sha256').update(base).digest('hex'),expires_at:expiry,context:[{role:'user',content:'fixture only'}]}));
   const header=Buffer.alloc(4);header.writeUInt32BE(data.length);child.stdin.write(Buffer.concat([header,data]));
  }
 });
 const result=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>resolve({code,signal}));});
 assert.equal(result.code,0,'Finite fixture child must exit normally; a killed/timed-out child is not evidence');assert.equal(result.signal,null);assert(sent);
 const events=[];
 while(output.length){assert(output.length>=4);const size=output.readUInt32BE(0);assert(size>0&&size<=256<<10&&output.length>=size+4);events.push(JSON.parse(output.subarray(4,size+4)));output=output.subarray(size+4);}
 assert(events.every(value=>value.job_id===job));
 const usage=events.filter(value=>value.type==='usage');assert.equal(usage.length,1);assert.equal(usage[0].posts,expired?0:1);
 if(expired)assert(events.some(value=>value.type==='error'&&value.code==='invalid_request'));
 else {assert(events.some(value=>value.type==='done'));assert(Date.now()>expiry,'Response must outlive the one-use dispatch permission');}
 console.log('PASS: '+(expired?'artificial readiness delay expires a shorter valid permission before any POST':'sampling delay occurs after the sole mocked POST; completion outlives permission without retries')+'; installed worker, kernel network guard, no native/model action.');
}finally{clearTimeout(deadline);child.stdin.destroy();if(child.exitCode===null&&child.signalCode===null)child.kill('SIGKILL');}
