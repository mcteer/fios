#!/usr/bin/env node
// Actual C shim plus actual current negative probe/tracker. No model/device test.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,copyFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync} from 'node:fs';
import {join,resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
const [source,zig]=[args[2],args[4]].map(file=>{assert(file.startsWith('/private/tmp/'));assert.equal(realpathSync(file),file);return file;});
const sha=bytes=>createHash('sha256').update(bytes).digest('hex'),hash=file=>sha(readFileSync(file));
assert.equal(hash(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const directory=mkdtempSync('/private/tmp/fios-009-llama-parent-root-'),unit=join(directory,'source');mkdirSync(unit,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer'};
const inputs={},nativeNames=['fios/request_ownership.zig','fios/queued_request_ownership.zig','fios/current_backend_uncertainty.zig','sdk/util/shared.zig'];
for(const name of nativeNames){const file=join(source,'src',name),stat=lstatSync(file);assert(stat.isFile()&&!stat.isSymbolicLink()&&stat.uid===process.getuid()&&(stat.mode&0o022)===0);inputs['src/'+name]=hash(file);mkdirSync(resolve(unit,name,'..'),{recursive:true,mode:0o700});copyFileSync(file,join(unit,name));}
assert.equal(inputs['src/fios/current_backend_uncertainty.zig'],hash(join(root,'platform/studio/native/current_backend_uncertainty.zig')));
const execute=(command,argv)=>execFileSync(command,argv,{env,encoding:'utf8',timeout:120000,maxBuffer:1<<20});
assert.equal(sha(execute('/usr/bin/git',['--no-replace-objects','-C',source,'show','4e231ceebe63308cc038117d40b9f9b64bd0372e:src/sdk/util/shared.zig'])),inputs['src/sdk/util/shared.zig']);
for(const name of ['lib/llama_shim/llama_shim.cpp','lib/llama_shim/llama_shim.h','lib/llama/include/llama.h','lib/llama/lib/libllama.dylib'])inputs[name]=hash(join(source,name));
assert.equal(inputs['lib/llama/lib/libllama.dylib'],'10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b');
const fixture='platform/studio/native/current_llama_parent_probe.cpp.fixture',host='tests/fixtures/platform/native-current-llama-parent-root.zig';
for(const name of [fixture,host])inputs[name]=hash(join(root,name));
writeFileSync(join(directory,'unit.cpp'),Buffer.concat([readFileSync(join(source,'lib/llama_shim/llama_shim.cpp')),readFileSync(join(root,fixture))]),{mode:0o600});
copyFileSync(join(root,host),join(directory,'host.zig'));
writeFileSync(join(unit,'native.zig'),'pub const owners = @import("fios/request_ownership.zig");\npub const queue = @import("fios/queued_request_ownership.zig");\npub const probe = @import("fios/current_backend_uncertainty.zig");\n',{mode:0o600});
for(const mode of ['Debug','ReleaseSafe']){
 const object=join(directory,mode+'.o'),binary=join(directory,mode);
 execute('/usr/bin/clang++',['-std=c++17',mode==='Debug'?'-O0':'-O2','-I'+join(source,'lib/llama/include'),'-I'+join(source,'lib/llama_shim'),'-c',join(directory,'unit.cpp'),'-o',object]);
 execute(zig,['build-exe','-O'+mode,object,'-L'+join(source,'lib/llama/lib'),'-lllama','-rpath',join(source,'lib/llama/lib'),'-lc++','-lc','--dep','native','-Mroot='+join(directory,'host.zig'),'-Mnative='+join(unit,'native.zig'),'-femit-bin='+binary]);
 const run=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:10000,maxBuffer:8192});
 const log=(run.stdout??'')+(run.stderr??'');writeFileSync(join(directory,mode+'.log'),log,{mode:0o600});
 assert(!run.error&&!run.signal);assert.equal(run.status,0,log);assert(log.includes('PASS: actual llama parent refusal preserves original lineage'));
}
for(const [name,digest]of Object.entries(inputs))assert.equal(hash(join(name.startsWith('platform/')||name.startsWith('tests/')?root:source,name)),digest);
const receipt={directory,inputs,modes:['Debug','ReleaseSafe'],scope:'declared_genuine_shim_empty_parent_to_original_metadata_root',models:0,native_contexts:0,backend_terminality:false,native_authority:false,coverage:'unknown',installed:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600});console.log(JSON.stringify(receipt));
