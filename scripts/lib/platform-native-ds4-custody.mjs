// Supplementary source edges only; not a backend/runtime/terminal proof.
import assert from 'node:assert/strict';
export function verifyDs4PrefixRefusal(scheduler) {
 assert(scheduler.includes('const cached = try sess.commonPrefix(i32_prompt);')&&!scheduler.includes('sess.commonPrefix(i32_prompt) catch 0'),'FIO_DS4_PREFIX_REFUSAL_SWALLOWED');
}
export function verifyDs4Custody(arch,registry) {
 const engineOpen=arch.slice(arch.indexOf('    pub fn open('),arch.indexOf('    pub fn fiosCanCloseSession('));
 const sessionOpen=arch.slice(arch.indexOf('    pub fn createSession('),arch.indexOf('\nfn tokensToOwnedSlice('));
 assert(engineOpen.indexOf('allocator.create(Ds4Engine)')>=0&&engineOpen.indexOf('allocator.create(Ds4Engine)')<engineOpen.indexOf('ensureMetalKernels(')&&engineOpen.indexOf('allocator.create(Ds4Engine)')<engineOpen.indexOf('ffi.ds4_engine_open('),'FIO_DS4_HEADER_AFTER_NATIVE');
 assert(sessionOpen.indexOf('self.allocator.create(Ds4Session)')>=0&&sessionOpen.indexOf('self.allocator.create(Ds4Session)')<sessionOpen.indexOf('ffi.ds4_session_create('),'FIO_DS4_HEADER_AFTER_NATIVE');
 for(const edge of [
  /fios_lifetime: lifetime\.Lifetime/,
  /const fios_parent = self\.fios_lifetime\.borrow\(\) catch return Error\.LifetimeUnavailable;/,
  /errdefer _ = self\.fios_lifetime\.release\(fios_parent\);/,
  /pub fn tryCloseReserved\(self: \*Ds4Engine, closing: CloseTicket\) bool \{\s*if \(!self\.fios_lifetime\.commitClose\(closing\)\) return false;/,
  /pub fn tryFree\(self: \*Ds4Session\) bool \{\s*const closing = self\.fios_lifetime\.beginClose\(null\) catch return false;/,
  /\.fios_parent = fios_parent/,
 ])assert.match(arch,edge,'FIO_DS4_CUSTODY_WIRING_MISSING');
 assert.match(arch,/return self\.fiosFinishClose\(ffi\.ds4_engine_close_checked\(self\.handle\)\);/,'FIO_DS4_CHECKED_CLOSE_RESULT_DISCONNECTED');
 assert.match(arch,/fn fiosFinishClose\(self: \*Ds4Engine, native_result: c_int\) bool \{\s*if \(native_result != 1\) \{\s*self\.fios_lifetime\.fence\(\);\s*return false;\s*\}\s*self\.allocator\.free/,'FIO_DS4_CHECKED_CLOSE_REFUSAL_DROPPED_OWNER');
 assert.match(arch,/return self\.fiosFinishFree\(ffi\.ds4_session_free_checked\(self\.handle\)\);/,'FIO_DS4_CHECKED_SESSION_RESULT_DISCONNECTED');
 assert.match(arch,/fn fiosFinishFree\(self: \*Ds4Session, native_result: c_int\) bool \{\s*if \(native_result != 1\) \{\s*self\.fios_lifetime\.fence\(\);\s*self\.engine\.fios_lifetime\.fence\(\);\s*return false;\s*\}\s*if \(!self\.engine\.fios_lifetime\.release/,'FIO_DS4_CHECKED_SESSION_DROPPED_PARENT_OWNER');
 for(const name of ['pos','rewind','invalidate','argmax','argmaxExcluding','sample','sync','commonPrefix','eval','evalSpeculative','evalSpeculativeSampled','saveSnapshot','loadSnapshot']){
  const start=arch.indexOf(`    pub fn ${name}(`,arch.indexOf('pub const Ds4Session'));
  assert(start>=0,'FIO_DS4_CUSTODY_WIRING_MISSING');
  const next=arch.indexOf('    pub fn ',start+1),body=arch.slice(start,next<0?undefined:next);
  const borrow=body.indexOf('const lease = self.fios_lifetime.borrow()'),foreign=body.indexOf('ffi.');
  assert(borrow>=0&&foreign>borrow&&body.includes('defer _ = self.fios_lifetime.release(lease);'),'FIO_DS4_CUSTODY_WIRING_MISSING');
 }
 for(const name of ['hasMtp','mtpDraftTokens','eosToken','isStop','vocabSize','assistantToken','userToken','tokenizeText','encodeChatPrompt','encodeChatTranscript','detokenizeOne']) {
  const start=arch.indexOf(`    pub fn ${name}(`,arch.indexOf('pub const Ds4Engine'));
  assert(start>=0,'FIO_DS4_ENGINE_OPERATION_CUSTODY_MISSING');
  const opening=arch.indexOf('{',arch.indexOf(') Error!',start));
  const next=arch.indexOf('    pub fn ',opening+1),body=arch.slice(opening,next<0?undefined:next);
  const borrow=body.indexOf('const lease = self.fios_lifetime.borrow() catch return Error.LifetimeUnavailable;'),foreign=body.indexOf('ffi.');
  assert(borrow>=0&&foreign>borrow&&body.includes('defer _ = self.fios_lifetime.release(lease);'),'FIO_DS4_ENGINE_OPERATION_CUSTODY_MISSING');
 }
 assert.match(arch,/pub fn tryFree\(self: \*Ds4Snapshot\) bool \{\s*const closing = self\.fios_lifetime\.beginClose\(null\)/,'FIO_DS4_SNAPSHOT_CUSTODY_WIRING_MISSING');
 assert.match(arch,/errdefer ffi\.ds4_session_snapshot_free\(&snap\);/,'FIO_DS4_SNAPSHOT_CUSTODY_WIRING_MISSING');
 assert.match(arch,/const snapshot_lease = snap\.fios_lifetime\.borrow\(\) catch return Error\.LifetimeUnavailable;/,'FIO_DS4_SNAPSHOT_CUSTODY_WIRING_MISSING');
 assert.match(registry,/session\.fiosCanFree\(\)/,'FIO_DS4_CUSTODY_WIRING_MISSING');
 assert.match(registry,/engine\.fiosBeginCloseWithSession\(self\.ds4_session\)/,'FIO_DS4_CUSTODY_WIRING_MISSING');
 assert.match(registry,/if \(!session\.tryFree\(\)\)/,'FIO_DS4_CUSTODY_WIRING_MISSING');
 assert.match(registry,/if \(!engine\.tryCloseReserved\(ds4_close\.\?\)\)/,'FIO_DS4_CUSTODY_WIRING_MISSING');
}
