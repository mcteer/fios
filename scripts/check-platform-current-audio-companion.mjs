#!/usr/bin/env node
// Actual audio companion association; CPU loader substitute.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
const [source,zig]=[args[2],args[4]].map(p=>{assert(isAbsolute(p)&&p.startsWith('/private/tmp/')&&realpathSync(p)===p);return p;});
const hash=b=>createHash('sha256').update(b).digest('hex');
const bytes=p=>{const s=lstatSync(p);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<(64<<20));return readFileSync(p);};
assert.equal(hash(readFileSync(zig)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const directory=mkdtempSync('/private/tmp/fios-009-audio-companion-check-'),unit=join(directory,'unit'),review=join(directory,'review');
for(const p of [unit,review])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(p,a,cwd=directory)=>execFileSync(p,a,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const git=(...a)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...a]);
const base='3736ed55f81c6cf0966a0f0dc7265e783655d244',name='host/api/audio.zig',original=Buffer.from(git('show',base+':src/'+name)),patchFile=join(root,'platform/studio/native/mlx-serve-current-audio-companion.patch'),patch=bytes(patchFile);
mkdirSync(join(review,'src/host/api'),{recursive:true,mode:0o700});writeFileSync(join(review,'src',name),original,{mode:0o600});writeFileSync(join(directory,'source.patch'),patch,{mode:0o600});run('/usr/bin/git',['apply',join(directory,'source.patch')],review);
const audio=bytes(join(source,'src',name));assert(audio.equals(readFileSync(join(review,'src',name))));
const oldCall='http_server.launch().global_scheduler.?.ensureLoaded(';assert.equal(original.toString().split(oldCall).length-1,2);assert.equal(audio.toString().split('ensureCompanionLoaded(').length-1,3);assert(!audio.toString().includes(oldCall));
const pending=['fios/request_ownership.zig'],copied=new Set(),declared={[name]:hash(audio)};
while(pending.length){const n=pending.pop();if(copied.has(n))continue;copied.add(n);const p=join(source,'src',n),b=bytes(p);declared[n]=hash(b);const dest=join(unit,n);mkdirSync(dirname(dest),{recursive:true,mode:0o700});writeFileSync(dest,b,{mode:0o600});for(const m of b.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){const dependency=resolve(dirname(p),m[1]),d=relative(join(source,'src'),dependency);assert(!d.startsWith('..')&&!isAbsolute(d));if(existsSync(dependency))pending.push(d);}}
const fixtureFile=join(root,'platform/studio/native/current_audio_companion_test.zig.fixture'),fixture=bytes(fixtureFile),text=audio.toString(),start=text.indexOf('fn ensureCompanionLoaded('),end=text.indexOf('\nconst Conn =',start);assert(start>=0&&end>start);
const receipt={version:1,scope:'actual_host_audio_companion_helper_native_tracker_CPU_loader_substitute',directory,source,base,source_revision:git('rev-parse','HEAD').trim(),declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(readFileSync(import.meta.filename)),models:0,inference:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false,all_client_coverage:false,results:[]};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const label of ['baseline','candidate']){
 const helper=label==='baseline'?'fn ensureCompanionLoaded(id: []const u8) !*LoadedModel { return http_server.launch().global_scheduler.?.ensureLoaded(id); }':text.slice(start,end);
 writeFileSync(join(unit,'main.zig'),fixture.toString().replace('// ACTUAL_HELPER',helper),{mode:0o600});
 for(const mode of ['Debug','ReleaseSafe'])for(const scenario of label==='baseline'?[0,1,5]:[0,1,2,3,4,5,6]){
  writeFileSync(join(unit,'options.zig'),`pub const fios_source_ane=false;\npub const scenario=${scenario};\n`,{mode:0o600});
  const key=label+'-'+mode+'-'+scenario,binary=join(directory,key),built=spawnSync(zig,['build-exe','-lc','-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-femit-bin='+binary],{env,encoding:'utf8',timeout:120000,maxBuffer:4<<20});
  writeFileSync(join(directory,key+'-build.log'),(built.stdout??'')+(built.stderr??''));const item={label,mode,scenario,build_status:built.status,build_signal:built.signal};receipt.results.push(item);save();assert.equal(built.status,0,'Compile failed: '+directory);
  const executed=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:10000,maxBuffer:65536}),log=(executed.stdout??'')+(executed.stderr??'');writeFileSync(join(directory,key+'-run.log'),log);item.run_status=executed.status;item.run_signal=executed.signal;
  item.expected=label==='baseline'&&scenario!==5?executed.status===1&&log.includes('FIO_COMPANION_UNASSOCIATED_BEFORE_LOAD'):executed.status===0&&log.includes('PASS: actual companion helper');save();assert(item.expected,'Execution failed: '+directory);
 }
}
receipt.declared_inputs_unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,'src',n)))===h)&&hash(bytes(patchFile))===receipt.patch_sha256&&hash(bytes(fixtureFile))===receipt.fixture_sha256&&hash(readFileSync(import.meta.filename))===receipt.runner_sha256;
save();assert(receipt.declared_inputs_unchanged);console.log(JSON.stringify({directory,receipt_sha256:hash(readFileSync(join(directory,'receipt.json'))),expected_baseline_failures:4,baseline_healthy_passes:2,candidate_passes:14,models:0,native_authority:false}));
