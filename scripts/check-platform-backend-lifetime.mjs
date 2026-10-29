#!/usr/bin/env node
// Finite native metadata custody test, not a fake backend/model/terminal proof.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,writeFileSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
const args=process.argv.slice(2),root=path.resolve(import.meta.dirname,'..');
assert(args[0]==='--zig'&&path.isAbsolute(args[1]??'')&&(args.length===2||(args.length===3&&['--release','--mutation-close-edge'].includes(args[2]))));
const zig=realpathSync(args[1]);
assert.equal(createHash('sha256').update(readFileSync(zig)).digest('hex'),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const scratch=mkdtempSync(path.join(tmpdir(),'fios-backend-custody-')),mutation=args[2]==='--mutation-close-edge';
try {
 const original=readFileSync(path.join(root,'platform/studio/native/backend_lifetime.zig'),'utf8');
 const pin='        if (!self.eligible(except)) return error.LifetimeBusy;';
 assert.equal(original.split(pin).length,2);
 writeFileSync(path.join(scratch,'backend_lifetime.zig'),mutation?original.replace(pin,'        _ = self.eligible(except); // Deliberate held-child close bypass.'):original,{mode:0o600});
 writeFileSync(path.join(scratch,'backend_lifetime_test.zig'),readFileSync(path.join(root,'platform/studio/native/backend_lifetime_test.zig')),{mode:0o600});
 const result=spawnSync(zig,['test',path.join(scratch,'backend_lifetime_test.zig'),...(args.length===3?['-O','ReleaseSafe']:[]),...(mutation?['--test-filter','native lifetime holds children']:[])],{encoding:'utf8',timeout:120000,maxBuffer:1<<20});
 const output=(result.stdout??'')+(result.stderr??'');process.stdout.write(output);
 assert.equal(result.status,mutation?1:0);
 if(mutation){assert.match(output,/FIO_BACKEND_LIFETIME_CLOSED_HELD_CHILD/);assert.match(output,/1\/1 [\s\S]*FAIL/);}
 else assert.match(output,/All 3 tests passed/);
 assert.equal(readFileSync(path.join(root,'platform/studio/native/backend_lifetime.zig'),'utf8'),original);
 console.log('PASS: bounded native metadata custody '+(mutation?'precise close-edge bypass witness':'holds, replay/exhaustion and concurrent close/borrow')+'; no backend or terminal authority.');
}finally{rmSync(scratch,{recursive:true,force:true});}
