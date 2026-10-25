import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {observe} from '../scripts/observe-hosts.mjs';
import {discover} from '../src/agent/availability.js';
import {mockMlx} from './mock-mlx.js';

test('container observer shares fresh endpoint-bound metadata; offline, expired, tampered and missing observations fail closed',async()=>{
  const gateway=await mockMlx(),peer=await mockMlx();
  gateway.addPeer();
  const root=mkdtempSync(join(tmpdir(),'fios-observer-'));
  const output=join(root,'metadata'),file=join(output,'peers.json');
  writeFileSync(join(root,'.env'),`MLX_BASE_URL=${gateway.url}\nMLX_PEER_URLS=${JSON.stringify({'studio-a':peer.url})}\n`,{mode:0o600});
  const options={base:gateway.url,peers:{'studio-a':peer.url},snapshotFile:file,fetchImpl:async(url,opts)=>{
    assert.ok(!url.startsWith(peer.url),'container must not need direct access to Studio addresses');
    return fetch(url,opts);
  }};
  try{
    await observe({output,env:{MLX_BASE_URL:gateway.url,MLX_PEER_URLS:JSON.stringify({'studio-a':peer.url})}});
    let result=await discover(options);
    assert.equal(result.models.find(m=>m.peer).availability,'available');
    assert.equal(gateway.requests.length+peer.requests.length,0);
    const fresh=JSON.parse(readFileSync(file,'utf8'));
    assert.ok(!JSON.stringify(fresh).includes(peer.url));
    for(const mutate of [v=>{v.peers[0].checkedAt=Date.now()-5001;},v=>{v.peers[0].checkedAt=Date.now()+10000;},v=>{v.peers[0].endpointHash='0'.repeat(64);},v=>{v.peers[0].status='invented';}]){
      const changed=structuredClone(fresh);mutate(changed);writeFileSync(file,JSON.stringify(changed));
      result=await discover(options);assert.equal(result.models.find(m=>m.peer).availability,'unknown');
    }
    peer.health.status=503;
    await observe({repo:root,output});
    result=await discover(options);assert.equal(result.models.find(m=>m.peer).availability,'unavailable');
    peer.health.status=200;
    await observe({repo:root,output});
    result=await discover(options);assert.equal(result.models.find(m=>m.peer).availability,'available');
    rmSync(file);
    result=await discover(options);assert.equal(result.models.find(m=>m.peer).availability,'unknown');
  }finally{
    for(const mock of [gateway,peer]){mock.server.closeAllConnections();await new Promise(r=>mock.server.close(r));}
    rmSync(root,{recursive:true,force:true});
  }
});
