// Actual source constructor with refusing synthetic native callbacks only.
// No native ledger, model, Metal constructor, arrays or admission authority.
#include "mlx/stream.h"
#include <cstdio>
#include <cstring>
#include <stdexcept>
extern "C" void* fios_native_request_owners_capture() { return nullptr; }
extern "C" uint64_t fios_native_request_owners_enter(void*) { return 0; }
extern "C" int fios_native_request_owners_leave(uint64_t) { return 0; }
extern "C" void fios_native_request_owners_release(void*) {}
extern "C" void* fios_native_request_owners_merge(void*, void*) { return nullptr; }
extern "C" int fios_native_request_owners_covers_current(void*) { return 0; }
extern "C" void fios_native_request_owners_uncertain() {}
extern "C" int fios_native_host_request_event_observe(void*, uint64_t, uint32_t) { return 0; }
extern "C" int fios_native_metal_request_event_observe(void*, uint64_t, uint32_t) { return 0; }
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  bool denied = false;
  try { mlx::core::fios_note_untracked_residency_refresh(); }
  catch (const std::runtime_error&) { denied = true; }
  const bool expected = std::strcmp(argv[1], "sealed") == 0;
  if (denied != expected) {
    std::puts("FAIL: startup did not establish expected background exclusion");
    return 1;
  }
  if (!mlx::core::fios_untracked_residency_refresh_seen() ||
      mlx::core::fios_known_source_uncertain()) return 3;
  std::puts("PASS: actual constructor background exclusion with synthetic native callbacks; no native authority");
}
