// Test instrumentation appended to the ACTUAL upstream warm implementation.
// Uses its real Warm/Metal objects, not replacement SDK declarations/contexts.
#ifdef FIOS_GENUINE_WARM_ENGINE_FIXTURE
#include <thread>
#include <chrono>
extern "C" {
uint64_t fios_test_mimo_event_create() {
  mimo_warm::Pool pool;
  return reinterpret_cast<uint64_t>(mx::metal::device(mx::Device::gpu).mtl_device()->newSharedEvent());
}
void fios_test_mimo_event_set(uint64_t value,uint64_t signal) {
  reinterpret_cast<MTL::SharedEvent*>(value)->setSignaledValue(signal);
}
void fios_test_mimo_event_release(uint64_t value) {
  reinterpret_cast<MTL::SharedEvent*>(value)->release();
}
int fios_test_mimo_configure(void* handle,uint64_t first,uint64_t second) {
  auto* warm=static_cast<mimo_warm::Warm*>(handle);
  warm->fixture_second=reinterpret_cast<MTL::SharedEvent*>(second);
  mimo_warm::Pool pool;
  auto* buffer=warm->queue->commandBuffer();if(!buffer)return -1;
  buffer->encodeWait(reinterpret_cast<MTL::SharedEvent*>(first),1);buffer->commit();
  return 0;
}
uint64_t fios_test_mimo_retires() {return mimo_warm::fixture_retire_calls.load();}
int fios_test_mimo_second_pending(void* handle) {
  auto* buffer=static_cast<mimo_warm::Warm*>(handle)->fixture_last.load();
  return buffer&&(buffer->status()==MTL::CommandBufferStatusCommitted||buffer->status()==MTL::CommandBufferStatusScheduled);
}
struct FiosMimoTestTimer {
  MTL::SharedEvent *first,*second;
  std::atomic<bool> quit{false},expired{false};
  std::thread worker;
  FiosMimoTestTimer(uint64_t a,uint64_t b):first(reinterpret_cast<MTL::SharedEvent*>(a)),second(reinterpret_cast<MTL::SharedEvent*>(b)) {
    first->retain();second->retain();
    worker=std::thread([this]{
      for(unsigned i=0;i<5000;++i){if(quit.load())return;std::this_thread::sleep_for(std::chrono::milliseconds(1));}
      expired.store(true);first->setSignaledValue(1);second->setSignaledValue(1);
    });
  }
  ~FiosMimoTestTimer(){quit.store(true);if(worker.joinable())worker.join();first->release();second->release();}
};
void* fios_test_mimo_timer_start(uint64_t a,uint64_t b){return new FiosMimoTestTimer(a,b);}
int fios_test_mimo_timer_stop(void* pointer){auto* timer=static_cast<FiosMimoTestTimer*>(pointer);timer->quit.store(true);timer->worker.join();const bool failed=timer->expired.load();delete timer;return failed;}
}
#endif
