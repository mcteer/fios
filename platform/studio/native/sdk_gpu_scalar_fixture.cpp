// Actual four-element SDK GPU graph; no model or all-client authority.
#include "mlx/array.h"
#include "mlx/ops.h"
#include "mlx/memory.h"
#include "mlx/stream.h"
#include <atomic>
#include <future>
#include <chrono>
#include <cstdio>
#include <exception>
#include <dlfcn.h>
#include <limits.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
namespace mx = mlx::core;
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
extern "C" void* fios_native_request_owners_merge(void*, void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
extern "C" int fios_native_host_request_event_observe(void*, uint64_t, uint32_t);
extern "C" int fios_scalar_metal_event_observe(void*, uint64_t, uint32_t);
extern "C" int fios_gpu_scalar_library_matches(const char* expected, size_t length) {
  Dl_info host{}, metal{};
  char mapped[PATH_MAX], requested[PATH_MAX];
  const std::string path(expected, length);
  return dladdr(reinterpret_cast<const void*>(&mx::fios_host_queue_state), &host) &&
      dladdr(reinterpret_cast<const void*>(&mx::fios_metal_request_event_state), &metal) &&
      host.dli_fbase == metal.dli_fbase && realpath(host.dli_fname, mapped) &&
      realpath(path.c_str(), requested) && std::strcmp(mapped, requested) == 0;
}
static int run_graph() {
  try {
    // This is an allocator guideline inside this private child, not a GPU quota.
    mx::set_memory_limit(64 << 20);
    mx::set_cache_limit(0);
    const auto stream = mx::new_stream(mx::Device::gpu);
    {
      mx::array input({1.f, 2.f, 3.f, 4.f});
      auto output = mx::add(input, mx::array(1.f), stream);
      output.eval();
      const auto values = output.data<float>();
      for (int i = 0; i < 4; ++i) if (values[i] != float(i + 2)) return 0;
    }
    mx::synchronize(stream);
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (std::chrono::steady_clock::now() < deadline) {
      const auto host = mx::fios_host_queue_state();
      const auto metal = mx::fios_metal_buffer_state();
      const auto events = mx::fios_metal_request_event_state();
      if (host.uncertain || metal.uncertain) return 0;
      if (!host.pending && !host.active && !metal.pending && !metal.captures &&
          !events.pending && !events.scopes) return 1;
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return 0;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "SDK_GPU_SCALAR: %s\n", error.what());
    return 0;
  }
}

// A single explicitly owned fixture thread waits before entering its captured
// SDK scope. The caller can release both initiating references first.
static std::thread worker;
static std::promise<void> entered, proceed;
static std::atomic<int> outcome{0};
extern "C" int fios_gpu_scalar_begin() {
  try {
    static const mx::FiosRequestOwnerHooks hooks{
      fios_native_request_owners_capture, fios_native_request_owners_enter,
      fios_native_request_owners_leave, fios_native_request_owners_release,
      fios_native_request_owners_merge, fios_native_request_owners_covers_current,
      fios_native_request_owners_uncertain};
    static const mx::FiosHostRequestEventHooksV1 host_events{
      1, sizeof(mx::FiosHostRequestEventHooksV1), fios_native_host_request_event_observe};
    // The test observer checks both original tokens, then invokes the actual
    // native Metal event ledger. It supplies no production admission capability.
    static const mx::FiosMetalRequestEventHooksV1 metal_events{
      1, sizeof(mx::FiosMetalRequestEventHooksV1), fios_scalar_metal_event_observe};
    if (!mx::fios_register_request_owner_hooks(&hooks) ||
        !mx::fios_enable_stream_custody_fixture() ||
        !mx::fios_seal_background_participants_fixture() ||
        !mx::fios_register_host_request_event_hooks_v1(&host_events) ||
        !mx::fios_register_metal_request_event_hooks_v1(&metal_events)) return 0;
    auto captured = mx::fios_capture_request_owners();
    if (!captured) return 0;
    auto ready = entered.get_future();
    auto go = proceed.get_future();
    worker = std::thread([captured = std::move(captured), go = std::move(go)]() mutable {
      entered.set_value();
      if (go.wait_for(std::chrono::seconds(2)) != std::future_status::ready) return;
      try {
        mx::FiosRequestOwnerScope scope(std::move(captured));
        outcome.store(run_graph(), std::memory_order_release);
      } catch (const std::exception& error) {
        std::fprintf(stderr, "SDK_GPU_SCALAR_SCOPE: %s\n", error.what());
      }
    });
    return ready.wait_for(std::chrono::seconds(2)) == std::future_status::ready;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "SDK_GPU_SCALAR_BEGIN: %s\n", error.what());return 0;
  }
}
extern "C" int fios_gpu_scalar_finish() {
  proceed.set_value();worker.join();return outcome.load(std::memory_order_acquire);
}
