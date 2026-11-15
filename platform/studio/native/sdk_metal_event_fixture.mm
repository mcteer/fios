#include "mlx/stream.h"
#include "mlx/backend/metal/device.h"
#include <chrono>
#include <thread>
#include <atomic>
#include <dlfcn.h>
#include <limits.h>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
extern "C" void* fios_native_request_owners_merge(void*,void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
extern "C" int fios_source_metal_event_observe(void*,uint64_t,uint32_t);
namespace mx=mlx::core;
static std::atomic<uint32_t> scenario{0};
static std::atomic<bool> observer_waiting{false},observer_continue{false};
extern "C" int fios_metal_fixture_pause() {
 if(scenario.load(std::memory_order_acquire)!=2)return 1;
 observer_waiting.store(true,std::memory_order_release);
 const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(1);
 while(std::chrono::steady_clock::now()<deadline) {
  if(observer_continue.load(std::memory_order_acquire))return 1;
  std::this_thread::sleep_for(std::chrono::milliseconds(1));
 }
 return 0;
}
extern "C" int fios_metal_library_matches(const char* expected) {
 Dl_info info{};char mapped[PATH_MAX],requested[PATH_MAX];
 return expected&&dladdr(reinterpret_cast<const void*>(&mx::fios_host_queue_state),&info)&&realpath(info.dli_fname,mapped)&&realpath(expected,requested)&&std::strcmp(mapped,requested)==0;
}
extern "C" int fios_metal_fixture_run(uint32_t mode) {
 @autoreleasepool {
 scenario.store(mode,std::memory_order_release);
 if(!mx::fios_enable_stream_custody_fixture())return 0;
 static const mx::FiosRequestOwnerHooks hooks{fios_native_request_owners_capture,fios_native_request_owners_enter,fios_native_request_owners_leave,fios_native_request_owners_release,fios_native_request_owners_merge,fios_native_request_owners_covers_current,fios_native_request_owners_uncertain};
 if(!mx::fios_register_request_owner_hooks(&hooks))return 0;
#ifdef MLX_FIOS_REQUEST_METAL_EVENTS_V1
 static const mx::FiosMetalRequestEventHooksV1 events{1,sizeof(events),fios_source_metal_event_observe};
 if(mode!=1) {
  const mx::FiosMetalRequestEventHooksV1 bad_version{2,sizeof(events),fios_source_metal_event_observe};
  const mx::FiosMetalRequestEventHooksV1 bad_size{1,0,fios_source_metal_event_observe};
  const mx::FiosMetalRequestEventHooksV1 bad_callback{1,sizeof(events),nullptr};
  if(mx::fios_register_metal_request_event_hooks_v1(&bad_version)||mx::fios_register_metal_request_event_hooks_v1(&bad_size)||mx::fios_register_metal_request_event_hooks_v1(&bad_callback))return 0;
  if(!mx::fios_register_metal_request_event_hooks_v1(&events)||mx::fios_register_metal_request_event_hooks_v1(&events))return 0;
 }
#endif
 try {
  const auto stream=mx::new_stream(mx::Device::gpu);
#ifdef MLX_FIOS_REQUEST_METAL_EVENTS_V1
  if(mx::fios_register_metal_request_event_hooks_v1(&events))return 0;
#endif
  auto& encoder=mx::metal::get_command_encoder(stream);encoder.end_encoding();encoder.commit();
#ifdef MLX_FIOS_REQUEST_METAL_EVENTS_V1
  if(mode==2) {
   const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(1);
   while(!observer_waiting.load(std::memory_order_acquire)&&std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(1));
   const auto physical=mx::fios_metal_buffer_state();const auto events_state=mx::fios_metal_request_event_state();
   const bool refused=observer_waiting.load(std::memory_order_acquire)&&!physical.pending&&!physical.captures&&events_state.pending==1&&!events_state.scopes&&mx::fios_hold_source_components(physical.epoch)==0;
   observer_continue.store(true,std::memory_order_release);
   if(!refused)return 0;
  }
#endif
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
  while(std::chrono::steady_clock::now()<deadline) {
   const auto host=mx::fios_host_queue_state();const auto metal=mx::fios_metal_buffer_state();
   if(host.uncertain||metal.uncertain) {
    if(mode==4) {
     try {encoder.commit();return 0;}
     catch(const std::exception&) {return 1;}
    }
    return mode==3?1:0;
   }
   bool events_done=true;
#ifdef MLX_FIOS_REQUEST_METAL_EVENTS_V1
   const auto events_state=mx::fios_metal_request_event_state();events_done=!events_state.pending&&!events_state.scopes;
#endif
   if(!host.pending&&!host.active&&!metal.pending&&!metal.captures&&events_done) {
    if(mode==2) {
     const auto ready=mx::fios_metal_buffer_state();
     const auto hold=mx::fios_hold_source_components(ready.epoch);
     if(!hold||!mx::fios_release_metal_buffers(hold))return 0;
    }
    return mode==3||mode==4?0:1;
   }
   std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return 0;
 } catch(const std::exception&) {return (mode==3||mode==4)&&mx::fios_known_source_uncertain()?1:0;}
 }
}
