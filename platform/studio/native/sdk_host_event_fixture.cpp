
#include "mlx/stream.h"
#include "mlx/array.h"
#include "mlx/ops.h"
#include <chrono>
#include <thread>
#include <dlfcn.h>
#include <limits.h>
#include <cstdlib>
#include <cstring>
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
extern "C" void* fios_native_request_owners_merge(void*,void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
namespace mx=mlx::core;
#ifdef MLX_FIOS_REQUEST_HOST_EVENTS_V1
extern "C" int fios_source_host_event_observe(void*,uint64_t,uint32_t);
#endif
extern "C" int fios_cpu_graph_library_matches(const char* expected) {
 Dl_info info{};char mapped[PATH_MAX],requested[PATH_MAX];
 return expected&&dladdr(reinterpret_cast<const void*>(&mx::fios_host_queue_state),&info)&&realpath(info.dli_fname,mapped)&&realpath(expected,requested)&&std::strcmp(mapped,requested)==0;
}
extern "C" int fios_cpu_graph_run(uint32_t mode) {
 if(!mx::fios_enable_stream_custody_fixture())return 0;
 static const mx::FiosRequestOwnerHooks hooks{fios_native_request_owners_capture,fios_native_request_owners_enter,fios_native_request_owners_leave,fios_native_request_owners_release,fios_native_request_owners_merge,fios_native_request_owners_covers_current,fios_native_request_owners_uncertain};
 if(!mx::fios_register_request_owner_hooks(&hooks))return 0;
#ifdef MLX_FIOS_REQUEST_HOST_EVENTS_V1
 static const mx::FiosHostRequestEventHooksV1 events{1,sizeof(mx::FiosHostRequestEventHooksV1),fios_source_host_event_observe};
 if(mode!=1) {
  const mx::FiosHostRequestEventHooksV1 bad_version{2,sizeof(events),fios_source_host_event_observe};
  const mx::FiosHostRequestEventHooksV1 bad_size{1,0,fios_source_host_event_observe};
  const mx::FiosHostRequestEventHooksV1 bad_callback{1,sizeof(events),nullptr};
  if(mx::fios_register_host_request_event_hooks_v1(&bad_version)||mx::fios_register_host_request_event_hooks_v1(&bad_size)||mx::fios_register_host_request_event_hooks_v1(&bad_callback))return 0;
  if(!mx::fios_register_host_request_event_hooks_v1(&events)||mx::fios_register_host_request_event_hooks_v1(&events))return 0;
 }
 if(mode==4) {auto event=mx::fios_reserve_host_request_event(mx::fios_capture_request_owners());event.reset();return mx::fios_host_queue_state().uncertain?1:0;}

#endif
 const auto stream=mx::new_stream(mx::Device::cpu);
#ifdef MLX_FIOS_REQUEST_HOST_EVENTS_V1
 if(mx::fios_register_host_request_event_hooks_v1(&events))return 0;
#endif
 try {
 {
  mx::array a({1.f,2.f,3.f,4.f});
  auto output=mx::add(a,mx::array(1.f),stream);
  output.eval();
  const auto values=output.data<float>();
  for(int i=0;i<4;++i)if(values[i]!=float(i+2))return 0;
 }
 mx::synchronize(stream);
 const auto until=std::chrono::steady_clock::now()+std::chrono::seconds(3);
 while(std::chrono::steady_clock::now()<until) {
  const auto host=mx::fios_host_queue_state();const auto metal=mx::fios_metal_buffer_state();
  if(host.uncertain||metal.uncertain)return mode==2||mode==3?1:0;
  if(!host.pending&&!host.active&&!metal.pending&&!metal.captures)return mode==2||mode==3?0:1;
  std::this_thread::sleep_for(std::chrono::milliseconds(1));
 }
 return 0;
 } catch(const std::exception&) {return (mode==2||mode==3)&&mx::fios_host_queue_state().uncertain?1:0;}
}
