#!/usr/bin/env node
// Finite actual owned-process lifecycle only; no native MLX app/model/runtime.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,readdirSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');assert(process.getuid()>0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-serving-runtime-');
const hash=b=>createHash('sha256').update(b).digest('hex');
const helper=join(directory,'serving-helper'),c=join(directory,'helper.c');
writeFileSync(c,'#include <unistd.h>\n#include <signal.h>\nint main(void){alarm(30);for(;;)pause();}\n',{mode:0o600});
function run(program,args,timeout=120000){const r=spawnSync(program,args,{encoding:'utf8',timeout,maxBuffer:2<<20});assert(!r.error&&!r.signal);assert.equal(r.status,0,r.stderr);return r.stdout;}
run('/usr/bin/clang',[c,'-O2','-o',helper],30000);
const core=join(root,'platform/studio/Sources/StudioCore'),name='MLXServingProcessRuntime.swift';
const implementation=readFileSync(join(core,name)),fixture=readFileSync(join(root,'platform/studio/Tests/NativeFixtures/MLXServingProcessRuntime.swift.fixture'));
const unit=join(directory,'RuntimeFixture.swift');writeFileSync(unit,Buffer.concat([implementation,Buffer.from('\n'),fixture]));
for(const mode of ['debug','release']){
 const binary=join(directory,mode),state=join(directory,mode+'-state');
 run('swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors',...(mode==='release'?['-O']:[]),'-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(n=>n.endsWith('.swift')&&n!==name).sort().map(n=>join(core,n)),unit,'-o',binary]);
 const output=run(binary,[helper,hash(readFileSync(helper)),state],30000);writeFileSync(join(directory,mode+'.log'),output,{mode:0o600});
 assert(output.includes('PASS: actual private serving-role process launch/identity/local reap/relaunch'));
}
assert(implementation.equals(readFileSync(join(core,name))));
const receipt={ok:true,directory,provenance_scope:'declared_runtime_and_fixture_only',modes:['debug','release'],source_sha256:hash(implementation),fixture_sha256:hash(fixture),actual_private_child_starts:4,native_mlx_actions:0,native_inference:false,native_authority:false,installed:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600});console.log(JSON.stringify(receipt));
