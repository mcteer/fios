#!/usr/bin/env node
// Finite native metadata custody test, not a fake backend/model/terminal proof.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,writeFileSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
const args=process.argv.slice(2),root=path.resolve(import.meta.dirname,'..');
assert(args[0]==='--zig'&&path.isAbsolute(args[1]??'')&&(args.length===2||(args.length===3&&['--release','--mutation-close-edge','--mutation-fence'].includes(args[2]))));
const zig=realpathSync(args[1]);
assert.equal(createHash('sha256').update(readFileSync(zig)).digest('hex'),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const scratch=mkdtempSync(path.join(tmpdir(),'fios-backend-custody-')),mutation=args[2]?.startsWith('--mutation-')??false,fenceMutation=args[2]==='--mutation-fence';
try {
 const original=readFileSync(path.join(root,'platform/studio/native/backend_lifetime.zig'),'utf8');
 const pin='        if (!self.eligible(except)) return error.LifetimeBusy;';
 assert.equal(original.split(pin).length,2);
 const fencePin='        self.uncertain = true;\n    }\n    pub fn canClose';
 assert.equal(original.split(fencePin).length,2);
 const candidate=fenceMutation?original.replace(fencePin,'        // Deliberate uncertainty fence omission.\n    }\n    pub fn canClose'):mutation?original.replace(pin,'        _ = self.eligible(except); // Deliberate held-child close bypass.'):original;
 writeFileSync(path.join(scratch,'backend_lifetime.zig'),candidate,{mode:0o600});
 writeFileSync(path.join(scratch,'backend_lifetime_test.zig'),readFileSync(path.join(root,'platform/studio/native/backend_lifetime_test.zig')),{mode:0o600});
 const result=spawnSync(zig,['test',path.join(scratch,'backend_lifetime_test.zig'),...(args.length===3?['-O','ReleaseSafe']:[]),...(mutation?['--test-filter',fenceMutation?'native lifetime foreign replay':'native lifetime holds children']:[])],{encoding:'utf8',timeout:120000,maxBuffer:1<<20});
 const output=(result.stdout??'')+(result.stderr??'');process.stdout.write(output);
 assert.equal(result.status,mutation?1:0);
 if(mutation){assert.match(output,fenceMutation?/FIO_BACKEND_LIFETIME_FENCE_REOPENED/:/FIO_BACKEND_LIFETIME_CLOSED_HELD_CHILD/);assert.match(output,/1\/1 [\s\S]*FAIL/);}
 else assert.match(output,/All 3 tests passed/);
 assert.equal(readFileSync(path.join(root,'platform/studio/native/backend_lifetime.zig'),'utf8'),original);
 console.log('PASS: bounded native metadata custody '+(mutation?(fenceMutation?'precise uncertainty-fence omission witness':'precise close-edge bypass witness'):'holds, sticky uncertainty, replay/exhaustion and concurrent close/borrow')+'; no backend or terminal authority.');
}finally{rmSync(scratch,{recursive:true,force:true});}
