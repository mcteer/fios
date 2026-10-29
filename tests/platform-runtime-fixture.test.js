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
