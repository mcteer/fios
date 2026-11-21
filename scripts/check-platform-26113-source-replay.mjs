// Source-only replay: neither compile nor run anything from the upstream archive.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,rmSync,statSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename,isAbsolute,join} from 'node:path';
import {fileURLToPath} from 'node:url';

const args=process.argv.slice(2);
const manifestOnly=args.length===1&&args[0]==='--manifest-only';
if(!manifestOnly&&(args.length!==2||args[0]!=='--source-archive'||!isAbsolute(args[1])))
 throw Error('usage: --manifest-only | --source-archive /absolute/path/to/pinned-codeload.tar.gz');
const sha256=bytes=>createHash('sha256').update(bytes).digest('hex');
const native=fileURLToPath(new URL('../platform/studio/native/',import.meta.url));
const entries=readFileSync(join(native,'mlx-serve-26.11.3-source-series.txt'),'utf8').split('\n').filter(line=>line&&!line.startsWith('#'));
assert.equal(entries.length,72);
const seen=new Set();
const patches=entries.map(line=>{
 const [,hash,name]=line.match(/^([0-9a-f]{64})  (mlx-serve-(?:26\.11\.[23]-[a-z0-9-]+|current-ds4-checked-cleanup)\.patch)$/)||[];
 assert.ok(hash&&name===basename(name)&&!seen.has(name),`invalid or duplicate manifest entry: ${line}`);
 seen.add(name);
 const bytes=readFileSync(join(native,name));assert.equal(sha256(bytes),hash,`${name}: patch digest`);
 return {name,bytes};
});
if(manifestOnly){
 console.log(`PASS: ${entries.length} local patch hashes; no archive replay or native execution`);
 process.exit(0);
}
const archive=statSync(args[1]);
assert.ok(archive.isFile()&&archive.size>0&&archive.size<=80*1024*1024,'bounded regular source archive required');
const source=readFileSync(args[1]);
assert.equal(sha256(source),'f48a65d735a77fb2366b77d0000ff7f13794a505e66b67c1bab0dedc43500271','unexpected source archive digest');
const scratch=mkdtempSync(join(tmpdir(),'fios-26113-replay-'));
const env={PATH:'/usr/bin:/bin',HOME:scratch,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_CEILING_DIRECTORIES:scratch};
function run(command,args,input){
 const result=spawnSync(command,args,{cwd:scratch,env,input,encoding:'utf8',timeout:10000});
 if(result.error)throw result.error;
 assert.equal(result.status,0,`${command} ${args.join(' ')}: ${result.stderr}`);
}
try{
 writeFileSync(join(scratch,'input.tar.gz'),source,{mode:0o600});
 run('/usr/bin/tar',['-xzf','input.tar.gz','--strip-components=1']);
 for(const {name,bytes} of patches){
  try{run('/usr/bin/git',['apply','--check','-'],bytes);run('/usr/bin/git',['apply','-'],bytes);}
  catch(error){throw new Error(name,{cause:error});}
 }
 const scheduler=readFileSync(join(scratch,'src/engines/mlx/scheduler.zig'),'utf8');
 const unload=scheduler.slice(scheduler.indexOf('pub fn unloadModelIfIdle('),scheduler.indexOf('pub fn idleModelToUnload('));
 const typedRefusal='if (req.fios_cleanup_refused) return error.NativeCleanupUncertain;';
 assert.equal(scheduler.split(typedRefusal).length,2,'missing or duplicate unload refusal');
 assert.ok(unload.indexOf('self.unload_queue.append(')>=0);
 assert.ok(unload.indexOf(typedRefusal)>unload.indexOf('while (!req.done)'), 'typed refusal not at unload acknowledgement');
 const blocking=scheduler.slice(scheduler.indexOf('pub fn submit('),scheduler.indexOf('pub fn submitNow('));
 const nonblocking=scheduler.slice(scheduler.indexOf('pub fn submitNow('),scheduler.indexOf('fn submitWaiting('));
 assert.ok(blocking.includes('return submitWaiting(self, params, true);'));
 assert.ok(nonblocking.includes('return submitWaiting(self, params, false);'));
 assert.match(scheduler,/fn submitWaiting\([^\n]+\{\n    if \(model_registry_mod\.cleanupUncertain\(self\.io\)\) return error\.NativeCleanupUncertain;/,
  'both blocking and nonblocking submissions must share the pre-allocation refusal');
 const requests=readFileSync(join(scratch,'src/engines/mlx/runtime/load_requests.zig'),'utf8');
 const queued=requests.split('test "fios current queued unload preserves sender and worker origins"')[1]?.split('\ntest "')[0];
 assert.ok(queued?.includes('model.fios_owner_guard = true;')&&queued.includes('expectError(error.ModelOwned,'),
  'guarded fixture must distinguish an active model owner from the administrative sender');
 assert.match(requests,/if \(!warm_requests\.forget\(sch, victim\)\) return error\.NativeCleanupUncertain;\n        moveHotCacheViewOff/);
 assert.match(requests,/if \(!warm_requests\.forget\(sch, entry\)\) return refuseUnloadRequest\(sch, req\);\n    moveHotCacheViewOff/);
 const loop=readFileSync(join(scratch,'src/engines/mlx/runtime/loop.zig'),'utf8');
 assert.match(loop,/if \(!warm_requests\.stop\(sch\) or cleanupUncertain\(sch\.io\)\) return;\n    persistAtShutdown/);
 const macos=readFileSync(join(scratch,'build/macos.zig'),'utf8');
 const shared=macos.slice(macos.indexOf('const Shared = struct'),macos.indexOf('pub fn addServer('));
 for(const bridge of ['sdk','ds4']){
  const file=`src/fios/current_${bridge}_owners.cpp`;
  assert.equal(macos.split(file).length,2,`expected one reference to ${file}`);
  assert.ok(shared.includes(file),`${file} must attach to the common executable/test module builder`);
 }
 assert.ok(readFileSync(join(scratch,'src/tests.zig'),'utf8').includes(
  'if (@import("build_options").fios_source_sdk) _ = @import("fios/sdk_request_ownership.zig");'),
 'instrumented unit root must export the same ownership functions as the server');
 assert.match(macos,/"fios-source-background-seal",[^\n]+orelse false;\n        if \(fios_source_background_seal and !fios_source_sdk\)/,
  'strict background exclusion must stay explicitly selected and require the real SDK');
 const sdkBridge=readFileSync(join(scratch,'src/fios/current_sdk_owners.cpp'),'utf8');
 assert.match(sdkBridge,/#ifdef FIOS_REQUIRE_BACKGROUND_PARTICIPANT_SEAL\n#ifdef MLX_FIOS_BACKGROUND_PARTICIPANT_SEAL[\s\S]+?fios_seal_background_participants_fixture\(\)\) std::_Exit\(78\);\n#else\n    std::_Exit\(78\);/);
 console.log(`PASS: pinned archive, ${entries.length} ordered patch hashes, exact refusal and private seal scopes; source only`);
}finally{rmSync(scratch,{recursive:true,force:true});}
