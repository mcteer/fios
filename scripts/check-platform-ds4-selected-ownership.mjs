#!/usr/bin/env node
// Unmodified complete C module; real GPU primitives, empty invalid-model jobs.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyDs4SourceBuild} from './lib/platform-ds4-source-review.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
assert(args.length===7&&args[0]==='--isolated'&&args[1]==='--build'&&args[3]==='--sha256'&&args[5]==='--developer-dir'&&args[6]==='/Applications/Xcode.app/Contents/Developer');
const config={document:args[2],expected:args[4],root},selected=verifyDs4SourceBuild(config),source=selected.source;
const directory=mkdtempSync('/private/tmp/fios-ds4-selected-ownership-');
const env={DEVELOPER_DIR:args[6],PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C'};
const run=(file,argv)=>execFileSync(file,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const compiler=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','clang']).trim()),sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
const sha=value=>createHash('sha256').update(value).digest('hex'),receipt=JSON.parse(readFileSync(args[2],'utf8'));
assert.equal(sha(readFileSync(compiler)),receipt.compiler_sha256);run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',compiler]);
const original=readFileSync(path.join(source,'ds4.c'),'utf8'),fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4SelectedOwnership.c.fixture'),fixture=readFileSync(fixtureFile,'utf8');
const objects=['ds4_image.o','ds4_distributed.o','ds4_tp.o','ds4_ssd.o','ds4_layer_pack.o','ds4_engram.o','ds4_gpu_args.o','ds4_help.o','ds4_metal.o'];
for(const name of objects){const record=receipt.objects[name];assert(record);const bytes=readFileSync(path.join(source,name));assert.equal(bytes.length,record.bytes);assert.equal(sha(bytes),record.sha256);}
const unit=path.join(directory,'ownership.c'),binary=path.join(directory,'ownership');writeFileSync(unit,original+'\n'+fixture);
console.log('Selected ownership fixture state:',directory);
run(compiler,['-isysroot',sdk,'-I',source,'-std=gnu11','-O3','-ffast-math','-g','-mcpu=native','-UNDEBUG',unit,...objects.map(name=>path.join(source,name)),'-lm','-pthread','-framework','Foundation','-framework','Metal','-o',binary]);
for(const mode of ['--foreign','--foreign-initialized','--stale','--ticket-exhaustion']){
 const result=spawnSync(binary,[mode],{env,cwd:source,encoding:'utf8',timeout:90000,maxBuffer:1<<20});
 writeFileSync(path.join(directory,mode+'-stdout.log'),result.stdout??'');writeFileSync(path.join(directory,mode+'-stderr.log'),result.stderr??'');
 assert(!result.error&&!result.signal,'Ownership fixture crash/deadline is not acceptance');assert.equal(result.status,0,result.stderr);console.log(result.stdout.trim());
}
assert.deepEqual(verifyDs4SourceBuild(config),selected);assert.equal(readFileSync(path.join(source,'ds4.c'),'utf8'),original);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);
console.log(JSON.stringify({directory,build_receipt_sha256:args[4],fixture_sha256:sha(fixture),binary_sha256:sha(readFileSync(binary)),source_modified_for_test:false,private_ticket_counter_boundary:true,genuine_tensor_and_event:true,copied_actual_job_tickets:true,empty_invalid_model_payload:true,model_opened:false,native_inference:false,native_authority:false,all_backend_terminality:false}));
