#!/usr/bin/env node
// Ordinary source metadata check; no native model, network or GPU operation.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import {join,resolve,isAbsolute} from 'node:path';
import {userInfo} from 'node:os';
import {createHash,randomUUID} from 'node:crypto';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(args.length===4&&args[0]==='--source'&&args[2]==='--zig'&&isAbsolute(args[1])&&isAbsolute(args[3]));
const source=args[1],zig=args[3],name='fios-catalog-'+randomUUID(),created=[];
const version=spawnSync(zig,['version'],{encoding:'utf8',timeout:2000});assert.equal(version.status,0);assert.equal(version.stdout.trim(),'0.17.0');
const config=readFileSync(join(userInfo().homedir,'.mlx-serve/models/mlx-community/gemma-4-e4b-it-4bit/config.json'));
const configName=name+'.json',configPath=join(source,'src',configName),fixture=join(source,'src',name+'.zig');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
function run(args){const result=spawnSync(zig,args,{encoding:'utf8',timeout:90000,maxBuffer:1<<20,env:{PATH:'/usr/bin:/bin',HOME:userInfo().homedir,DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer'}});assert.equal(result.status,0,result.stderr);}
try{
 writeFileSync(configPath,config,{flag:'wx',mode:0o600});created.push(configPath);
 writeFileSync(fixture,readFileSync(join(root,'platform/studio/Tests/NativeFixtures/NativeCatalogVision.zig.fixture'),'utf8').replace('@MODEL_CONFIG@',configName),{flag:'wx',mode:0o600});created.push(fixture);
 for(const mode of ['Debug','ReleaseSafe'])run(['test',fixture,'-lc','-O',mode,'--test-filter','catalog serving modalities']);
 console.log(JSON.stringify({ok:true,zig_version:version.stdout.trim(),source_sha256:sha(readFileSync(join(source,'src/model_discovery.zig'))),model_config_sha256:sha(config),modes:['Debug','ReleaseSafe'],model_requests:0,gpu_operations:0}));
}finally{
 for(const file of created.reverse())try{unlinkSync(file);}catch(error){if(error.code!=='ENOENT')throw error;}
}
