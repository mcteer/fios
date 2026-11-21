// Genuine source SDK reservation paired with a private, unsubmitted Metal
// buffer. Component lifetime only: no shader/model, injected failure or alias
// into an SDK encoder. This does not prove automatic encoder-path coverage.
#include "mlx/stream.h"
#include "mlx/backend/metal/device.h"
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
extern "C" void* fios_native_request_owners_merge(void*,void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
namespace mx=mlx::core;
namespace {
NS::SharedPtr<MTL::CommandQueue> queue;
NS::SharedPtr<MTL::CommandBuffer> buffer;
std::shared_ptr<mx::FiosMetalBuffer> record;
}
extern "C" int fios_abandoned_owner_fixture_begin() {
  if(!mx::fios_enable_stream_custody_fixture())return 0;
  static const mx::FiosRequestOwnerHooks hooks{
    fios_native_request_owners_capture,fios_native_request_owners_enter,
    fios_native_request_owners_leave,fios_native_request_owners_release,
    fios_native_request_owners_merge,fios_native_request_owners_covers_current,
    fios_native_request_owners_uncertain};
  if(!mx::fios_register_request_owner_hooks(&hooks))return 0;
  const auto stream=mx::new_stream(mx::Device::gpu);
  queue=NS::TransferPtr(mx::metal::device(stream.device).mtl_device()->newCommandQueue());
  if(!queue)return 0;
  buffer=NS::RetainPtr(queue->commandBufferWithUnretainedReferences());
  if(!buffer)return 0;
  record=mx::fios_reserve_metal_buffer(stream.index);
  if(!record)return 0;
  mx::fios_record_metal_request_owners(record);
  return mx::fios_metal_buffer_state().pending==1;
}
extern "C" int fios_abandoned_owner_fixture_drop() {
  // Drop the actual unsubmitted object and its genuine SDK bookkeeping.
  // No submitted work or completion is manufactured by this component case.
  buffer.reset();record.reset();queue.reset();
  const auto value=mx::fios_metal_buffer_state();
  return value.uncertain&&value.pending==1;
}
