// Compile the actual pinned upstream warm implementation, not an SDK/API
// stand-in or model-context fabrication. One group/32 lanes/one FMA iteration;
// separate 256KiB warm buffer only, no model arrays, weights or inference.
#include "mlx/stream.h"
namespace mx=mlx::core;
#include "mimo_gpu_warm.inc"
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <future>
#include <stdexcept>
#include <thread>
using namespace std::chrono_literals;
static void require(bool value,const char* reason){if(!value)throw std::runtime_error(reason);}
int main(int argc,char** argv){
 if(argc!=2)return 78;
 const bool gap=std::string(argv[1])=="--scope-gap";
 if(!gap&&std::string(argv[1])!="--drain-only")return 78;
 void* warm=nullptr;void* chunk=nullptr;
 MTL::SharedEvent* event=nullptr;MTL::CommandBuffer* predecessor=nullptr;
 uint64_t held=0;bool witnessed=false;std::string error;
 NS::AutoreleasePool* pool=NS::AutoreleasePool::alloc()->init();
 std::promise<void> finished;auto finish=finished.get_future().share();
 std::atomic<bool> timed_out{false};std::thread watchdog;
 double start=0,end=0;
 try{
  require(mx::fios_enable_stream_custody_fixture(),"fixture enable");(void)mx::new_stream(mx::Device::cpu);
  require(mimo_warm_create(1,32,&warm)==0,mimo_warm_last_error());
  auto* native=static_cast<mimo_warm::Warm*>(warm);
  event=mx::metal::device(mx::Device::gpu).mtl_device()->newSharedEvent();require(event,"real SharedEvent");
  require(event->signaledValue()==0,"new event must be unsignaled");
  // A bounded safety release prevents a fixture failure leaving its OWN queue
  // waiting forever. Timeout is failure, never a retirement receipt.
  watchdog=std::thread([&]{if(finish.wait_for(5s)!=std::future_status::ready){timed_out.store(true);event->setSignaledValue(1);}});
  predecessor=native->queue->commandBuffer();require(predecessor,"real predecessor");predecessor->retain();
  predecessor->encodeWait(event,1);predecessor->commit();
  require(mimo_warm_commit(warm,1,&chunk)==0,mimo_warm_last_error());
  auto* committed=static_cast<MTL::CommandBuffer*>(chunk);
  require(committed->status()!=MTL::CommandBufferStatusCompleted&&committed->status()!=MTL::CommandBufferStatusError,"actual gated chunk must remain pending");
  if(gap){
   auto state=mx::fios_metal_buffer_state();require(!state.uncertain&&state.pending==0,"MLX buffer scope does not see independent warm queue");
   const auto creation=mx::fios_hold_stream_creation(state.epoch);require(creation,"creator hold");
   const auto host=mx::fios_hold_host_queues(creation,mx::fios_metal_buffer_state().epoch);require(host,"host hold");
   held=mx::fios_hold_metal_buffers(creation,host,mx::fios_metal_buffer_state().epoch);require(held,"MLX-only buffer hold");
   witnessed=!timed_out.load()&&event->signaledValue()==0&&committed->status()!=MTL::CommandBufferStatusCompleted;
   require(witnessed,"independent queue must be demonstrably live while MLX-only gate is closed");
  }
 }catch(const std::exception& exception){error=exception.what();}
 // Always release exact owned scope, unblock the owned queue, and require the
 // REAL upstream retirement/status receipt before releasing its resources.
 if(held&&!mx::fios_release_metal_buffers(held))error="exact MLX buffer release refused";
 if(event)event->setSignaledValue(1);
 if(chunk){const int code=mimo_warm_retire(chunk,&start,&end);chunk=nullptr;if(code!=0)error=mimo_warm_last_error();}
 if(predecessor){predecessor->waitUntilCompleted();if(predecessor->status()!=MTL::CommandBufferStatusCompleted)error="predecessor failed";predecessor->release();}
 finished.set_value();if(watchdog.joinable())watchdog.join();
 if(timed_out.load())error="safety deadline fired; no retirement acceptance";
 if(event)event->release();if(warm)mimo_warm_destroy(warm);pool->release();
 if(!error.empty()){std::fprintf(stderr,"FAIL: genuine warm fixture: %s\n",error.c_str());return 78;}
 if(!std::isfinite(start)||!std::isfinite(end)||start<=0||end<start)return 78;
 std::printf("Actual independent warm queue retired successfully; groups=1 threads=32 iterations=1 buffer_bytes=262144 gpu_ns=%.0f; no model/inference/lifecycle grant\n",(end-start)*1e9);
 if(gap&&witnessed){std::fputs("LIVE_MIMO_WARM_QUEUE_WITH_MLX_ONLY_GATE: actual event-gated independent upstream queue remained pending under MLX-only gates; exact release and genuine retirement succeeded\n",stderr);return 77;}
 return 0;
}
