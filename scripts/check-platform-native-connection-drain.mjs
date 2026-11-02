#!/usr/bin/env node
// Finite ordinary shutdown with one real unfinished HTTP body, empty catalog
// and no inference. Native source process only; never an installed service.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer,createConnection} from 'node:net';
import {request} from 'node:http';
import {setTimeout as delay} from 'node:timers/promises';
import {mkdtempSync,mkdirSync,openSync,closeSync,writeFileSync,readFileSync,readdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
const args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--release'&&args[3]==='--sha256');
const review=verifyNativeReview(args[2],args[4]),directory=mkdtempSync('/private/tmp/f9-connection-drain-'),models=join(directory,'models');
const scriptHash=createHash('sha256').update(readFileSync(import.meta.filename)).digest('hex');
mkdirSync(models,{mode:0o700});
const listener=createServer();await new Promise((resolve,reject)=>{listener.once('error',reject);listener.listen(0,'127.0.0.1',resolve);});
const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
const env={PATH:'/usr/bin:/bin',HOME:directory,XDG_CACHE_HOME:join(directory,'cache'),LANG:'C',LC_ALL:'C',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_NATIVE_CONTROL:'isolated-source-fixture'};
const policy=`(version 1)(allow default)(deny network*)(allow network* (local unix-socket)(remote unix-socket)(local ip "localhost:${port}")(remote ip "localhost:${port}"))`;
const log=openSync(join(directory,'native.log'),'wx',0o600);
const child=spawn('/usr/bin/sandbox-exec',['-p',policy,review.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager'],{env,stdio:['ignore',log,log]});closeSync(log);
const exited=()=>child.exitCode!==null||child.signalCode!==null;
async function until(check,ms=10000){const end=performance.now()+ms;while(performance.now()<end){const value=await check();if(value)return value;await delay(25);}throw Error('Finite private connection-drain deadline');}
function get(path){return new Promise((resolve,reject)=>{
 const req=request({host:'127.0.0.1',port,path,method:'GET',agent:false,timeout:2000},res=>{
  let body=Buffer.alloc(0);res.on('data',part=>{body=Buffer.concat([body,part]);if(body.length>8192)res.destroy(Error('Response bound'));});
  res.once('error',reject);res.once('end',()=>{try{assert.equal(res.statusCode,200);resolve(JSON.parse(body));}catch(error){reject(error);}});
 });req.once('error',reject);req.once('timeout',()=>req.destroy(Error('GET deadline')));req.end();
});}
let instance=null,sequence=0n;
function observe(){return new Promise((resolve,reject)=>{
 const frame=Buffer.alloc(32);frame.write('FIC9');frame[4]=3;
 const socket=createConnection(join(directory,'.fios-native-control/control.sock'));let bytes=Buffer.alloc(0);
 socket.setTimeout(2000,()=>socket.destroy(Error('Observation deadline')));socket.once('connect',()=>socket.end(frame));socket.once('error',reject);
 socket.on('data',part=>{bytes=Buffer.concat([bytes,part]);if(bytes.length>80)socket.destroy(Error('Observation bound'));});
 socket.once('end',()=>{try{
  assert.equal(bytes.length,80);assert.equal(bytes.subarray(0,4).toString(),'FIR9');assert.deepEqual([...bytes.subarray(4,8)],[3,0,0,0]);
  const current=bytes.subarray(8,24).toString('hex'),capture=bytes.readBigUInt64BE(64),at=Number(bytes.readBigUInt64BE(72));
  assert.notEqual(current,'0'.repeat(32));assert(instance===null||instance===current);instance=current;
  assert(capture>sequence&&capture<=BigInt(Number.MAX_SAFE_INTEGER));sequence=capture;
  assert(Number.isSafeInteger(at)&&Date.now()-at>=-1000&&Date.now()-at<=5000);
  assert(bytes.subarray(40,56).every(x=>x===0));assert(bytes[57]<=1);
  resolve({owned:bytes.readUInt32BE(32),ingress:bytes.readUInt32BE(36),uncertain:bytes[57]===1,sequence:Number(capture),sampled_at:at});
 }catch(error){reject(error);}});
});}
let partial=null,forced=false;
console.log(JSON.stringify({directory,model_posts:0,unfinished_get_bodies:1,private_native_children:1,installed:false}));
try {
 await until(async()=>{assert(!exited());try{return (await get('/health')).status==='ok';}catch(error){if(!['ECONNREFUSED','ECONNRESET'].includes(error.code))throw error;return false;}});
 assert.deepEqual((await get('/v1/models')).data,[]);
 await until(async()=>{const s=await observe();return s.owned===0&&!s.uncertain;});
 partial=createConnection({host:'127.0.0.1',port});partial.on('error',()=>{});
 await new Promise((resolve,reject)=>{partial.once('connect',resolve);partial.once('error',reject);});
 partial.write('GET /health HTTP/1.1\r\nHost: localhost\r\nContent-Length: 128\r\n\r\n{');
 const before=await until(async()=>{const s=await observe();return s.owned===1&&s.ingress===1&&!s.uncertain?s:null;});
 const began=performance.now();assert(child.kill('SIGTERM'));
 // Progress within the genuine body-read deadline, without finishing its
 // declared body. No counters, source rewrite or synthetic timeout is used.
 let bytesSent=1;
 while(performance.now()-began<31500){assert(!exited(),'Native server returned while original HTTP connection still owns its frame');assert(!partial.destroyed);partial.write(' ');bytesSent++;await delay(500);}
 assert(!exited(),'Native server returned after the thirty-second observation limit');
 const held=await observe();console.log(JSON.stringify({shutdown_observation:held,elapsed_ms:Math.round(performance.now()-began),original_connection_open:!partial.destroyed}));
 assert.equal(held.owned,1);assert.equal(held.ingress,1);assert(held.uncertain);
 const retainedLog=readFileSync(join(directory,'native.log'),'utf8');
 assert(retainedLog.includes('retaining original server state'));assert(!retainedLog.includes('Shutting down gracefully'));
 const heldMs=performance.now()-began;partial.destroy();partial=null;
 await until(exited,5000);assert.equal(child.exitCode,0);assert.equal(child.signalCode,null);
 assert(readFileSync(join(directory,'native.log'),'utf8').includes('Shutting down gracefully'));
 assert.equal(createHash('sha256').update(readFileSync(import.meta.filename)).digest('hex'),scriptHash);
 assert.deepEqual(readdirSync(models),[]);assert.deepEqual(verifyNativeReview(args[2],args[4]),review);
 const result={ok:true,directory,review_sha256:args[4],driver_sha256:scriptHash,source_instance:instance,before,held,held_ms:Math.round(heldMs),body_bytes_sent:bytesSent,declared_body_bytes:128,local_exit_after_original_connection_release:true,model_posts:0,models:0,installed:false,native_authority:false,native_quiescence:'unproven',coverage:'unknown'};
 writeFileSync(join(directory,'receipt.json'),JSON.stringify(result)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(result));
} finally {
 partial?.destroy();
 if(!exited()){child.kill('SIGTERM');try{await until(exited,5000);}catch{forced=true;child.kill('SIGKILL');await until(exited,5000);}}
 if(forced)throw Error('Forced private cleanup is not accepted; retained output must be reviewed');
}
