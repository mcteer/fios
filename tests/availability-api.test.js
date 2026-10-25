import test from 'node:test';
import assert from 'node:assert/strict';
import {agentApp} from './agent-support.js';
import {mockMlx} from './mock-mlx.js';
import {AgentClient} from '../src/agent/client.js';

test('stale peer/offline gateway block before persistence; direct harness independently refuses and recovers', async () => {
  const peer=await mockMlx();
  const app=await agentApp({peers:{'studio-a':peer.url}});
  const client=new AgentClient({env:{MLX_BASE_URL:app.mock.url,MLX_PEER_URLS:JSON.stringify({'studio-a':peer.url})}});
  try {
    const target=app.mock.addPeer();
    const chat=await app.chat();
    let catalog=await(await app.request('/api/models')).json();
    assert.equal(catalog.models.find(m=>m.id===target).availability,'available');
    peer.health.status=503;
    catalog=await(await app.request('/api/models')).json();
    assert.equal(catalog.models.find(m=>m.id===target).availability,'unavailable');
    assert.equal((await app.send(chat.id,'must not send',target)).status,503);
    assert.equal((await(await app.request(`/api/chats/${chat.id}`)).json()).messages.length,0);
    await assert.rejects(async()=>{for await(const e of client.run({model:target,context:[{role:'user',content:'direct'}]})){}},e=>e.code==='model_unavailable');
    assert.equal(app.mock.requests.length,0);
    peer.health.status=200;
    peer.catalog.splice(0,peer.catalog.length);
    assert.equal((await app.send(chat.id,'missing',target)).status,503);
    peer.catalog.push({id:'test/coding-model',loaded:false,capabilities:['chat']});
    assert.match(await(await app.send(chat.id,'recovered',target)).text(),/"status":"complete"/);
    assert.equal(app.mock.requests.length,1);
    app.mock.health.status=503;
    catalog=await(await app.request('/api/models')).json();
    assert.ok(catalog.models.every(m=>m.availability!=='available'));
    assert.equal(catalog.hosts.find(h=>h.name==='gateway').status,'unavailable');
    assert.equal((await app.send(chat.id,'offline')).status,503);
    assert.equal(app.mock.requests.length,1);
    app.mock.health.status=200;
    catalog=await(await app.request('/api/models')).json();
    assert.equal(catalog.models.find(m=>m.id==='test/coding-model').availability,'available');
  } finally {await client.close();await app.close();peer.server.closeAllConnections();await new Promise(r=>peer.server.close(r));}
});
