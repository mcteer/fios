import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {parseCurrentMlxSourceReview} from '../scripts/lib/platform-current-mlx-source-review.mjs';
const hash=data=>createHash('sha256').update(data).digest('hex');
const paths=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
function receipt(){return {
 version:1,purpose:'private_current_mlx_source_dependency_review',activation:false,installed:false,native_authority:false,all_backend_terminality:false,native_inference:false,
 scope:'reviewed_patch_and_declared_dependencies_not_whole_native_provenance',features:{safetensors:true,gguf:false,cpu:true,metal:true,metal_jit:false},loader_fixture_sha256:'a'.repeat(64),
 pins:{mlx:'c69303b00f5f61860436e832f23fa8c34b96f93a',json:'9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03',fmt:'407c905e45ad75fc29bf0f9bb7c5c2fd3475976f'},patch_sha256:'b'.repeat(64),declared_sources:Object.fromEntries(paths.map(path=>[path,'c'.repeat(64)])),
 cmake_sha256:'08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490',metal_cpp_zip_sha256:'4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4',metal_driver_sha256:'d'.repeat(64),metal_version:'Apple metal version 32023.922 (fixture)',sdk:'27.2',
 files:Object.fromEntries(['libjaccl.dylib','libmlx.dylib','mlx.metallib'].map(path=>[path,{bytes:1,sha256:'e'.repeat(64)}]))
};}
function parse(value){const bytes=Buffer.from(JSON.stringify(value)+'\n');return parseCurrentMlxSourceReview(bytes,hash(bytes));}
test('current dependency metadata stays scoped and carries no native authority',()=>{
 const value=receipt();assert.deepEqual(parse(value),value);
 assert.equal(parse(value).native_authority,false);assert.equal(parse(value).features.metal_jit,false);
});
test('historical source generations cannot satisfy the current dependency receipt',()=>{
 const value=receipt();value.pins.mlx='64ea011cb65f14d9ce2737e60db9a4ae91ed7441';assert.throws(()=>parse(value));
});
test('metadata cannot promote a dependency build to native admission or a different feature set',()=>{
 const value=receipt();value.native_authority=true;assert.throws(()=>parse(value));
 const other=receipt();other.features.metal_jit=true;assert.throws(()=>parse(other));
});
