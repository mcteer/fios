import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// Source-input integrity only; actual compilation/HTTP/Unix/manager receipts
// are separate. This test grants no backend coverage or admission authority.
test('current ingress patch changes only host integration and exact shared companions',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ingress.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  const companions=['request_ownership.zig','control_protocol.zig','control_transport.zig','device_owner.zig'];
  const expected=new Set(['src/host/http/request.zig','src/host/http/server.zig',...companions.map(name=>'src/fios/'+name)]);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]),'Unexpected or duplicate port path');
    if(header[1].startsWith('src/fios/')){
      assert(section.includes('\nnew file mode 100644\n'));
      const hunk=section.slice(section.indexOf('\n@@ ')+1).split('\n').slice(1);
      const bytes=hunk.filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/'+header[1].slice('src/fios/'.length),'utf8'));
    }
  }
  assert.equal(expected.size,0);
});

test('current process-instance addition remains separate from engine implementation',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-instance.patch','utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)];
  assert.equal(paths.length,2);
  assert.deepEqual(new Set(paths.map(match=>{
    assert.equal(match[1],match[2]);return match[1];
  })),new Set(['src/fios/instance_header.zig','src/host/http/router.zig']));
});

test('current local-target addition changes only the host router',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-target.patch','utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)];
  assert.equal(paths.length,1);
  assert.equal(paths[0][1],'src/host/http/router.zig');
  assert.equal(paths[0][2],paths[0][1]);
});

test('current startup addition preserves the existing exclusion companion',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-startup.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,2);
  const expected=new Set(['src/main.zig','src/fios/startup_guard.zig']);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/fios/startup_guard.zig'){
      assert(section.includes('\nnew file mode 100644\n'));
      const hunk=section.slice(section.indexOf('\n@@ ')+1).split('\n').slice(1);
      const bytes=hunk.filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/startup_guard.zig','utf8'));
    }
  }
  assert.equal(expected.size,0);
});

test('current correlation addition stays within host ingress ownership',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-correlation.patch','utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)];
  assert.equal(paths.length,4);
  assert.deepEqual(new Set(paths.map(match=>{
    assert.equal(match[1],match[2]);return match[1];
  })),new Set(['src/fios/correlation_header.zig','src/host/http/request.zig','src/host/http/router.zig','src/host/http/server.zig']));
});

test('current primary phase addition stays in the host and explicit startup scope',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-primary.patch','utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)];
  assert.equal(paths.length,2);
  assert.deepEqual(new Set(paths.map(match=>{
    assert.equal(match[1],match[2]);return match[1];
  })),new Set(['src/host/http/router.zig','src/host/http/server.zig']));
});

test('current MLX dependency ownership addition stays within the seven reviewed SDK paths',()=>{
  const patch=readFileSync('platform/studio/native/mlx-c69303b-owner-uncertainty.patch','utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)];
  assert.equal(paths.length,7);
  assert.deepEqual(new Set(paths.map(match=>{
    assert.equal(match[1],match[2]);return match[1];
  })),new Set(['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h']));
});

test('current load handoff adds only scheduling metadata and the exact queue companion',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-load-origins.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,4);
  const expected=new Set(['src/host/gpu_thread/requests.zig','src/engines/mlx/scheduler.zig','src/engines/mlx/runtime/load_requests.zig','src/fios/queued_request_ownership.zig']);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/fios/queued_request_ownership.zig'){
      assert(section.includes('\nnew file mode 100644\n'));
      const hunk=section.slice(section.indexOf('\n@@ ')+1).split('\n').slice(1);
      const bytes=hunk.filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/queued_request_ownership.zig','utf8'));
    }
  }
  assert.equal(expected.size,0);
});

test('current shared ownership adapter stays within storage and its existing callers',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-unit-ownership.patch','utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)];
  assert.equal(paths.length,7);
  assert.deepEqual(new Set(paths.map(match=>{
    assert.equal(match[1],match[2]);return match[1];
  })),new Set(['src/fios/request_ownership.zig','src/fios/queued_request_ownership.zig','src/fios/control_transport.zig','src/host/http/request.zig','src/host/http/router.zig','src/host/http/server.zig','src/shared_all.zig']));
});

test('current optional SDK bridge preserves canonical native owner logic with shared accessors',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-sdk-ownership.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,5);
  const expected=new Set(['build/macos.zig','src/fios/current_sdk_owners.cpp','src/fios/sdk_request_ownership.zig','src/fios/request_ownership.zig','src/host/http/server.zig']);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/fios/sdk_request_ownership.zig'){
      const hunk=section.slice(section.indexOf('\n@@ ')+1).split('\n').slice(1);
      const bytes=hunk.filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      const original=readFileSync('platform/studio/native/sdk_request_ownership.zig','utf8')
        .replace(/&owners\.shared\b/g,'owners.shared()')
        .replace(/owners\.shared\b(?!\()/g,'owners.shared()')
        .replace(/owners\.current_group\b(?!\()/g,'owners.current_group().*')
        .replace(/owners\.current\b(?!\()/g,'owners.current().*');
      assert.equal(bytes,original);
    }
  }
  assert.equal(expected.size,0);
});

test('current slot custody stays within the existing scheduler and preserves its executable fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-slot-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,2);
  const expected=new Set(['src/engines/mlx/scheduler.zig','src/engines/mlx/slot.zig']);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/engines/mlx/scheduler.zig'){
      const start=section.indexOf('\n+test "fios current slot');
      assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_slot_custody_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});

test('current actor origins preserve the tested helper and actual finish regression',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-actor-origins.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  const expected=new Set(['src/fios/current_slot_origins.zig','src/engines/mlx/scheduler.zig',
    'src/engines/mlx/decode.zig','src/engines/mlx/finish.zig','src/engines/mlx/step.zig',
    'src/engines/mlx/prefill_interleave.zig','src/engines/mlx/runtime/loop.zig']);
  assert.equal(sections.length,expected.size);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/fios/current_slot_origins.zig'){
      const hunk=section.slice(section.indexOf('\n@@ ')+1).split('\n').slice(1);
      const bytes=hunk.filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/current_slot_origins.zig','utf8'));
    }
    if(header[1]==='src/engines/mlx/scheduler.zig'){
      const start=section.indexOf('\n+test "fios current actor');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_actor_origins_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});

test('current media origins preserve the queued adapter and actual sender regression',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-media-origins.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  const expected=new Set(['src/fios/current_queued_origins.zig','src/host/gpu_thread/requests.zig',
    'src/engines/mlx/scheduler.zig','src/engines/mlx/media_encode.zig','src/engines/mlx/runtime/media_runner.zig']);
  assert.equal(sections.length,expected.size);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/fios/current_queued_origins.zig'){
      const hunk=section.slice(section.indexOf('\n@@ ')+1).split('\n').slice(1);
      const bytes=hunk.filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/current_queued_origins.zig','utf8'));
    }
    if(header[1]==='src/engines/mlx/scheduler.zig'){
      const start=section.indexOf('\n+test "fios current media');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_media_origins_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});

test('current request-book custody stays within existing request metadata and preserves its fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-book-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/src/engines/own_thread/book.zig b/src/engines/own_thread/book.zig\n'));
  const start=sections[0].indexOf('\n+test "fios current book');assert(start>=0);
  const fixture=sections[0].slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_book_custody_test.zig.fixture','utf8').trimStart());
});

test('current DS4 actor changes only existing worker attribution and preserves its model-free fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ds4-actor.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/src/engines/ds4/engine.zig b/src/engines/ds4/engine.zig\n'));
  const start=sections[0].indexOf('\n+test "fios current ds4 adapter');assert(start>=0);
  const fixture=sections[0].slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_ds4_actor_test.zig.fixture','utf8').trimStart());
});

test('current ANE actor changes only existing worker attribution and preserves its model-free fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-actor.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/src/engines/ane/engine.zig b/src/engines/ane/engine.zig\n'));
  const start=sections[0].indexOf('\n+test "fios current ane adapter');assert(start>=0);
  const fixture=sections[0].slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_ane_actor_test.zig.fixture','utf8').trimStart());
});

test('current llama actor stays in the existing adapter and preserves its model-free fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-llama-actor.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/src/engines/llama/engine.zig b/src/engines/llama/engine.zig\n'));
  const start=sections[0].indexOf('\n+test "fios current llama adapter');assert(start>=0);
  const fixture=sections[0].slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_llama_actor_test.zig.fixture','utf8').trimStart());
});

test('current llama batch supplement adds only its executable fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-llama-batch-fixture.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/src/engines/llama/engine.zig b/src/engines/llama/engine.zig\n'));
  assert(!sections[0].split('\n').some(line=>line.startsWith('-')&&!line.startsWith('---')));
  const additions=sections[0].split('\n').filter(line=>line.startsWith('+')&&!line.startsWith('+++')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(additions.trimStart(),readFileSync('platform/studio/native/current_llama_batch_test.zig.fixture','utf8').trimStart());
});


test('current offload submission changes only the existing handoff and preserves its model-free fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-offload-submit.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/src/engines/mlx/runtime/offload.zig b/src/engines/mlx/runtime/offload.zig\n'));
  const start=sections[0].indexOf('\n+test "fios current offload submission');assert(start>=0);
  const fixture=sections[0].slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_offload_submit_test.zig.fixture','utf8').trimStart());
});


test('current unload origins preserve the existing queue and model-free worker fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-unload-origins.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  const expected=new Set(['src/host/gpu_thread/requests.zig','src/engines/mlx/scheduler.zig','src/engines/mlx/runtime/load_requests.zig']);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/engines/mlx/runtime/load_requests.zig'){
      const start=section.indexOf('\n+test "fios current unload worker');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_unload_origins_test.zig.fixture','utf8').trimStart()+readFileSync('platform/studio/native/current_queued_unload_test.zig.fixture','utf8'));
    }
  }
  assert.equal(expected.size,0);
});


test('current CPU media ownership keeps the plugin SDK closed and preserves its opaque companions',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-cpu-media-origins.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  const companions=new Map([
    ['src/fios/current_cpu_media_origins.zig','current_cpu_media_origins.zig'],
    ['src/sdk/media/offload_origins.zig','current_cpu_media_hooks.zig'],
  ]);
  const expected=new Set([...companions.keys(),'src/sdk/media/progress.zig','src/host/http/server.zig','src/host/media_jobs/sse.zig']);
  for(const section of sections){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(companions.has(header[1])){
      assert(section.includes('\nnew file mode 100644\n'));
      const bytes=section.split('\n').filter(line=>line.startsWith('+')&&!line.startsWith('+++')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/'+companions.get(header[1]),'utf8'));
    }
    if(header[1]==='src/host/media_jobs/sse.zig'){
      const start=section.indexOf('\n+test "fios current CPU media');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_cpu_media_origins_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current llama parent custody stays in its genuine shim, matching wrappers and fixed negative probe',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-llama-parent.patch','utf8');
  const expected=new Set(['lib/llama_shim/llama_shim.cpp','lib/llama_shim/llama_shim.h','src/engines/llama/bridge.zig','src/engines/llama/ffi.zig','src/host/http/server.zig','src/fios/current_backend_uncertainty.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/fios/current_backend_uncertainty.zig'){
      assert(section.includes('\nnew file mode 100644\n'));
      const bytes=section.split('\n').filter(line=>line.startsWith('+')&&!line.startsWith('+++')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/current_backend_uncertainty.zig','utf8'));
    }
  }
  assert.equal(expected.size,0);
});
