import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync,symlinkSync,statSync,utimesSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {capturePlatformSources,verifyPlatformSources} from '../scripts/lib/platform-source.mjs';

function fixture(run) {
 const root=mkdtempSync(path.join(tmpdir(),'fios-source-proof-'));
 try {const file=path.join(root,'source.swift');writeFileSync(file,'original');run(root,file);}finally{rmSync(root,{recursive:true,force:true});}
}
test('platform build source proof is deterministic but fences content/list mutation',()=>fixture((root,file)=>{
 const proof=capturePlatformSources(root,[file]);
 assert.equal(capturePlatformSources(root,[file]).digest,proof.digest);
 verifyPlatformSources(proof,root,[file]);
 const added=path.join(root,'added.swift');writeFileSync(added,'added');
 assert.throws(()=>verifyPlatformSources(proof,root,[file,added]));
 writeFileSync(file,'changed');assert.throws(()=>verifyPlatformSources(proof,root,[file]));
}));
test('source restoration cannot hide an edit made during compilation',()=>fixture((root,file)=>{
 const proof=capturePlatformSources(root,[file]),old=statSync(file);
 writeFileSync(file,'changed');writeFileSync(file,'original');utimesSync(file,old.atime,old.mtime);
 assert.equal(capturePlatformSources(root,[file]).digest,proof.digest);
 assert.throws(()=>verifyPlatformSources(proof,root,[file]));
}));
test('temporary source-directory changes cannot disappear behind a restored file list',()=>fixture((root,file)=>{
 const proof=capturePlatformSources(root,[file]),temporary=path.join(root,'temporary.swift');
 writeFileSync(temporary,'temporary');rmSync(temporary);
 assert.equal(capturePlatformSources(root,[file]).digest,proof.digest);
 assert.throws(()=>verifyPlatformSources(proof,root,[file]));
}));
test('source proof rejects duplicate, escaping and symbolic inputs',()=>fixture((root,file)=>{
 assert.throws(()=>capturePlatformSources(root,[file,file]));
 assert.throws(()=>capturePlatformSources(root,[path.join(root,'../outside')]));
 const link=path.join(root,'link.swift');symlinkSync(file,link);
 assert.throws(()=>capturePlatformSources(root,[link]));
}));
