#!/usr/bin/env node
// Genuine SDK CPU queues + native ownership implementation, no model,
// fault/counter campaign, replacement SDK, native server or installed change.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,copyFileSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname} from 'node:path';
import {verifyMlxSourceReview} from './lib/platform-mlx-source-review.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===11&&args[0]==='--isolated');
for(const [i,key] of ['--sdk','--sha256','--source','--zig','--developer-dir'].entries())assert.equal(args[i*2+1],key);
const [document,source,zig,developer]=[2,6,8,10].map(i=>{assert(args[i].startsWith('/'));return realpathSync(args[i]);});
const proof=verifyMlxSourceReview(document,args[4],source),directory=mkdtempSync('/private/tmp/fios-009-sdk-host-owners-'),unit=join(directory,'unit');mkdirSync(unit,{mode:0o700});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const sha=file=>hash(readFileSync(file));
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const names=['request_ownership.zig','sdk_request_ownership.zig','sdk_host_owners_fixture.cpp','sdk_host_owners_test.zig.fixture'];
const inputs=Object.fromEntries(names.map(name=>[name,sha(join(root,'platform/studio/native',name))]));
for(const name of names)copyFileSync(join(root,'platform/studio/native',name),join(unit,name.endsWith('.fixture')?'test.zig':name));
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:1<<20,...options});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),proof.sdk);
const sdk=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim();
console.log(JSON.stringify({directory,models:0,native_server:false,actual_cpu_callbacks:2,installed:false}));
for(const [mode,optimize] of [['Debug','-O0'],['ReleaseSafe','-O2']]){
 const object=join(directory,mode+'.o'),binary=join(directory,mode);
 run('/usr/bin/clang++',['-std=c++20',optimize,'-UNDEBUG','-isysroot',sdk,'-I',source,'-c',join(unit,'sdk_host_owners_fixture.cpp'),'-o',object]);
 run(zig,['test',join(unit,'test.zig'),object,'-O'+mode,'-lc','-lc++','--sysroot',sdk,proof.libraries['libmlx.dylib'],'-rpath',dirname(proof.libraries['libmlx.dylib']),'-F/System/Library/Frameworks','-framework','Metal','-framework','Foundation','--test-filter','fios genuine SDK host callbacks','--test-no-exec','-femit-bin='+binary]);
 const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:20000,maxBuffer:8192});
 const log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,mode+'-run.log'),log,{mode:0o600});
 assert(!result.error&&!result.signal,JSON.stringify({error:result.error?.code,signal:result.signal}));assert.equal(result.status,0,log);
 assert(log.includes('PASS: genuine SDK parent and nested CPU callbacks retain native request roots'));assert(log.includes('All 1 tests passed.'));console.log(mode+': '+log.trim());
}
for(const name of names)assert.equal(sha(join(root,'platform/studio/native',name)),inputs[name]);
assert.deepEqual(verifyMlxSourceReview(document,args[4],source),proof);
const result={ok:true,directory,scope:'declared_native_owner_implementation_and_source_SDK_CPU_callbacks_only',inputs,sdk_receipt_sha256:proof.receipt_sha256,modes:['Debug','ReleaseSafe'],actual_cpu_callbacks_per_mode:2,models:0,installed:false,native_authority:false,all_backend_terminality:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(result)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(result));
