#!/usr/bin/env node
// Ordinary metadata contention in the complete actual Objective-C module.
// No source rewrite, scheduling shim, model, tensor, network or failure injection.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {verifyDs4SourceBuild} from './lib/platform-ds4-source-review.mjs';
const root=path.resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(args.length===7&&args[0]==='--isolated'&&args[1]==='--build'&&args[3]==='--sha256'&&args[5]==='--developer-dir'&&args[6]==='/Applications/Xcode.app/Contents/Developer');
const config={document:args[2],expected:args[4],root},selected=verifyDs4SourceBuild(config),source=selected.source;
const directory=mkdtempSync('/private/tmp/fios-ds4-metadata-lifecycle-');
const env={DEVELOPER_DIR:args[6],PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C'};
const hash=value=>createHash('sha256').update(value).digest('hex');
const run=(file,argv)=>execFileSync(file,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const compiler=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','clang']).trim()),sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
const receipt=JSON.parse(readFileSync(args[2],'utf8'));assert.equal(hash(readFileSync(compiler)),receipt.compiler_sha256);
const original=readFileSync(path.join(source,'ds4_metal.m'),'utf8');
const metadataFixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4MetalMetadata.c.fixture'),metadataFixture=readFileSync(metadataFixtureFile,'utf8');
const fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4MetadataLifecycle.m.fixture'),fixture=readFileSync(fixtureFile,'utf8');
const joinFixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4JoinWait.c.fixture'),joinFixture=readFileSync(joinFixtureFile,'utf8');
const objects=['ds4.o','ds4_image.o','ds4_distributed.o','ds4_tp.o','ds4_ssd.o','ds4_layer_pack.o','ds4_engram.o','ds4_gpu_args.o','ds4_help.o'];
for(const name of objects){const bytes=readFileSync(path.join(source,name)),value=receipt.objects[name];assert(value);assert.equal(bytes.length,value.bytes);assert.equal(hash(bytes),value.sha256);}
const unit=path.join(directory,'metadata-lifecycle.m'),binary=path.join(directory,'metadata-lifecycle');
writeFileSync(unit,original+'\n'+joinFixture+'\n'+metadataFixture+'\n'+fixture,{mode:0o600});
const compilation=spawnSync(compiler,['-isysroot',sdk,'-I',source,'-std=gnu11','-fobjc-arc','-O3','-ffast-math','-mcpu=native','-UNDEBUG',unit,
 ...objects.map(name=>path.join(source,name)),'-lm','-pthread','-framework','Foundation','-framework','Metal','-o',binary],
 {env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
writeFileSync(path.join(directory,'compile.log'),(compilation.stdout??'')+(compilation.stderr??''),{mode:0o600});
assert.equal(compilation.status,0,`Actual lifecycle interface compilation failed; retain ${directory}`);
const result=spawnSync(binary,[],{cwd:source,env,encoding:'utf8',timeout:10000,maxBuffer:1<<20});
writeFileSync(path.join(directory,'run.log'),(result.stdout??'')+(result.stderr??''),{mode:0o600});
assert(!result.error&&!result.signal,`Lifecycle check did not complete normally; retain ${directory}`);
assert.equal(result.status,0,`Ordinary lifecycle failed; retain ${directory}`);
assert.deepEqual(verifyDs4SourceBuild(config),selected);assert.equal(readFileSync(path.join(source,'ds4_metal.m'),'utf8'),original);
assert.equal(readFileSync(fixtureFile,'utf8'),fixture);assert.equal(readFileSync(metadataFixtureFile,'utf8'),metadataFixture);assert.equal(readFileSync(joinFixtureFile,'utf8'),joinFixture);
const outcome={ok:true,directory,build_receipt_sha256:args[4],fixture_sha256:hash(fixture),metadata_fixture_sha256:hash(metadataFixture),join_fixture_sha256:hash(joinFixture),binary_sha256:hash(readFileSync(binary)),
 bounded_pending_join:true,metadata_cases:3,pread_worker_joins:2,source_rewritten:false,model_jobs:0,gpu_objects:0,fault_injection:false,native_inference:false,native_authority:false};
writeFileSync(path.join(directory,'receipt.json'),JSON.stringify(outcome,null,2)+'\n',{mode:0o600});
console.log(result.stdout.trim());console.log(JSON.stringify(outcome));
