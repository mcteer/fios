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
 const outcome={scope:'full_ds4_initializer_and_known_keepalive_only',build_receipt_sha256:args[4],fixture_sha256:sha(fixture),binary_sha256:sha(readFileSync(binary)),original_full_shader_library:true,model_opened:false,native_inference:false,installed:false,native_authority:false,all_backend_terminality:false,directory};
 writeFileSync(path.join(directory,'result.json'),JSON.stringify(outcome)+'\n',{mode:0o400});console.log(JSON.stringify(outcome));
}catch(error){console.error('Full-module fixture state retained:',directory);throw error;}
