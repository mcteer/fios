// Supplementary source-edge checks, never model/runtime/native authority.
import assert from 'node:assert/strict';
export function verifyLlamaCustody(arch,registry,shim) {
 const dropStart=shim.indexOf('static bool drop_mtp('),dropEnd=shim.indexOf('// Pair each target row',dropStart),drop=shim.slice(dropStart,dropEnd);
 assert(dropStart>=0&&drop.indexOf('mlx_llama_ctx_terminal(c) != 1')>=0&&drop.indexOf('c->fios_uncertain = true;')>drop.indexOf('mlx_llama_ctx_terminal(c) != 1')&&drop.indexOf('return false;')<drop.indexOf('llama_batch_ext_free(c->dbatch)'),'FIO_LLAMA_MTP_RETIREMENT_MISSING');
 assert(shim.includes('if (c->dft && mtp_catch_up(c, rows, n) != 0 && !drop_mtp(c)) return -1;'),'FIO_LLAMA_MTP_RETIREMENT_MISSING');
 assert.match(shim,/static bool valid_seq\(const mlx_llama_ctx \*c, int32_t seq\) \{\s*return c && !c->fios_uncertain/,'FIO_LLAMA_MTP_RETIREMENT_MISSING');
 assert(!arch.includes('pub fn chatTemplate(self:'),'FIO_LLAMA_TEMPLATE_BORROW_ESCAPES');
 assert.match(arch,/return allocator\.dupe\(u8, std\.mem\.sliceTo\(raw\.\?, 0\)\) catch Error\.OutOfMemory;/,'FIO_LLAMA_TEMPLATE_BORROW_ESCAPES');
 const create=arch.indexOf('    pub fn createContext('),native=arch.indexOf('ffi.mlx_llama_ctx_create(',create);
 const allocation=arch.indexOf('self.allocator.create(LlamaContext)',create),sequences=arch.indexOf('self.allocator.alloc(LlamaSeq, n_seq)',create);
 assert(allocation>create&&sequences>allocation&&native>sequences,'FIO_LLAMA_RETIREMENT_WIRING_MISSING');
 assert(!arch.includes('ffi.mlx_llama_ctx_free('),'FIO_LLAMA_RETIREMENT_WIRING_MISSING');
 assert.match(arch,/if \(ffi\.mlx_llama_ctx_try_free\(self\.handle\) != 1\) \{\s*ownership\.shared\.fence\(self\.engine\.fios_io\);\s*return false;\s*\}/,'FIO_LLAMA_RETIREMENT_WIRING_MISSING');
 assert.match(shim,/mlx_llama_ctx_try_free\(mlx_llama_ctx \*c\) \{\s*if \(mlx_llama_ctx_terminal\(c\) != 1\) return 0;\s*mlx_llama_ctx_free\(c\);\s*return 1;/,'FIO_LLAMA_RETIREMENT_WIRING_MISSING');
 const closeStart=arch.indexOf('    pub fn tryFree(self: *LlamaContext)'),closeEnd=arch.indexOf('    pub fn free(self: *LlamaContext)',closeStart),close=arch.slice(closeStart,closeEnd);
 const retire=close.indexOf('ffi.mlx_llama_ctx_try_free('),metadata=close.indexOf('for (self.seqs)'),sequenceFree=close.indexOf('self.allocator.free(self.seqs)'),parent=close.indexOf('self.engine.fios_lifetime.release(');
 assert(retire>=0&&metadata>retire&&sequenceFree>metadata&&parent>sequenceFree,'FIO_LLAMA_RETIREMENT_WIRING_MISSING');
 const affinity=close.indexOf('self.fiosCanFree()');
 assert(affinity>=0&&affinity<close.indexOf('beginClose(null)'),'FIO_LLAMA_RETIREMENT_WIRING_MISSING');
 const ctor=shim.indexOf('extern "C" mlx_llama_ctx *mlx_llama_ctx_create('),owner=shim.indexOf('const uint64_t fios_owner = fios_llama_owner();',ctor),backend=shim.indexOf('llama_init_from_model(e->model, cp)',ctor);
 assert(owner>ctor&&backend>owner&&shim.slice(owner,backend).includes('if (!fios_owner)'),'FIO_LLAMA_RETIREMENT_WIRING_MISSING');
 for(const [scope,name,owner,refusal] of [['LlamaContext','mtpDrafts','self','0'],['LlamaSeq','pos','self.ctx','-1'],['LlamaSeq','sample','self.ctx','-1'],['LlamaSeq','reset','self.ctx','']]) {
  const start=arch.indexOf(`    pub fn ${name}(`,arch.indexOf(`pub const ${scope} = struct`)),next=arch.indexOf('    pub fn ',start+1),body=arch.slice(start,next<0?undefined:next);
  const borrow=body.indexOf(`const lease = ${owner}.fios_lifetime.borrow() catch return${refusal?' '+refusal:''};`),foreign=body.indexOf('ffi.');
  assert(start>=0&&borrow>=0&&foreign>borrow&&body.includes(`defer _ = ${owner}.fios_lifetime.release(lease);`),'FIO_LLAMA_SEQUENCE_CUSTODY_MISSING');
 }
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
 for(const [scope,names,owner] of [['LlamaEngine',['tokenizeText','detokenizeOne','applyChatTemplate','chatTemplateOwned'],'self'],['LlamaContext',['step'],'self'],['LlamaSeq',['sync','syncWithFallback','eval','specStep'],'self.ctx']]) {
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
