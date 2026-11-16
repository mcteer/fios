import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
test('combined platform/runtime review links templates, preserves partial data and never executes candidate programs',()=>{
 const result=spawnSync(fileURLToPath(new URL('../.venv/bin/python',import.meta.url)),['-I','-B',fileURLToPath(new URL('./fixtures/platform/composition.py',import.meta.url))],{encoding:'utf8',timeout:30000,maxBuffer:65536});
 assert.equal(result.status,0,result.stderr);assert.match(result.stderr,/Ran 10 tests/);
});
