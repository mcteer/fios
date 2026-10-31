import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,lstatSync,renameSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {verifyDs4DeclaredSource} from '../scripts/lib/platform-ds4-source-review.mjs';
function fixture(t){
 const directory=mkdtempSync(path.join(tmpdir(),'fios-ds4-source-identity-'));
 t.after(()=>rmSync(directory,{recursive:true,force:true}));
 const file=path.join(directory,'source.c');writeFileSync(file,'original',{mode:0o600});
 const s=lstatSync(file),record={bytes:s.size,sha256:createHash('sha256').update(readFileSync(file)).digest('hex'),inode:s.ino,mtime:s.mtimeMs,ctime:s.ctimeMs};
 return {directory,file,record};
}
test('declared DS4 source bytes and original file identity verify together',t=>{
 const {file,record}=fixture(t);assert.doesNotThrow(()=>verifyDs4DeclaredSource(file,record));
 writeFileSync(file,'modified');assert.throws(()=>verifyDs4DeclaredSource(file,record));
});
test('restoring identical declared source bytes cannot hide file replacement',t=>{
 const {directory,file,record}=fixture(t),replacement=path.join(directory,'replacement.c');
 writeFileSync(replacement,'original',{mode:0o600});assert.notEqual(lstatSync(replacement).ino,record.inode);
 renameSync(replacement,file);
 assert.throws(()=>verifyDs4DeclaredSource(file,record),'replaced source identity must not inherit the original build receipt');
});
