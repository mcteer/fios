import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {nativeReviewModelSupports} from '../scripts/lib/platform-native-review-intent.mjs';

test('the actual cold Gemma catalog supports text and reports image unavailable',()=>{
 const model=JSON.parse(readFileSync(new URL('./fixtures/platform/native-gemma-text-catalog.json',import.meta.url)));
 const catalog={data:[model]};
 assert.equal(nativeReviewModelSupports(catalog,model.id,'text'),true);
 assert.equal(nativeReviewModelSupports(catalog,model.id,'image'),false);
 assert.equal(model.loaded,false);
});
