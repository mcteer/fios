#!/usr/bin/env node
// Actual older executable refusal/current library restore, serialization only.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,readdirSync,mkdtempSync,realpathSync,lstatSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join,resolve,isAbsolute} from 'node:path';
import {spawnSync} from 'node:child_process';
import {validatePlatformRelease} from './lib/platform-release.mjs';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--previous'&&args[3]==='--sha256');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const previous=args[2];assert(isAbsolute(previous)&&previous.startsWith('/private/tmp/')&&realpathSync(previous)===previous);
const info=lstatSync(previous);assert(info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o077)===0);
validatePlatformRelease(previous,args[4]);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const work=mkdtempSync('/private/tmp/fios-009-pristine-compat-');
const sources=readdirSync(join(root,'platform/studio/Sources/StudioCore')).filter(n=>n.endsWith('.swift')).sort().map(n=>join(root,'platform/studio/Sources/StudioCore',n));
const fixture=join(root,'platform/studio/Tests/StudioCoreTests/NativePristineCompatibility.swift.fixture');
const inputs=Object.fromEntries([...sources,fixture].map(p=>[p,sha(readFileSync(p))]));
const copy=join(work,'Compatibility.swift'),binary=join(work,'compatibility');writeFileSync(copy,readFileSync(fixture),{mode:0o600});
const receipt={scope:'version4_attempted_serialization_fixture_old_executable_refusal_current_restore_not_native_proof',inputs,previous_manifest_sha256:args[4],models:0,installed:false,native_authority:false,results:[]};
const save=()=>writeFileSync(join(work,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
function run(name,command,args,timeout=10000){
 const result=spawnSync(command,args,{cwd:work,encoding:'utf8',timeout,maxBuffer:1<<20});
 const output=(result.stdout??'')+(result.stderr??'');writeFileSync(join(work,name+'.log'),output,{mode:0o600});
 receipt.results.push({name,status:result.status,signal:result.signal,log_sha256:sha(Buffer.from(output))});save();
 assert(!result.error&&!result.signal,'Bounded compatibility command failed: '+work);return result;
}
const build=run('compile','/usr/bin/swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors','-O','-whole-module-optimization','-num-threads','1','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,copy,'-o',binary],300000);assert.equal(build.status,0,'Compatibility compile failed: '+work);
const state=join(work,'state'),bundle=join(work,'bundle');
const seeded=run('seed-current-verify-restore','/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary,state,bundle]);assert.equal(seeded.status,0,'Current compatibility failed: '+work);
const seed=JSON.parse(seeded.stdout);assert.equal(seed.state,'attempted');assert.equal(seed.uncertain,1);assert.equal(seed.native_proof,false);
const before=sha(readFileSync(join(bundle,'state.sqlite'))),manifest=sha(readFileSync(join(bundle,'backup.json')));assert.equal(manifest,seed.backup_sha256);
const refused=run('old-verify',join(previous,'bin/studioctl'),['--state',bundle,'verify-backup','--sha256',manifest]);assert.equal(refused.status,1,'Older executable accepted version4: '+work);
const target=join(work,'old-must-not-restore');
const restore=run('old-restore',join(previous,'bin/studioctl'),['--state',bundle,'restore-state','--sha256',manifest,'--to',target]);assert.equal(restore.status,1);assert(!existsSync(target));
assert.equal(sha(readFileSync(join(bundle,'state.sqlite'))),before);assert.equal(sha(readFileSync(join(bundle,'backup.json'))),manifest);
validatePlatformRelease(previous,args[4]);for(const [p,digest] of Object.entries(inputs))assert.equal(sha(readFileSync(p)),digest);
receipt.backup_sha256=manifest;receipt.current_restore_preserves_attempted_uncertainty=true;receipt.older_refuses_without_publishing=true;receipt.inputs_unchanged=true;save();console.log(work);console.log('PASS older executable refuses version4 attempted backup; current restore preserves uncertainty; no native proof');
