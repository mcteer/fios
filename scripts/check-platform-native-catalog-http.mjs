#!/usr/bin/env node
// Ordinary cold catalog check on core. Only GET requests; no model loading.
import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,symlinkSync,writeFileSync} from 'node:fs';
import {join,resolve,isAbsolute} from 'node:path';
import {userInfo} from 'node:os';
import {randomBytes} from 'node:crypto';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
import {nativeReviewJSON} from './lib/platform-native-review-intent.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(args.length===4&&args[0]==='--capsule'&&args[2]==='--sha256'&&isAbsolute(args[1]));
assert.equal(execFileSync('/usr/sbin/scutil',['--get','LocalHostName'],{encoding:'utf8',timeout:2000}).trim(),'fios-core');
const capsule=verifyNativeReview(args[1],args[3]),directory=mkdtempSync('/private/tmp/f9-catalog-http-'),home=join(directory,'home');
mkdirSync(home,{mode:0o700});const models=join(home,'models');mkdirSync(models,{mode:0o700});mkdirSync(join(models,'mlx-community'),{mode:0o700});mkdirSync(join(home,'tmp'),{mode:0o700});
const id='mlx-community/gemma-4-e4b-it-4bit';symlinkSync(join(userInfo().homedir,'.mlx-serve/models',id),join(models,id),'dir');
const listener=createServer();await new Promise(ok=>listener.listen(0,'127.0.0.1',ok));const port=listener.address().port;await new Promise(ok=>listener.close(ok));
const key=randomBytes(32).toString('hex'),profile=join(root,'tests/fixtures/platform/native-model-review.sb');
const child=spawn('/usr/bin/sandbox-exec',['-D','FIOS_REVIEW_ENDPOINT=localhost:'+port,'-D','FIOS_REVIEW_STATE='+home,'-D','FIOS_REVIEW_BINARY='+capsule.binary,'-f',profile,capsule.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager','--ctx-size','512','--max-concurrent','1','--api-key-env','FIOS_SOURCE_MODEL_KEY','--api-key-strict'],{env:{PATH:'/usr/bin:/bin',HOME:home,TMPDIR:join(home,'tmp'),XDG_CACHE_HOME:join(home,'cache'),LANG:'C',LC_ALL:'C',FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_SOURCE_MODEL_KEY:key},stdio:['ignore','pipe','pipe']});
let bytes=0;for(const pipe of [child.stdout,child.stderr])pipe.on('data',part=>{bytes+=part.length;if(bytes>128*1024)child.kill('SIGTERM');});
const exited=()=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout){const end=performance.now()+timeout;while(performance.now()<end){if(await check())return;await delay(25);}throw Error('Cold catalog deadline');}
try{
 await until(async()=>{assert(!exited(),'Private source server exited');try{const r=await fetch('http://127.0.0.1:'+port+'/health',{headers:{Authorization:'Bearer '+key},signal:AbortSignal.timeout(500)});return r.ok;}catch{return false;}},10000);
 const response=await fetch('http://127.0.0.1:'+port+'/v1/models',{headers:{Authorization:'Bearer '+key},redirect:'error',signal:AbortSignal.timeout(2000)});assert.equal(response.status,200);
 const catalog=await nativeReviewJSON(response),model=catalog.data.find(m=>m.id===id);assert(model);assert.equal(model.loaded,false);
 const observed={id:model.id,loaded:model.loaded,input_modalities:model.input_modalities,capabilities:model.capabilities};writeFileSync(join(directory,'catalog-observation.json'),JSON.stringify(observed)+'\n',{mode:0o600});
 assert.deepEqual(model.input_modalities,['text']);assert(!model.capabilities.includes('vision'));
 console.log(JSON.stringify({ok:true,host:'fios-core',model:id,loaded:false,input_modalities:model.input_modalities,model_posts:0,native_authority:false,review_directory:directory}));
}catch(error){console.error('Retained private catalog observation: '+directory);throw error;}finally{
 if(!exited()){child.kill('SIGTERM');try{await until(exited,5000);}catch{child.kill('SIGKILL');await until(exited,2000);}}
 assert(exited());assert.equal(child.exitCode,0);
}
