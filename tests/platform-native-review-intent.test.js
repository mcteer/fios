import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {nativeReviewIntent,nativeReviewHTTPFailure,nativeReviewJSON,nativeReviewActivity,nativeReviewModelInputs,nativeReviewLineage,nativeReviewComponents,nativeReviewHTTPStream,nativeReviewHTTPStreamEvent,nativeReviewAudioInput} from '../scripts/lib/platform-native-review-intent.mjs';

test('model-free SDK compositions cannot enter model prerequisites through legacy metadata',()=>{
 assert.throws(()=>nativeReviewModelInputs({model_effects:'forbidden'}),/model-free/);
 assert.throws(()=>nativeReviewModelInputs({model_effects:'permitted'}),/Unknown/);
 assert.throws(()=>nativeReviewModelInputs({source_sdk_residency_refresh_observation_version:1,source_sdk_residency_refresh_enrollment_refusal_version:1}),/SDK dependency declaration/);
 assert.throws(()=>nativeReviewModelInputs({source_sdk_residency_refresh_observation_version:2,source_sdk_residency_refresh_enrollment_refusal_version:1,model_effects:'forbidden'}),/Unsupported/);
});
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
 assert.throws(()=>nativeReviewModelInputs({provider_source_fixture:true}),/model-free/);
 nativeReviewModelInputs({provider_source_fixture:false});
 assert.throws(()=>nativeReviewModelInputs({mlx_source_dependency:{source_fixture_only:true,native_authority:false,features:{safetensors:true}}}),/C\+\+/);
 for(const dependency of [{},{source_fixture_only:true,native_authority:false},{source_fixture_only:true,native_authority:false,features:{safetensors:false}},{source_fixture_only:true,native_authority:true,features:{safetensors:true}},{source_fixture_only:true,native_authority:false,features:{safetensors:'true'}}])assert.throws(()=>nativeReviewModelInputs({mlx_source_dependency:dependency}));
});

test('same-model pair is an explicit fixed scenario, not a model or budget override',()=>{
 const base=['--plan','--capsule','/private/capsule','--sha256','a'.repeat(64),'--output','/private/plan'];
 assert.deepEqual(nativeReviewIntent([...base,'--scenario','same-model-pair']),{mode:'plan',inferenceRequested:false,scenario:'same-model-pair'});
 assert.deepEqual(nativeReviewIntent(['--run','--plan','/private/plan','--sha256','a'.repeat(64),'--allow-native-inference','--scenario','same-model-pair']),{mode:'run',inferenceRequested:true,scenario:'same-model-pair'});
 for(const tail of [['--scenario','other-model'],['--scenario','same-model-pair','--model','other'],['--scenario','same-model-pair','--scenario','same-model-pair'],['--model-posts','99']])assert.throws(()=>nativeReviewIntent([...base,...tail]));
 assert.throws(()=>nativeReviewIntent(['--run','--plan','/private/plan','--sha256','a'.repeat(64),'--scenario','same-model-pair']));
});

test('ordinary cancellation is a fixed single-model source scenario',()=>{
 const base=['--plan','--capsule','/private/capsule','--sha256','a'.repeat(64),'--output','/private/plan'];
 for(const scenario of ['cancel-request','cancel-response']){
  assert.deepEqual(nativeReviewIntent([...base,'--scenario',scenario]),{mode:'plan',inferenceRequested:false,scenario});
  assert.deepEqual(nativeReviewIntent(['--run','--plan','/private/plan','--sha256','a'.repeat(64),'--allow-native-inference','--scenario',scenario]),{mode:'run',inferenceRequested:true,scenario});
 }
});

test('cancelled older request followed by success is an explicit fixed scenario',()=>{
 const scenario='cancel-then-success',base=['--plan','--capsule','/private/capsule','--sha256','a'.repeat(64),'--output','/private/plan'];
 assert.deepEqual(nativeReviewIntent([...base,'--scenario',scenario]),{mode:'plan',inferenceRequested:false,scenario});
 assert.deepEqual(nativeReviewIntent(['--check','--plan','/private/plan','--sha256','a'.repeat(64),'--scenario',scenario]),{mode:'check',inferenceRequested:false,scenario});
 assert.deepEqual(nativeReviewIntent(['--run','--plan','/private/plan','--sha256','a'.repeat(64),'--allow-native-inference','--scenario',scenario]),{mode:'run',inferenceRequested:true,scenario});
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

test('source components remain partial even when epochs agree and counters are zero',()=>{
 const instance='a'.repeat(32);
 const flags={enabled:true,uncertain:false,held:false};
 const fixture=()=>({source_instance:instance,sample_sequence:1,components:{schema_version:1,scope:'partial_mlx_source_components',coverage:'unknown',authority:false,available:true,coherent:true,stream:{epoch:2,registered:0,pending:0,...flags,shared:false},host:{epoch:2,pending:0,active:0,...flags},metal:{epoch:2,pending:0,captures:0,...flags}}});
 const value=nativeReviewComponents(fixture(),instance);assert.equal(value.coverage,'unknown');assert.equal(value.authority,false);
 const absent=fixture();absent.components={schema_version:1,scope:'partial_mlx_source_components',coverage:'unknown',authority:false,available:false};assert.equal(nativeReviewComponents(absent,instance).available,false);
 const diagnostic=fixture();diagnostic.components.schema_version=2;diagnostic.components.uncertainty_site=17;assert.equal(nativeReviewComponents(diagnostic,instance).uncertainty_site,17);
 for(const bad of [-1,65,'17',true])assert.throws(()=>nativeReviewComponents({...diagnostic,components:{...diagnostic.components,uncertainty_site:bad}},instance));
 const changing=fixture();changing.components.host.epoch=3;changing.components.coherent=false;assert.equal(nativeReviewComponents(changing,instance).coherent,false);
 for(const change of [v=>v.components.authority=true,v=>v.components.coverage='all_clients',v=>v.components.host.active=-1,v=>v.components.metal.pending=2147483648,v=>v.components.stream.shared=0,v=>v.components.host.epoch=3,v=>v.components.extra=0]){const b=fixture();change(b);assert.throws(()=>nativeReviewComponents(b,instance));}
 assert.throws(()=>nativeReviewComponents(fixture(),'b'.repeat(32)));assert.throws(()=>nativeReviewComponents(fixture(),instance,1));
});

test('backend source fences retain independent unknown coverage and unavailable values',()=>{
 const instance='a'.repeat(32);
 const mlx={schema_version:1,scope:'partial_mlx_source_components',coverage:'unknown',authority:false,available:false};
 const components={schema_version:3,scope:'independent_partial_backend_fences',coverage:'unknown',authority:false,mlx,mimo_warm_uncertain:true,ds4_metal_uncertainty:1};
 const packet={source_instance:instance,sample_sequence:1,components};
 const parsed=nativeReviewComponents(packet,instance);
 assert.equal(parsed.available,false);assert.equal(parsed.authority,false);
 assert.equal(parsed.component_envelope_schema_version,3);
 assert.deepEqual(parsed.backend_fences,{scope:'independent_partial_backend_fences',coverage:'unknown',authority:false,mimo_warm_uncertain:true,ds4_metal_uncertainty:1});
 const absent=nativeReviewComponents({...packet,components:{...components,mimo_warm_uncertain:null,ds4_metal_uncertainty:null}},instance);
 assert.equal(absent.backend_fences.mimo_warm_uncertain,null);assert.equal(absent.backend_fences.ds4_metal_uncertainty,null);
 const cold=nativeReviewComponents({...packet,components:{...components,mimo_warm_uncertain:false,ds4_metal_uncertainty:0}},instance);
 assert.equal(cold.available,false);assert.equal(cold.authority,false);assert.equal(cold.backend_fences.coverage,'unknown');
});

test('backend source fence schema refuses invented coverage, coercion and recursive envelopes',()=>{
 const instance='a'.repeat(32);
 const base={schema_version:3,scope:'independent_partial_backend_fences',coverage:'unknown',authority:false,mlx:{schema_version:1,scope:'partial_mlx_source_components',coverage:'unknown',authority:false,available:false},mimo_warm_uncertain:false,ds4_metal_uncertainty:0};
 const parse=components=>nativeReviewComponents({source_instance:instance,sample_sequence:1,components},instance);
 for(const patch of [{authority:true},{coverage:'all_clients'},{scope:'all_backends'},{coherent:true},{mimo_warm_uncertain:0},{mimo_warm_uncertain:'false'},{ds4_metal_uncertainty:-1},{ds4_metal_uncertainty:32},{ds4_metal_uncertainty:true},{ds4_metal_uncertainty:'1'},{ds4_metal_uncertainty:1.5}])assert.throws(()=>parse({...base,...patch}));
 assert.throws(()=>parse({...base,mlx:base}));
 assert.throws(()=>parse({...base,mlx:{...base.mlx,authority:true}}));
});

test('backend fence envelope4 observes host uncertainty separately from Metal and older envelopes',()=>{
 const instance='a'.repeat(32);
 const state={schema_version:4,scope:'independent_partial_backend_fences',coverage:'unknown',authority:false,mlx:{schema_version:1,scope:'partial_mlx_source_components',coverage:'unknown',authority:false,available:false},mimo_warm_uncertain:false,ds4_metal_uncertainty:0,ds4_host_uncertainty:3};
 const parse=components=>nativeReviewComponents({source_instance:instance,sample_sequence:1,components},instance);
 const value=parse(state);assert.equal(value.component_envelope_schema_version,4);assert.equal(value.available,false);
 assert.equal(value.backend_fences.ds4_host_uncertainty,3);assert.equal(value.backend_fences.ds4_metal_uncertainty,0);
 assert.equal(value.backend_fences.coverage,'unknown');assert.equal(value.backend_fences.authority,false);
 assert.equal(parse({...state,ds4_host_uncertainty:null}).backend_fences.ds4_host_uncertainty,null);
 for(const ds4_host_uncertainty of [0,1,2,4,7])assert.equal(parse({...state,ds4_host_uncertainty}).backend_fences.ds4_host_uncertainty,ds4_host_uncertainty);
 for(const ds4_host_uncertainty of [-1,8,true,'1',1.5])assert.throws(()=>parse({...state,ds4_host_uncertainty}));
 const old={...state,schema_version:3};delete old.ds4_host_uncertainty;
 assert.equal(Object.hasOwn(parse(old).backend_fences,'ds4_host_uncertainty'),false);
 assert.throws(()=>parse({...old,schema_version:4}));assert.throws(()=>parse({...state,schema_version:3}));
});

test('source journal correlation keeps planning/check model-free and run explicit',()=>{
 const digest='a'.repeat(64);
 for(const scenario of ['journal-correlation','journal-same-model-pair']){
  assert.deepEqual(nativeReviewIntent(['--plan','--capsule','/private/capsule','--sha256',digest,'--output','/private/plan','--scenario',scenario]),{mode:'plan',inferenceRequested:false,scenario});
  assert.deepEqual(nativeReviewIntent(['--check','--plan','/private/plan','--sha256',digest,'--scenario',scenario]),{mode:'check',inferenceRequested:false,scenario});
  assert.throws(()=>nativeReviewIntent(['--run','--plan','/private/plan','--sha256',digest,'--scenario',scenario]));
  assert.deepEqual(nativeReviewIntent(['--run','--plan','/private/plan','--sha256',digest,'--allow-native-inference','--scenario',scenario]),{mode:'run',inferenceRequested:true,scenario});
 }
});

// Metadata fixtures only: neither these declarations nor this parser grant
// native admission, mapped-runtime provenance or inference authorization.
test('source SDK model preparation requires the matched C++ compatibility record',()=>{
 const dependency={source_fixture_only:true,native_authority:false,sdk:'27.2',features:{safetensors:true}};
 const sdk='/fixture/SDK',root='/fixture/repo';
 const files=[sdk+'/usr/lib/libc++.1.tbd',...['__config','__config_site','cstdint','memory','functional','optional','stdexcept','typeinfo','exception'].map(name=>sdk+'/usr/include/c++/v1/'+name),root+'/scripts/lib/platform-native-system-cxx.mjs',root+'/platform/studio/native/mlx_cxx_callback_error_test.cpp'];
 const cxx={version:1,sdk:'27.2',callback_error_controls:['Debug','ReleaseFast'],scope:'selected_SDK_stub_and_header_inputs_not_mapped_OS_runtime_attestation',declared_inputs:Object.fromEntries(files.map(name=>[name,'a'.repeat(64)]))};
 nativeReviewModelInputs({mlx_source_dependency:dependency,system_cxx:cxx});
 for(const key of ['incremental_patch_sha256','command_status_patch_sha256','capture_refusal_patch_sha256','observed_source_patch_sha256']){
  assert.throws(()=>nativeReviewModelInputs({mlx_source_dependency:{...dependency,[key]:'b'.repeat(64)},system_cxx:cxx}),/C\+\+/);
 }

 for(const system_cxx of [null,{}, {...cxx,version:2},{...cxx,sdk:'27.0'},{...cxx,callback_error_controls:[]},{...cxx,callback_error_controls:['Debug','Debug']},{...cxx,scope:'mapped_runtime_attestation'},{...cxx,declared_inputs:{}},{...cxx,declared_inputs:{...cxx.declared_inputs,[files[0]]:'invalid'}}]){
  assert.throws(()=>nativeReviewModelInputs({mlx_source_dependency:dependency,system_cxx}),/C\+\+/);
 }
});

function currentCxxMetadata(){
 const digest=file=>createHash('sha256').update(readFileSync(new URL('../'+file,import.meta.url))).digest('hex');
 const source='/private/tmp/fixture/current-source',sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk';
 const inputs=[sdk+'/usr/lib/libc++.1.tbd',...['__config','__config_site','cstdint','memory','functional','optional','stdexcept','typeinfo','exception'].map(name=>sdk+'/usr/include/c++/v1/'+name)];
 const patch=digest('platform/studio/native/mlx-c69303b-owner-uncertainty.patch');
 const cxx={version:1,scope:'current_build_helper_CPU_callback_compatibility_not_native_authority',source,
  library_sha256:'b'.repeat(64),config_sha256:'a'.repeat(64),helper_sha256:digest('platform/studio/native/current_system_cxx_build.zig.fixture'),
  fixture_sha256:digest('platform/studio/native/mlx_cxx_callback_error_test.cpp'),runner_sha256:digest('scripts/check-platform-current-cxx.mjs'),sdk:'27.2',
  selected_sdk_inputs:Object.fromEntries(inputs.map(file=>[file,'a'.repeat(64)])),source_patch_sha256:patch,
  results:['Debug','ReleaseFast'].map(mode=>({mode,build_status:0,build_signal:null,run_status:0,run_signal:null,passed:true})),
  models:0,inference:false,source_fixture_only:true,installed:false,activation:false,native_authority:false,whole_native_provenance:false,declared_inputs_unchanged:true};
 const dependency={source_fixture_only:true,native_authority:false,sdk:'27.2',source:source+'/lib/mlx-src',patch_sha256:patch,
  library_inputs:{'libmlx.dylib':{sha256:cxx.library_sha256}},features:{safetensors:true}};
 return {native_base:'4e231ceebe63308cc038117d40b9f9b64bd0372e',mlx_source_dependency:dependency,system_cxx:cxx};
}
test('current source CPU compatibility metadata is accepted only for its own dependency generation',()=>{
 const value=currentCxxMetadata();nativeReviewModelInputs(value);
 assert.throws(()=>nativeReviewModelInputs({...value,native_base:'046b647686419df06c6c7132fb1d15d76185c3e5'}),/C\+\+/);
 assert.throws(()=>nativeReviewModelInputs({...value,mlx_source_dependency:{...value.mlx_source_dependency,source:'/private/tmp/other/lib/mlx-src'}}),/C\+\+/);
 assert.throws(()=>nativeReviewModelInputs({...value,mlx_source_dependency:{...value.mlx_source_dependency,library_inputs:{'libmlx.dylib':{sha256:'c'.repeat(64)}}}}),/C\+\+/);
});
test('current CPU compatibility declarations cannot promote authority or omit a successful mode',()=>{
 for(const change of [v=>v.system_cxx.native_authority=true,v=>v.system_cxx.activation=true,v=>v.system_cxx.installed=true,
  v=>v.system_cxx.whole_native_provenance=true,v=>v.system_cxx.models=1,v=>v.system_cxx.inference=true,
  v=>v.system_cxx.declared_inputs_unchanged=false,v=>v.system_cxx.enrolled=true,v=>v.system_cxx.version=2,
  v=>v.system_cxx.helper_sha256='a'.repeat(64),v=>v.system_cxx.runner_sha256='a'.repeat(64),
  v=>v.system_cxx.fixture_sha256='a'.repeat(64),v=>v.system_cxx.source_patch_sha256='a'.repeat(64),
  v=>v.system_cxx.selected_sdk_inputs={},v=>v.system_cxx.results.pop(),v=>v.system_cxx.results[1].passed=false,
  v=>v.system_cxx.results[1].mode='Debug',v=>v.system_cxx.results[0].run_signal='SIGABRT',v=>v.system_cxx.results[0].build_status=null]){
  const value=currentCxxMetadata();change(value);assert.throws(()=>nativeReviewModelInputs(value),/C\+\+/);
 }
});

function extendedCurrentCxxMetadata(stage=3){
 const value=currentCxxMetadata(),cxx=value.system_cxx,dependency=value.mlx_source_dependency;
 const digest=file=>createHash('sha256').update(readFileSync(new URL('../'+file,import.meta.url))).digest('hex');
 cxx.sdk_source='/private/tmp/fixture/extended-sdk-source';cxx.sdk_library='/private/tmp/fixture/extended-sdk-build/lib/libmlx.dylib';
 cxx.incremental_patch_sha256=digest('platform/studio/native/mlx-c69303b-metal-callback-fence.patch');
 cxx.observed_source_patch_sha256='c'.repeat(64);
 dependency.source=cxx.sdk_source;dependency.incremental_patch_sha256=cxx.incremental_patch_sha256;dependency.observed_source_patch_sha256=cxx.observed_source_patch_sha256;
 value.native_cxx_config_sha256=cxx.config_sha256;
 if(stage>=2){cxx.command_status_patch_sha256=digest('platform/studio/native/mlx-c69303b-metal-callback-status.patch');dependency.command_status_patch_sha256=cxx.command_status_patch_sha256;}
 if(stage>=3){cxx.capture_refusal_patch_sha256=digest('platform/studio/native/mlx-c69303b-owner-capture-refusal.patch');dependency.capture_refusal_patch_sha256=cxx.capture_refusal_patch_sha256;}
 return value;
}
test('extended current C++ CPU receipts require exact selected SDK composition and app config binding',()=>{
 for(const stage of [1,2,3])nativeReviewModelInputs(extendedCurrentCxxMetadata(stage));
});
test('event SDK CPU compatibility remains separate from model prerequisites',()=>{
 for(const base of ['3736ed55f81c6cf0966a0f0dc7265e783655d244','4e231ceebe63308cc038117d40b9f9b64bd0372e']){
  const value=extendedCurrentCxxMetadata();value.native_base=base;
  value.system_cxx.scope='current_build_helper_event_SDK_CPU_compatibility_not_native_authority';
  value.system_cxx.request_event_patches=Object.fromEntries(
   ['mlx-c69303b-host-request-events.patch','mlx-c69303b-metal-request-events.patch'].map(name=>
    [name,createHash('sha256').update(readFileSync(new URL('../platform/studio/native/'+name,import.meta.url))).digest('hex')]));
  assert.throws(()=>nativeReviewModelInputs(value),/C\+\+/);
 }
});
test('extended CPU compatibility refuses missing reordered or unmatched declarations without authority promotion',()=>{
 for(const change of [v=>delete v.native_cxx_config_sha256,v=>v.native_cxx_config_sha256='b'.repeat(64),
  v=>delete v.system_cxx.sdk_source,v=>v.system_cxx.sdk_library='relative/libmlx.dylib',v=>v.system_cxx.sdk_source='/private/tmp/other-sdk',
  v=>delete v.mlx_source_dependency.incremental_patch_sha256,v=>v.mlx_source_dependency.observed_source_patch_sha256='d'.repeat(64),
  v=>v.system_cxx.incremental_patch_sha256='a'.repeat(64),v=>v.system_cxx.command_status_patch_sha256='a'.repeat(64),
  v=>v.system_cxx.capture_refusal_patch_sha256='a'.repeat(64),v=>v.mlx_source_dependency.capture_refusal_patch_sha256='a'.repeat(64),
  v=>delete v.system_cxx.command_status_patch_sha256,v=>delete v.system_cxx.incremental_patch_sha256,
  v=>v.system_cxx.native_authority=true,v=>v.system_cxx.installed=true,v=>v.system_cxx.whole_native_provenance=true,
  v=>v.system_cxx.results[1].passed=false,v=>v.system_cxx.enrolled=true]){
  const value=extendedCurrentCxxMetadata();change(value);assert.throws(()=>nativeReviewModelInputs(value),/C\+\+/);
 }
 const canonical=currentCxxMetadata();canonical.mlx_source_dependency.capture_refusal_patch_sha256='a'.repeat(64);
 assert.throws(()=>nativeReviewModelInputs(canonical),/C\+\+/);
});

function eventCompatibilityMetadata(){
 const value=extendedCurrentCxxMetadata(3),cxx=value.system_cxx,dep=value.mlx_source_dependency;
 value.native_base='3736ed55f81c6cf0966a0f0dc7265e783655d244';
 cxx.scope='current_build_helper_event_SDK_CPU_compatibility_not_native_authority';
 cxx.request_event_patches=Object.fromEntries(['mlx-c69303b-host-request-events.patch','mlx-c69303b-metal-request-events.patch'].map(name=>[name,createHash('sha256').update(readFileSync(new URL('../platform/studio/native/'+name,import.meta.url))).digest('hex')]));
 dep.request_event_patches={...cxx.request_event_patches};
 const prefix='/private/tmp/fixture/prefix';cxx.sdk_library=prefix+'/lib/libmlx.dylib';
 const hash=file=>createHash('sha256').update(readFileSync(new URL('../'+file,import.meta.url))).digest('hex');
 dep.c_binding_cpu={scope:'actual_MLXC_CPU_graph_error_cleanup_selected_C_headers_and_mapped_library_identity_not_native_authority',prefix,
  inputs:{[prefix+'/lib/libmlx.dylib']:cxx.library_sha256,[prefix+'/lib/libmlxc.dylib']:'c'.repeat(64),
   '/fixture/platform/studio/native/current_mlxc_cpu_test.c':hash('platform/studio/native/current_mlxc_cpu_test.c'),
   '/fixture/scripts/check-platform-current-mlxc.py':hash('scripts/check-platform-current-mlxc.py'),
   [prefix+'/include/mlx/c/mlx.h']:'a'.repeat(64),'/fixture/usr/bin/clang':'a'.repeat(64),'/fixture/usr/lib/libSystem.tbd':'a'.repeat(64)},
  records:['Debug','Optimized'].flatMap(mode=>['compile','runtime'].map(stage=>({mode,stage,arguments:stage==='compile'?['/fixture/usr/bin/clang','-std=c11','-UNDEBUG','-target','arm64-apple-macosx26.2','-isysroot','/fixture','-I',prefix+'/include',mode==='Debug'?'-O0':'-O2','/fixture/platform/studio/native/current_mlxc_cpu_test.c',prefix+'/lib/libmlxc.dylib',prefix+'/lib/libmlx.dylib','-Wl,-rpath,'+prefix+'/lib','-o','/private/tmp/fixture/control/'+mode]:['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)','/private/tmp/fixture/control/'+mode,prefix+'/lib/libmlx.dylib',prefix+'/lib/libmlxc.dylib'],status:0,passed:true,log_sha256:'a'.repeat(64)}))),
  models:0,inference:false,GPU_dispatch:false,installed:false,native_authority:false,whole_native_provenance:false,inputs_unchanged:true};
 value.runtime_inputs={'libmlx.dylib':{sha256:cxx.library_sha256,bytes:1},'libmlxc.dylib':{sha256:'c'.repeat(64),bytes:1}};
 return value;
}
test('event SDK compatibility requires matching C ABI controls and runtime pair without granting authority',()=>{
 nativeReviewModelInputs(eventCompatibilityMetadata());
 for(const change of [v=>delete v.mlx_source_dependency.c_binding_cpu,
  v=>delete v.mlx_source_dependency.c_binding_cpu.inputs['/private/tmp/fixture/prefix/include/mlx/c/mlx.h'],
  v=>v.mlx_source_dependency.c_binding_cpu.records[1].arguments.pop(),
  v=>v.mlx_source_dependency.c_binding_cpu.records[0].arguments[9]='-O2',
  v=>v.mlx_source_dependency.c_binding_cpu.records[1].arguments[2]='(version 1)(allow default)',
  v=>v.mlx_source_dependency.c_binding_cpu.records[2].arguments[10]='/fixture/other.c',
  v=>v.mlx_source_dependency.c_binding_cpu.records[0].log_sha256=['a'.repeat(64)],v=>v.native_base='4e231ceebe63308cc038117d40b9f9b64bd0372e',
  v=>delete v.mlx_source_dependency.request_event_patches,v=>v.system_cxx.request_event_patches['mlx-c69303b-host-request-events.patch']='a'.repeat(64),
  v=>v.runtime_inputs['libmlxc.dylib'].sha256='d'.repeat(64),v=>v.runtime_inputs['libmlx.dylib'].bytes=0,
  v=>v.mlx_source_dependency.c_binding_cpu.native_authority=true,v=>v.mlx_source_dependency.c_binding_cpu.inference=true,
  v=>v.mlx_source_dependency.c_binding_cpu.inputs_unchanged=false,v=>v.mlx_source_dependency.c_binding_cpu.records.pop(),
  v=>v.mlx_source_dependency.c_binding_cpu.records[1].passed=false,v=>v.mlx_source_dependency.c_binding_cpu.records[0].mode='Optimized',
  v=>v.mlx_source_dependency.c_binding_cpu.inputs['/fixture/scripts/check-platform-current-mlxc.py']='a'.repeat(64),
  v=>v.system_cxx.config_sha256='b'.repeat(64),v=>delete v.system_cxx.capture_refusal_patch_sha256]){
  const value=eventCompatibilityMetadata();change(value);assert.throws(()=>nativeReviewModelInputs(value));
 }
});

test('native HTTP stream fixtures use fixed routes and read ordinary terminal events',()=>{
 const model='fixture/Exact-Model';
 const base=['--plan','--capsule','/private/capsule','--sha256','a'.repeat(64),'--output','/private/plan.json'];
 const fixtures=[
  ['text-completion-stream','/v1/completions','max_tokens',{choices:[{text:'ready'}]},{choices:[],usage:{completion_tokens:2}},false],
  ['messages-stream','/v1/messages','max_tokens',{type:'content_block_delta',delta:{type:'text_delta',text:'ready'}},{type:'message_delta',usage:{output_tokens:2}},true],
  ['responses-stream','/v1/responses','max_output_tokens',{type:'response.output_text.delta',delta:'ready'},{type:'response.completed',response:{usage:{output_tokens:2}}},false],
 ];
 for(const [scenario,route,budget,delta,usage,selfTerminating] of fixtures){
  assert.equal(nativeReviewIntent([...base,'--scenario',scenario]).scenario,scenario);
  const request=nativeReviewHTTPStream(scenario,model,8);
  assert.equal(request.route,route);
  assert.equal(request.body.model,model);
  assert.equal(request.body.stream,true);
  assert.equal(request.body[budget],8);
  assert.deepEqual(nativeReviewHTTPStreamEvent(scenario,delta),{delta:true,tokens:undefined,terminal:false});
  assert.equal(nativeReviewHTTPStreamEvent(scenario,usage).tokens,2);
  assert.equal(nativeReviewHTTPStreamEvent(scenario,{type:'message_stop'}).terminal,selfTerminating);
 }
 assert.equal(nativeReviewHTTPStream('single-model',model,8),null);
});

test('native audio fixture is a fixed quarter-second mono PCM wave',()=>{
 const {wav,sampleRate,samples}=nativeReviewAudioInput();
 assert.equal(wav.toString('ascii',0,4),'RIFF');
 assert.equal(wav.toString('ascii',8,16),'WAVEfmt ');
 assert.equal(wav.readUInt16LE(20),1);
 assert.equal(wav.readUInt16LE(22),1);
 assert.equal(wav.readUInt32LE(24),16000);
 assert.equal(wav.readUInt16LE(34),16);
 assert.equal(samples/sampleRate,0.25);
 assert.equal(wav.readUInt32LE(40),samples*2);
 assert.equal(wav.length,44+samples*2);
 assert.equal(wav.readInt16LE(44),1024);
 assert.equal(wav.readInt16LE(84),-1024);
});
