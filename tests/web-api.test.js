import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {agentApp} from './agent-support.js';
test('authenticated API uses installed Agent tool, resets preliminary text and saves exact source provenance',async()=>{
 const app=await agentApp({python:fileURLToPath(new URL('./fixtures/web-python',import.meta.url))});
 try{
  const c=await app.chat();
  const response=await app.send(c.id,'Python release web evidence');
  assert.equal(response.status,200);
  const stream=await response.text();
  assert.match(stream,/event: answer_reset/);
  assert.match(stream,/event: sources/);
  const detail=await(await app.request('/api/chats/'+c.id)).json();
  const answer=detail.messages.at(-1);
  assert.equal(answer.status,'complete',stream);
  assert.equal(answer.web.evidence_state,'sent_to_model');
  assert.equal(answer.web.sources.length,1);
  assert.equal(answer.web.sources[0].url,'https://www.python.org/doc/');
  assert.doesNotMatch(answer.content,/Preliminary text/);
  assert.equal(app.mock.requests.length,2);
  assert.equal(app.mock.requests[0].model,app.mock.requests[1].model);
  assert.ok(app.mock.requests[1].messages.some(m=>m.role==='tool'&&m.content.includes('fixture version')));
  assert.doesNotMatch(JSON.stringify(detail),/"query"|"excerpt"|"arguments"/);
  await app.request('/api/chats/'+c.id,{method:'DELETE'});
  assert.equal((await app.request('/api/chats/'+c.id)).status,404);
 }finally{await app.close();}
});
