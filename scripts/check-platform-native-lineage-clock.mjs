#!/usr/bin/env node
// Normal lineage source/query clocks; no runtime or model action.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,readdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
assert.deepEqual(process.argv.slice(2),['--isolated']);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-lineage-clock-');
const core=join(root,'platform/studio/Sources/StudioCore');
const files=[...readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>join(core,n)),join(root,'platform/studio/Tests/StudioCoreTests/NativeLineageClockTests.swift'),join(root,'platform/studio/Tests/StudioCoreTests/NativeLineagePollingTests.swift')];
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const inputs=Object.fromEntries([...files,resolve(process.argv[1])].map(p=>[p,sha(p)]));
const source=join(directory,'Main.swift');
writeFileSync(source,'import Foundation\nimport Darwin\n@main struct Check {static func main(){do {try runNativeLineageClockTests();try runNativeLineagePollingTests()}catch {print(error.localizedDescription);exit(1)}}}\n');
const records=[];
for(const mode of ['debug','optimized']){
 const binary=join(directory,mode);
 for(const [stage,program,args] of [
  ['compile','swiftc',['-swift-version','6','-warnings-as-errors',...(mode==='optimized'?['-O']:[]),'-I',join(root,'platform/studio/Sources/CSQLite'),...files,source,'-o',binary]],
  ['run',binary,[]],
 ]){
  const result=spawnSync(program,args,{cwd:root,encoding:'utf8',timeout:stage==='compile'?180000:10000,maxBuffer:2<<20});
  const log=join(directory,mode+'-'+stage+'.log');writeFileSync(log,(result.stdout??'')+(result.stderr??''));
  assert.equal(result.status,0,'Normal lineage clock check failed; retain '+directory);
  records.push({mode,stage,status:result.status,log_sha256:sha(log)});
 }
}
assert(Object.entries(inputs).every(([p,digest])=>sha(p)===digest));
const receipt={scope:'normal_native_lineage_capture_clock_and_existing_lineage_polling',inputs,records,native_actions:0,model_requests:0};
const output=join(directory,'receipt.json');writeFileSync(output,JSON.stringify(receipt,null,2)+'\n');
console.log(JSON.stringify({ok:true,directory,receipt_sha256:sha(output),records:records.length,native_actions:0}));
