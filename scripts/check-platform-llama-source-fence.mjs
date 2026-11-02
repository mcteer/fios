#!/usr/bin/env node
// Ordinary empty-metadata refusal through the genuine shim. No model, native
// context, simulated backend, source mutation or historical fault campaign.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,writeFileSync,realpathSync,lstatSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===3&&args[0]==='--isolated'&&args[1]==='--source'&&path.isAbsolute(args[2]));
const source=realpathSync(args[2]),root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
assert(source.startsWith('/private/tmp/')&&lstatSync(source).uid===process.getuid()&&(lstatSync(source).mode&0o022)===0);
const patch=readFileSync(path.join(root,'platform/studio/native/mlx-serve-26.10.3.patch'),'utf8');
const paths=[...patch.matchAll(/^diff --git a\/(.*?) b\//gm)].map(m=>m[1]);
const env={PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_NO_REPLACE_OBJECTS:'1'};
assert.equal(execFileSync('/usr/bin/git',['--no-replace-objects','-c','core.attributesfile=/dev/null','-c','core.fsmonitor=false','-C',source,'diff','--no-ext-diff','--no-textconv','HEAD','--',...paths],{env,encoding:'utf8',maxBuffer:4*1024*1024}),patch);
const library=path.join(source,'lib/llama/lib/libllama.dylib');
const sha=file=>createHash('sha256').update(readFileSync(file)).digest('hex');
assert.equal(sha(library),'10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b');
const original=readFileSync(path.join(source,'lib/llama_shim/llama_shim.cpp'),'utf8');
const server=readFileSync(path.join(source,'src/server.zig'),'utf8');
assert(server.includes('or arch_llama.fiosSourceUncertain() or'));
assert(server.includes('fios_sdk_owners.diagnostic().uncertain or fiosKnownBackendUncertain()'));
const scratch=mkdtempSync('/private/tmp/f9-llama-source-fence-');env.HOME=scratch;
const profile=path.join(scratch,'network.sb');writeFileSync(profile,'(version 1)(allow default)(deny network*)');
const test=String.raw`
extern "C" void mlx_llama_log(bool, const char *) {}
int main() {
    alarm(5);
    const int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd >= 0) {
        sockaddr_in address{}; address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        const int status = bind(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address));
        const int code = errno; close(fd);
        if (status == 0 || (code != EPERM && code != EACCES)) return 10;
    } else if (errno != EPERM && errno != EACCES) return 11;
    if (mlx_llama_source_uncertainty() != 0) return 12;
    if (mlx_llama_ctx_terminal(nullptr) || mlx_llama_ctx_try_free(nullptr)) return 13;
    if (mlx_llama_source_uncertainty() != 0) return 14;
    mlx_llama_ctx context{};
    if (drop_mtp(&context) || !context.fios_uncertain) return 15;
    if (mlx_llama_source_uncertainty() != 1) return 16;
    mlx_llama_ctx other{};
    mlx_llama_seq_reset(&context, 0);
    if (mlx_llama_ctx_terminal(&other) || mlx_llama_ctx_try_free(&other)) return 17;
    if (mlx_llama_source_uncertainty() != 1 || !context.fios_uncertain) return 18;
    if (context.tgt || context.dft || context.batch || context.dbatch) return 19;
    puts("PASS: empty-metadata context refusal retains module uncertainty; null preflight does not fence");
}
`;
for(const optimized of [false,true]) {
 const unit=path.join(scratch,'test.cpp'),binary=path.join(scratch,optimized?'optimized':'debug');
 writeFileSync(unit,'#include <unistd.h>\n#include <sys/socket.h>\n#include <netinet/in.h>\n#include <errno.h>\n'+original+test);
 execFileSync('/usr/bin/clang++',['-std=c++17',optimized?'-O2':'-O0','-I'+path.join(source,'lib/llama/include'),'-I'+path.join(source,'lib/llama_shim'),unit,library,'-Wl,-rpath,'+path.dirname(library),'-o',binary],{env,timeout:60000,stdio:'pipe'});
 const result=spawnSync('/usr/bin/sandbox-exec',['-f',profile,binary],{env,timeout:10000,encoding:'utf8',maxBuffer:16384});
 writeFileSync(path.join(scratch,optimized?'optimized.log':'debug.log'),JSON.stringify(result));
 assert(!result.error&&!result.signal&&result.status===0,result.stderr||'fixture failed; private scratch retained');
 assert(result.stdout.includes('PASS: empty-metadata context refusal'));
}
assert.equal(readFileSync(path.join(source,'lib/llama_shim/llama_shim.cpp'),'utf8'),original);
assert.equal(sha(library),'10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b');
console.log(JSON.stringify({scratch,modes:['Debug','optimized'],empty_metadata_only:true,native_contexts:0,model_requests:0,coverage:'unknown',native_authority:false}));
