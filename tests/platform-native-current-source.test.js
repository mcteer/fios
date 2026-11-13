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
