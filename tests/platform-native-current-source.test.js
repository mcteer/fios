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
