import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
test('Python candidate copies only rooted files and retains descriptor custody on destination races',()=>{
 const r=spawnSync(fileURLToPath(new URL('../.venv/bin/python',import.meta.url)),['-I','-B',fileURLToPath(new URL('./fixtures/platform/python-candidate.py',import.meta.url))],{encoding:'utf8',timeout:15000,maxBuffer:65536});
 assert.equal(r.status,0,r.stderr);assert.match(r.stderr,/Ran 8 tests/);
});
