// Additive fixture entry points after the unchanged upstream implementation.
// Only genuine private events/command buffers on the actual engine's queue.
// No replacement SDK declarations, production-body rewrites or injected errors.
#include <pthread.h>
#include <new>
#include <errno.h>
namespace fios_join_gate {
struct Gate {
  MTL::SharedEvent* event=nullptr;
  MTL::CommandBuffer* buffer=nullptr;
  MTL::CommandQueue* queue=nullptr;
  pthread_t timer{};
  bool started=false;
  bool joined=false;
};
static void* release_after_interval(void* pointer) {
  auto* gate=static_cast<Gate*>(pointer);
  timespec interval{3,0},remaining{};
  while(nanosleep(&interval,&remaining)!=0 && errno==EINTR)interval=remaining;
  gate->event->setSignaledValue(1);
  return nullptr;
}
}
extern "C" {
uint64_t fios_join_event_create() {
  mimo_warm::Pool pool;
  return reinterpret_cast<uint64_t>(mx::metal::device(mx::Device::gpu).mtl_device()->newSharedEvent());
}
void fios_join_event_release(uint64_t event) {reinterpret_cast<MTL::SharedEvent*>(event)->release();}
void* fios_join_gate_create(void* handle) {
  auto* warm=static_cast<mimo_warm::Warm*>(handle);
  if(!warm || !warm->queue)return nullptr;
  mimo_warm::Pool pool;
  auto* gate=new(std::nothrow) fios_join_gate::Gate;
  if(!gate)return nullptr;
  gate->queue=warm->queue;gate->queue->retain();
  gate->event=gate->queue->device()->newSharedEvent();
  if(!gate->event){gate->queue->release();delete gate;return nullptr;}
  gate->buffer=gate->queue->commandBuffer();
  if(!gate->buffer){gate->event->release();gate->queue->release();delete gate;return nullptr;}
  gate->buffer->retain();gate->buffer->encodeWait(gate->event,1);gate->buffer->commit();
  // The normal host signal is finite and independent of cleanup success.
  if(pthread_create(&gate->timer,nullptr,fios_join_gate::release_after_interval,gate)!=0){
    gate->event->setSignaledValue(1);gate->buffer->waitUntilCompleted();
    gate->buffer->release();gate->event->release();gate->queue->release();delete gate;return nullptr;
  }
  gate->started=true;return gate;
}
int fios_join_gate_finish(void* context) {
  auto* gate=static_cast<fios_join_gate::Gate*>(context);if(!gate || !gate->started)return 0;
  if(!gate->joined){if(pthread_join(gate->timer,nullptr)!=0)return 0;gate->joined=true;}
  gate->buffer->waitUntilCompleted();
  return gate->buffer->status()==MTL::CommandBufferStatusCompleted;
}
void fios_join_gate_release(void* context) {
  auto* gate=static_cast<fios_join_gate::Gate*>(context);
  if(!gate || !gate->joined || gate->buffer->status()!=MTL::CommandBufferStatusCompleted)return;
  gate->buffer->release();gate->event->release();gate->queue->release();delete gate;
}
}
