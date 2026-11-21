import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeReviewIntent,nativeReviewHTTPFailure} from '../scripts/lib/platform-native-review-intent.mjs';

test('ordinary single-image scenario retains the fixed model experiment commands',()=>{
 const sha='a'.repeat(64),suffix=['--scenario','single-image'];
 assert.deepEqual(nativeReviewIntent(['--plan','--capsule','/private/capsule','--sha256',sha,'--output','/private/plan',...suffix]),{mode:'plan',inferenceRequested:false,scenario:'single-image'});
 assert.deepEqual(nativeReviewIntent(['--check','--plan','/private/plan','--sha256',sha,...suffix]),{mode:'check',inferenceRequested:false,scenario:'single-image'});
 assert.deepEqual(nativeReviewIntent(['--run','--plan','/private/plan','--sha256',sha,'--allow-native-inference',...suffix]),{mode:'run',inferenceRequested:true,scenario:'single-image'});
});

test('ordinary unavailable vision reply has a fixed functional diagnostic',()=>{
 const message='This model is serving without its vision tower (--no-vision, no vision weights, or on the Neural Engine); image/video content is not supported';
 const result=nativeReviewHTTPFailure(400,{error:{type:'invalid_request_error',message}});
 assert.equal(result.modality_error,'vision_unavailable');
 assert.equal(result.http_status,400);assert.equal(result.error_type,'invalid_request_error');
});
