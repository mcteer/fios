// Parsing an operator command is not native admission or installation authority.
import assert from 'node:assert/strict';
import path from 'node:path';
import {createHash} from 'node:crypto';
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
