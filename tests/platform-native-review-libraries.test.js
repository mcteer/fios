import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeReviewLibraryAliases,nativeReviewMaximumBytes} from '../scripts/lib/platform-native-review.mjs';
const ids=()=>Object.fromEntries(['libmlx.dylib','libmlxc.dylib','libjaccl.dylib','libwebp.dylib','libsharpyuv.dylib','libllama.dylib'].map(name=>[name,'@rpath/'+name]));
test('private review aliases bind to the supplied libraries exact versioned identities',()=>{
 const original={...ids(),'libwebp.dylib':'@rpath/libwebp.7.dylib','libsharpyuv.dylib':'@rpath/libsharpyuv.0.dylib'};
 const aliases=nativeReviewLibraryAliases(original);
 assert.deepEqual(aliases,{'@rpath/libwebp.7.dylib':'@rpath/libwebp.dylib','@rpath/libsharpyuv.0.dylib':'@rpath/libsharpyuv.dylib'});
 assert(Object.isFrozen(aliases));assert.equal(original['libwebp.dylib'],'@rpath/libwebp.7.dylib');
});
test('canonical, unrelated and unmatched versions cannot supply alias mappings',()=>{
 assert.deepEqual(nativeReviewLibraryAliases(ids()),{});
 assert.deepEqual(nativeReviewLibraryAliases({...ids(),'libwebp.dylib':'@rpath/libwebp.8.dylib','libsharpyuv.dylib':'@rpath/libsharpyuv.1.dylib'}),{});
 assert.deepEqual(nativeReviewLibraryAliases({...ids(),'libmlx.dylib':'@rpath/libwebp.7.dylib'}),{});
 assert.deepEqual(nativeReviewLibraryAliases({...ids(),'libwebp.dylib':'/unreviewed/libwebp.7.dylib'}),{});
 assert.throws(()=>nativeReviewLibraryAliases({...ids(),'extra.dylib':'@rpath/extra.dylib'}));
 assert.throws(()=>nativeReviewLibraryAliases({...ids(),'libwebp.dylib':null}));
});
test('current private artifact byte bound stays separate from historical source reviews',()=>{
 assert.equal(nativeReviewMaximumBytes({native_base:'4e231ceebe63308cc038117d40b9f9b64bd0372e'}),384*2**20);
 for(const inputs of [undefined,{}, {native_base:'046b647686419df06c6c7132fb1d15d76185c3e5'},
  {native_base:'unknown',artifact_byte_limit:2**30}])assert.equal(nativeReviewMaximumBytes(inputs),256*2**20);
});
