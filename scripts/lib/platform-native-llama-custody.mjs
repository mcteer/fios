// Supplementary source-edge checks, never model/runtime/native authority.
import assert from 'node:assert/strict';
export function verifyLlamaCustody(arch,registry) {
 const checks=[
  /fios_lifetime: lifetime\.Lifetime/,
  /const fios_parent = self\.fios_lifetime\.borrow\(\) catch return Error\.SessionCreateFailed;/,
  /errdefer _ = self\.fios_lifetime\.release\(fios_parent\);/,
  /pub fn tryClose\(self: \*LlamaEngine\) bool \{[\s\S]*?commitClose[\s\S]*?ffi\.mlx_llama_close/,
  /pub fn tryFree\(self: \*LlamaContext\) bool \{[\s\S]*?beginClose\(null\)[\s\S]*?commitClose[\s\S]*?for \(self\.seqs\)/,
  /pub fn terminal\(self: \*LlamaContext\) Error!void \{\s*const lease = self\.fios_lifetime\.borrow\(\)/,
  /\.fios_parent = fios_parent/,
 ];
 for(const check of checks)assert.match(arch,check,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
 assert.match(registry,/ctx\.fiosCanFree\(\)/,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
 assert.match(registry,/engine\.fiosBeginCloseWithContext\(self\.llama_ctx\)/,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
 assert.match(registry,/if \(!ctx\.tryFree\(\)\)/,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
 assert.match(registry,/if \(!engine\.tryCloseReserved\(llama_close\.\?\)\)/,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
}
