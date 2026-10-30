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
 for(const [scope,names,owner] of [['LlamaEngine',['tokenizeText','detokenizeOne','applyChatTemplate'],'self'],['LlamaContext',['step'],'self'],['LlamaSeq',['sync','syncWithFallback','eval','specStep'],'self.ctx']]) {
  for(const name of names){
   const start=arch.indexOf(`    pub fn ${name}(`,arch.indexOf(`pub const ${scope} = struct`));
   assert(start>=0,'FIO_LLAMA_OPERATION_CUSTODY_MISSING');
   const next=arch.indexOf('    pub fn ',start+1),body=arch.slice(start,next<0?undefined:next);
   const guard=`const lease = ${owner}.fios_lifetime.borrow() catch return Error.LifetimeUnavailable;`;
   const borrow=body.indexOf(guard),foreign=body.indexOf('ffi.');
   assert(borrow>=0 && (foreign<0 || borrow<foreign) && body.includes(`defer _ = ${owner}.fios_lifetime.release(lease);`),'FIO_LLAMA_OPERATION_CUSTODY_MISSING');
  }
 }
 assert.match(arch,/if \(err == Error\.LifetimeUnavailable\) return err;/,'FIO_LLAMA_LIFETIME_REFUSAL_RETRIED');
 assert.match(registry,/ctx\.fiosCanFree\(\)/,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
 assert.match(registry,/engine\.fiosBeginCloseWithContext\(self\.llama_ctx\)/,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
 assert.match(registry,/if \(!ctx\.tryFree\(\)\)/,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
 assert.match(registry,/if \(!engine\.tryCloseReserved\(llama_close\.\?\)\)/,'FIO_LLAMA_CUSTODY_WIRING_MISSING');
}
