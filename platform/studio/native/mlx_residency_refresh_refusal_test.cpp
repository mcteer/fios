// Genuine SDK metadata only by default. Explicit Core-only mode exercises
// the real refresh constructor; neither mode loads a model or evaluates arrays.
#include "mlx/stream.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#ifdef FIOS_REAL_RESIDENCY_METADATA
#include "mlx/config.h"
#include "mlx/backend/gpu/device_info.h"
#include <chrono>
#include <thread>
#endif
#ifndef MLX_FIOS_RESIDENCY_REFRESH_REFUSAL
#error "Reviewed residency-refresh refusal source is required"
#endif
namespace {
void require(bool value) { if (!value) std::abort(); }
}
int main(int argc, char** argv) {
  require(argc == 2);
  using namespace mlx::core;
#ifdef FIOS_REAL_RESIDENCY_METADATA
  if (std::strcmp(argv[1], "real-refresh-metadata") == 0) {
    config::update("MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS", 25);
    require(fios_enable_stream_custody_fixture());
    require(!fios_untracked_residency_refresh_seen());
    require(gpu::device_count() == 1); // Device metadata only; no stream/eval.
    require(fios_untracked_residency_refresh_seen());
    require(!fios_known_source_uncertain());
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    require(fios_untracked_residency_refresh_seen());
    require(!fios_known_source_uncertain());
    std::puts("PASS: actual refresh worker records unsupported coverage independently of cleanup; no model or evaluation");
    return 0;
  }
#endif
  if (std::strcmp(argv[1], "before-enrollment") == 0) {
    fios_note_untracked_residency_refresh();
    require(!fios_known_source_uncertain());
    require(fios_untracked_residency_refresh_seen());
    require(!fios_enable_stream_custody_fixture());
    require(fios_stream_custody_state().registered == 0);
  } else if (std::strcmp(argv[1], "after-enrollment") == 0) {
    require(fios_enable_stream_custody_fixture());
    require(!fios_known_source_uncertain());
    fios_note_untracked_residency_refresh();
    require(!fios_known_source_uncertain());
    require(fios_untracked_residency_refresh_seen());
    require(fios_first_uncertainty_site() == 0);
    const auto state = fios_stream_custody_state();
    require(state.enabled && !state.uncertain && state.registered == 0);
    fios_note_untracked_residency_refresh();
    require(!fios_known_source_uncertain());
    require(fios_untracked_residency_refresh_seen());
    require(fios_first_uncertainty_site() == 0);
  } else {
    require(std::strcmp(argv[1], "unused") == 0);
    require(fios_enable_stream_custody_fixture());
    require(!fios_known_source_uncertain());
    require(!fios_stream_custody_state().uncertain);
    require(!fios_untracked_residency_refresh_seen());
  }
  std::puts("PASS: residency refresh remains unsupported metadata, never idle or terminal proof");
}
