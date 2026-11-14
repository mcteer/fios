// Actual original MIMO event C ABI + actual MLX pass-through graph.
// One genuine float32 scalar aliases through wait/signal; no kernel/model/inference.
// Source-subdomain evidence only: process-life event pool is NOT retired here.
#include "mlx/stream.h"
#include "mlx/backend/metal/device.h"
#include "mlx/c/private/array.h"
#include "mlx/c/private/stream.h"
#include "mlx_event_shim.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <stdexcept>
#include <source_location>
#include <thread>
using namespace mlx::core;
using namespace std::chrono_literals;
static void require(bool value,const std::source_location where=std::source_location::current()){if(!value){std::fprintf(stderr,"Actual MIMO graph assertion at source line %u\n",where.line());throw std::runtime_error("actual MIMO event graph assertion");}}
struct Safety {
 MTL::SharedEvent* event;std::atomic<bool> done{false},expired{false};std::thread worker;
 explicit Safety(MTL::SharedEvent* e):event(e),worker([this]{for(int i=0;i<500&&!done.load();i++)std::this_thread::sleep_for(10ms);if(!done.load()){expired.store(true);event->setSignaledValue(1);}}){}
 ~Safety(){if(event->signaledValue()<1)event->setSignaledValue(1);done.store(true);worker.join();}
};
int main(){
 try{
  require(fios_enable_stream_custody_fixture());const auto stream=new_stream(Device::gpu);auto cstream=mlx_stream_new_(stream);
  uint64_t object=0;const auto event=dsv41ev_create_metal(0,&object);require(event>0&&object);
  Safety safety(reinterpret_cast<MTL::SharedEvent*>(object));
  auto input=mlx_array_new_(array(1.0f)),waited=mlx_array_new_(),signaled=mlx_array_new_();
  require(dsv41ev_wait(&input,1,event,1,nullptr,0,false,cstream,&waited)==0);
  async_eval({mlx_array_get_(waited)});
  bool observed=false;
  for(int i=0;i<300;i++){
   int64_t stats[8]={0};dsv41ev_stats(stats);const auto host=fios_host_queue_state();
   if(stats[0]==1&&!host.pending&&!host.active){observed=true;break;}
   std::this_thread::sleep_for(10ms);
  }
  const auto blocked=fios_metal_buffer_state();
  bool broken=!observed||blocked.uncertain||!blocked.pending||!blocked.captures;
  if(!broken){
   const auto creator=fios_hold_stream_creation(blocked.epoch);require(creator);
   const auto host=fios_hold_host_queues(creator,fios_metal_buffer_state().epoch);require(host);
   const auto premature=fios_hold_metal_buffers(creator,host,fios_metal_buffer_state().epoch);
   if(premature){broken=true;require(fios_release_metal_buffers(premature));}
   else{
    // Exact host release already rearms BOTH host and creator gates.
    require(fios_release_host_queues(host));
    require(!fios_release_stream_creation(creator));
    require(!fios_host_queue_state().held&&!fios_stream_custody_state().held);
   }
  }
  safety.event->setSignaledValue(1);eval({mlx_array_get_(waited)});
  require(mlx_array_get_(waited).item<float>()==1.0f);
  require(dsv41ev_signal(&waited,1,event,2,cstream,&signaled)==0);eval({mlx_array_get_(signaled)});
  require(dsv41ev_value(event)==2&&mlx_array_get_(signaled).item<float>()==1.0f);
  for(int i=0;i<300;i++){const auto state=fios_metal_buffer_state();if(!state.pending&&!state.captures)break;std::this_thread::sleep_for(10ms);}
  safety.done.store(true);require(!safety.expired.load());
  const auto final=fios_metal_buffer_state();broken|=final.uncertain;
  mlx_array_free_(signaled);mlx_array_free_(waited);mlx_array_free_(input);mlx_stream_free_(cstream);
  if(broken){std::fputs("MIMO_EVENT_GRAPH_RAW_ESCAPE_OR_UNTRACKED_BUFFER\n",stderr);return 77;}
  require(!final.pending&&!final.captures&&!final.uncertain);
  const auto creator=fios_hold_stream_creation(final.epoch);require(creator);
  const auto host=fios_hold_host_queues(creator,fios_metal_buffer_state().epoch);require(host);
  const auto gpu=fios_hold_metal_buffers(creator,host,fios_metal_buffer_state().epoch);require(gpu);require(fios_release_metal_buffers(gpu));
  std::puts("PASS: actual MIMO C ABI, one-scalar MLX wait/signal graph, live blocked GPU/capture refusal and genuine drain; process-life event pool/model/context/lifecycle authority NOT established");
 }catch(const std::exception& error){std::fprintf(stderr,"FAIL: %s\n",error.what());return 78;}
}
