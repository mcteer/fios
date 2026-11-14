#include "mlx/stream.h"
#include "mlx/scheduler.h"
#include <atomic>
#include <chrono>
#include <thread>
#include <stdexcept>
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
extern "C" void* fios_native_request_owners_merge(void*,void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
namespace mx=mlx::core;
namespace { std::atomic<bool> ran{false}, owned{false}; }
extern "C" int fios_capture_refusal_probe(int scenario) {
  if (!mx::fios_enable_stream_custody_fixture()) return -1;
  static const mx::FiosRequestOwnerHooks hooks{
    fios_native_request_owners_capture,fios_native_request_owners_enter,
    fios_native_request_owners_leave,fios_native_request_owners_release,
    fios_native_request_owners_merge,fios_native_request_owners_covers_current,
    fios_native_request_owners_uncertain};
  if (scenario && !mx::fios_register_request_owner_hooks(&hooks)) return -2;
  const auto stream=mx::new_stream(mx::Device::cpu);
  if (scenario==2) fios_native_request_owners_uncertain();
  try {
    mx::scheduler::enqueue(stream,[scenario]{
      if (scenario==1) {
        auto root=fios_native_request_owners_capture();owned.store(root!=nullptr,std::memory_order_release);
        if (root) fios_native_request_owners_release(root);
      }
      ran.store(true,std::memory_order_release);
    });
  } catch(const std::runtime_error&) {
    const auto state=mx::fios_host_queue_state();
    return scenario>=2&&mx::fios_known_source_uncertain()&&!ran.load(std::memory_order_acquire)&&!state.pending&&!state.active?1:-3;
  }
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
  while(std::chrono::steady_clock::now()<deadline) {
    const auto state=mx::fios_host_queue_state();
    if(ran.load(std::memory_order_acquire)&&!state.pending&&!state.active)
      return scenario>=2?0:!mx::fios_known_source_uncertain()&&(scenario==0||owned.load(std::memory_order_acquire))?1:-5;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return -4;
}
