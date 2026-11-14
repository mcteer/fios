#!/usr/bin/env node
// Disposable kernel-authenticated Unix RPC plus fake application transport.
// No root policy, GUI app, keychain, runtime, launchd or inference operation.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,copyFileSync,readdirSync,readFileSync,writeFileSync,existsSync,mkdirSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {createConnection} from 'node:net';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {fileURLToPath} from 'node:url';
assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const mutation=process.argv[3]==='--mutate-eof';
assert.deepEqual(process.argv.slice(2),mutation?['--isolated','--mutate-eof']:['--isolated']);
const root=fileURLToPath(new URL('../',import.meta.url)),temporary=mkdtempSync('/tmp/fios009-session-rpc-'),state=join(temporary,'state');
mkdirSync(state,{mode:0o700});const children=[],sockets=[];
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,limit=5000){const end=performance.now()+limit;while(performance.now()<end){const value=check();if(value)return value;await delay(20);}throw Error('Finite session RPC fixture deadline');}
function frame(value){const body=Buffer.from(JSON.stringify(value)),head=Buffer.alloc(4);head.writeUInt32BE(body.length);return Buffer.concat([head,body]);}
async function raw(value,extra=Buffer.alloc(0)){
 const socket=createConnection(join(state,'session-control.sock'));sockets.push(socket);socket.on('error',()=>{});socket.setTimeout(3000,()=>socket.destroy());
 await new Promise((accept,reject)=>{socket.once('connect',accept);socket.once('error',reject);});
 const reply=new Promise(resolve=>{const blocks=[];socket.on('data',b=>blocks.push(b));socket.once('close',()=>resolve(Buffer.concat(blocks)));});
 socket.end(Buffer.concat([frame(value),extra]));return reply;
}
try {
 const core=join(root,'platform/studio/Sources/StudioCore'),source=join(temporary,'SessionTransport.swift'),binary=join(temporary,'session-rpc');
 copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/SessionTransport.swift.fixture'),source);
 const sources=readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>{
  const original=join(core,n);if(!mutation||n!=='SessionControl.swift')return original;
  const bytes=readFileSync(original,'utf8');assert.equal(bytes.split('maximum:1024,requireEOF:true').length,2);
  const copy=join(temporary,n);writeFileSync(copy,bytes.replace('maximum:1024,requireEOF:true','maximum:1024,requireEOF:false'));return copy;
 });
 const built=spawnSync('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,source,'-o',binary],{cwd:root,encoding:'utf8',timeout:180000,maxBuffer:65536});
 assert.equal(built.status,0,'Session RPC fixture build failed: '+built.stderr);
 const server=spawn('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))',binary,'server',state],{stdio:'ignore'});children.push(server);
 await until(()=>existsSync(join(state,'session-control.json')));
 const metadata=JSON.parse(readFileSync(join(state,'session-control.json')));
 const request={version:1,id:randomUUID(),operation:'launch',service:'mlx',instance:metadata.instance,profile:metadata.profile};
 // Node has the correct UID but the wrong executable: metadata cannot mint
 // manager authority or supply a forged caller PID/role.
 await raw(request);assert.equal(existsSync(join(state,'calls')),false);
 await raw({...request,pid:server.pid,role:'operator'});assert.equal(existsSync(join(state,'calls')),false);
 const nonce=randomUUID();
 const invoke=(operation,id)=>spawnSync(binary,['client',state,operation,id],{encoding:'utf8',timeout:5000,maxBuffer:4096});
 for(const operation of ['launch','launch','lookup']){const result=invoke(operation,nonce);assert.equal(result.status,0,result.stderr);assert.equal(result.stdout.trim(),'not_sent');}
 assert.equal(readFileSync(join(state,'calls'),'utf8'),'1','Replayed RPC executed the fake action twice');
 const missing=invoke('lookup',randomUUID());assert.equal(missing.status,0,missing.stderr);assert.equal(missing.stdout.trim(),'uncertain');
 assert.equal(readFileSync(join(state,'calls'),'utf8'),'1');
 const partial=invoke('partial',randomUUID());assert.equal(partial.status,0,partial.stderr);assert.equal(partial.stdout.trim(),'partial_pass');
 assert.equal(readFileSync(join(state,'calls'),'utf8'),'2');
 const trailing=invoke('trailing',randomUUID());assert.equal(trailing.status,0,trailing.stderr);assert.equal(trailing.stdout.trim(),'trailing_pass');
 assert.equal(readFileSync(join(state,'calls'),'utf8'),'2','Trailing-byte request executed an action');
 // A slow unauthenticated caller must neither execute nor block another RPC.
 const slow=createConnection(join(state,'session-control.sock'));sockets.push(slow);slow.on('error',()=>{});
 await new Promise(resolve=>slow.once('connect',resolve));slow.write(Buffer.from([0]));
 const began=performance.now(),live=invoke('lookup',nonce);assert.equal(live.status,0);assert(performance.now()-began<2000);slow.destroy();
 const duplicate=spawn(binary,['server',state],{stdio:'ignore'});children.push(duplicate);await until(()=>exited(duplicate));assert.notEqual(duplicate.exitCode,0);
 assert.equal(invoke('lookup',nonce).status,0,'Duplicate helper replaced the active socket');
 server.kill('SIGTERM');await until(()=>exited(server));
 console.log('PASS: actual UID/PID/start/hash authenticated private session RPC, wrong-image/forged-role refusal, once-only launch/lookup, unknown-history uncertainty, nonblocking slow client and singleton; fake launcher only.');
}finally {
 for(const socket of sockets)socket.destroy();
 for(const child of children)if(!exited(child))child.kill('SIGTERM');
 await until(()=>children.every(exited),10000);
 rmSync(temporary,{recursive:true,force:true});
}
