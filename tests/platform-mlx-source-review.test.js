import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {parseMlxSourceReview} from '../scripts/lib/platform-mlx-source-review.mjs';
// Metadata fixtures only: no library, SDK object or source build is substituted.
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const paths=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
const fixture=()=>({version:1,purpose:'private_mlx_source_dependency_review',activation:false,installed:false,native_authority:false,all_backend_terminality:false,native_inference:false,
 scope:'reviewed_patch_and_declared_dependencies_not_whole_native_provenance',features:{safetensors:true,gguf:false,cpu:true,metal:true,metal_jit:true},loader_fixture_sha256:'f'.repeat(64),pins:{mlx:'64ea011cb65f14d9ce2737e60db9a4ae91ed7441',json:'9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03',fmt:'407c905e45ad75fc29bf0f9bb7c5c2fd3475976f'},patch_sha256:'a'.repeat(64),declared_sources:Object.fromEntries(paths.map(p=>[p,'b'.repeat(64)])),cmake_sha256:'08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490',metal_cpp_zip_sha256:'4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4',metal_driver_sha256:'c'.repeat(64),metal_version:'Apple metal version 32023.922 (fixture metadata)',sdk:'27.2',files:{'libjaccl.dylib':{bytes:1,sha256:'f'.repeat(64)},'libmlx.dylib':{bytes:1,sha256:'d'.repeat(64)},'mlx.metallib':{bytes:2,sha256:'e'.repeat(64)}}});
const parse=value=>{const bytes=Buffer.from(JSON.stringify(value)+'\n');return parseMlxSourceReview(bytes,hash(bytes));};
test('MLX source metadata preserves explicit zero authority and declared-input scope',()=>{
 const value=parse(fixture());assert.equal(value.activation,false);assert.equal(value.native_authority,false);assert.equal(value.all_backend_terminality,false);
 assert.equal(value.scope,'reviewed_patch_and_declared_dependencies_not_whole_native_provenance');
});
test('a recomputed metadata hash cannot claim installation, inference or terminal authority',()=>{
 for(const field of ['activation','installed','native_authority','all_backend_terminality','native_inference'])for(const bad of [true,0,null,'false'])assert.throws(()=>parse({...fixture(),[field]:bad}));
 assert.throws(()=>parse({...fixture(),features:{...fixture().features,safetensors:false}}));
 for(const patch of [{version:2},{purpose:'installed_release'},{scope:'whole_native_provenance'},{command:'/bin/sh'}])assert.throws(()=>parse({...fixture(),...patch}));
});
test('MLX dependency metadata refuses duplicate JSON and digest mismatch',()=>{
 const bytes=Buffer.from(JSON.stringify(fixture())+'\n');assert.throws(()=>parseMlxSourceReview(bytes,'0'.repeat(64)));
 for(const text of [bytes.toString().replace('"version":1','"version":1,"version":1'),bytes.toString()+'\n']){
  const duplicate=Buffer.from(text);assert.throws(()=>parseMlxSourceReview(duplicate,hash(duplicate)));
 }
});
test('MLX metadata cannot select paths, extra inputs or unbounded library payloads',()=>{
 for(const bytes of [0,-1,256*2**20+1,Number.MAX_SAFE_INTEGER+1,'1',true,null]){
  const value=fixture();value.files['libmlx.dylib'].bytes=bytes;assert.throws(()=>parse(value));
 }
 for(const change of [v=>v.files['../libmlx.dylib']=v.files['libmlx.dylib'],v=>v.files['libmlx.dylib'].path='/tmp/other',v=>delete v.declared_sources[paths[0]],v=>v.declared_sources['extra.cpp']='f'.repeat(64)]){
  const value=fixture();change(value);assert.throws(()=>parse(value));
 }
});
test('MLX metadata requires pinned dependencies and reviewed compiler/SDK pairing',()=>{
 const value=fixture();value.pins.mlx='0'.repeat(40);assert.throws(()=>parse(value));
 for(const patch of [{sdk:'99.0'},{sdk:'27.0'},{metal_driver_sha256:'not a digest'},{metal_driver_sha256:['c'.repeat(64)]},{sdk:['27.2']},{cmake_sha256:'0'.repeat(64)}])assert.throws(()=>parse({...fixture(),...patch}));
});
