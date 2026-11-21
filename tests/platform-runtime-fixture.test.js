import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,writeFileSync,readFileSync,rmSync,lstatSync,realpathSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';

test('isolated runtime driver retains evidence after uncertain post-create failure',()=>{
  const directory=mkdtempSync(join(tmpdir(),'fios-fixture-retention-test-'));
  let retained;
  try{
    mkdirSync(join(directory,'scripts'),{mode:0o700});
    const script=join(directory,'scripts/check-platform-sandbox.mjs'),log=join(directory,'commands.jsonl');
    copyFileSync(new URL('../scripts/check-platform-sandbox.mjs',import.meta.url),script);
    // A finite fake CLI only records argv and emits synthetic IDs. It has no
    // socket/client/process API and never contacts a real runtime. Missing
    // Swift fixture source forces failure after the synthetic create result.
    writeFileSync(join(directory,'docker'),`#!/usr/bin/env node
const fs=require('node:fs'),args=process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(log)},JSON.stringify(args)+'\\n');
if(args[0]==='context'){console.log('unix:///var/empty/fios-fixture-never-opened.sock');}
else if(args.includes('create')){console.log('b'.repeat(64));}
else if(args.includes('inspect')||args.includes('build')){console.log('sha256:'+'a'.repeat(64));}
else {process.exitCode=1;}
`,{mode:0o700});
    const result=spawnSync(process.execPath,[script,'--isolated'],{
      encoding:'utf8',timeout:5000,env:{PATH:[directory,dirname(process.execPath),'/usr/bin','/bin'].join(':'),HOME:directory,TMPDIR:directory,LANG:'C',LC_ALL:'C'},
    });
    assert.equal(result.error,undefined);assert.equal(result.status,1);
    const match=result.stderr.match(/^RETAINED: uncertain isolated runtime fixture; no parent cleanup attempted: (.+)$/m);
    assert.ok(match,'Uncertain create lost its retained-state diagnostic');
    const candidate=realpathSync.native(match[1]);
    assert.equal(dirname(candidate),realpathSync.native(directory));
    assert.match(candidate.split('/').at(-1),/^fios-platform-sandbox-/);
    const info=lstatSync(candidate);
    assert.equal(info.isDirectory(),true);assert.equal(info.uid,process.getuid());assert.equal(info.mode&0o777,0o700);
    retained=candidate;
    const commands=readFileSync(log,'utf8').trim().split('\n').map(line=>JSON.parse(line));
    assert.ok(commands.some(args=>args.includes('create')));
    assert.equal(commands.some(args=>args.includes('rm')||args.includes('remove')||args.includes('prune')),false);
    assert.equal(lstatSync(join(retained,'Dockerfile')).isFile(),true);
  }finally{
    // The child is reaped; the fake CLI above cannot create runtime objects.
    // These are known private test files, never native completion evidence.
    if(retained)rmSync(retained,{recursive:true,force:true});
    rmSync(directory,{recursive:true,force:true});
  }
});

test('container recovery driver retains the known created ID and never cleans uncertain resources',()=>{
  const directory=mkdtempSync(join(tmpdir(),'fios-recovery-driver-test-'));let retained;
  try{
    for(const relative of ['scripts','platform/studio/Sources/StudioCore','platform/studio/Tests/StudioCoreTests'])mkdirSync(join(directory,relative),{recursive:true,mode:0o700});
    const script=join(directory,'scripts/check-platform-container.mjs'),log=join(directory,'commands.jsonl');
    copyFileSync(new URL('../scripts/check-platform-container.mjs',import.meta.url),script);
    writeFileSync(join(directory,'scripts/check-platform-sandbox.mjs'),"console.log('FINITE_FAKE_ISOLATION_CHILD');\n");
    writeFileSync(join(directory,'platform/studio/Tests/StudioCoreTests/ContainerRecoveryLive.swift.fixture'),'// Finite fake compiler input only.\n');
    writeFileSync(join(directory,'docker'),`#!/usr/bin/env node
const fs=require('node:fs'),a=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(log)},JSON.stringify(a)+'\\n');
if(a[0]==='context')console.log('unix:///var/empty/fios-fake-never-opened.sock');
else if(a.includes('volume')){
 const path=${JSON.stringify(join(directory,'fake-volume.json'))};
 if(a.includes('create')){const label=a[a.indexOf('--label')+1].split('=');fs.writeFileSync(path,JSON.stringify({Name:a.at(-1),Driver:'local',Labels:{[label[0]]:label[1]}}));console.log(a.at(-1));}
 else if(a.includes('inspect'))console.log(fs.readFileSync(path,'utf8'));else process.exitCode=1;
}
else if(a.includes('image'))console.log('sha256:'+'a'.repeat(64));
else if(a.includes('create'))console.log('c'.repeat(64));
else if(a.includes('inspect'))console.log(JSON.stringify({Id:'c'.repeat(64)}));
else process.exitCode=1;
`,{mode:0o700});
    writeFileSync(join(directory,'swiftc'),`#!/usr/bin/env node
const fs=require('node:fs'),a=process.argv.slice(2),out=a[a.indexOf('-o')+1];
fs.writeFileSync(out,"#!/usr/bin/env node\\nif(process.argv[2]==='create-lost')console.log(JSON.stringify({created_id:'b'.repeat(64),create_result_delivered:false}));else process.exitCode=1;\\n",{mode:0o700});
`,{mode:0o700});
    const result=spawnSync(process.execPath,[script,'--isolated'],{encoding:'utf8',timeout:10000,env:{PATH:[directory,dirname(process.execPath),'/usr/bin','/bin'].join(':'),HOME:directory,TMPDIR:directory,LANG:'C',LC_ALL:'C'}});
    assert.equal(result.error,undefined);assert.equal(result.status,1);
    const match=result.stderr.match(/^RETAINED: uncertain container rehearsal; no parent cleanup attempted: (.+)$/m);assert.ok(match);
    retained=realpathSync.native(match[1]);assert.equal(dirname(retained),realpathSync.native(directory));
    const receipt=JSON.parse(readFileSync(join(retained,'fixture-receipt.json'),'utf8'));
    assert.equal(receipt.phase,'recover-create');
    assert.equal(receipt.created_id,'b'.repeat(64),'Later failure discarded an already-known owned runtime ID');
    const commands=readFileSync(log,'utf8').trim().split('\n').map(JSON.parse);
    assert.equal(commands.some(a=>a.includes('rm')||a.includes('prune')||a.includes('remove')),false);
  }finally{
    // These fakes cannot create a child daemon, socket, container or journal.
    if(retained)rmSync(retained,{recursive:true,force:true});
    rmSync(directory,{recursive:true,force:true});
  }
});

test('runner fixture retains its created ID after failure and preserves a supplied image',()=>{
 const directory=mkdtempSync(join(tmpdir(),'fios-runner-retention-test-'));let retained;
 try{
  mkdirSync(join(directory,'scripts/lib'),{recursive:true,mode:0o700});
  copyFileSync(new URL('../scripts/check-platform-runner.mjs',import.meta.url),join(directory,'scripts/check-platform-runner.mjs'));
  copyFileSync(new URL('../scripts/lib/platform-sandbox-image.mjs',import.meta.url),join(directory,'scripts/lib/platform-sandbox-image.mjs'));
  const log=join(directory,'commands.jsonl'),image='sha256:'+'a'.repeat(64);
  const info={Id:image,Os:'linux',Architecture:'arm64',Config:{User:'65532:65532',WorkingDir:'/workspace',Entrypoint:['/opt/venv/bin/python','-I','-B','/runner.py'],Cmd:null,Env:['PATH=/opt/venv/bin:/usr/bin:/bin','LANG=C','LC_ALL=C','PYTHONDONTWRITEBYTECODE=1']}};
  writeFileSync(join(directory,'docker'),`#!/usr/bin/env node
const fs=require('node:fs'),a=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(log)},JSON.stringify(a)+'\\n');
if(a[0]==='context')console.log('unix:///var/empty/never-opened-runner.sock');else if(a.includes('create'))console.log('b'.repeat(64));else if(a.includes('image')&&a.includes('inspect'))console.log(JSON.stringify([${JSON.stringify(info)}]));else if(a.includes('rm'))console.log('b'.repeat(64));else process.exitCode=1;
`,{mode:0o700});
  const result=spawnSync(process.execPath,[join(directory,'scripts/check-platform-runner.mjs'),'--isolated','--image',image],{encoding:'utf8',timeout:10000,env:{PATH:[directory,dirname(process.execPath),'/usr/bin','/bin'].join(':'),HOME:directory,TMPDIR:directory,LANG:'C',LC_ALL:'C'}});
  assert.equal(result.error,undefined);assert.equal(result.status,1);
  const match=result.stderr.match(/^RETAINED: uncertain runner fixture; no parent cleanup attempted: (.+)$/m);assert.ok(match);
  retained=realpathSync.native(match[1]);assert.equal(dirname(retained),realpathSync.native(directory));
  const state=JSON.parse(readFileSync(join(retained,'fixture-state.json'),'utf8'));
  assert.equal(state.image,image);assert.equal(state.owned[0].id,'b'.repeat(64));
  const commands=readFileSync(log,'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(commands.some(a=>a.includes('rm')||a.includes('prune')),false);
 }finally{if(retained)rmSync(retained,{recursive:true,force:true});rmSync(directory,{recursive:true,force:true});}
});

test('attach fixture retains uncertain image build evidence instead of parent cleanup',()=>{
 const directory=mkdtempSync(join(tmpdir(),'fios-attach-retention-test-'));let retained;
 try{
  mkdirSync(join(directory,'scripts/lib'),{recursive:true,mode:0o700});
  copyFileSync(new URL('../scripts/check-platform-attach.mjs',import.meta.url),join(directory,'scripts/check-platform-attach.mjs'));
  copyFileSync(new URL('../scripts/lib/platform-release.mjs',import.meta.url),join(directory,'scripts/lib/platform-release.mjs'));
  const log=join(directory,'commands.jsonl');
  writeFileSync(join(directory,'docker'),`#!/usr/bin/env node
const fs=require('node:fs'),a=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(log)},JSON.stringify(a)+'\\n');
if(a[0]==='context')console.log('unix:///var/empty/never-opened-attach.sock');else if(a.includes('inspect')||a.includes('build'))console.log('sha256:'+'a'.repeat(64));else process.exitCode=1;
`,{mode:0o700});
  const result=spawnSync(process.execPath,[join(directory,'scripts/check-platform-attach.mjs'),'--isolated'],{encoding:'utf8',timeout:10000,env:{PATH:[directory,dirname(process.execPath),'/usr/bin','/bin'].join(':'),HOME:directory,TMPDIR:directory,LANG:'C',LC_ALL:'C'}});
  assert.equal(result.error,undefined);assert.equal(result.status,1);
  const match=result.stderr.match(/^RETAINED: uncertain attach fixture; no parent cleanup attempted: (.+)$/m);assert.ok(match);
  retained=realpathSync.native(match[1]);assert.equal(dirname(retained),realpathSync.native(directory));
  assert.equal(JSON.parse(readFileSync(join(retained,'fixture-state.json'),'utf8')).image,'sha256:'+'a'.repeat(64));
  const commands=readFileSync(log,'utf8').trim().split('\n').map(JSON.parse);assert.equal(commands.some(a=>a.includes('rm')||a.includes('prune')),false);
 }finally{if(retained)rmSync(retained,{recursive:true,force:true});rmSync(directory,{recursive:true,force:true});}
});
