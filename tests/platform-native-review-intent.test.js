import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {nativeReviewIntent,nativeReviewHTTPFailure,nativeReviewJSON,nativeReviewActivity,nativeReviewModelInputs,nativeReviewLineage} from '../scripts/lib/platform-native-review-intent.mjs';
test('native review JSON is bounded while reading, before parsing',async()=>{
 assert.deepEqual(await nativeReviewJSON(new Response('{"ok":true}'),11),{ok:true});
 await assert.rejects(nativeReviewJSON(new Response('{"ok":true}'),10),/response limit/);
 await assert.rejects(nativeReviewJSON(new Response('not JSON')));
});
test('partial native phase observations reject incoherence, replay and foreign instances',()=>{
 const v={schema_version:1,coverage:'unknown',observer_included:true,source_instance:'a'.repeat(32),sample_sequence:2,owned_requests:3,ingress:1,preparing:1,active:1,responding:0,uncertain:false};
 const r=nativeReviewActivity(v,'a'.repeat(32),1);assert.equal(r.preparing,1);assert.equal(r.active,1);assert.equal(r.uncertain,false);
 for(const bad of [{coverage:'all_clients'},{observer_included:false},{sample_sequence:1},{owned_requests:2},{active:-1},{ingress:257},{sample_sequence:Number.MAX_SAFE_INTEGER+1},{uncertain:null},{source_instance:'b'.repeat(32)}])assert.throws(()=>nativeReviewActivity({...v,...bad},'a'.repeat(32),1));
 for(const source_instance of [['a'.repeat(32)],'0'.repeat(32),null])assert.throws(()=>nativeReviewActivity({...v,source_instance}));
});
test('native review failures retain only fixed diagnostic categories',()=>{
 const hash=s=>createHash('sha256').update(s).digest('hex');
 assert.deepEqual(nativeReviewHTTPFailure(500,{error:{type:'model_load_failed',message:'Model load failed: AccessDenied'}}),{http_status:500,error_message_sha256:hash('Model load failed: AccessDenied'),error_type:'model_load_failed',load_error:'AccessDenied'});
 for(const error of [{type:'secret',message:'Model load failed: Secret'},{type:'secret',message:'/private/credentials'},{type:'secret',message:'generated prose'}])assert.deepEqual(nativeReviewHTTPFailure(500,{error}),{http_status:500,error_message_sha256:hash(error.message)});
});
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

test('source model preparation refuses a declared SDK without selected-format support',()=>{
 nativeReviewModelInputs({});
 nativeReviewModelInputs({mlx_source_dependency:{source_fixture_only:true,native_authority:false,features:{safetensors:true}}});
 for(const dependency of [{},{source_fixture_only:true,native_authority:false},{source_fixture_only:true,native_authority:false,features:{safetensors:false}},{source_fixture_only:true,native_authority:true,features:{safetensors:true}},{source_fixture_only:true,native_authority:false,features:{safetensors:'true'}}])assert.throws(()=>nativeReviewModelInputs({mlx_source_dependency:dependency}));
});

test('same-model pair is an explicit fixed scenario, not a model or budget override',()=>{
 const base=['--plan','--capsule','/private/capsule','--sha256','a'.repeat(64),'--output','/private/plan'];
 assert.deepEqual(nativeReviewIntent([...base,'--scenario','same-model-pair']),{mode:'plan',inferenceRequested:false,scenario:'same-model-pair'});
 assert.deepEqual(nativeReviewIntent(['--run','--plan','/private/plan','--sha256','a'.repeat(64),'--allow-native-inference','--scenario','same-model-pair']),{mode:'run',inferenceRequested:true,scenario:'same-model-pair'});
 for(const tail of [['--scenario','other-model'],['--scenario','same-model-pair','--model','other'],['--scenario','same-model-pair','--scenario','same-model-pair'],['--model-posts','99']])assert.throws(()=>nativeReviewIntent([...base,...tail]));
 assert.throws(()=>nativeReviewIntent(['--run','--plan','/private/plan','--sha256','a'.repeat(64),'--scenario','same-model-pair']));
});

test('readonly lineage frames bind source/request and missing remains uncertain',()=>{
 const instance='a'.repeat(32),correlation='b'.repeat(64);
 const frame=()=>{const b=Buffer.alloc(112);b.write('FIP9');b[4]=1;b[6]=1;Buffer.from(instance,'hex').copy(b,8);Buffer.from(correlation,'hex').copy(b,24);b.writeBigUInt64BE(10n,56);b.writeBigUInt64BE(5n,64);b.writeBigUInt64BE(3n,72);b.writeUInt32BE(2,80);b.writeUInt32BE(1,88);b.writeUInt32BE(1,92);return b;};
 assert.deepEqual(nativeReviewLineage(frame(),instance,correlation,9),{sequence:10,found:true,uncertain:false,root_sequence:'5',references:3,owners:2,ingress:0,preparing:1,active:1,responding:0});
 const missing=frame();missing[6]=0;missing[7]=1;missing.fill(0,64);assert.equal(nativeReviewLineage(missing,instance,correlation).uncertain,true);
 const broken=[b=>b[6]=2,b=>b[5]=3,b=>b[100]=1,b=>b.writeUInt32BE(3,80),b=>b.writeBigUInt64BE(9007199254740992n,56),b=>b.writeBigUInt64BE(0n,56)];
 for(const change of broken){const b=frame();change(b);assert.throws(()=>nativeReviewLineage(b,instance,correlation));}
 assert.throws(()=>nativeReviewLineage(frame(),'c'.repeat(32),correlation));assert.throws(()=>nativeReviewLineage(frame(),instance,'d'.repeat(64)));
 assert.throws(()=>nativeReviewLineage(frame(),instance,correlation,10));assert.throws(()=>nativeReviewLineage(frame(),instance,correlation,-1));
 missing[7]=0;assert.throws(()=>nativeReviewLineage(missing,instance,correlation));
});
