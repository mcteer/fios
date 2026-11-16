// CPU metadata by default; explicit Core mode checks constructor refusal.
// Neither mode loads a model or evaluates arrays.
#include "mlx/stream.h"
#include <atomic>
#include <barrier>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <thread>
#ifdef FIOS_REAL_RESIDENCY_METADATA
#include "mlx/config.h"
#include "mlx/backend/gpu/device_info.h"
#endif
#ifndef MLX_FIOS_BACKGROUND_PARTICIPANT_SEAL
#error "Reviewed background participant seal required"
#endif
namespace {
void requireAt(bool value, int line) { if (!value) { std::fprintf(stderr, "Fixture assertion line %d\n", line); std::abort(); } }
#define require(value) requireAt((value), __LINE__)
bool note() {
  try { mlx::core::fios_note_untracked_residency_refresh(); return true; }
  catch (const std::runtime_error&) { return false; }
}
}
int main(int argc, char** argv) {
  require(argc == 2);
  using namespace mlx::core;
#ifdef FIOS_REAL_RESIDENCY_METADATA
  if (std::strcmp(argv[1], "real-refresh-sealed") == 0) {
    config::update("MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS", 25);
    require(fios_enable_stream_custody_fixture());
    require(fios_seal_background_participants_fixture());
    // This public metadata API catches device-initialization exceptions and
    // reports unavailable. Zero devices is not native idle/terminal proof.
    require(gpu::device_count() == 0);
    require(fios_untracked_residency_refresh_seen());
    require(!fios_known_source_uncertain());
    std::puts("PASS: actual Core refresh constructor refuses before thread creation; no model or array evaluation");
    return 0;
  }
#endif
  if (std::strcmp(argv[1], "before-enrollment") == 0) {
    require(!fios_seal_background_participants_fixture());
    require(note());
    require(!fios_enable_stream_custody_fixture());
    require(!fios_seal_background_participants_fixture());
  } else if (std::strcmp(argv[1], "existing-participant") == 0) {
    require(fios_enable_stream_custody_fixture());
    require(note());
    require(!fios_seal_background_participants_fixture());
  } else if (std::strcmp(argv[1], "sealed") == 0) {
    require(fios_enable_stream_custody_fixture());
    require(fios_seal_background_participants_fixture());
    require(!fios_seal_background_participants_fixture());
    require(!note()); require(!note());
  } else {
    require(std::strcmp(argv[1], "race") == 0);
    require(fios_enable_stream_custody_fixture());
    std::barrier start(2);
    std::atomic<bool> sealed{false}, admitted{false};
    std::thread actor([&] {
      start.arrive_and_wait();
      admitted.store(note(), std::memory_order_release);
    });
    start.arrive_and_wait();
    sealed.store(fios_seal_background_participants_fixture(), std::memory_order_release);
    actor.join();
    // Exactly one serialized edge wins. A note is the metadata edge that
    // precedes thread creation, not a physical worker or device-completion test.
    require(sealed.load(std::memory_order_acquire) != admitted.load(std::memory_order_acquire));
  }
  require(fios_untracked_residency_refresh_seen());
  require(!fios_known_source_uncertain());
  require(fios_first_uncertainty_site() == 0);
  require(fios_stream_custody_state().registered == 0);
  std::puts("PASS: atomic source-fixture background-start exclusion; no device/native authority");
}
