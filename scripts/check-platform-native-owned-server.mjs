#!/usr/bin/env node
// Finite original-child runtime composition with the actual source server.
// Empty private catalog, no inference; synthetic reservations are not authority.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {createHash} from 'node:crypto';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,readdirSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
const args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--release'&&args[3]==='--sha256');
const review=verifyNativeReview(args[2],args[4]),root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/f9-native-owned-');
const core=join(root,'platform/studio/Sources/StudioCore'),name='MLXServingProcessRuntime.swift';
const source=readFileSync(join(core,name)),fixture=readFileSync(join(root,'platform/studio/Tests/NativeFixtures/NativeOwnedServer.swift.fixture'));
const unit=join(directory,'RuntimeFixture.swift');writeFileSync(unit,Buffer.concat([source,Buffer.from('\n'),fixture]),{mode:0o600});
const sha=b=>createHash('sha256').update(b).digest('hex');
console.log(JSON.stringify({directory,model_request_budget:0,source_fixture_only:true,installed:false}));
const receipts=[];
for(const mode of ['debug','release']){
 const binary=join(directory,mode),home=join(directory,mode+'-home');mkdirSync(home,{mode:0o700});mkdirSync(join(home,'models'),{mode:0o700});
 const compile=spawnSync('swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors',...(mode==='release'?['-O']:[]),'-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(n=>n.endsWith('.swift')&&n!==name).sort().map(n=>join(core,n)),unit,'-o',binary],{encoding:'utf8',timeout:120000,maxBuffer:2<<20});
 writeFileSync(join(directory,mode+'-build.log'),(compile.stdout??'')+(compile.stderr??''),{mode:0o600});
 assert(!compile.error&&!compile.signal&&compile.status===0,'Private Swift compilation failed; retained build log');
 const listener=createServer();await new Promise((resolve,reject)=>{listener.once('error',reject);listener.listen(0,'127.0.0.1',resolve);});const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
 const policy=`(version 1)(allow default)(deny network*)(allow network* (local unix-socket)(remote unix-socket)(local ip "localhost:${port}")(remote ip "localhost:${port}"))`;
 const run=spawnSync('/usr/bin/sandbox-exec',['-p',policy,binary,review.binary,review.binarySHA256??sha(readFileSync(review.binary)),home,String(port)],{env:{PATH:'/usr/bin:/bin',HOME:home,LANG:'C',LC_ALL:'C'},encoding:'utf8',timeout:35000,maxBuffer:2<<20});
 writeFileSync(join(directory,mode+'-run.log'),(run.stdout??'')+(run.stderr??''),{mode:0o600});
 assert(!run.error&&!run.signal&&run.status===0,'Private native lifecycle failed; retained log is not acceptance');
 assert(run.stdout.includes('PASS: actual empty-model native server owned start/identity/listener-health/local stop/restart; two original children, no model request, synthetic reservations only'));
 receipts.push({mode,binary_sha256:sha(readFileSync(binary)),native_children:2});
}
assert.deepEqual(verifyNativeReview(args[2],args[4]),review);
const receipt={ok:true,directory,review_sha256:args[4],fixture_sha256:sha(fixture),runtime_sha256:sha(source),modes:receipts,model_posts:0,source_fixture_only:true,synthetic_reservations:true,native_authority:false,installed:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(receipt));
