// Ordinary CLI usage tests only: never connects to a manager or acts on services.
import assert from 'node:assert/strict';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const args=process.argv.slice(2);
assert(args.length===2&&args[0]==='--binary'&&path.isAbsolute(args[1]),'usage: check-platform-cli.mjs --binary ABS_STUDIOCTL');
for(const flag of ['--help','-h']){
 const result=spawnSync(args[1],[flag],{encoding:'utf8',timeout:5000});
 assert.ifError(result.error);assert.equal(result.status,0,`${flag} should succeed without a running manager`);
 assert.match(result.stdout,/Usage: studioctl/);assert.match(result.stdout,/status\|activity\|resources/);assert.equal(result.stderr,'');
}
for(const argv of [[],['--state'],['--state','relative','status'],['--state','/nonexistent-fios-cli-usage-only','not-a-command']]){
 const result=spawnSync(args[1],argv,{encoding:'utf8',timeout:5000});
 assert.ifError(result.error);assert.equal(result.status,2,'invalid invocation should return usage, not attempt IPC');
 assert.match(result.stderr,/Usage: studioctl/);assert.equal(result.stdout,'');
}
for(const [ram,headroom,headroomGiB] of [['24',17179869184,16],['64',17179869184,16],['128',27487790695,25.6],['256',54975581389,51.2]]){
 const result=spawnSync(args[1],['plan-memory','--ram-gib',ram],{encoding:'utf8',timeout:5000});
 assert.ifError(result.error);assert.equal(result.status,0,'RAM planning should work without a manager');
 assert.equal(result.stderr,'');const plan=JSON.parse(result.stdout);
 assert.equal(plan.mode,'planning_only');assert.equal(plan.measured,false);
 assert.equal(plan.physical_bytes,Number(ram)*2**30);assert.equal(plan.native_headroom_bytes,headroom);
 assert.equal(plan.physical_gib,Number(ram));assert.equal(plan.native_headroom_gib_approx,headroomGiB);
 assert.equal(result.stdout.match(/"native_headroom_gib_approx":([^,}\s]+)/)?.[1],JSON.stringify(headroomGiB),"Approximate GiB should have concise decimal output");
}
console.log('PASS: standalone CLI help, ordinary argument handling and offline RAM planning; no manager connection, service action or inference.');
