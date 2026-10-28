// Genuine MLX/Metal shared events, no arrays/kernels/models/inference.
// Explicit source-candidate subdomain only; never lifecycle authority.
#include "mlx/stream.h"
#include "mlx/backend/metal/device.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <string>
#include <thread>
#include <stdexcept>
using namespace mlx::core;
using namespace std::chrono_literals;
static void require(bool value){if(!value){std::fputs("FAIL: genuine shared-event fixture\n",stderr);std::exit(78);}}
static uint64_t close_all(){
 const auto creator=fios_hold_stream_creation(fios_metal_buffer_state().epoch);require(creator);
 const auto host=fios_hold_host_queues(creator,fios_metal_buffer_state().epoch);require(host);
 const auto gpu=fios_hold_metal_buffers(creator,host,fios_metal_buffer_state().epoch);require(gpu);return gpu;
}
int main(int argc,char**argv){
 require(argc==2);const std::string mode=argv[1];require(fios_enable_stream_custody_fixture());
 const auto stream=new_stream(Device::gpu);auto& encoder=metal::get_command_encoder(stream);
 auto event=NS::TransferPtr(metal::device(Device::gpu).mtl_device()->newSharedEvent());require(bool(event));
 require(event->signaledValue()==0);
 bool broken=false;
 if(mode=="--wait"){
  std::atomic<bool> done{false},expired{false};
  std::thread watchdog([&]{for(int i=0;i<500&&!done.load();i++)std::this_thread::sleep_for(10ms);if(!done.load()){expired.store(true);event->setSignaledValue(1);}});
  encoder.fios_encode_shared_wait(event.get(),1);
  const auto encoded=fios_metal_buffer_state();broken=encoded.pending!=1||encoded.captures!=1||encoded.uncertain;
  encoder.commit();const auto submitted=fios_metal_buffer_state();broken|=submitted.pending!=1||submitted.captures!=1||submitted.uncertain;
  const auto creator=fios_hold_stream_creation(submitted.epoch);require(creator);
  const auto host=fios_hold_host_queues(creator,fios_metal_buffer_state().epoch);require(host);
  const auto premature=fios_hold_metal_buffers(creator,host,fios_metal_buffer_state().epoch);
  if(premature){broken=true;require(fios_release_metal_buffers(premature));}
  event->setSignaledValue(1);encoder.synchronize();done.store(true);watchdog.join();require(!expired.load());
  if(!premature){const auto gpu=fios_hold_metal_buffers(creator,host,fios_metal_buffer_state().epoch);require(gpu);require(fios_release_metal_buffers(gpu));}
 }else if(mode=="--signal"){
  encoder.fios_encode_shared_signal(event.get(),1);const auto state=fios_metal_buffer_state();broken=state.pending!=1||state.captures!=1||state.uncertain;
  encoder.synchronize();require(event->signaledValue()==1);
 }else if(mode=="--held-signal"){
  encoder.synchronize();const auto held=close_all();bool refused=false;
  try{encoder.fios_encode_shared_signal(event.get(),1);}catch(const std::runtime_error&){refused=true;}
  require(fios_release_metal_buffers(held));encoder.synchronize();broken=!refused||event->signaledValue()!=0;
 }else return 78;
 // All negative witnesses drain real GPU work before returning their marker.
 if(broken){std::fputs("METAL_SHARED_EVENT_RESERVATION_OR_CAPTURE_BOUNDARY\n",stderr);return 77;}
 const auto final=fios_metal_buffer_state();require(!final.pending&&!final.captures&&!final.uncertain);
 require(fios_release_metal_buffers(close_all()));
 std::printf("PASS: actual MLX shared-event %s reservation/capture/gate boundary; no raw buffer escape, NOT all-context/model/lifecycle proof\n",mode.c_str());
}
