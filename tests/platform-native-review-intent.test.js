import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeReviewIntent} from '../scripts/lib/platform-native-review-intent.mjs';
const digest='a'.repeat(64);
test('native source planning and empty checks never request inference',()=>{
 assert.deepEqual(nativeReviewIntent(['--plan','--capsule','/private/capsule','--sha256',digest,'--output','/private/plan.json']),{mode:'plan',inferenceRequested:false});
 assert.deepEqual(nativeReviewIntent(['--check','--plan','/private/plan.json','--sha256',digest]),{mode:'check',inferenceRequested:false});
});
test('a native source run requires its separate explicit inference opt-in',()=>{
 assert.throws(()=>nativeReviewIntent(['--run','--plan','/private/plan.json','--sha256',digest]));
 assert.throws(()=>nativeReviewIntent(['--run','--plan','/private/plan.json','--sha256',digest,'--force']));
 assert.deepEqual(nativeReviewIntent(['--run','--plan','/private/plan.json','--sha256',digest,'--allow-native-inference']),{mode:'run',inferenceRequested:true});
});
test('operator/model/endpoint overrides cannot expand the fixed native review case',()=>{
 for(const tail of [['--model','other/model'],['--endpoint','http://peer.invalid'],['--role','operator'],['--allow-native-inference']])assert.throws(()=>nativeReviewIntent(['--check','--plan','/private/plan.json','--sha256',digest,...tail]));
 assert.throws(()=>nativeReviewIntent(['--check','--plan','relative.json','--sha256',digest]));
 assert.throws(()=>nativeReviewIntent(['--check','--plan','/private/plan.json','--sha256','self-claimed']));
});
