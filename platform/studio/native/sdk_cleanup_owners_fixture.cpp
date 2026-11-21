// Genuine CPU callback and supported SDK stream cleanup. No fault injection,
// model, fake SDK, native server or GPU dispatch.
#include "mlx/stream.h"
#include "mlx/scheduler.h"
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
extern "C" void* fios_native_request_owners_merge(void*,void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
namespace mx=mlx::core;
using namespace std::chrono_literals;
namespace {
std::mutex lock;std::condition_variable changed;
bool entered=false,released=false,finished=false;
}
extern "C" int fios_cleanup_owner_fixture_begin() {
  if(!mx::fios_enable_stream_custody_fixture())return 0;
  static const mx::FiosRequestOwnerHooks hooks{
    fios_native_request_owners_capture,fios_native_request_owners_enter,
    fios_native_request_owners_leave,fios_native_request_owners_release,
    fios_native_request_owners_merge,fios_native_request_owners_covers_current,
    fios_native_request_owners_uncertain};
  if(!mx::fios_register_request_owner_hooks(&hooks))return 0;
  const auto stream=mx::new_stream(mx::Device::cpu);
  mx::scheduler::enqueue(stream,[]{
    {std::unique_lock guard(lock);entered=true;changed.notify_all();changed.wait(guard,[]{return released;});}
    mx::clear_streams(); // Existing supported cleanup publishes SDK uncertainty.
    {std::lock_guard guard(lock);finished=true;changed.notify_all();}
  });
  std::unique_lock guard(lock);
  return changed.wait_for(guard,3s,[]{return entered;});
}
extern "C" int fios_cleanup_owner_fixture_finish() {
  {std::lock_guard guard(lock);released=true;changed.notify_all();}
  const auto end=std::chrono::steady_clock::now()+5s;
  while(std::chrono::steady_clock::now()<end) {
    const auto value=mx::fios_host_queue_state();
    bool done;{std::lock_guard guard(lock);done=finished;}
    if(done&&!value.pending&&!value.active)return value.uncertain;
    std::this_thread::sleep_for(1ms);
  }
  return 0;
}
