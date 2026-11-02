// Genuine CPU scheduler work only. No SDK substitute, model, source mutation,
// artificial counter or device completion/error input.
#include "mlx/stream.h"
#include "mlx/scheduler.h"
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <memory>
#include <thread>
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
namespace mx=mlx::core;
using namespace std::chrono_literals;
namespace {
struct Gate {
  std::mutex lock;
  std::condition_variable changed;
  bool first=false,second=false,release_first=false,release_second=false;
  bool first_owner=false,second_owner=false,second_finished=false;
} gate;
bool current_owner() {
  auto owner=fios_native_request_owners_capture();
  if (!owner) return false;
  fios_native_request_owners_release(owner);return true;
}
struct CallbackCleanup {
  ~CallbackCleanup() {
    // Actual captured-object destruction after the original body returns,
    // on its original worker. It creates its own genuine owned CPU stream.
    const auto child=mx::new_stream(mx::Device::cpu);
    mx::scheduler::enqueue(child,[]{
      const bool owner=current_owner();
      std::unique_lock lock(gate.lock);gate.second_owner=owner;gate.second=true;
      gate.changed.notify_all();gate.changed.wait(lock,[]{return gate.release_second;});
      gate.second_finished=true;
    });
  }
};
}
extern "C" int fios_host_owner_fixture_start() {
  if (!mx::fios_enable_stream_custody_fixture()) return 0;
#ifdef MLX_FIOS_REQUEST_HOST_OWNERS
  static const mx::FiosRequestOwnerHooks hooks{
    fios_native_request_owners_capture,fios_native_request_owners_enter,
    fios_native_request_owners_leave,fios_native_request_owners_release};
  if (!mx::fios_register_request_owner_hooks(&hooks)) return 0;
#endif
  const auto stream=mx::new_stream(mx::Device::cpu);
  auto cleanup=std::make_shared<CallbackCleanup>();
  mx::scheduler::enqueue(stream,[cleanup]{
    {
      const bool owner=current_owner();
      std::unique_lock lock(gate.lock);gate.first_owner=owner;gate.first=true;
      gate.changed.notify_all();gate.changed.wait(lock,[]{return gate.release_first;});
    }

  });
  return 1;
}
extern "C" int fios_host_owner_fixture_wait(int second) {
  std::unique_lock lock(gate.lock);
  return gate.changed.wait_for(lock,3s,[=]{return second?gate.second:gate.first;})?1:0;
}
extern "C" int fios_host_owner_fixture_owner(int second) {
  std::lock_guard lock(gate.lock);return second?gate.second_owner:gate.first_owner;
}
extern "C" void fios_host_owner_fixture_release_first() {
  std::lock_guard lock(gate.lock);gate.release_first=true;gate.changed.notify_all();
}
extern "C" int fios_host_owner_fixture_cleanup() {
  {
    std::lock_guard lock(gate.lock);gate.release_first=true;gate.release_second=true;gate.changed.notify_all();
  }
  const auto end=std::chrono::steady_clock::now()+3s;
  while(std::chrono::steady_clock::now()<end) {
    const auto host=mx::fios_host_queue_state();
    bool finished;{std::lock_guard lock(gate.lock);finished=gate.second_finished;}
    if(finished&&!host.pending&&!host.active)return host.uncertain?0:1;
    std::this_thread::sleep_for(1ms);
  }
  return 0;
}
