// Parsing an operator command is not native admission or installation authority.
import assert from 'node:assert/strict';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
const currentCxxScope='current_build_helper_CPU_callback_compatibility_not_native_authority';
const reviewDigest=relative=>createHash('sha256').update(readFileSync(new URL('../../'+relative,import.meta.url))).digest('hex');
// Current checker result metadata remains distinct from the historical graph
// declaration. Parsing either record grants no native or installed authority.
function currentCxxInputs(inputs,dependency,cxx,message){
 const fields=['version','scope','source','library_sha256','config_sha256','helper_sha256','fixture_sha256','runner_sha256','sdk',
  'selected_sdk_inputs','source_patch_sha256','results','models','inference','source_fixture_only','installed','activation',
  'native_authority','whole_native_provenance','declared_inputs_unchanged'];
 assert.deepEqual(Object.keys(cxx).sort(),fields.sort(),message);
 assert(cxx.version===1&&cxx.sdk==='27.2'&&dependency.sdk===cxx.sdk&&inputs.native_base==='4e231ceebe63308cc038117d40b9f9b64bd0372e',message);
 assert(cxx.source_fixture_only===true&&cxx.declared_inputs_unchanged===true&&cxx.models===0,message);
 for(const key of ['inference','installed','activation','native_authority','whole_native_provenance'])assert(cxx[key]===false,message);
 assert(typeof cxx.source==='string'&&cxx.source.startsWith('/private/tmp/')&&path.isAbsolute(cxx.source)&&
  path.normalize(cxx.source)===cxx.source&&!cxx.source.includes('\0')&&cxx.source.length<=4096&&
  dependency.source===path.join(cxx.source,'lib/mlx-src'),message);
 for(const key of ['library_sha256','config_sha256','helper_sha256','fixture_sha256','runner_sha256','source_patch_sha256'])assert(typeof cxx[key]==='string'&&/^[a-f0-9]{64}$/.test(cxx[key]),message);
 assert(cxx.library_sha256===dependency.library_inputs?.['libmlx.dylib']?.sha256&&cxx.source_patch_sha256===dependency.patch_sha256,message);
 for(const [key,file]of [['helper_sha256','platform/studio/native/current_system_cxx_build.zig.fixture'],
  ['fixture_sha256','platform/studio/native/mlx_cxx_callback_error_test.cpp'],['runner_sha256','scripts/check-platform-current-cxx.mjs'],
  ['source_patch_sha256','platform/studio/native/mlx-c69303b-owner-uncertainty.patch']])assert(cxx[key]===reviewDigest(file),message);
 assert(cxx.selected_sdk_inputs&&typeof cxx.selected_sdk_inputs==='object'&&!Array.isArray(cxx.selected_sdk_inputs),message);
 const files=Object.keys(cxx.selected_sdk_inputs),suffix='/usr/lib/libc++.1.tbd',stubs=files.filter(file=>file.endsWith(suffix));
 assert(files.length===10&&stubs.length===1&&files.every(file=>path.isAbsolute(file)&&path.normalize(file)===file&&!file.includes('\0')&&file.length<=4096&&/^[a-f0-9]{64}$/.test(cxx.selected_sdk_inputs[file])),message);
 const sdk=stubs[0].slice(0,-suffix.length);
 assert(['__config','__config_site','cstdint','memory','functional','optional','stdexcept','typeinfo','exception'].every(name=>files.includes(sdk+'/usr/include/c++/v1/'+name)),message);
 assert(Array.isArray(cxx.results)&&cxx.results.length===2,message);
 for(const [index,result]of cxx.results.entries()){
  assert(result&&typeof result==='object'&&!Array.isArray(result),message);
  assert.deepEqual(Object.keys(result).sort(),['mode','build_status','build_signal','run_status','run_signal','passed'].sort(),message);
  assert(result.mode===['Debug','ReleaseFast'][index]&&result.build_status===0&&result.run_status===0&&
   result.build_signal===null&&result.run_signal===null&&result.passed===true,message);
 }
}
// An optional source dependency must declare the selected format before any
// model effect. This is a refusal prerequisite, never an admission grant.
export function nativeReviewModelInputs(inputs){
 assert(inputs?.provider_source_fixture!==true,'Provider source fixture is model-free');
 const dependency=inputs?.mlx_source_dependency;
 if(dependency!==undefined&&dependency!==null){
  assert(dependency.source_fixture_only===true&&dependency.native_authority===false&&dependency.features?.safetensors===true,'Source SDK lacks required Safetensors support');
  const cxx=inputs.system_cxx,message='Source SDK lacks matched C++ runtime compatibility';
  if(cxx&&typeof cxx==='object'&&!Array.isArray(cxx)&&cxx.scope===currentCxxScope){currentCxxInputs(inputs,dependency,cxx,message);return;}
  assert(cxx&&typeof cxx==='object'&&!Array.isArray(cxx)&&cxx.version===1&&cxx.sdk===dependency.sdk&&cxx.sdk==='27.2'&&
   JSON.stringify(cxx.callback_error_controls)===JSON.stringify(['Debug','ReleaseFast'])&&
   cxx.scope==='selected_SDK_stub_and_header_inputs_not_mapped_OS_runtime_attestation',message);
  assert(cxx.declared_inputs&&typeof cxx.declared_inputs==='object'&&!Array.isArray(cxx.declared_inputs),message);
  const files=Object.keys(cxx.declared_inputs),suffix='/usr/lib/libc++.1.tbd',stubs=files.filter(file=>file.endsWith(suffix));
  assert(files.length===12&&stubs.length===1&&files.every(file=>path.isAbsolute(file)&&path.normalize(file)===file&&!file.includes('\0')&&/^[a-f0-9]{64}$/.test(cxx.declared_inputs[file])),message);
  const sdk=stubs[0].slice(0,-suffix.length);
  assert(['__config','__config_site','cstdint','memory','functional','optional','stdexcept','typeinfo','exception'].every(name=>files.includes(sdk+'/usr/include/c++/v1/'+name))&&
   files.some(file=>file.endsWith('/scripts/lib/platform-native-system-cxx.mjs'))&&files.some(file=>file.endsWith('/platform/studio/native/mlx_cxx_callback_error_test.cpp')),message);

 }
}
// Fixed experiment capability check only; not native admission/ownership proof.
export function nativeReviewModelSupports(catalog,id,modality){
 const model=catalog.data.find(entry=>entry.id===id);
 return Array.isArray(model?.input_modalities)&&model.input_modalities.includes(modality);
}
export async function nativeReviewJSON(response, maximum=65536) {
 let size=0;const chunks=[];
 for await(const chunk of response.body){size+=chunk.length;assert(size<=maximum,'Native review response limit');chunks.push(Buffer.from(chunk));}
 return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
// Partial request-phase metadata; observer ownership is included. No idle,
// terminal, all-client coverage or admission decision can be derived here.
export function nativeReviewActivity(value, instance, previousSequence=0) {
 assert(value?.coverage==='unknown'&&value.observer_included===true&&value.schema_version===1);
 assert(typeof value.source_instance==='string'&&/^[a-f0-9]{32}$/.test(value.source_instance)&&value.source_instance!=='0'.repeat(32)&&(!instance||value.source_instance===instance));
 assert(Number.isSafeInteger(value.sample_sequence)&&value.sample_sequence>previousSequence);
 const counts=Object.fromEntries(['ingress','preparing','active','responding'].map(k=>{assert(Number.isInteger(value[k])&&value[k]>=0&&value[k]<=256);return [k,value[k]];}));
 assert(Number.isInteger(value.owned_requests)&&value.owned_requests<=256&&Object.values(counts).reduce((a,b)=>a+b,0)===value.owned_requests&&typeof value.uncertain==='boolean');
 return {instance:value.source_instance,sequence:value.sample_sequence,...counts,uncertain:value.uncertain};
}
// Subdomain observations only, including explicit unavailability. Matching
// SDK epochs do not reserve transitions or establish all-context coverage.
export function nativeReviewComponents(value,instance,previous=0){
 const exact=(object,fields)=>{assert(object&&typeof object==='object'&&!Array.isArray(object));assert.deepEqual(Object.keys(object).sort(),[...fields].sort());};
 exact(value,['source_instance','sample_sequence','components']);
 assert(typeof value.source_instance==='string'&&value.source_instance===instance&&/^[a-f0-9]{32}$/.test(instance)&&instance!=='0'.repeat(32));
 assert(Number.isSafeInteger(previous)&&previous>=0&&Number.isSafeInteger(value.sample_sequence)&&value.sample_sequence>0&&value.sample_sequence>previous);
 const state=value.components;
 if([3,4].includes(state?.schema_version)){
  exact(state,['schema_version','scope','coverage','authority','mlx','mimo_warm_uncertain','ds4_metal_uncertainty',...(state.schema_version===4?['ds4_host_uncertainty']:[])]);
  assert(state.scope==='independent_partial_backend_fences'&&state.coverage==='unknown'&&state.authority===false);
  assert(state.mimo_warm_uncertain===null||typeof state.mimo_warm_uncertain==='boolean');
  assert(state.ds4_metal_uncertainty===null||(Number.isInteger(state.ds4_metal_uncertainty)&&state.ds4_metal_uncertainty>=0&&state.ds4_metal_uncertainty<=31));
  if(state.schema_version===4)assert(state.ds4_host_uncertainty===null||(Number.isInteger(state.ds4_host_uncertainty)&&state.ds4_host_uncertainty>=0&&state.ds4_host_uncertainty<=7));
  // Exactly one legacy MLX subdomain, never recursively nested envelopes.
  assert([1,2].includes(state.mlx?.schema_version));
  const mlx=nativeReviewComponents({...value,components:state.mlx},instance,previous);
  return {...mlx,component_envelope_schema_version:state.schema_version,backend_fences:{scope:state.scope,coverage:'unknown',authority:false,
   mimo_warm_uncertain:state.mimo_warm_uncertain,ds4_metal_uncertainty:state.ds4_metal_uncertainty,...(state.schema_version===4?{ds4_host_uncertainty:state.ds4_host_uncertainty}:{})}};
 }
 const base=['schema_version','scope','coverage','authority','available'];
 assert(typeof state?.available==='boolean');exact(state,state.available?[...base,'coherent','stream','host','metal',...(state.schema_version===2?['uncertainty_site']:[])]:base);
 assert([1,2].includes(state.schema_version)&&state.scope==='partial_mlx_source_components'&&state.coverage==='unknown'&&state.authority===false);
 if(!state.available)return {sequence:value.sample_sequence,available:false,authority:false};
 if(state.schema_version===2)assert(state.uncertainty_site===null||(Number.isInteger(state.uncertainty_site)&&state.uncertainty_site>=0&&state.uncertainty_site<=64));
 const domains={stream:{counts:['registered','pending'],flags:['enabled','uncertain','held','shared']},host:{counts:['pending','active'],flags:['enabled','uncertain','held']},metal:{counts:['pending','captures'],flags:['enabled','uncertain','held']}};
 for(const [name,{counts,flags}]of Object.entries(domains)){
  const part=state[name];exact(part,['epoch',...counts,...flags]);
  assert(Number.isSafeInteger(part.epoch)&&part.epoch>=0);for(const key of counts)assert(Number.isInteger(part[key])&&part[key]>=0&&part[key]<=2147483647);
  assert(part.epoch>0);for(const key of flags)assert(typeof part[key]==='boolean');
 }
 assert(typeof state.coherent==='boolean'&&state.coherent===(state.stream.epoch===state.host.epoch&&state.host.epoch===state.metal.epoch));
 return {sequence:value.sample_sequence,...state};
}
// Readonly live correlation metadata, never terminal/not-sent/device proof.
export function nativeReviewLineage(bytes,instance,correlation,previous=0){
 assert(Buffer.isBuffer(bytes)&&bytes.length===112&&bytes.subarray(0,4).toString()==='FIP9'&&bytes[4]===1&&bytes[5]===0&&bytes[6]<=1&&bytes[7]<=1);
 assert(/^[a-f0-9]{32}$/.test(instance)&&instance!=='0'.repeat(32)&&/^[a-f0-9]{64}$/.test(correlation));
 assert(bytes.subarray(8,24).toString('hex')===instance&&bytes.subarray(24,56).toString('hex')===correlation&&bytes.subarray(100).every(b=>b===0));
 const safe=at=>{const n=bytes.readBigUInt64BE(at);assert(n<=BigInt(Number.MAX_SAFE_INTEGER));return Number(n);};
 const sequence=safe(56),root=bytes.readBigUInt64BE(64),references=safe(72);assert(Number.isSafeInteger(previous)&&previous>=0&&sequence>0&&sequence>previous);
 const counts=Object.fromEntries(['owners','ingress','preparing','active','responding'].map((k,i)=>{const n=bytes.readUInt32BE(80+i*4);assert(n<=256);return [k,n];}));
 assert(counts.owners===counts.ingress+counts.preparing+counts.active+counts.responding);
 const found=bytes[6]===1,uncertain=bytes[7]===1;
 if(found)assert(root>0n&&references>0&&counts.owners>0);
 else assert(uncertain&&root===0n&&references===0&&counts.owners===0);
 return {sequence,found,uncertain,root_sequence:root.toString(),references,...counts};
}
// Retain fixed diagnostic categories only, never server prose or generated data.
export function nativeReviewHTTPFailure(status, body) {
 const result={http_status:status};
 if(body?.error?.message==='This model is serving without its vision tower (--no-vision, no vision weights, or on the Neural Engine); image/video content is not supported')result.modality_error='vision_unavailable';
 if(typeof body?.error?.message==='string')result.error_message_sha256=createHash('sha256').update(body.error.message).digest('hex');
 const types=['model_load_failed','model_not_found','invalid_request_error','forbidden','model_busy','native_tracking_unavailable','native_instance_changed','native_target_not_local','native_target_not_found','internal_error','shutting_down','gpu_context_lost'];
 if(types.includes(body?.error?.type))result.error_type=body.error.type;
 const names=['FileNotFound','AccessDenied','PermissionDenied','OutOfMemory','NoDevice','DeviceNotFound','UnsupportedArchitecture','UnsupportedModel','InsufficientMemory','LifetimeUnavailable','GpuContextLost'];
 const match=/^(?:Failed to load model|Model load failed): ([A-Za-z]+)$/.exec(body?.error?.message ?? '');
 if(match&&names.includes(match[1]))result.load_error=match[1];
 return result;
}
export function nativeReviewIntent(input) {
 const args=[...input];let scenario;
 const at=args.indexOf('--scenario');
 if(at!==-1){assert(at===args.length-2&&['same-model-pair','single-image','cancel-request','cancel-response','cancel-then-success','journal-correlation'].includes(args[at+1]));scenario=args[at+1];args.splice(at,2);}
 const result=value=>scenario?{...value,scenario}:value;
 const mode=args[0];assert(['--plan','--check','--run'].includes(mode));
 if(mode==='--plan'){
  assert(args.length===7&&args[1]==='--capsule'&&args[3]==='--sha256'&&args[5]==='--output');
  assert(path.isAbsolute(args[2])&&path.isAbsolute(args[6])&&/^[a-f0-9]{64}$/.test(args[4]));
  return result({mode:'plan',inferenceRequested:false});
 }
 assert(args.length===(mode==='--run'?6:5)&&args[1]==='--plan'&&args[3]==='--sha256');
 assert(path.isAbsolute(args[2])&&/^[a-f0-9]{64}$/.test(args[4]));
 if(mode==='--run')assert(args[5]==='--allow-native-inference');
 return result({mode:mode.slice(2),inferenceRequested:mode==='--run'});
}
