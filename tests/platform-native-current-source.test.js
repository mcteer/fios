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


test('current llama error custody stays within the existing C shim',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-llama-errors.patch','utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)];
  assert.equal(paths.length,1);
  assert.equal(paths[0][1],'lib/llama_shim/llama_shim.cpp');
  assert.equal(paths[0][2],paths[0][1]);
});


test('current llama construction custody stays within the existing C shim',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-llama-construction.patch','utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)];
  assert.equal(paths.length,1);
  assert.equal(paths[0][1],'lib/llama_shim/llama_shim.cpp');
  assert.equal(paths[0][2],paths[0][1]);
});


test('current registry cleanup preflight stays in the registry and preserves its ordinary fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-registry-cleanup.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/src/host/registry/registry.zig b/src/host/registry/registry.zig\n'));
  const start=sections[0].indexOf('\n+test "fios current registry cleanup');assert(start>=0);
  const fixture=sections[0].slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_registry_cleanup_test.zig.fixture','utf8').trimStart());
});


test('current served close retains its negative cleanup companion and ordinary callback fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-served-close.patch','utf8');
  const expected=new Set(['src/host/engines/served.zig','src/host/registry/registry.zig','src/fios/current_cleanup_uncertainty.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/fios/current_cleanup_uncertainty.zig'){
      assert(section.includes('\nnew file mode 100644\n'));
      const bytes=section.split('\n').filter(line=>line.startsWith('+')&&!line.startsWith('+++')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/current_cleanup_uncertainty.zig','utf8'));
    }
    if(header[1]==='src/host/engines/served.zig'){
      const start=section.indexOf('\n+test "fios current served close');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_served_close_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current registry checked close preserves the two-entry model-free fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-registry-close.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);
  assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/src/host/registry/registry.zig b/src/host/registry/registry.zig\n'));
  const start=sections[0].indexOf('\n+test "fios current registry close');assert(start>=0);
  const fixture=sections[0].slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_registry_close_test.zig.fixture','utf8').trimStart());
});


test('current unload refusal preserves its existing load call graph and model-free accounting fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-unload-refusal.patch','utf8');
  const expected=new Set(['src/host/registry/registry.zig','src/engines/mlx/runtime/model_state.zig','src/engines/mlx/runtime/load_requests.zig','src/engines/mlx/load.zig','src/engines/mlx/runtime/engine_load.zig','src/engines/mlx/scheduler.zig','src/host/gpu_thread/requests.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/engines/mlx/runtime/load_requests.zig'){
      const start=section.indexOf('\n+test "fios current unload refuses');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_unload_refusal_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current scheduler cleanup keeps the host record and existing teardown fixture together',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-scheduler-cleanup.patch','utf8');
  const expected=new Set(['src/host/gpu_thread/scheduler.zig','src/engines/mlx/scheduler.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/engines/mlx/scheduler.zig'){
      const start=section.indexOf('\n+test "fios current scheduler cleanup');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_scheduler_cleanup_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current media cleanup keeps wrapper, registry and unload fixtures at the existing boundaries',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-media-close.patch','utf8');
  const fixtures=new Map([
    ['src/host/media_jobs/plugin/engine.zig',['fios current media close','current_media_close_test.zig.fixture']],
    ['src/host/registry/registry.zig',['fios current registry media close','current_registry_media_close_test.zig.fixture']],
    ['src/engines/mlx/runtime/load_requests.zig',['fios current media unload','current_media_unload_refusal_test.zig.fixture']],
  ]);
  const expected=new Set([...fixtures.keys(),'src/engines/mlx/runtime/model_state.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(fixtures.has(header[1])){
      const [name,file]=fixtures.get(header[1]);
      const start=section.indexOf('\n+test "'+name);assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/'+file,'utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current slot cleanup preserves its original model custody and scheduler quarantine fixtures',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-slot-cleanup.patch','utf8');
  const expected=new Set(['src/engines/mlx/slot.zig','src/engines/mlx/scheduler.zig','src/engines/mlx/runtime/loop.zig','src/host/gpu_thread/scheduler.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/engines/mlx/scheduler.zig'){
      const start=section.indexOf('\n+test "fios current slot cleanup');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      const files=['current_slot_cleanup_test.zig.fixture','current_scheduler_slot_cleanup_test.zig.fixture','current_side_slot_cleanup_test.zig.fixture','current_untracked_slot_custody_test.zig.fixture'];
      assert.equal(fixture,files.map((file,i)=>{const data=readFileSync('platform/studio/native/'+file,'utf8');return i===0?data.trimStart():data;}).join(''));
    }
  }
  assert.equal(expected.size,0);
});


test('current request book cleanup preserves locked negative evidence and actual parent fixtures',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-book-cleanup.patch','utf8');
  const fixtures=new Map([
    ['src/engines/own_thread/book.zig',['fios current book cleanup','current_book_cleanup_test.zig.fixture']],
    ['src/engines/llama/engine.zig',['fios current llama close','current_llama_book_parent_test.zig.fixture']],
  ]);
  const helper='src/fios/current_locked_cleanup_uncertainty.zig';
  const expected=new Set([...fixtures.keys(),'src/engines/ds4/engine.zig','src/engines/ane/engine.zig',helper]);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]===helper){
      assert(section.includes('\nnew file mode 100644\n'));
      const bytes=section.split('\n').filter(line=>line.startsWith('+')&&!line.startsWith('+++')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/current_locked_cleanup_uncertainty.zig','utf8'));
    }
    if(fixtures.has(header[1])){
      const [name,file]=fixtures.get(header[1]);
      const start=section.indexOf('\n+test "'+name);assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/'+file,'utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current MLX teardown propagates plugin refusal through model and registry custody',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-mlx-registry-cleanup.patch','utf8');
  const expected=new Set(['src/engines/mlx/plugin/driver.zig','src/engines/mlx/transformer.zig','src/engines/mlx/runtime/model_state.zig','src/host/registry/registry.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/host/registry/registry.zig'){
      const start=section.indexOf('\n+test "fios current MLX model teardown');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_mlx_registry_cleanup_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current served construction checks uncertainty before publication and ANE fallback',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-served-open.patch','utf8');
  const expected=new Set(['src/host/engines/served.zig','src/engines/mlx/runtime/engine_load.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/host/engines/served.zig'){
      const start=section.indexOf('\n+test "fios current served open refuses');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_served_open_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current registry negative guards preserve ready and cold bookkeeping fixtures',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-registry-negative-guards.patch','utf8');
  const expected=new Set(['src/host/registry/registry.zig','src/engines/mlx/scheduler.zig','src/engines/mlx/runtime/loop.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/host/registry/registry.zig'){
      const start=section.indexOf('\n+test "fios current ready model borrow');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_registry_negative_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current load reservation keeps uncertain and pre-epoch parent fixtures together',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-load-reservation.patch','utf8');
  const expected=new Set(['src/host/registry/registry.zig','src/engines/mlx/scheduler.zig','src/engines/mlx/runtime/load_requests.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1]==='src/engines/mlx/runtime/load_requests.zig'){
      const start=section.indexOf('\n+test "fios current uncertain load failure');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_load_reservation_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current native load custody keeps media publication and raw cleanup fixtures exact',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-native-load-custody.patch','utf8');
  const fixtures=new Map([
    ['src/host/media_jobs/plugin/engine.zig',['fios current media load refuses','current_media_load_test.zig.fixture']],
    ['src/engines/mlx/runtime/model_state.zig',['fios current raw MLX state API','current_raw_model_cleanup_test.zig.fixture']],
  ]);
  const expected=new Set(fixtures.keys());
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    const [name,file]=fixtures.get(header[1]);
    const start=section.indexOf('\n+test "'+name);assert(start>=0);
    const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
    assert.equal(fixture,readFileSync('platform/studio/native/'+file,'utf8').trimStart());
  }
  assert.equal(expected.size,0);
});


test('current plugin construction preserves exact publication and cleanup-order fixtures',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-plugin-load-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);assert.equal(sections.length,1);
  const section=sections[0];assert(section.startsWith('diff --git a/src/engines/mlx/plugin/driver.zig b/src/engines/mlx/plugin/driver.zig\n'));
  const start=section.indexOf('\n+test "fios current plugin load refuses');assert(start>=0);
  const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_plugin_load_test.zig.fixture','utf8').trimStart());
});


test('current DS4 request-buffer fixture preserves historical behavior with real current accessors',()=>{
  const legacy=readFileSync('platform/studio/native/ds4_request_origins.zig.fixture','utf8');
  const expected=legacy.replaceAll('@import("request_ownership.zig")','@import("fios/request_ownership.zig")')
    .replaceAll('@import("sdk_request_ownership.zig")','@import("fios/sdk_request_ownership.zig")')
    .replaceAll('owners.shared.','owners.shared().').replaceAll('owners.current =','owners.current().* =');
  assert.equal(readFileSync('platform/studio/native/current_ds4_request_origins_test.zig.fixture','utf8'),expected);
});


test('current DS4 private composition preserves canonical negative helpers and exact bridge inputs',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ds4-composition.patch','utf8');
  const companions=['current_ds4_owners.cpp','current_ds4_backend_uncertainty.zig','current_ds4_cleanup_uncertainty.zig','current_ds4_locked_cleanup_uncertainty.zig'];
  const expected=new Set(['build/libs.zig','build/macos.zig','src/engines/ane/engine.zig','src/engines/ds4/engine.zig','src/engines/llama/engine.zig','src/engines/mlx/plugin/driver.zig','src/engines/mlx/transformer.zig','src/engines/own_thread/book.zig','src/host/engines/served.zig','src/host/http/server.zig','src/host/media_jobs/plugin/engine.zig','src/host/registry/registry.zig',...companions.map(name=>'src/fios/'+name)]);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);
    assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1].startsWith('src/fios/')){
      assert(section.includes('\nnew file mode 100644\n'));
      const bytes=section.split('\n').filter(line=>line.startsWith('+')&&!line.startsWith('+++')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/'+header[1].slice('src/fios/'.length),'utf8'));
    }
  }
  assert.equal(expected.size,0);
  for(const name of ['current_cleanup_uncertainty.zig','current_locked_cleanup_uncertainty.zig']){
    assert.equal(readFileSync('platform/studio/native/'+name.replace('current_','current_ds4_'),'utf8'),readFileSync('platform/studio/native/'+name,'utf8').replaceAll('current_backend_uncertainty.zig','current_ds4_backend_uncertainty.zig'));
  }
});


test('current ANE pool publication preserves the exact model-free constructor fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-pool-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);assert.equal(sections.length,1);
  const section=sections[0];assert(section.startsWith('diff --git a/src/engines/ane/engine.zig b/src/engines/ane/engine.zig\n'));
  const start=section.indexOf('\n+// Existing model-free bridge only;');assert(start>=0);
  const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
  assert.equal(fixture,readFileSync('platform/studio/native/current_ane_pool_test.zig.fixture','utf8').trimStart());
});


test('current DS4 and llama constructor patches preserve exact model-free boundary fixtures',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-adapter-constructor-custody.patch','utf8');
  const expected=new Set(['src/engines/ds4/engine.zig','src/engines/ds4/load.zig','src/engines/llama/engine.zig','src/engines/llama/load.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1].endsWith('/engine.zig')){
      const backend=header[1].split('/')[2];const start=section.indexOf('\n+// Existing model-free bridge with metadata callbacks;');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_'+backend+'_constructor_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);
});


test('current ANE outcome latch composes exact helpers and bookkeeping fixture without changing canonical probes',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-run-custody.patch','utf8');
  const expected=new Set(["src/engines/ane/engine.zig", "src/engines/ane/lm.zig", "src/engines/ane/rt.zig", "src/engines/ds4/engine.zig", "src/engines/ds4/load.zig", "src/engines/llama/engine.zig", "src/engines/llama/load.zig", "src/engines/mlx/plugin/driver.zig", "src/engines/mlx/transformer.zig", "src/engines/own_thread/book.zig", "src/fios/current_ane_backend_uncertainty.zig", "src/fios/current_ane_cleanup_uncertainty.zig", "src/fios/current_ane_locked_cleanup_uncertainty.zig", "src/fios/current_ane_run_uncertainty.zig", "src/host/engines/served.zig", "src/host/http/server.zig", "src/host/media_jobs/plugin/engine.zig", "src/host/registry/registry.zig"]);
  const companions=new Set(['current_ane_run_uncertainty.zig','current_ane_backend_uncertainty.zig','current_ane_cleanup_uncertainty.zig','current_ane_locked_cleanup_uncertainty.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1].startsWith('src/fios/')){
      assert(companions.delete(header[1].slice('src/fios/'.length)));assert(section.includes('\nnew file mode 100644\n'));
      const bytes=section.split('\n').filter(line=>line.startsWith('+')&&!line.startsWith('+++')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/'+header[1].slice('src/fios/'.length),'utf8'));
    }
    if(header[1]==='src/engines/ane/lm.zig'){
      const start=section.indexOf('\n+// Direct bookkeeping outcomes only;');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_ane_run_outcome_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);assert.equal(companions.size,0);
  for(const name of ['current_cleanup_uncertainty.zig','current_locked_cleanup_uncertainty.zig']){
    assert.equal(readFileSync('platform/studio/native/'+name.replace('current_','current_ane_'),'utf8'),readFileSync('platform/studio/native/'+name,'utf8').replaceAll('current_backend_uncertainty.zig','current_ane_backend_uncertainty.zig'));
  }
});


test('current checked ANE custody preserves exact negative companions and model-free pool fixture',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-parent-custody.patch','utf8');
  const expected=new Set(["build/macos.zig", "lib/ane/ane_bridge.h", "lib/ane/ane_bridge.m", "src/engines/ane/dflash.zig", "src/engines/ane/engine.zig", "src/engines/ane/lm.zig", "src/engines/ane/rt.zig", "src/engines/ds4/engine.zig", "src/engines/ds4/load.zig", "src/engines/llama/engine.zig", "src/engines/llama/load.zig", "src/engines/mlx/plugin/driver.zig", "src/engines/mlx/transformer.zig", "src/engines/own_thread/book.zig", "src/fios/current_ane_native_backend_uncertainty.zig", "src/fios/current_ane_native_cleanup_uncertainty.zig", "src/fios/current_ane_native_locked_cleanup_uncertainty.zig", "src/host/engines/served.zig", "src/host/http/server.zig", "src/host/media_jobs/plugin/engine.zig", "src/host/registry/registry.zig"]);
  const companions=new Set(['current_ane_native_backend_uncertainty.zig','current_ane_native_cleanup_uncertainty.zig','current_ane_native_locked_cleanup_uncertainty.zig']);
  for(const section of patch.split(/(?=^diff --git )/m).filter(Boolean)){
    const header=/^diff --git a\/(\S+) b\/(\S+)\n/.exec(section);assert(header);assert.equal(header[1],header[2]);assert(expected.delete(header[1]));
    if(header[1].startsWith('src/fios/')){
      assert(companions.delete(header[1].slice('src/fios/'.length)));assert(section.includes('\nnew file mode 100644\n'));
      const bytes=section.split('\n').filter(line=>line.startsWith('+')&&!line.startsWith('+++')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(bytes,readFileSync('platform/studio/native/'+header[1].slice('src/fios/'.length),'utf8'));
    }
    if(header[1]==='src/engines/ane/lm.zig'){
      const start=section.indexOf('\n+// Pure bookkeeping graph:');assert(start>=0);
      const fixture=section.slice(start+1).split('\n').filter(line=>line.startsWith('+')).map(line=>line.slice(1)).join('\n')+'\n';
      assert.equal(fixture,readFileSync('platform/studio/native/current_ane_pool_close_test.zig.fixture','utf8').trimStart());
    }
  }
  assert.equal(expected.size,0);assert.equal(companions.size,0);
  for(const name of ['current_cleanup_uncertainty.zig','current_locked_cleanup_uncertainty.zig']){
    assert.equal(readFileSync('platform/studio/native/'+name.replace('current_','current_ane_native_'),'utf8'),readFileSync('platform/studio/native/'+name,'utf8').replaceAll('current_backend_uncertainty.zig','current_ane_native_backend_uncertainty.zig'));
  }
});


test('current private ANE PID policy changes only the declared bridge source',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-pid-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/lib/ane/ane_bridge.m b/lib/ane/ane_bridge.m\n'));
  const fixture=readFileSync('platform/studio/native/current_ane_pid_metadata.c.fixture','utf8');
  const calls=new Set([...fixture.replace(/"(?:[^"\\]|\\.)*"/g,'""').matchAll(/\b([A-Za-z_]\w*)\s*\(/g)].map(match=>match[1]));
  assert.deepEqual([...calls].sort(),['fios_ane_pid_metadata_allows_reap','fprintf','if','main'].sort());
});


test('current private ANE staging custody changes only the declared bridge source',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-staging-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/lib/ane/ane_bridge.m b/lib/ane/ane_bridge.m\n'));
  const fixture=readFileSync('platform/studio/native/current_ane_staging.m.fixture','utf8');
  assert(fixture.includes('fios_ane_prepare_staging'));
  assert(!/\b(?:kill|msv_ane_\w+|objc_msgSend)\s*\(/.test(fixture));
});


test('current private ANE compile custody changes only the declared bridge source',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-compile-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/lib/ane/ane_bridge.m b/lib/ane/ane_bridge.m\n'));
  const fixture=readFileSync('platform/studio/native/current_ane_compile_metadata.m.fixture','utf8');
  assert(fixture.includes('FiosCompileMetadata'));
  assert(!/\b_ANE[A-Za-z]/.test(fixture));
  assert(!/\b(?:kill|objc_msgSend)\s*\(/.test(fixture));
});


test('current private legacy ANE custody changes only the declared bridge pair',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-legacy-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);assert.equal(sections.length,2);
  const expected=new Set(['lib/ane/ane_bridge.m','lib/ane/ane_bridge.h']);
  for(const section of sections){ const name=section.match(/^diff --git a\/(\S+) b\/(\S+)/);assert(name&&name[1]===name[2]&&expected.delete(name[1])); }
  assert.equal(expected.size,0);
  const fixture=readFileSync('platform/studio/native/current_ane_legacy_metadata.m.fixture','utf8');
  assert(fixture.includes('FiosCleanupMetadata'));assert(!/\b_ANE[A-Za-z]/.test(fixture));
});


test('current private ANE resident custody changes only the declared bridge source',()=>{
  const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-ane-resident-custody.patch','utf8');
  const sections=patch.split(/(?=^diff --git )/m).filter(Boolean);assert.equal(sections.length,1);
  assert(sections[0].startsWith('diff --git a/lib/ane/ane_bridge.m b/lib/ane/ane_bridge.m\n'));
  const fixture=readFileSync('platform/studio/native/current_ane_resident_metadata.m.fixture','utf8');
  assert(fixture.includes('FiosResidentMetadata'));assert(!/\b_ANE[A-Za-z]/.test(fixture));
});
