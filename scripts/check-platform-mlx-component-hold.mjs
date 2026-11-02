#!/usr/bin/env node
// Finite ordinary source build/lifecycle only. No historical mutation, fault,
// counter-boundary campaign, model, native server or installed operation.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,lstatSync,realpathSync,copyFileSync,chmodSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {homedir} from 'node:os';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
const metalOwnersIndex=args.indexOf('--request-metal-owners'),requestMetalOwners=metalOwnersIndex>=0;
if(requestMetalOwners){assert.equal(args.lastIndexOf('--request-metal-owners'),metalOwnersIndex);args.splice(metalOwnersIndex,1);}
const ownersIndex=args.indexOf('--request-host-owners'),requestHostOwners=ownersIndex>=0||requestMetalOwners;
if(ownersIndex>=0){assert.equal(args.lastIndexOf('--request-host-owners'),ownersIndex);args.splice(ownersIndex,1);}
assert(process.platform==='darwin'&&process.getuid()>0);
assert(args.length===13&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--cmake'&&args[5]==='--json-source'&&args[7]==='--fmt-source'&&args[9]==='--metal-cpp-zip'&&args[11]==='--developer-dir',
 'Usage: --isolated --source ABS --cmake ABS --json-source ABS --fmt-source ABS --metal-cpp-zip ABS --developer-dir ABS');
const [source,cmake,json,fmt,metalZIP,developer]=[2,4,6,8,10,12].map(i=>{assert(args[i].startsWith('/'));return realpathSync(args[i]);});
const directory=mkdtempSync('/private/tmp/fios-009-mlx-component-build-');
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:homedir(),LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer,
 GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:900000,maxBuffer:16<<20,...options});
const git=(where,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',where,...argv]);
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
function bytes(file,maximum=256<<20){const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=maximum);return readFileSync(file);}
const sha=file=>digest(bytes(file));
const pins={mlx:'64ea011cb65f14d9ce2737e60db9a4ae91ed7441',json:'9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03',fmt:'407c905e45ad75fc29bf0f9bb7c5c2fd3475976f'};
for(const path of [source,json,fmt]){const info=lstatSync(path);assert(path.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);}
const clean=(path,pin)=>{assert.equal(git(path,'rev-parse','HEAD').trim(),pin);assert.equal(git(path,'status','--porcelain','--untracked-files=all','--ignored=matching').trim(),'');};
clean(json,pins.json);clean(fmt,pins.fmt);assert.equal(git(source,'rev-parse','HEAD').trim(),pins.mlx);
assert.equal(sha(cmake),'08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490');
assert.equal(sha(metalZIP),'4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4');
const sdk=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim();
const sdkPath=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim();
const metal=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','metal']).trim());
run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',metal]);
const metalVersion=run('/usr/bin/xcrun',['--sdk','macosx','metal','--version']).trim();
const versions={'27.0':'32023.921','27.2':'32023.922'};assert(versions[sdk]&&metalVersion.startsWith('Apple metal version '+versions[sdk]+' '));
const paths=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
const patchFile=join(root,'platform/studio/native',requestMetalOwners?'mlx-64ea011-request-metal-owners.patch':requestHostOwners?'mlx-64ea011-request-host-owners.patch':'mlx-64ea011-source-component-hold.patch'),patch=bytes(patchFile),patchSHA=digest(patch);
assert.equal(git(source,'diff','--no-ext-diff','--no-textconv','HEAD','--',...paths),patch.toString());
assert.deepEqual(git(source,'status','--porcelain','--untracked-files=all','--ignored=matching').trimEnd().split('\n'),paths.map(path=>' M '+path));
const fixture=join(root,'platform/studio/native/mlx_source_component_hold_test.cpp'),fixtureSHA=sha(fixture);
const loader=join(root,'platform/studio/native/mlx_safetensors_source_test.cpp'),loaderSHA=sha(loader);
const checkout=join(directory,'source'),build=join(directory,'build');
run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',source,checkout]);
git(checkout,'checkout','--quiet','--detach',pins.mlx);git(checkout,'apply','--check',patchFile);git(checkout,'apply',patchFile);
run('/usr/bin/unzip',['-q',metalZIP,'-d',join(directory,'headers')]);
const headers=join(directory,'headers/metal-cpp');
run(cmake,['-S',checkout,'-B',build,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_C_COMPILER=/usr/bin/clang','-DCMAKE_CXX_COMPILER=/usr/bin/clang++','-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET=27.0',`-DCMAKE_OSX_SYSROOT=${sdkPath}`,'-DBUILD_SHARED_LIBS=ON','-DMLX_BUILD_CPU=ON','-DMLX_BUILD_METAL=ON','-DMLX_BUILD_CUDA=OFF','-DMLX_BUILD_TESTS=OFF','-DMLX_BUILD_EXAMPLES=OFF','-DMLX_BUILD_BENCHMARKS=OFF','-DMLX_BUILD_PYTHON_BINDINGS=OFF','-DMLX_BUILD_GGUF=OFF','-DMLX_BUILD_SAFETENSORS=ON','-DMLX_USE_CCACHE=OFF','-DMLX_METAL_JIT=ON','-DFETCHCONTENT_FULLY_DISCONNECTED=ON',`-DFETCHCONTENT_SOURCE_DIR_JSON=${json}`,`-DFETCHCONTENT_SOURCE_DIR_FMT=${fmt}`,`-DFETCHCONTENT_SOURCE_DIR_METAL_CPP=${headers}`,'-DJSON_BuildTests=OFF','-DJSON_Install=OFF','-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF']);
run(cmake,['--build',build,'--target','mlx','--parallel','2']);
const library=join(build,'libmlx.dylib');
function compile(input,output,optimize){run('/usr/bin/clang++',['-std=c++20',optimize,'-UNDEBUG','-isysroot',sdkPath,'-I',checkout,'-I',headers,input,library,`-Wl,-rpath,${build}`,'-framework','Metal','-framework','Foundation','-o',output]);}
for(const [mode,optimize] of [['debug','-O0'],['optimized','-O2']]){
 const output=join(directory,'fixture-'+mode);compile(fixture,output,optimize);
 const log=run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',output],{timeout:20000,maxBuffer:4096});
 assert(log.includes('PASS: genuine CPU work refuses atomic source-component hold'));assert(log.includes('PASS: genuine stream cleanup publishes sticky atomic source uncertainty'));console.log(mode+': '+log.trim());
}
const loaderBinary=join(directory,'safetensors-fixture');compile(loader,loaderBinary,'-O2');
assert(run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',loaderBinary,join(directory,'scalar.safetensors')],{timeout:20000,maxBuffer:4096}).includes('PASS: genuine CPU scalar safetensors roundtrip'));
assert.equal(git(checkout,'diff','--no-ext-diff','--no-textconv','HEAD','--',...paths),patch.toString());
assert.equal(sha(patchFile),patchSHA);assert.equal(sha(fixture),fixtureSHA);assert.equal(sha(loader),loaderSHA);clean(json,pins.json);clean(fmt,pins.fmt);
const output=join(directory,'sdk');mkdirSync(output,{mode:0o700});
const files={};
for(const [name,input] of [['libmlx.dylib',library],['libjaccl.dylib',join(build,'jaccl/libjaccl.dylib')],['mlx.metallib',join(build,'mlx/backend/metal/kernels/mlx.metallib')]]){
 const data=bytes(input),target=join(output,name);copyFileSync(input,target);chmodSync(target,0o400);assert.equal(sha(target),digest(data));files[name]={bytes:data.length,sha256:digest(data)};
}
const receipt={version:1,purpose:'private_mlx_source_dependency_review',activation:false,installed:false,native_authority:false,all_backend_terminality:false,native_inference:false,
 scope:'reviewed_patch_and_declared_dependencies_not_whole_native_provenance',features:{safetensors:true,gguf:false,cpu:true,metal:true,metal_jit:true},loader_fixture_sha256:loaderSHA,pins,patch_sha256:patchSHA,
 declared_sources:Object.fromEntries(paths.map(path=>[path,sha(join(checkout,path))])),cmake_sha256:sha(cmake),metal_cpp_zip_sha256:sha(metalZIP),metal_driver_sha256:sha(metal),metal_version:metalVersion,sdk,files};
const review=Buffer.from(JSON.stringify(receipt)+'\n');writeFileSync(join(output,'candidate.json'),review,{mode:0o400,flag:'wx'});
const result={ok:true,directory,request_host_owners:requestHostOwners,request_metal_owners:requestMetalOwners,dependency_review:{directory:output,receipt_sha256:digest(review)},fixture_sha256:fixtureSHA,patch_sha256:patchSHA,source_component_hold:'atomic_partial_only',source_fixture_only:true,native_authority:false,all_backend_terminality:false,installed:false,native_inference:false,models:0};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(result)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(result));
