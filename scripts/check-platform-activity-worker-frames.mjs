#!/usr/bin/env node
// Actual current export -> installed worker decoder; isolated fixture authority only.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readdirSync,readFileSync,writeFileSync,copyFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join} from 'node:path';
const root=resolve(import.meta.dirname,'..');
assert.deepEqual(process.argv.slice(2),['--isolated']);
assert(process.platform==='darwin'&&process.getuid()>0);
const directory=mkdtempSync('/private/tmp/fios-009-activity-worker-'),core=join(root,'platform/studio/Sources/StudioCore');
const sources=readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>join(core,n));
const fixture=join(root,'platform/studio/Tests/StudioCoreTests/ActivityWorkerFrames.swift.fixture'),swift=join(directory,'Frames.swift');copyFileSync(fixture,swift);
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const files=[...sources,fixture,join(root,'tests/fixtures/platform/activity-worker-frames.py'),join(root,'src/agent/fios_agent/platform_guard.py'),join(root,'src/agent/fios_agent/platform_protocol.py'),join(root,'scripts/check-platform-activity-worker-frames.mjs')];
const capture=()=>Object.fromEntries(files.map(p=>[p.slice(root.length+1),sha(p)])),inputs=capture(),records=[];
function run(name,program,args){const r=spawnSync(program,args,{cwd:root,encoding:'utf8',timeout:300000,maxBuffer:1<<20});writeFileSync(join(directory,name+'.log'),(r.stdout??'')+(r.stderr??''));records.push({name,status:r.status,signal:r.signal});assert(!r.error&&r.status===0,name+' failed; retain '+directory)}
for(const [mode,flags] of [['debug',['-j2']],['optimized',['-O','-whole-module-optimization','-num-threads','2']]]) {
 const binary=join(directory,mode),frames=join(directory,mode+'-frames');mkdirSync(frames,{mode:0o700});
 run(mode+'-build','/usr/bin/swiftc',['-swift-version','6','-warnings-as-errors',...flags,'-I',join(root,'platform/studio/Sources/CSQLite'),...sources,swift,'-o',binary]);
 run(mode+'-export',binary,[frames]);
 run(mode+'-python',join(root,'.venv/bin/python'),['-I','-B',join(root,'tests/fixtures/platform/activity-worker-frames.py'),frames]);
}
assert.deepEqual(capture(),inputs);
const receipt={scope:'actual_current_swift_export_to_installed_python_guard',inputs,records,native_authority:false,real_inference_posts:0};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify({directory,stages:records.length,receipt_sha256:sha(join(directory,'receipt.json')),native_authority:false}));
