#!/usr/bin/env node
// Finite empty-model source observation only. No model POST, management
// action, historical HTTP/fault matrix, installed server or Studio operation.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer,createConnection} from 'node:net';
import {request} from 'node:http';
import {setTimeout as delay} from 'node:timers/promises';
import {mkdtempSync,mkdirSync,openSync,closeSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
import {nativeReviewComponents} from './lib/platform-native-review-intent.mjs';
const args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--release'&&args[3]==='--sha256');
const review=verifyNativeReview(args[2],args[4]),directory=mkdtempSync('/private/tmp/f9-backend-fences-'),models=join(directory,'models');
mkdirSync(models,{mode:0o700});
const listener=createServer();await new Promise((resolve,reject)=>{listener.once('error',reject);listener.listen(0,'127.0.0.1',resolve);});
const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
const env={PATH:'/usr/bin:/bin',HOME:directory,XDG_CACHE_HOME:join(directory,'cache'),LANG:'C',LC_ALL:'C',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_NATIVE_CONTROL:'isolated-source-fixture'};
const policy=`(version 1)(allow default)(deny network*)(allow network* (local unix-socket)(remote unix-socket)(local ip "localhost:${port}")(remote ip "localhost:${port}"))`;
const log=openSync(join(directory,'native.log'),'wx',0o600);
const child=spawn('/usr/bin/sandbox-exec',['-p',policy,review.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager'],{env,stdio:['ignore',log,log]});closeSync(log);
const exited=()=>child.exitCode!==null||child.signalCode!==null;
async function until(check,bound=10000){const end=performance.now()+bound;while(performance.now()<end){const result=check();if(result)return result;await delay(20);}throw Error('Private source observation deadline');}
function get(path){return new Promise((resolve,reject)=>{
 const req=request({host:'127.0.0.1',port,path,method:'GET',agent:false,timeout:2000},res=>{
  let body=Buffer.alloc(0);res.on('data',chunk=>{body=Buffer.concat([body,chunk]);if(body.length>8192)res.destroy(Error('Private response bound'));});
  res.once('error',reject);res.once('end',()=>{try{assert.equal(res.statusCode,200);resolve(JSON.parse(body.toString('utf8')));}catch(error){reject(error);}});
 });req.once('error',reject);req.once('timeout',()=>req.destroy(Error('Private GET deadline')));req.end();
});}
function sourceInstance(){return new Promise((resolve,reject)=>{
 const frame=Buffer.alloc(32);frame.write('FIC9');frame[4]=3; // observe only
 const socket=createConnection(join(directory,'.fios-native-control/control.sock'));let bytes=Buffer.alloc(0);
 socket.setTimeout(2000,()=>socket.destroy(Error('Private readonly control deadline')));
 socket.once('connect',()=>socket.end(frame));socket.once('error',reject);
 socket.on('data',part=>{bytes=Buffer.concat([bytes,part]);if(bytes.length>80)socket.destroy(Error('Private readonly control bound'));});
 socket.once('end',()=>{try{
  assert.equal(bytes.length,80);assert.equal(bytes.subarray(0,4).toString(),'FIR9');assert.equal(bytes[4],3);assert.equal(bytes[5],0);assert.equal(bytes[6],0);assert.equal(bytes[7],0);
  const instance=bytes.subarray(8,24).toString('hex');assert.notEqual(instance,'0'.repeat(32));resolve(instance);
 }catch(error){reject(error);}});
});}
let startupComplete=false,forced=false;
console.log(JSON.stringify({retained_directory:directory,model_request_budget:0,management_action_budget:0,installed:false}));
try {
 const end=performance.now()+10000;
 while(performance.now()<end){assert(!exited());try{const health=await get('/health');if(health.status==='ok'){startupComplete=true;break;}}catch(error){if(!['ECONNREFUSED','ECONNRESET'].includes(error.code))throw error;}await delay(50);}
 assert(startupComplete);const instance=await sourceInstance();const catalog=await get('/v1/models');assert.deepEqual(catalog.data,[]);
 const first=await get('/v1/fios/source-components');
 console.log(JSON.stringify({observed_component_schema:first.components?.schema_version,models:catalog.data.length,model_posts:0}));
 assert.equal(first.components?.schema_version,4);
 const parsed=nativeReviewComponents(first,instance);assert(!exited());
 assert.equal(parsed.component_envelope_schema_version,4);assert.equal(parsed.backend_fences.coverage,'unknown');assert.equal(parsed.backend_fences.authority,false);
 assert.equal(parsed.backend_fences.mimo_warm_uncertain,false);assert.equal(parsed.backend_fences.ds4_metal_uncertainty,0);assert.equal(parsed.backend_fences.ds4_host_uncertainty,0);
 const second=await get('/v1/fios/source-components'),next=nativeReviewComponents(second,instance,parsed.sequence);assert(!exited());
 assert(next.sequence>parsed.sequence);assert.deepEqual(next.backend_fences,parsed.backend_fences);
 assert.deepEqual((await get('/v1/models')).data,[]);
 child.kill('SIGTERM');await until(exited,5000);
 assert.deepEqual(verifyNativeReview(args[2],args[4]),review);
 const receipt={ok:true,directory,review_sha256:args[4],component_schema:4,backend_fences:parsed.backend_fences,source_instance:first.source_instance,first_sequence:parsed.sequence,last_sequence:next.sequence,model_posts:0,models:0,management_actions:0,installed:false,native_authority:false,all_backend_terminality:false};
 writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(receipt));
} finally {
 if(!exited()){child.kill('SIGTERM');try{await until(exited,5000);}catch{forced=true;child.kill('SIGKILL');await until(exited,5000);}}
 if(forced)throw Error('Forced private fixture cleanup is not acceptance; retained output must be reviewed');
}
