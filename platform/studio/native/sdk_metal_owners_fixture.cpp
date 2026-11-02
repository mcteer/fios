// Genuine source SDK command buffer/shared event and destructor-enqueued CPU
// callback only. No model, shader dispatch, fake SDK/completion or fault input.
#include "mlx/stream.h"
#include "mlx/scheduler.h"
#include "mlx/backend/metal/device.h"
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
  std::mutex lock;std::condition_variable changed;
  bool child=false,release=false,child_owner=false,finished=false;
  NS::SharedPtr<MTL::SharedEvent> event;
} gate;
bool current_owner() {
  auto owner=fios_native_request_owners_capture();if(!owner)return false;
  fios_native_request_owners_release(owner);return true;
}
struct CallbackCleanup {
  ~CallbackCleanup() {
    const auto child=mx::new_stream(mx::Device::cpu);
    mx::scheduler::enqueue(child,[]{
      const bool owner=current_owner();
      std::unique_lock lock(gate.lock);gate.child_owner=owner;gate.child=true;
      gate.changed.notify_all();gate.changed.wait(lock,[]{return gate.release;});gate.finished=true;
    });
  }
};
}
extern "C" int fios_metal_owner_fixture_start() {
  if(!mx::fios_enable_stream_custody_fixture())return 0;
  static const mx::FiosRequestOwnerHooks hooks{
    fios_native_request_owners_capture,fios_native_request_owners_enter,
    fios_native_request_owners_leave,fios_native_request_owners_release};
  if(!mx::fios_register_request_owner_hooks(&hooks))return 0;
  const auto stream=mx::new_stream(mx::Device::gpu);
  auto& device=mx::metal::device(stream.device);
  gate.event=NS::TransferPtr(device.mtl_device()->newSharedEvent());
  if(!gate.event)return 0;
  auto& encoder=mx::metal::get_command_encoder(stream);
  encoder.fios_encode_shared_wait(gate.event.get(),1);
  auto cleanup=std::make_shared<CallbackCleanup>();
  encoder.add_completed_handler([cleanup](MTL::CommandBuffer*){});
  encoder.commit();
  return gate.event->signaledValue()==0&&mx::fios_metal_buffer_state().pending>0?1:0;
}
extern "C" void fios_metal_owner_fixture_release_gpu() {gate.event->setSignaledValue(1);}
extern "C" int fios_metal_owner_fixture_wait_child() {
  std::unique_lock lock(gate.lock);return gate.changed.wait_for(lock,3s,[]{return gate.child;})?1:0;
}
extern "C" int fios_metal_owner_fixture_child_owner() {std::lock_guard lock(gate.lock);return gate.child_owner?1:0;}
extern "C" int fios_metal_owner_fixture_cleanup() {
  if(gate.event)gate.event->setSignaledValue(1);
  {std::lock_guard lock(gate.lock);gate.release=true;gate.changed.notify_all();}
  const auto end=std::chrono::steady_clock::now()+5s;
  while(std::chrono::steady_clock::now()<end) {
    const auto host=mx::fios_host_queue_state();const auto metal=mx::fios_metal_buffer_state();
    bool finished;{std::lock_guard lock(gate.lock);finished=gate.finished;}
    if(finished&&!host.pending&&!host.active&&!metal.pending&&!metal.captures)
      return !host.uncertain&&!metal.uncertain?1:0;
    std::this_thread::sleep_for(1ms);
  }
  return 0;
}
