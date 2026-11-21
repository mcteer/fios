import test from 'node:test';
import assert from 'node:assert/strict';
import {localLinuxProcessExited} from '../scripts/lib/linux-process-exited.mjs';

test('fixture child disappearing before the proc read is an observed local exit', () => {
  const seen=[];
  assert.equal(localLinuxProcessExited(182,(path,encoding)=>{
    seen.push([path,encoding]);throw Object.assign(new Error('exited'),{code:'ENOENT'});
  }),true);
  assert.deepEqual(seen,[['/proc/182/stat','utf8']]);
});
test('fixture proc state accepts live and zombie observations with parenthesized names', () => {
  for(const name of ['python','worker name','worker ) ( nested']){
    assert.equal(localLinuxProcessExited(182,()=>`182 (${name}) S 1 2 3`),false);
    assert.equal(localLinuxProcessExited(182,()=>`182 (${name}) Z 1 2 3`),true);
  }
});
test('fixture observation errors and malformed or foreign rows cannot certify exit', () => {
  for(const code of ['EACCES','EIO','EAGAIN']){
    const error=Object.assign(new Error('unavailable'),{code});
    assert.throws(()=>localLinuxProcessExited(182,()=>{throw error;}),value=>value===error);
  }
  for(const row of ['', '183 (python) Z 1', '182 python Z 1', '182 (python) ZOMBIE 1'])
    assert.throws(()=>localLinuxProcessExited(182,()=>row));
  for(const pid of [0,-1,1.5,NaN,Infinity])assert.throws(()=>localLinuxProcessExited(pid,()=>''));
});
test('the exact embedded fixture function retains the exit/read-error behavior', () => {
  const embedded=Function('return ('+localLinuxProcessExited.toString()+')')();
  assert.equal(embedded(182,()=>{throw Object.assign(new Error('gone'),{code:'ENOENT'});}),true);
  assert.equal(embedded(182,()=> '182 (python) S 1'),false);
});
