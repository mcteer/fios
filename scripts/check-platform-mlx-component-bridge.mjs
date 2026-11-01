#!/usr/bin/env node
// Genuine CPU-only partial bridge/source composition. No mutation/fault/
// counter campaign, model, GPU dispatch, native server or installed operation.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync,lstatSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {verifyMlxSourceReview} from './lib/platform-mlx-source-review.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.getuid()>0);
assert(args.length===13&&args[0]==='--isolated');
for(const [i,name] of ['--sdk','--sha256','--source','--mlxc-source','--mlxc-library','--developer-dir'].entries())assert.equal(args[1+i*2],name);
const [document,source,mlxc,mlxcLibrary,developer]=[2,6,8,10,12].map(i=>{assert(args[i].startsWith('/'));return realpathSync(args[i]);});
const sha=path=>{const info=lstatSync(path);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=256<<20);return createHash('sha256').update(readFileSync(path)).digest('hex');};
const proof=verifyMlxSourceReview(document,args[4],source);
assert.equal(proof.patch_sha256,sha(join(root,'platform/studio/native/mlx-64ea011-source-component-hold.patch')));
assert(mlxc.startsWith('/private/tmp/')&&lstatSync(mlxc).isDirectory());
assert.equal(sha(mlxcLibrary),'6b4c9224691c2857cf7d386e75c1247cc6b0a4ae17d6ec6d1b455ec177e9929f');
const directory=mkdtempSync('/private/tmp/fios-009-mlx-component-bridge-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:60000,maxBuffer:1<<20,...options});
const git=(...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',mlxc,...argv]);
function checkMLXC(){assert.equal(git('rev-parse','HEAD').trim(),'56b2d39fc831f2c0eb5bb94d82ef7191f7b31fa6');assert.equal(git('status','--porcelain','--untracked-files=all','--ignored=matching').trim(),'');}
checkMLXC();
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),proof.sdk);
const sdk=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim();
const native=join(root,'platform/studio/native');
const files=['device_owner_barrier.cpp','device_owner_barrier.h','source_mlx_participants.cpp','mlx_source_component_bridge_test.cpp','device_owner_barrier_test.cpp'];
const inputs=Object.fromEntries(files.map(name=>[name,sha(join(native,name))]));
const shim=join(directory,'participants.cpp');
writeFileSync(shim,'#define FIOS_SOURCE_COMPONENT_HOLD 1\n#include '+JSON.stringify(join(source,'mlx/stream.h'))+'\n#include '+JSON.stringify(join(native,'device_owner_barrier.h'))+'\n'+readFileSync(join(native,'source_mlx_participants.cpp'),'utf8'),{mode:0o600});
for(const [mode,optimize] of [['debug','-O0'],['optimized','-O2']]){
 for(const linked of [true,false]){
  const binary=join(directory,mode+(linked?'-composed':'-bridge-only'));
  run('/usr/bin/clang++',['-std=c++20',optimize,'-UNDEBUG','-isysroot',sdk,'-I',source,'-I',mlxc,'-I',native,
   join(native,'device_owner_barrier.cpp'),join(native,linked?'mlx_source_component_bridge_test.cpp':'device_owner_barrier_test.cpp'),...(linked?[shim]:[]),
   proof.libraries['libmlx.dylib'],mlxcLibrary,`-Wl,-rpath,${resolve(proof.libraries['libmlx.dylib'],'..')}`,`-Wl,-rpath,${resolve(mlxcLibrary,'..')}`,'-framework','Metal','-framework','Foundation','-o',binary]);
  const log=run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary,...(linked?[]:['--registry-hold'])],{timeout:20000,maxBuffer:4096});
  assert(log.includes(linked?'PASS: actual owned CPU synchronization seals tracked source gates afterward':'PASS: owned-wrapper registry hold blocks creation'));
  console.log(mode+(linked?' composed: ':' default bridge: ')+log.trim());
 }
}
for(const name of files)assert.equal(sha(join(native,name)),inputs[name]);checkMLXC();
assert.deepEqual(verifyMlxSourceReview(document,args[4],source),proof);
assert.equal(sha(mlxcLibrary),'6b4c9224691c2857cf7d386e75c1247cc6b0a4ae17d6ec6d1b455ec177e9929f');
const result={ok:true,directory,scope:'declared_bridge_source_sdk_and_mlx_c_inputs_only',inputs,sdk_receipt_sha256:proof.receipt_sha256,mlxc_source:'56b2d39fc831f2c0eb5bb94d82ef7191f7b31fa6',mlxc_library_sha256:sha(mlxcLibrary),modes:['debug','optimized'],actual_composed_processes:2,actual_default_bridge_processes:2,source_component_hold:'partial_only',native_authority:false,all_backend_terminality:false,installed:false,native_inference:false,models:0};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(result)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(result));
