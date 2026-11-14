#!/usr/bin/env node
// Genuine C++ bridge, empty CPU metadata only. No context/model creation or
// backend substitutions. This proves sticky refusal, not loaded-GPU retirement.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,writeFileSync,realpathSync,lstatSync,rmSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===3&&args[0]==='--isolated'&&args[1]==='--source'&&path.isAbsolute(args[2]));
const source=realpathSync(args[2]),root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
assert(source.startsWith('/private/tmp/')&&lstatSync(source).uid===process.getuid()&&(lstatSync(source).mode&0o022)===0);
const patch=readFileSync(path.join(root,'platform/studio/native/mlx-serve-26.10.3.patch'),'utf8');
const paths=[...patch.matchAll(/^diff --git a\/(.*?) b\//gm)].map(m=>m[1]);
assert.equal(execFileSync('/usr/bin/git',['-C',source,'diff','--binary','--',...paths],{encoding:'utf8',maxBuffer:4*1024*1024}),patch);
const library=path.join(source,'lib/llama/lib/libllama.dylib');
assert.equal(createHash('sha256').update(readFileSync(library)).digest('hex'),'10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b');
const scratch=mkdtempSync('/private/tmp/f9-llama-retirement-'),env={PATH:'/usr/bin:/bin',HOME:scratch,LANG:'C',LC_ALL:'C'};
let cleanupProven=true;
const original=readFileSync(path.join(source,'lib/llama_shim/llama_shim.cpp'),'utf8');
const allocatorFile=path.join(root,'platform/studio/Tests/NativeFixtures/LlamaAllocation.cpp.fixture'),allocator=readFileSync(allocatorFile,'utf8');
const test=String.raw`
extern "C" void mlx_llama_log(bool, const char *) {}
int main() {
    alarm(5);
    const int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd >= 0) {
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        const int status = bind(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address));
        const int code = errno;
        close(fd);
        if (status == 0 || (code != EPERM && code != EACCES)) return 16;
    } else if (errno != EPERM && errno != EACCES) return 17;
    if (const int allocation = fios_context_metadata_failures()) return allocation;
    mlx_llama_ctx c{};
    c.n_seq = 1;
    if (drop_mtp(&c)) return 10;
    if (!c.fios_uncertain) { fprintf(stderr, "FIO_LLAMA_MTP_UNCERTAINTY_LOST\n"); return 11; }
    if (valid_seq(&c, 0) || mlx_llama_ctx_terminal(&c) || mlx_llama_ctx_try_free(&c)) return 12;
    char err[64]{};
    if (mlx_llama_step(&c, nullptr, nullptr, 0, err, sizeof(err)) != -1) return 13;
    if (mlx_llama_seq_trim(&c, 0, 0) != -1 || mlx_llama_seq_pos(&c, 0) != -1) return 14;
    mlx_llama_seq_reset(&c, 0);
    if (!c.fios_uncertain || c.tgt || c.dft || c.batch || c.dbatch || !c.pos.empty() || !c.rows.empty()) return 15;
    return 0;
}
`;
try {
 const profile=path.join(scratch,'network.sb');writeFileSync(profile,'(version 1)(allow default)(deny network*)');
 for(const optimized of [false,true])for(const kind of [null,'sticky','metadata_cleanup']) {
  const pin='        c->fios_uncertain = true;';assert.equal(original.split(pin).length,2);
  const cleanupPin='    } catch (...) {\n        delete c;\n        copy_err(err, errlen, "out of memory allocating context metadata");\n        return NULL;\n    }';
  assert.equal(original.split(cleanupPin).length,2);
  const ctor=original.indexOf('extern "C" mlx_llama_ctx *mlx_llama_ctx_create('),native=original.indexOf('llama_init_from_model(e->model, cp)',ctor);
  for(const edge of ['mlx_llama_ctx *c = new (std::nothrow) mlx_llama_ctx();','c->pos.assign((size_t)n_seq, 0);','c->out_idx.assign((size_t)n_seq, -1);']){const at=original.indexOf(edge,ctor);assert(at>ctor&&at<native);}
  const body=kind==='sticky'?original.replace(pin,'        // private exact sticky-fence omission'):kind==='metadata_cleanup'?original.replace(cleanupPin,cleanupPin.replace('        delete c;\n','')):original;
  const unit=path.join(scratch,'test.cpp'),binary=path.join(scratch,'test');
  writeFileSync(unit,'#include <unistd.h>\n#include <sys/socket.h>\n#include <netinet/in.h>\n#include <errno.h>\n'+body+allocator+test);
  execFileSync('/usr/bin/clang++',['-std=c++17',optimized?'-O2':'-O0','-I'+path.join(source,'lib/llama/include'),'-I'+path.join(source,'lib/llama_shim'),unit,library,'-Wl,-rpath,'+path.dirname(library),'-o',binary],{env,timeout:60000,stdio:'pipe'});
  const result=spawnSync('/usr/bin/sandbox-exec',['-f',profile,binary],{env,timeout:10000,encoding:'utf8',maxBuffer:16384});
  if(result.error)cleanupProven=false;
  assert(!result.error&&!result.signal,'fixture process did not exit normally');
  if(kind){assert.equal(result.status,kind==='sticky'?11:18);assert(result.stderr.includes(kind==='sticky'?'FIO_LLAMA_MTP_UNCERTAINTY_LOST':'FIO_LLAMA_CONTEXT_METADATA_LEAK'));}
  else assert.equal(result.status,0,result.stderr);
 }
 assert.equal(readFileSync(allocatorFile,'utf8'),allocator);
 assert.equal(readFileSync(path.join(source,'lib/llama_shim/llama_shim.cpp'),'utf8'),original);
 assert.equal(createHash('sha256').update(readFileSync(library)).digest('hex'),'10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b');
 console.log('PASS: genuine Debug/optimized empty-metadata draft-retirement refusal, three pre-native allocator failures, sticky uncertainty, operation/reset/cleanup refusal and exact fence/metadata-cleanup runtime omissions. No model/context/backend work or native terminality proof.');
} finally {if(cleanupProven)rmSync(scratch,{recursive:true,force:true});else console.error('Fixture state retained: process termination was not established.');}
