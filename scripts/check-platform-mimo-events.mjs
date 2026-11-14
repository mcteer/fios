#!/usr/bin/env node
// Genuine source SDK + ORIGINAL MIMO event producer/C ABI and one-scalar graph.
// No model, inference, SDK/module stand-ins, installed writes or lifecycle grant.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync,mkdtempSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import os from 'node:os';import path from 'node:path';import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url)),args=process.argv.slice(2);
const raw=args.at(-1)==='--raw-baseline';if(raw)args.pop();
const keys=['--source','--mimo-source','--mlxc-source','--cmake','--json-source','--fmt-source','--metal-cpp-zip','--developer-dir'];
assert(process.platform==='darwin'&&process.getuid()!==0&&args.length===17&&args[0]==='--isolated'&&keys.every((key,i)=>args[1+i*2]===key&&path.isAbsolute(args[2+i*2])),
 'Use --isolated --source ABS_SHARED_EVENT_CORE --mimo-source ABS_FCB4011 --mlxc-source ABS_56B2 --cmake ABS --json-source ABS --fmt-source ABS --metal-cpp-zip ABS --developer-dir ABS [--raw-baseline]');
const [source,mimo,mlxc,cmake,json,fmt,metalZIP,developer]=keys.map((_,i)=>realpathSync(args[2+i*2]));
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:os.homedir(),LC_ALL:'C',DEVELOPER_DIR:developer,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:900000,maxBuffer:16<<20,...options});
const git=(dir,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',dir,...argv]);
const sha=file=>{const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink());return createHash('sha256').update(readFileSync(file)).digest('hex');};
for(const dir of [source,mimo,mlxc,json,fmt]){const info=lstatSync(dir);assert(dir.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);}
const pins={core:'64ea011cb65f14d9ce2737e60db9a4ae91ed7441',mimo:'fcb4011347ff80eeeb19e2a1f0180e13199c7c8b',mlxc:'56b2d39fc831f2c0eb5bb94d82ef7191f7b31fa6',json:'9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03',fmt:'407c905e45ad75fc29bf0f9bb7c5c2fd3475976f'};
for(const [dir,pin]of [[source,pins.core],[mimo,pins.mimo],[mlxc,pins.mlxc],[json,pins.json],[fmt,pins.fmt]])assert.equal(git(dir,'rev-parse','HEAD').trim(),pin);
for(const dir of [mlxc,json,fmt])assert.equal(git(dir,'status','--porcelain','--untracked-files=all','--ignored=matching').trim(),'');
assert.equal(sha(cmake),'08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490');
assert.equal(sha(metalZIP),'4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4');
const metal=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','metal']).trim());run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',metal]);
const metalVersion=run('/usr/bin/xcrun',['--sdk','macosx','metal','--version']);assert(metalVersion.startsWith('Apple metal version 32023.921 '));assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.0');
const corePatchFile=path.join(root,'platform/studio/native/mlx-64ea011-shared-event-custody.patch'),corePatch=readFileSync(corePatchFile,'utf8'),coreSHA=sha(corePatchFile);
const corePaths=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
assert.equal(git(source,'diff','--',...corePaths),corePatch);assert.deepEqual(git(source,'diff','--name-only').trim().split('\n').sort(),corePaths);
const producerPath='csrc/mlx_event_shim.cpp',producerPatchFile=path.join(root,'platform/studio/native/mlx-stream-fcb4011-event-custody.patch');
const producerPatch=raw?'':readFileSync(producerPatchFile,'utf8'),producerSHA=raw?null:sha(producerPatchFile);
assert.equal(git(mimo,'diff','--',producerPath),producerPatch);assert.equal(git(mimo,'diff','--name-only').trim(),raw?'':producerPath);
const fixture=path.join(root,'platform/studio/native/mimo_event_graph_custody_test.cpp'),fixtureSHA=sha(fixture);
const temporary=mkdtempSync(path.join(os.tmpdir(),'fios-009-mimo-events-'));env.TMPDIR=temporary;let completed=false;
try{
 const checkout=path.join(temporary,'core'),plugin=path.join(temporary,'mimo'),build=path.join(temporary,'build'),binary=path.join(temporary,'fixture');
 for(const [input,output,pin,patch]of [[source,checkout,pins.core,corePatchFile],[mimo,plugin,pins.mimo,raw?null:producerPatchFile]]){run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',input,output]);git(output,'checkout','--quiet','--detach',pin);if(patch){git(output,'apply','--check',patch);git(output,'apply',patch);}}
 run('/usr/bin/unzip',['-q',metalZIP,'-d',path.join(temporary,'headers')]);const headers=path.join(temporary,'headers/metal-cpp');
 console.log(run(cmake,['-S',checkout,'-B',build,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_C_COMPILER=/usr/bin/clang','-DCMAKE_CXX_COMPILER=/usr/bin/clang++','-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET=27.0','-DBUILD_SHARED_LIBS=ON','-DMLX_BUILD_CPU=ON','-DMLX_BUILD_METAL=ON','-DMLX_BUILD_CUDA=OFF','-DMLX_BUILD_TESTS=OFF','-DMLX_BUILD_EXAMPLES=OFF','-DMLX_BUILD_BENCHMARKS=OFF','-DMLX_BUILD_PYTHON_BINDINGS=OFF','-DMLX_BUILD_GGUF=OFF','-DMLX_BUILD_SAFETENSORS=OFF','-DMLX_USE_CCACHE=OFF','-DMLX_METAL_JIT=ON','-DFETCHCONTENT_FULLY_DISCONNECTED=ON',`-DFETCHCONTENT_SOURCE_DIR_JSON=${json}`,`-DFETCHCONTENT_SOURCE_DIR_FMT=${fmt}`,`-DFETCHCONTENT_SOURCE_DIR_METAL_CPP=${headers}`,'-DJSON_BuildTests=OFF','-DJSON_Install=OFF','-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF']));
 console.log(run(cmake,['--build',build,'--target','mlx','--parallel','2']));const library=path.join(build,'libmlx.dylib'),librarySHA=sha(library),producer=path.join(plugin,producerPath);
 const compile=()=>run('/usr/bin/clang++',['-std=c++20','-O2','-UNDEBUG','-I',checkout,'-I',headers,'-I',mlxc,'-I',path.join(plugin,'csrc'),fixture,producer,library,`-Wl,-rpath,${build}`,'-framework','Metal','-framework','Foundation','-o',binary]);
 const execute=expected=>{const result=spawnSync(binary,[],{env,encoding:'utf8',timeout:20000,maxBuffer:1<<20});assert.equal(result.error,undefined);assert.equal(result.signal,null);const log=(result.stdout??'')+(result.stderr??'');assert.equal(result.status,expected,log);if(expected===77)assert(log.includes('MIMO_EVENT_GRAPH_RAW_ESCAPE_OR_UNTRACKED_BUFFER'));console.log(log);};
 compile();execute(raw?77:0);
 if(!raw){
  const original=readFileSync(producer,'utf8');
  for(const [tracked,escaped]of [['    enc.fios_encode_shared_wait(ev_->mtl, value_);','    enc.get_command_buffer()->encodeWait(ev_->mtl, value_);'],['    enc.fios_encode_shared_signal(ev_->mtl, value_);','    enc.get_command_buffer()->encodeSignalEvent(ev_->mtl, value_);']]){assert.equal(original.split(tracked).length,2);writeFileSync(producer,original.replace(tracked,escaped));compile();execute(77);writeFileSync(producer,original);compile();execute(0);}
 }
 assert.equal(sha(library),librarySHA);assert.equal(sha(fixture),fixtureSHA);assert.equal(sha(corePatchFile),coreSHA);if(!raw)assert.equal(sha(producerPatchFile),producerSHA);
 assert.equal(git(checkout,'diff','--',...corePaths),corePatch);assert.equal(git(plugin,'diff','--',producerPath),producerPatch);assert.equal(git(mimo,'diff','--',producerPath),producerPatch);
 for(const dir of [mlxc,json,fmt])assert.equal(git(dir,'status','--porcelain','--untracked-files=all','--ignored=matching').trim(),'');
 console.log(JSON.stringify({scope:'actual_mimo_event_c_abi_one_scalar_alias_graph',expected_raw_runtime_red:raw,all_context_terminality:false,activation:false,pins,core_patch_sha256:coreSHA,producer_patch_sha256:producerSHA,fixture_sha256:fixtureSHA,library_sha256:librarySHA,metal_executable_sha256:sha(metal),metal_version:metalVersion.trim(),sdk:'27.0'}));
 console.log(raw?'PASS: actual ORIGINAL producer raw-escape runtime red77 safely drained; NOT terminal proof':'PASS: actual MIMO one-scalar wait/signal graph and two separately rebuilt raw-escape causal variants, source/library restored; process-life event pool/host-word/raw profiling/model/context/lifecycle acceptance remains open');
 completed=true;
}finally{if(completed)rmSync(temporary,{recursive:true,force:true});else console.error('Failed standalone source/build evidence retained (no application database): '+temporary);}
