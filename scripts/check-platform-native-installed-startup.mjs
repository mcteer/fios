#!/usr/bin/env node
// Private process/metadata fixture only. Never accesses installed lock paths.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync,spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,chmodSync,statSync,renameSync,symlinkSync,unlinkSync,linkSync,existsSync,rmSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const args=process.argv.slice(2),uid=process.getuid();
assert(process.platform==='darwin'&&uid>0&&args.length===3&&args[0]==='--isolated'&&args[1]==='--zig'&&path.isAbsolute(args[2]));
const zig=args[2],sha=value=>createHash('sha256').update(value).digest('hex');
assert.equal(sha(readFileSync(zig)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const sourceFile=path.join(root,'platform/studio/native/startup_guard.zig'),original=readFileSync(sourceFile,'utf8');
const scratch=mkdtempSync('/private/tmp/f9-startup-'),installation=path.join(scratch,'installation');
let cleanupProven=true;
const environment={PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:scratch};
const harness=[
 'const std = @import("std");',
 'const guard = @import("startup_guard.zig");',
 'extern "c" fn alarm(seconds: c_uint) c_uint;',
 'pub fn main() !void {',
 '    _ = alarm(20);',
 '    const version = if (std.c.getenv("FIOS_STARTUP_TEST_VERSION")) |v| std.mem.span(v) else "26.10.3-fios-platform";',
 '    var held = (try guard.Guard.start(version)) orelse {',
 '        std.debug.print("FIO_NATIVE_STARTUP_NOT_RESERVED\\n", .{});',
 '        return error.StartupReservationMissing;',
 '    };',
 '    defer held.close();',
 '    if ((std.c.fcntl(held.fd, std.c.F.GETFD) & std.c.FD_CLOEXEC) == 0) return error.DescriptorInheritance;',
 '    if (std.c.getenv("FIOS_STARTUP_TEST_EARLY_CLOSE") != null) held.close();',
 '    std.debug.print("STARTUP_RESERVED\\n", .{});',
 '    if (std.c.getenv("FIOS_STARTUP_TEST_HOLD") != null) {',
 '        var byte: [1]u8 = undefined;',
 '        _ = std.c.read(0, &byte, 1);',
 '    }',
 '    held.close();',
 '    const other = std.c.openat(std.c.AT.FDCWD, "/dev/null", .{ .CLOEXEC = true });',
 '    if (other < 0) return error.FixtureUnavailable;',
 '    defer _ = std.c.close(other);',
 '    held.close();',
 '    if (std.c.fcntl(other, std.c.F.GETFD) < 0) return error.ReplayedClose;',
 '}',
].join('\n');
function replaceOnce(text,pin,value) {assert.equal(text.split(pin).length,2);return text.replace(pin,value);}
let fixture=replaceOnce(original,'c.openat(c.AT.FDCWD, "/",','c.openat(c.AT.FDCWD, '+JSON.stringify(installation)+',');
fixture=replaceOnce(fixture,'before.uid != 0','before.uid != c.getuid()');
fixture=replaceOnce(fixture,'info.uid == 0','info.uid == c.getuid()');
function build(name,text,optimize='ReleaseSafe') {
 const directory=path.join(scratch,name);mkdirSync(directory,{mode:0o700});
 writeFileSync(path.join(directory,'main.zig'),harness);writeFileSync(path.join(directory,'startup_guard.zig'),text);
 const binary=path.join(directory,'probe');
 execFileSync(zig,['build-exe',path.join(directory,'main.zig'),'-lc','-O',optimize,'-femit-bin='+binary],{env:environment,timeout:30000,stdio:'pipe'});
 return binary;
}
function probe(binary,extra={}) {
 const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env:{...environment,...extra},encoding:'utf8',timeout:3000,maxBuffer:8192});
 if(result.error)throw result.error;
 return result;
}
function refused(binary,extra={}) {const result=probe(binary,extra);assert.equal(result.status,1);assert.match(result.stderr,/error: StartupGuardUnavailable/);}
async function bounded(promise,ms) {
 let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Fixture deadline')),ms);})]);}
 finally {clearTimeout(timer);}
}
async function withHeld(binary,run,extra={}) {
 const child=spawn('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary],{env:{...environment,...extra,FIOS_STARTUP_TEST_HOLD:'1'},stdio:['pipe','ignore','pipe']});
 child.stdin.on('error',()=>{});
 let readyResolve,readyReject,output='';
 const ready=new Promise((resolve,reject)=>{readyResolve=resolve;readyReject=reject;});
 const exited=new Promise(resolve=>{child.once('exit',(code,signal)=>{resolve({code,signal});readyReject(Error('Holder exited before readiness'));});});
 child.once('error',readyReject);
 child.stderr.on('data',chunk=>{output+=chunk.toString();if(output.length>8192)readyReject(Error('Fixture output limit'));if(output.includes('STARTUP_RESERVED\n'))readyResolve();});
 try {await bounded(ready,3000);await run();}
 finally {
  child.stdin.end();
  let terminal;try {terminal=await bounded(exited,3000);}catch(error){cleanupProven=false;throw error;}
  assert.deepEqual(terminal,{code:0,signal:null},'Owned metadata holder must exit before cleanup');
 }
}
try {
 mkdirSync(installation,{mode:0o755});
 let parent=installation;for(const component of ['Library','Application Support','Fios','Studio','native']){parent=path.join(parent,component);mkdirSync(parent,{mode:0o755});}
 const recordFile=path.join(parent,'startup.lock'),record=Buffer.alloc(12);
 record.write('FSG9');record[4]=1;record.writeUInt32BE(uid,8);
 const put=bytes=>{if(existsSync(recordFile))chmodSync(recordFile,0o600);writeFileSync(recordFile,bytes,{mode:0o600});chmodSync(recordFile,0o444);};
 put(record);
 const debug=build('debug',fixture,'Debug');
 assert.equal(probe(debug).status,0);
 await withHeld(debug,()=>{refused(debug,{HOME:path.join(scratch,'debug-other-home')});});
 assert.equal(probe(debug).status,0);
 await withHeld(debug,()=>{
  const early=probe(debug);assert.equal(early.status,1,'FIO_NATIVE_STARTUP_EARLY_RELEASE');assert.match(early.stderr,/StartupGuardUnavailable/);
 },{FIOS_STARTUP_TEST_EARLY_CLOSE:'1'});
 const binary=build('positive',fixture),identity=statSync(recordFile);
 assert.equal(probe(binary).status,0);
 await withHeld(binary,()=>{refused(binary,{HOME:path.join(scratch,'different-home')});});
 await withHeld(binary,()=>{
  const early=probe(binary);assert.equal(early.status,1,'FIO_NATIVE_STARTUP_EARLY_RELEASE');assert.match(early.stderr,/StartupGuardUnavailable/);
 },{FIOS_STARTUP_TEST_EARLY_CLOSE:'1'});
 assert.equal(probe(binary,{FIOS_STARTUP_TEST_VERSION:'26.10.3-fios-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture'}).status,0,'Fixture close must remain idempotent after descriptor reuse');

 assert.equal(probe(binary).status,0);
 assert.equal(statSync(recordFile).ino,identity.ino,'Closing must never unlink/replace the lock');
 assert.equal(statSync(recordFile).dev,identity.dev);
 refused(binary,{FIOS_NATIVE_STARTUP:'isolated-source-fixture'});
 refused(binary,{FIOS_STARTUP_TEST_VERSION:'26.10.4-fios-platform'});
 for(const bytes of [Buffer.alloc(0),Buffer.concat([record,Buffer.from([0])]),Buffer.from(record)]){
  if(bytes.length===12)bytes[5]=1;
  put(bytes);refused(binary);
 }
 put(record);const foreign=Buffer.from(record);foreign.writeUInt32BE(uid+1,8);put(foreign);refused(binary);put(record);
 chmodSync(recordFile,0o666);refused(binary);chmodSync(recordFile,0o444);
 const extra=path.join(parent,'extra.lock');linkSync(recordFile,extra);try{refused(binary);}finally{unlinkSync(extra);}
 const saved=path.join(parent,'saved.lock');renameSync(recordFile,saved);
 try {refused(binary);assert.equal(existsSync(recordFile),false);symlinkSync(saved,recordFile);refused(binary);}
 finally {if(existsSync(recordFile))unlinkSync(recordFile);renameSync(saved,recordFile);}
 chmodSync(parent,0o777);try{refused(binary);}finally{chmodSync(parent,0o755);}
 const moved=parent+'.saved';renameSync(parent,moved);symlinkSync(moved,parent);
 try{refused(binary);}finally{unlinkSync(parent);renameSync(moved,parent);}
 const pin='if (c.flock(fd, c.LOCK.EX | c.LOCK.NB) != 0) return error.StartupGuardUnavailable;';
 const mutated=build('mutation',replaceOnce(fixture,pin,'// Deliberately omit installed startup exclusion.'));
 let witnessed=false;
 try {await withHeld(mutated,()=>{assert.notEqual(probe(mutated).status,0,'FIO_NATIVE_STARTUP_DUPLICATE_ALLOWED');});}
 catch(error){if(error.message.includes('FIO_NATIVE_STARTUP_DUPLICATE_ALLOWED'))witnessed=true;else throw error;}
 assert(witnessed,'The actual flock omission must fail its exact second-process assertion');
 const released=build('early-release-mutation',replaceOnce(fixture,'if (self.retain_until_exit) return;','// Deliberately release before kernel process exit.'));
 let premature=false;
 try {await withHeld(released,()=>{
  assert.equal(probe(released).status,1,'FIO_NATIVE_STARTUP_EARLY_RELEASE');
 },{FIOS_STARTUP_TEST_EARLY_CLOSE:'1'});}
 catch(error){if(error.message.includes('FIO_NATIVE_STARTUP_EARLY_RELEASE'))premature=true;else throw error;}
 assert(premature,'The actual early-close bypass must allow and expose the second process');

 assert.equal(probe(binary).status,0);
 assert.equal(readFileSync(sourceFile,'utf8'),original);
 console.log('PASS: actual Debug/ReleaseSafe two-process exclusion across HOME changes, kernel-lifetime/retained inode/release/CLOEXEC/fixture close replay, strict record/UID/version/metadata/link refusal and exact flock-omission/early-release witnesses.');
 console.log(JSON.stringify({source_fixture_only:true,production_enrollment:false,native_service:false,native_inference:false,root_ownership_synthetic:true,source_sha256:sha(original),fixture_source_sha256:sha(fixture),harness_sha256:sha(harness)}));
} finally {
 if(cleanupProven)rmSync(scratch,{recursive:true,force:true});
 else console.error('STARTUP_FIXTURE_RETAINED');
}
