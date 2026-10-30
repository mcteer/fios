#!/usr/bin/env node
// Explicit model-free full-module fixture; build receipts grant no authority.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,lstatSync,realpathSync,mkdtempSync,mkdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===7&&args[0]==='--isolated'&&args[1]==='--build'&&args[3]==='--sha256'&&args[5]==='--developer-dir');
const document=realpathSync(args[2]),developer=realpathSync(args[6]);assert.equal(document,args[2]);assert.equal(developer,'/Applications/Xcode.app/Contents/Developer');
const parent=path.dirname(document),parentInfo=lstatSync(parent),fileInfo=lstatSync(document);
assert(parent.startsWith('/private/tmp/')&&parentInfo.uid===process.getuid()&&(parentInfo.mode&0o077)===0);
assert(fileInfo.isFile()&&fileInfo.nlink===1&&fileInfo.uid===process.getuid()&&fileInfo.size>0&&fileInfo.size<1<<20);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex'),bytes=readFileSync(document);assert.equal(sha(bytes),args[4]);const receipt=JSON.parse(bytes);
assert(receipt.version===1&&receipt.purpose==='unapproved_ds4_native_source_build'&&receipt.activation===false&&receipt.native_authority===false&&receipt.executed===false&&receipt.installed===false&&receipt.native_inference===false);
assert.equal(receipt.revision,'9139e2ae58a41503968a500f36f75895c1ba63fc');assert.equal(receipt.sdk_version,'27.2');
const source=path.join(parent,'source');assert.equal(path.dirname(receipt.artifact.file),source);assert.equal(realpathSync(source),source);
assert.equal(receipt.patch_sha256,sha(readFileSync(path.join(root,'platform/studio/native/ds4-9139e2a-participant-retirement.patch'))));
const directory=mkdtempSync('/private/tmp/fios-ds4-full-module-'),home=path.join(directory,'home');mkdirSync(home,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:home,TMPDIR:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv)=>execFileSync(file,argv,{env,encoding:'utf8',timeout:30000,maxBuffer:8<<20});
const git=(...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv]);
function fingerprint(file,expected){const s=lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.size===expected.bytes&&s.size<64<<20);assert.equal(sha(readFileSync(file)),expected.sha256);}
function verify(){
 for(const [name,expected]of Object.entries(receipt.declared_sources)){assert(!path.isAbsolute(name)&&!name.split('/').includes('..'));fingerprint(path.join(source,name),expected);}
 for(const [name,expected]of Object.entries(receipt.objects)){assert(/^[a-z0-9_]+\.o$/.test(name));fingerprint(path.join(source,name),expected);}
 fingerprint(receipt.artifact.file,receipt.artifact);
}
try{
 assert.equal(git('rev-parse','HEAD').trim(),receipt.revision);
 const patch=readFileSync(path.join(root,'platform/studio/native/ds4-9139e2a-participant-retirement.patch'),'utf8');
 assert.equal(git('diff','HEAD','--name-only').trim(),'ds4_metal.m');assert.equal(git('diff','--no-ext-diff','HEAD','--','ds4_metal.m'),patch);
 const declared=git('ls-files','-z').split('\0').filter(name=>name==='Makefile'||/\.(?:c|m|h|inc|metal)$/.test(name)).sort();
 assert.deepEqual(Object.keys(receipt.declared_sources).sort(),declared);
 verify();
 assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
 const compiler=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','clang']).trim()),sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
 assert.equal(sha(readFileSync(compiler)),receipt.compiler_sha256);run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',compiler]);
 const fixtureFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4FullModule.m.fixture'),fixture=readFileSync(fixtureFile,'utf8');
 const unit=path.join(directory,'fixture.m'),binary=path.join(directory,'fixture');
 writeFileSync(unit,'#include '+JSON.stringify(path.join(source,'ds4_metal.m'))+'\n'+fixture);
 const objects=['ds4.o','ds4_image.o','ds4_distributed.o','ds4_tp.o','ds4_ssd.o','ds4_layer_pack.o','ds4_engram.o','ds4_gpu_args.o','ds4_help.o'];
 for(const name of objects)assert(receipt.objects[name]);
 run(compiler,['-isysroot',sdk,'-std=gnu11','-fobjc-arc','-O3','-ffast-math','-g','-mcpu=native','-UNDEBUG',unit,...objects.map(name=>path.join(source,name)),'-lm','-pthread','-framework','Foundation','-framework','Metal','-o',binary]);
 // Actual source initializer/full original shader library, no model/session.
 const result=spawnSync(binary,[],{env,cwd:source,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
 writeFileSync(path.join(directory,'stdout.log'),result.stdout??'',{mode:0o600});writeFileSync(path.join(directory,'stderr.log'),result.stderr??'',{mode:0o600});
 assert(!result.error&&!result.signal,'Full-module fixture deadline/crash is not acceptance');assert.equal(result.status,0,result.stderr);
 assert(result.stdout.includes('PASS: complete genuine DS4 module/full original shader initializer'));
 verify();assert.equal(readFileSync(fixtureFile,'utf8'),fixture);assert.equal(sha(readFileSync(document)),args[4]);
 assert.equal(git('diff','--no-ext-diff','HEAD','--','ds4_metal.m'),patch);
 // A second executable injects a wait failure only AFTER actual completion.
 // It exercises genuine pending-list/accounting code, not a fake SDK object.
 const pendingFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4Pending.m.fixture'),pending=readFileSync(pendingFile,'utf8');
 const original=readFileSync(path.join(source,'ds4_metal.m'),'utf8');
 const edge='if (cb.status != MTLCommandBufferStatusCompleted) {\n        fprintf(stderr, "ds4: Metal %s failed: %s\\n",';
 assert.equal(original.split(edge).length,2);
 assert.equal(original.split('if (pthread_join(g_queue_keepalive_thread, NULL) != 0) {').length,2);
 const faultUnit=path.join(directory,'pending.m'),faultBinary=path.join(directory,'pending');
 writeFileSync(faultUnit,'static int fios_private_wait_failure, fios_private_join_failure, fios_private_pread_join_failure;\n'+original.replace(edge,edge.replace('cb.status != MTLCommandBufferStatusCompleted','cb.status != MTLCommandBufferStatusCompleted || fios_private_wait_failure')).replace('if (pthread_join(g_queue_keepalive_thread, NULL) != 0) {','if (pthread_join(g_queue_keepalive_thread, NULL) != 0 || fios_private_join_failure) {').replace('const int rc = pthread_join(g_stream_expert_pread_pool_threads[i], NULL);','const int actual_rc = pthread_join(g_stream_expert_pread_pool_threads[i], NULL); const int rc = actual_rc == 0 && fios_private_pread_join_failure ? EIO : actual_rc;')+'\n'+pending);
 run(compiler,['-isysroot',sdk,'-I',source,'-std=gnu11','-fobjc-arc','-O3','-ffast-math','-g','-mcpu=native','-UNDEBUG',faultUnit,...objects.map(name=>path.join(source,name)),'-lm','-pthread','-framework','Foundation','-framework','Metal','-o',faultBinary]);
 const fault=spawnSync(faultBinary,[],{env,cwd:source,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
 writeFileSync(path.join(directory,'pending-stdout.log'),fault.stdout??'',{mode:0o600});writeFileSync(path.join(directory,'pending-stderr.log'),fault.stderr??'',{mode:0o600});
 assert(!fault.error&&!fault.signal,'Pending fixture deadline/crash is not acceptance');assert.equal(fault.status,0,fault.stderr);
 assert(fault.stdout.includes('PASS: actual completed buffers retained on injected wait failure'));
 const batch=spawnSync(faultBinary,['--batch-cleanup'],{env,cwd:source,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
 writeFileSync(path.join(directory,'batch-stdout.log'),batch.stdout??'',{mode:0o600});writeFileSync(path.join(directory,'batch-stderr.log'),batch.stderr??'',{mode:0o600});
 assert(!batch.error&&!batch.signal,'Batch fixture crash/deadline is not acceptance');assert.equal(batch.status,0,batch.stderr);
 assert(batch.stdout.includes('PASS: real cleanup batch physically completed before injected wait failure'));
 const success=spawnSync(faultBinary,['--batch-success'],{env,cwd:source,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
 writeFileSync(path.join(directory,'batch-success-stdout.log'),success.stdout??'',{mode:0o600});writeFileSync(path.join(directory,'batch-success-stderr.log'),success.stderr??'',{mode:0o600});
 assert(!success.error&&!success.signal,'Successful batch fixture crash/deadline is not acceptance');assert.equal(success.status,0,success.stderr);
 assert(success.stdout.includes('PASS: genuine successful empty batch cleanup'));
 const joined=spawnSync(faultBinary,['--keepalive-cleanup'],{env,cwd:source,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
 writeFileSync(path.join(directory,'keepalive-cleanup-stdout.log'),joined.stdout??'',{mode:0o600});writeFileSync(path.join(directory,'keepalive-cleanup-stderr.log'),joined.stderr??'',{mode:0o600});
 assert(!joined.error&&!joined.signal,'Keepalive cleanup crash/deadline is not acceptance');assert.equal(joined.status,0,joined.stderr);
 assert(joined.stdout.includes('PASS: cleanup retains global resources after actual producer join'));
 const foreign=spawnSync(faultBinary,['--foreign-cleanup'],{env,cwd:source,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
 writeFileSync(path.join(directory,'foreign-cleanup-stdout.log'),foreign.stdout??'',{mode:0o600});writeFileSync(path.join(directory,'foreign-cleanup-stderr.log'),foreign.stderr??'',{mode:0o600});
 assert(!foreign.error&&!foreign.signal,'Foreign cleanup crash/deadline is not acceptance');assert.equal(foreign.status,0,foreign.stderr);
 assert(foreign.stdout.includes('PASS: actual foreign-thread cleanup retains live producer'));
 for(const mode of ['--sealed-pread-dispatch','--ordinary-pread-dispatch','--pread-cleanup','--pread-success']){
 const pread=spawnSync(faultBinary,[mode],{env,cwd:source,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
 writeFileSync(path.join(directory,mode+'-stdout.log'),pread.stdout??'',{mode:0o600});writeFileSync(path.join(directory,mode+'-stderr.log'),pread.stderr??'',{mode:0o600});
 assert(!pread.error&&!pread.signal,'Pread cleanup crash/deadline is not acceptance');assert.equal(pread.status,0,pread.stderr);
 assert(pread.stdout.includes(mode==='--sealed-pread-dispatch'?'PASS: actual exhausted pool refuses alternate read threads':mode==='--ordinary-pread-dispatch'?'PASS: ordinary genuine pool dispatch':mode==='--pread-success'?'PASS: actual cleanup joins both idle pread workers':'PASS: cleanup preserves exact pread vector'));
 }





 verify();assert.equal(readFileSync(pendingFile,'utf8'),pending);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);assert.equal(readFileSync(path.join(source,'ds4_metal.m'),'utf8'),original);
 assert.equal(sha(readFileSync(document)),args[4]);assert.equal(git('diff','--no-ext-diff','HEAD','--','ds4_metal.m'),patch);
 const sequenceFile=path.join(root,'platform/studio/Tests/NativeFixtures/DS4Sequence.m.fixture'),sequence=readFileSync(sequenceFile,'utf8');
 const sequenceUnit=path.join(directory,'sequence.m'),sequenceBinary=path.join(directory,'sequence');
 writeFileSync(sequenceUnit,'#include '+JSON.stringify(path.join(source,'ds4_metal.m'))+'\n'+sequence);
 run(compiler,['-isysroot',sdk,'-std=gnu11','-fobjc-arc','-O3','-ffast-math','-g','-mcpu=native','-UNDEBUG',sequenceUnit,...objects.map(name=>path.join(source,name)),'-lm','-pthread','-framework','Foundation','-framework','Metal','-o',sequenceBinary]);
 for(const mode of ['--counter','--begin','--last']){
 const counter=spawnSync(sequenceBinary,[mode],{env,cwd:source,encoding:'utf8',timeout:10000,maxBuffer:1<<20});
 writeFileSync(path.join(directory,'sequence'+mode+'-stdout.log'),counter.stdout??'',{mode:0o600});writeFileSync(path.join(directory,'sequence'+mode+'-stderr.log'),counter.stderr??'',{mode:0o600});
 assert(!counter.error&&!counter.signal,'Sequence fixture deadline/crash is not acceptance');assert.equal(counter.status,0,counter.stderr);
 assert(counter.stdout.includes('PASS: exhausted actual cache sequence refuses without initialization'));
 }
 verify();assert.equal(readFileSync(sequenceFile,'utf8'),sequence);assert.equal(readFileSync(pendingFile,'utf8'),pending);assert.equal(readFileSync(fixtureFile,'utf8'),fixture);assert.equal(sha(readFileSync(document)),args[4]);assert.equal(git('diff','--no-ext-diff','HEAD','--','ds4_metal.m'),patch);
 const outcome={scope:'full_ds4_initializer_known_keepalive_pending_and_batch_failure_only',build_receipt_sha256:args[4],fixture_sha256:sha(fixture),binary_sha256:sha(readFileSync(binary)),original_full_shader_library:true,sequence_fixture_sha256:sha(sequence),sequence_binary_sha256:sha(readFileSync(sequenceBinary)),pending_fixture_sha256:sha(pending),pending_binary_sha256:sha(readFileSync(faultBinary)),injected_wait_failure_after_real_completion:true,batch_cleanup_failure_retained:true,keepalive_cleanup_failure_retained:true,foreign_cleanup_failure_retained:true,model_opened:false,native_inference:false,installed:false,native_authority:false,all_backend_terminality:false,directory};
 writeFileSync(path.join(directory,'result.json'),JSON.stringify(outcome)+'\n',{mode:0o400});console.log(JSON.stringify(outcome));
}catch(error){console.error('Full-module fixture state retained:',directory);throw error;}
