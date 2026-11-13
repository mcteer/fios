#!/usr/bin/env node
// Actual current C shim, ordinary empty metadata. No model/backend fault case.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,lstatSync,realpathSync} from 'node:fs';
import {join,resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
const missing=args.at(-1)==='--expect-missing';if(missing)args.pop();
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===3&&args[0]==='--isolated'&&args[1]==='--source');
const source=realpathSync(args[2]);assert(source===args[2]&&source.startsWith('/private/tmp/'));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const names=['lib/llama_shim/llama_shim.cpp','lib/llama_shim/llama_shim.h','lib/llama/include/llama.h','lib/llama/lib/libllama.dylib'];
const inputs=Object.fromEntries(names.map(name=>{const file=join(source,name),stat=lstatSync(file);assert(stat.isFile()&&!stat.isSymbolicLink()&&stat.uid===process.getuid()&&(stat.mode&0o022)===0);return [name,sha(readFileSync(file))];}));
assert.equal(inputs['lib/llama/lib/libllama.dylib'],'10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b');
const fixture=readFileSync(join(root,'platform/studio/native/current_llama_parent_test.cpp.fixture'));
const directory=mkdtempSync('/private/tmp/fios-009-current-llama-parent-'),unit=join(directory,'unit.cpp');
writeFileSync(unit,Buffer.concat([Buffer.from('#include <unistd.h>\n'),readFileSync(join(source,names[0])),fixture]),{mode:0o600});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer'};
const modes=[];
for(const mode of ['Debug','optimized']){
 const binary=join(directory,mode),compile=spawnSync('/usr/bin/clang++',['-std=c++17',mode==='Debug'?'-O0':'-O2','-I'+join(source,'lib/llama/include'),'-I'+join(source,'lib/llama_shim'),unit,join(source,names[3]),'-Wl,-rpath,'+join(source,'lib/llama/lib'),'-o',binary],{env,encoding:'utf8',timeout:60000,maxBuffer:1<<20});
 writeFileSync(join(directory,mode+'-compile.log'),(compile.stdout??'')+(compile.stderr??''),{mode:0o600});
 assert(!compile.error&&!compile.signal);
 if(missing){assert.notEqual(compile.status,0);assert((compile.stderr??'').includes('mlx_llama_try_close'));break;}
 assert.equal(compile.status,0,compile.stderr);
 const run=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env,encoding:'utf8',timeout:10000,maxBuffer:8192});
 const log=(run.stdout??'')+(run.stderr??'');writeFileSync(join(directory,mode+'.log'),log,{mode:0o600});
 assert(!run.error&&!run.signal);assert.equal(run.status,0,log);assert(log.includes('PASS: actual empty llama parent custody'));modes.push(mode);
}
for(const [name,digest]of Object.entries(inputs))assert.equal(sha(readFileSync(join(source,name))),digest);
assert.equal(sha(readFileSync(join(root,'platform/studio/native/current_llama_parent_test.cpp.fixture'))),sha(fixture));
const receipt={directory,missing_interface:missing,inputs,fixture_sha256:sha(fixture),modes,metadata_only:true,native_contexts:0,model_requests:0,native_authority:false,all_client_coverage:false,backend_terminality:false,installed:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600});console.log(JSON.stringify(receipt));
