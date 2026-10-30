// Parsing an operator command is not native admission or installation authority.
import assert from 'node:assert/strict';
import path from 'node:path';
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
