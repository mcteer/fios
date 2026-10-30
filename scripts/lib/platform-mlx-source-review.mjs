// Private development input verification, never installed/native authority.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,lstatSync,realpathSync,readdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const sha=b=>createHash('sha256').update(b).digest('hex');
// Parsing this metadata cannot load a library or construct native authority.
export function parseMlxSourceReview(data,expected){
 assert(Buffer.isBuffer(data)&&data.length>0&&data.length<=1<<20&&typeof expected==='string'&&/^[0-9a-f]{64}$/.test(expected));
 assert.equal(sha(data),expected);const receipt=JSON.parse(data);
 assert(Buffer.from(JSON.stringify(receipt)+'\n').equals(data),'Noncanonical/duplicate JSON refused');
 const fields=['version','purpose','activation','installed','native_authority','all_backend_terminality','native_inference','scope','features','loader_fixture_sha256','pins','patch_sha256','declared_sources','cmake_sha256','metal_cpp_zip_sha256','metal_driver_sha256','metal_version','sdk','files'];
 assert.deepEqual(Object.keys(receipt).sort(),fields.sort());
 assert.equal(receipt.version,1);assert.equal(receipt.purpose,'private_mlx_source_dependency_review');
 for(const key of ['activation','installed','native_authority','all_backend_terminality','native_inference'])assert.equal(receipt[key],false);
 assert.equal(receipt.scope,'reviewed_patch_and_declared_dependencies_not_whole_native_provenance');
 assert.deepEqual(receipt.features,{safetensors:true,gguf:false,cpu:true,metal:true,metal_jit:true});
 const pins={mlx:'64ea011cb65f14d9ce2737e60db9a4ae91ed7441',json:'9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03',fmt:'407c905e45ad75fc29bf0f9bb7c5c2fd3475976f'};
 assert.deepEqual(receipt.pins,pins);
 assert.equal(receipt.cmake_sha256,'08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490');
 assert.equal(receipt.metal_cpp_zip_sha256,'4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4');
 const versions={'27.0':'32023.921','27.2':'32023.922'};assert(typeof receipt.sdk==='string'&&versions[receipt.sdk]&&typeof receipt.metal_version==='string'&&receipt.metal_version.length<4096&&receipt.metal_version.startsWith('Apple metal version '+versions[receipt.sdk]+' '));
 for(const key of ['patch_sha256','metal_driver_sha256','loader_fixture_sha256'])assert(typeof receipt[key]==='string'&&/^[0-9a-f]{64}$/.test(receipt[key]));
 const paths=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
 assert.deepEqual(Object.keys(receipt.declared_sources).sort(),paths);
 for(const value of Object.values(receipt.declared_sources))assert(typeof value==='string'&&/^[0-9a-f]{64}$/.test(value));
 assert.deepEqual(Object.keys(receipt.files).sort(),['libjaccl.dylib','libmlx.dylib','mlx.metallib']);
 for(const value of Object.values(receipt.files)){
  assert.deepEqual(Object.keys(value).sort(),['bytes','sha256']);
  assert(Number.isSafeInteger(value.bytes)&&value.bytes>0&&value.bytes<=256<<20&&typeof value.sha256==='string'&&/^[0-9a-f]{64}$/.test(value.sha256));
 }
 return receipt;
}
export function verifyMlxSourceReview(document,expected,source){
 assert(process.platform==='darwin'&&process.getuid()>0&&path.isAbsolute(document)&&typeof expected==='string'&&/^[0-9a-f]{64}$/.test(expected));
 assert.equal(realpathSync(document),document);assert.equal(realpathSync(source),source);
 const parent=path.dirname(document);
 for(const directory of [parent,source]){const s=lstatSync(directory);assert(directory.startsWith('/private/tmp/')&&s.isDirectory()&&!s.isSymbolicLink()&&s.uid===process.getuid()&&(s.mode&0o022)===0);}
 assert.equal(lstatSync(parent).mode&0o077,0);
 function bytes(file,max){const s=lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<=max);return readFileSync(file);}
 const data=bytes(document,1<<20);const receipt=parseMlxSourceReview(data,expected);
 assert.deepEqual(readdirSync(parent).sort(),['candidate.json','libjaccl.dylib','libmlx.dylib','mlx.metallib']);
 assert.deepEqual(Object.keys(receipt.files).sort(),['libjaccl.dylib','libmlx.dylib','mlx.metallib']);
 const libraries={};for(const [name,identity]of Object.entries(receipt.files)){const file=path.join(parent,name),data=bytes(file,256<<20);assert.equal(data.length,identity.bytes);assert.equal(sha(data),identity.sha256);libraries[name]=file;}
 const env={PATH:'/usr/bin:/bin',HOME:parent,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
 const git=(...args)=>execFileSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...args],{env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
 const paths=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
 assert.equal(git('rev-parse','HEAD').trim(),receipt.pins.mlx);
 assert.deepEqual(git('status','--porcelain','--untracked-files=all','--ignored=matching').trimEnd().split('\n'),paths.map(file=>' M '+file));
 const patches=['mlx-64ea011-shared-event-custody.patch','mlx-64ea011-uncertainty-diagnostics.patch'].map(name=>readFileSync(path.join(root,'platform/studio/native',name),'utf8'));
 const patch=patches.find(value=>sha(value)===receipt.patch_sha256);assert(patch,'Unreviewed source dependency patch');
 assert.equal(sha(readFileSync(path.join(root,'platform/studio/native/mlx_safetensors_source_test.cpp'))),receipt.loader_fixture_sha256);
 assert.equal(sha(patch),receipt.patch_sha256);assert.equal(git('diff','--no-ext-diff','--no-textconv','HEAD','--',...paths),patch);
 assert.deepEqual(Object.keys(receipt.declared_sources).sort(),paths);
 for(const name of paths)assert.equal(sha(bytes(path.join(source,name),8<<20)),receipt.declared_sources[name]);
 return {libraries,source,receipt_sha256:expected,patch_sha256:receipt.patch_sha256,sdk:receipt.sdk,library_inputs:receipt.files,features:receipt.features,loader_fixture_sha256:receipt.loader_fixture_sha256,source_fixture_only:true,native_authority:false};
}
