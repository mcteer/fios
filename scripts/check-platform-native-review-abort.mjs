#!/usr/bin/env node
// Synthetic high-RSS observation, actual owned EMPTY-model child. Never a
// genuine resource receipt or native/model authority; run mode rejects it.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,chmodSync,rmSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const args=process.argv.slice(2),root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--plan'&&args[3]==='--sha256');
const sha=b=>createHash('sha256').update(b).digest('hex'),bytes=readFileSync(args[2]);assert(sha(bytes)===args[4]);const original=JSON.parse(bytes);
const directory=mkdtempSync(path.join(path.dirname(args[2]),'abort-fixture-'));let reaped=false;
try {
 const source=readFileSync(path.join(root,'platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture'),'utf8');
 const pin='(unsigned long long)usage.ri_resident_size';assert.equal(source.split(pin).length,2);
 const unit=path.join(directory,'synthetic.c'),observer=path.join(directory,'observe');
 writeFileSync(unit,source.replace(pin,'((unsigned long long)usage.ri_resident_size + 13ULL*1024*1024*1024)'));
 execFileSync('/usr/bin/clang',[unit,'-O2','-o',observer],{timeout:30000});chmodSync(observer,0o500);
 const plan={...original,synthetic_resource_fixture:true,observer,observer_sha256:sha(readFileSync(observer)),runner_inputs:Object.fromEntries(Object.keys(original.runner_inputs).map(n=>[n,sha(readFileSync(path.join(root,n)))]))};
 const file=path.join(directory,'plan.json'),data=Buffer.from(JSON.stringify(plan)+'\n');writeFileSync(file,data,{flag:'wx',mode:0o400});
 const result=spawnSync(process.execPath,[path.join(root,'scripts/check-platform-native-model.mjs'),'--check','--plan',file,'--sha256',sha(data)],{encoding:'utf8',timeout:15000,maxBuffer:8192});
 assert(!result.error&&!result.signal);assert.equal(result.status,1);const receipt=JSON.parse(result.stdout.trim());
 assert(receipt.synthetic_resource_fixture===true&&receipt.model===null&&receipt.native_inference===false&&receipt.actual_model_posts===0&&receipt.reason==='memory_abort_threshold'&&receipt.process_reaped===true);
 assert(receipt.peak_resident>12*2**30&&receipt.original_process?.start);reaped=true;
 console.log('PASS: synthetic first-sample memory breach aborts/reaps the exact owned empty-model process, with zero model POSTs; no real memory/terminality claim.');
} finally {if(reaped)rmSync(directory,{recursive:true,force:true});else console.error('Abort fixture state retained; inspect original child identity and reap status.');}
