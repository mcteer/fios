import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openStore} from '../server/store.js';
import {initialManifest} from '../src/agent/web-protocol.js';
test('startup recovers idle and active retrieval without overwriting finished outcomes',()=>{
 const directory=mkdtempSync(join(tmpdir(),'fios-web-recover-'));const path=join(directory,'test.sqlite');
 let store=openStore(path);
 try{
  const chat=store.create('mock');
  for(const phase of ['idle','searching','fetching']){
   const m=store.add(chat.id,'assistant','','streaming','mock');
   store.web(m.id,{...initialManifest(),phase,tool_attempted:phase!=='idle'});
  }
  const completed=store.add(chat.id,'assistant','partial answer','streaming','mock');
  store.web(completed.id,{...initialManifest(),phase:'finished',outcome:'empty',reason:'no_results',tool_attempted:true});
  store.db.close();store=openStore(path);
  const messages=store.detail(chat.id).messages;
  for(const m of messages.slice(0,3)){
   assert.equal(m.status,'interrupted');assert.equal(m.web.outcome,'cancelled');assert.equal(m.web.reason,'run_cancelled');
  }
  assert.equal(messages.at(-1).web.outcome,'empty');
  store.db.prepare('UPDATE web_retrieval SET manifest_json=? WHERE message_id=?').run('{"query":"PRIVATE_CANARY"}',completed.id);
  assert.doesNotMatch(JSON.stringify(store.detail(chat.id)),/PRIVATE_CANARY|"query"/);
 }finally{store.db.close();rmSync(directory,{recursive:true,force:true});}
});
test('additive provenance persists safe metadata, validates assistant and cascades deletion',()=>{
 const store=openStore(':memory:');
 try{
  const chat=store.create('mock');
  const user=store.add(chat.id,'user','Python');
  const assistant=store.add(chat.id,'assistant','','streaming','mock');
  assert.throws(()=>store.web(user.id,initialManifest()));
  store.web(assistant.id,initialManifest());
  assert.deepEqual(store.detail(chat.id).messages[1].web,initialManifest());
  assert.throws(()=>store.web(assistant.id,{...initialManifest(),query:'do not persist'}));
  store.remove(chat.id);
  assert.equal(store.db.prepare('SELECT count(*) AS n FROM web_retrieval').get().n,0);
 }finally{store.db.close();}
});
