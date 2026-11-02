#!/usr/bin/env node
// Actual request-buffer adapter + native ownership + private Metal objects.
// Does not initialize DS4, load models or claim auxiliary/whole-producer proof.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,realpathSync,lstatSync,copyFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2),priorIndex=args.indexOf('--prior'),prior=priorIndex>=0;
if(prior){assert.equal(args.lastIndexOf('--prior'),priorIndex);args.splice(priorIndex,1);}
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===7&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig'&&args[5]==='--developer-dir');
const [source,zig,developer]=[2,4,6].map(i=>{assert(args[i].startsWith('/'));return realpathSync(args[i]);});
assert.equal(developer,'/Applications/Xcode.app/Contents/Developer');
const info=lstatSync(source);assert(source.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);
const directory=mkdtempSync('/private/tmp/fios-009-ds4-request-buffer-'),checkout=join(directory,'source'),unit=join(directory,'unit');mkdirSync(unit,{mode:0o700});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex'),sha=file=>hash(readFileSync(file));
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:2<<20,...options});
const git=(where,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',where,...argv]);
const paths=['ds4.c','ds4.h','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m','ds4_tp.c'],revision='9139e2ae58a41503968a500f36f75895c1ba63fc';
const patchFile=join(root,prior?'platform/studio/native/ds4-9139e2a-participant-retirement.patch':'platform/studio/native/ds4-9139e2a-request-origins.patch'),patch=readFileSync(patchFile,'utf8');
function check(){assert.equal(git(source,'rev-parse','HEAD').trim(),revision);assert.equal(git(source,'diff','--cached','--name-only').trim(),'');assert.equal(git(source,'diff','HEAD','--name-only').trim(),paths.join('\n'));assert.equal(git(source,'diff','--no-ext-diff','--no-textconv','HEAD','--',...paths),patch);}
check();
run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',source,checkout]);git(checkout,'checkout','--quiet','--detach',revision);git(checkout,'apply',patchFile);
const declared=git(checkout,'ls-files','-z').split('\0').filter(name=>name==='Makefile'||/\.(?:c|m|h|inc|metal)$/.test(name)).sort();
const declaredSources=Object.fromEntries(declared.map(name=>[name,sha(join(checkout,name))]));
const helperFile=join(root,'platform/studio/native/ds4_request_origins_helpers.inc'),fixtureFile=join(root,'platform/studio/native/ds4_request_origins.zig.fixture');
const original=readFileSync(join(checkout,'ds4_metal.m')),helper=readFileSync(helperFile),fixture=readFileSync(fixtureFile),composed=Buffer.concat([original,Buffer.from('\n'),helper]);
writeFileSync(join(unit,'composed.m'),composed,{mode:0o600,flag:'wx'});writeFileSync(join(unit,'test.zig'),fixture,{mode:0o600,flag:'wx'});
const nativeNames=['request_ownership.zig','sdk_request_ownership.zig'],nativeInputs=Object.fromEntries(nativeNames.map(name=>[name,sha(join(root,'platform/studio/native',name))]));
for(const name of nativeNames)copyFileSync(join(root,'platform/studio/native',name),join(unit,name));
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const sdk=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim(),compiler=run('/usr/bin/xcrun',['--sdk','macosx','--find','clang']).trim();
console.log(JSON.stringify({directory,models:0,ds4_initialized:false,normal_producer_runtime_acceptance:false,auxiliary_coverage:false,private_buffer_bytes:64,event_delay_ms:3000,installed:false}));
// Link the real upstream dependencies (including its TTY helper), never a
// substitute implementation. These model/worker paths are not executed.
const coreNames=['ds4','ds4_image','ds4_distributed','ds4_tp','ds4_ssd','ds4_layer_pack','ds4_engram'];
const coreObjects=coreNames.map(name=>join(directory,name+'.o'));
for(const [i,name] of coreNames.entries())run(compiler,['-isysroot',sdk,'-O2','-mcpu=native','-I',checkout,'-c',join(checkout,name+'.c'),'-o',coreObjects[i]]);
for(const [mode,optimize] of [['Debug','-O0'],['ReleaseSafe','-O2']]){
 const object=join(directory,mode+'.o'),binary=join(directory,mode);
 run(compiler,['-isysroot',sdk,optimize,'-fobjc-arc','-I',checkout,'-c',join(unit,'composed.m'),'-o',object]);
 run(zig,['test',join(unit,'test.zig'),object,...coreObjects,'-O'+mode,'-lc','--sysroot',sdk,'-F/System/Library/Frameworks','-framework','Foundation','-framework','Metal','-framework','CoreFoundation','--test-filter','fios ordinary DS4 request buffer origins','--test-no-exec','-femit-bin='+binary]);
 for(const scenario of ['healthy','cached','missing']){
  const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env:{...env,FIOS_DS4_ORIGIN_SCENARIO:scenario},encoding:'utf8',timeout:20000,maxBuffer:8192});
  const log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,mode+'-'+scenario+'.log'),log,{mode:0o600});
  assert(!result.error&&!result.signal,JSON.stringify({error:result.error?.code,signal:result.signal}));assert.equal(result.status,0,log);
  assert(log.includes(scenario==='missing'?'PASS: actual DS4 adapter refuses missing request origin':'PASS: actual DS4 request-buffer adapter retains every encoding origin'));assert(log.includes('All 1 tests passed.'));console.log(mode+'/'+scenario+': '+log.trim());
 }
}
check();assert.equal(readFileSync(patchFile,'utf8'),patch);assert(readFileSync(helperFile).equals(helper));assert(readFileSync(fixtureFile).equals(fixture));
for(const name of nativeNames)assert.equal(sha(join(root,'platform/studio/native',name)),nativeInputs[name]);
assert.deepEqual(Object.fromEntries(declared.map(name=>[name,sha(join(checkout,name))])),declaredSources);
const receipt={ok:true,directory,prior_source:prior,scope:'declared_DS4_request_buffer_adapter_native_contexts_and_private_real_Metal_objects_only',patch_sha256:hash(patch),native_inputs:nativeInputs,declared_sources:declaredSources,helper_sha256:hash(helper),fixture_sha256:hash(fixture),original_metal_sha256:hash(original),composed_metal_sha256:hash(composed),sdk:'27.2',modes:['Debug','ReleaseSafe'],scenarios:['healthy','cached','missing'],models:0,ds4_initialized:false,normal_producer_runtime_acceptance:false,auxiliary_coverage:false,installed:false,native_authority:false};
const receiptBytes=JSON.stringify(receipt)+'\n';writeFileSync(join(directory,'receipt.json'),receiptBytes,{mode:0o600,flag:'wx'});console.log(JSON.stringify({ok:true,directory,receipt_sha256:hash(receiptBytes),patch_sha256:receipt.patch_sha256,modes:receipt.modes,scenarios:receipt.scenarios,models:0,ds4_initialized:false,normal_producer_runtime_acceptance:false,auxiliary_coverage:false,native_authority:false}));
