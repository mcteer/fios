#!/usr/bin/env node
// Ordinary separate-object metadata composition, no model or native authority.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,copyFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0);
assert.equal(args.length,5);assert.equal(args[0],'--isolated');assert.equal(args[1],'--source');assert.equal(args[3],'--zig');
const [source,zig]=[args[2],args[4]].map(file=>{assert(file.startsWith('/private/tmp/'));assert.equal(realpathSync(file),file);return file;});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex'),sha=file=>hash(readFileSync(file));
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const directory=mkdtempSync('/private/tmp/fios-009-cpu-media-units-'),unit=join(directory,'source');mkdirSync(unit,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C'};
const run=(command,argv)=>execFileSync(command,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:1<<20});
const inputs={};
for(const name of ['fios/request_ownership.zig','fios/queued_request_ownership.zig','fios/current_cpu_media_origins.zig','sdk/media/offload_origins.zig','sdk/util/shared.zig']){
 const file=join(source,'src',name),stat=lstatSync(file);assert(stat.isFile()&&!stat.isSymbolicLink()&&stat.nlink===1&&stat.uid===process.getuid()&&(stat.mode&0o022)===0);
 inputs[name]=sha(file);mkdirSync(resolve(unit,name,'..'),{recursive:true,mode:0o700});copyFileSync(file,join(unit,name));
}
for(const [name,canonical]of [['fios/current_cpu_media_origins.zig','current_cpu_media_origins.zig'],['sdk/media/offload_origins.zig','current_cpu_media_hooks.zig']])
 assert.equal(inputs[name],sha(join(root,'platform/studio/native',canonical)));
assert.equal(hash(run('/usr/bin/git',['--no-replace-objects','-C',source,'show','4e231ceebe63308cc038117d40b9f9b64bd0372e:src/sdk/util/shared.zig'])),inputs['sdk/util/shared.zig']);
for(const kind of ['host','plugin']){
 const name=`native-cpu-media-unit-${kind}.zig`,file=join(root,'tests/fixtures/platform',name);inputs[name]=sha(file);copyFileSync(file,join(directory,kind+'.zig'));
 writeFileSync(join(unit,kind+'-native.zig'),'pub const owners = @import("fios/request_ownership.zig");\npub const hooks = @import("sdk/media/offload_origins.zig");\n'+(kind==='host'?'pub const provider = @import("fios/current_cpu_media_origins.zig");\n':''),{mode:0o600});
}
for(const mode of ['Debug','ReleaseSafe']){
 const object=join(directory,mode+'.o'),binary=join(directory,mode);
 run(zig,['build-obj','-O'+mode,'-lc','--dep','native','-Mroot='+join(directory,'plugin.zig'),'-Mnative='+join(unit,'plugin-native.zig'),'-femit-bin='+object]);
 run(zig,['build-exe','-O'+mode,'-lc',object,'--dep','native','-Mroot='+join(directory,'host.zig'),'-Mnative='+join(unit,'host-native.zig'),'-femit-bin='+binary]);
 const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:10000,maxBuffer:8192});
 const log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,mode+'.log'),log,{mode:0o600});
 assert(!result.error&&!result.signal);assert.equal(result.status,0,log);assert(log.includes('PASS: actual host and plugin CPU hooks'));
}
for(const [name,identity]of Object.entries(inputs))assert.equal(sha(name.startsWith('fios/')||name.startsWith('sdk/')?join(source,'src',name):join(root,'tests/fixtures/platform',name)),identity);
const receipt={ok:true,directory,scope:'declared_actual_host_provider_and_plugin_opaque_hooks',inputs,modes:['Debug','ReleaseSafe'],cycles_per_mode:2,roots_per_cycle:2,models:0,installed:false,native_authority:false,all_client_coverage:false,all_backend_terminality:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600});console.log(JSON.stringify(receipt));
