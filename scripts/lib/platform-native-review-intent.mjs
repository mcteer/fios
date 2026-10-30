// Parsing an operator command is not native admission or installation authority.
import assert from 'node:assert/strict';
import path from 'node:path';
import {createHash} from 'node:crypto';
// An optional source dependency must declare the selected format before any
// model effect. This is a refusal prerequisite, never an admission grant.
export function nativeReviewModelInputs(inputs){
 const dependency=inputs?.mlx_source_dependency;
 if(dependency!==undefined&&dependency!==null){
  assert(dependency.source_fixture_only===true&&dependency.native_authority===false&&dependency.features?.safetensors===true,'Source SDK lacks required Safetensors support');
 }
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
// Retain fixed diagnostic categories only, never server prose or generated data.
export function nativeReviewHTTPFailure(status, body) {
 const result={http_status:status};
 if(typeof body?.error?.message==='string')result.error_message_sha256=createHash('sha256').update(body.error.message).digest('hex');
 const types=['model_load_failed','model_not_found','invalid_request_error','forbidden','model_busy','native_tracking_unavailable','internal_error','shutting_down','gpu_context_lost'];
 if(types.includes(body?.error?.type))result.error_type=body.error.type;
 const names=['FileNotFound','AccessDenied','PermissionDenied','OutOfMemory','NoDevice','DeviceNotFound','UnsupportedArchitecture','UnsupportedModel','InsufficientMemory','LifetimeUnavailable','GpuContextLost'];
 const match=/^(?:Failed to load model|Model load failed): ([A-Za-z]+)$/.exec(body?.error?.message ?? '');
 if(match&&names.includes(match[1]))result.load_error=match[1];
 return result;
}
export function nativeReviewIntent(args) {
 const mode=args[0];assert(['--plan','--check','--run'].includes(mode));
 if(mode==='--plan'){
  assert(args.length===7&&args[1]==='--capsule'&&args[3]==='--sha256'&&args[5]==='--output');
  assert(path.isAbsolute(args[2])&&path.isAbsolute(args[6])&&/^[a-f0-9]{64}$/.test(args[4]));
  return {mode:'plan',inferenceRequested:false};
 }
 assert(args.length===(mode==='--run'?6:5)&&args[1]==='--plan'&&args[3]==='--sha256');
 assert(path.isAbsolute(args[2])&&/^[a-f0-9]{64}$/.test(args[4]));
 if(mode==='--run')assert(args[5]==='--allow-native-inference');
 return {mode:mode.slice(2),inferenceRequested:mode==='--run'};
}
