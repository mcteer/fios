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
#ifdef MLX_FIOS_REQUEST_OWNER_GROUPS
extern "C" void* fios_native_request_owners_merge(void*,void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
#endif
namespace mx=mlx::core;
using namespace std::chrono_literals;
namespace {
struct Gate {
  std::mutex lock;std::condition_variable changed;
  bool child=false,release=false,child_owner=false,finished=false;
  NS::SharedPtr<MTL::SharedEvent> event;
  mx::metal::CommandEncoder* encoder=nullptr;
  bool submission_requested=false;
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
extern "C" int fios_metal_owner_fixture_begin() {
  if(!mx::fios_enable_stream_custody_fixture())return 0;
  static const mx::FiosRequestOwnerHooks hooks{
    fios_native_request_owners_capture,fios_native_request_owners_enter,
    fios_native_request_owners_leave,fios_native_request_owners_release
#ifdef MLX_FIOS_REQUEST_OWNER_GROUPS
        ,fios_native_request_owners_merge,fios_native_request_owners_covers_current,
        fios_native_request_owners_uncertain
#endif
    };
  if(!mx::fios_register_request_owner_hooks(&hooks))return 0;
  const auto stream=mx::new_stream(mx::Device::gpu);
  auto& device=mx::metal::device(stream.device);
  gate.event=NS::TransferPtr(device.mtl_device()->newSharedEvent());
  if(!gate.event)return 0;
  gate.encoder=&mx::metal::get_command_encoder(stream);
  // Real encoding under the first origin, without finishing or committing
  // the encoder. No shader/pipeline/dispatch or command-buffer alias is used.
  const uint32_t value=7;gate.encoder->set_bytes(value,0);
  return 1;
}
extern "C" int fios_metal_owner_fixture_submit() {
  gate.submission_requested=true;
  auto& encoder=*gate.encoder;
  encoder.fios_encode_shared_wait(gate.event.get(),1);
  auto cleanup=std::make_shared<CallbackCleanup>();
  encoder.add_completed_handler([cleanup](MTL::CommandBuffer*){});
  encoder.commit();
  return gate.event->signaledValue()==0&&mx::fios_metal_buffer_state().pending>0?1:0;
}
extern "C" int fios_metal_owner_fixture_start() {
  return fios_metal_owner_fixture_begin() && fios_metal_owner_fixture_submit();
}
extern "C" void fios_metal_owner_fixture_release_gpu() {gate.event->setSignaledValue(1);}
extern "C" int fios_metal_owner_fixture_wait_child() {
  std::unique_lock lock(gate.lock);return gate.changed.wait_for(lock,3s,[]{return gate.child;})?1:0;
}
extern "C" int fios_metal_owner_fixture_child_owner() {std::lock_guard lock(gate.lock);return gate.child_owner?1:0;}
extern "C" int fios_metal_owner_fixture_cleanup() {
  const bool expected_child=gate.submission_requested;
  if(!gate.submission_requested&&gate.encoder){
    gate.submission_requested=true;
    gate.encoder->end_encoding();gate.encoder->commit();
  }
  if(gate.event)gate.event->setSignaledValue(1);
  {std::lock_guard lock(gate.lock);gate.release=true;gate.changed.notify_all();}
  const auto end=std::chrono::steady_clock::now()+5s;
  while(std::chrono::steady_clock::now()<end) {
    const auto host=mx::fios_host_queue_state();const auto metal=mx::fios_metal_buffer_state();
    bool finished;{std::lock_guard lock(gate.lock);finished=gate.finished;}
    if((finished||!expected_child)&&!host.pending&&!host.active&&!metal.pending&&!metal.captures)
      return !host.uncertain&&!metal.uncertain?1:0;
    std::this_thread::sleep_for(1ms);
  }
  return 0;
}
