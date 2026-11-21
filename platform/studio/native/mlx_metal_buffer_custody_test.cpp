// Genuine MLX/Metal only, empty buffers/encoders and C++ payloads. No arrays,
// kernels, models, inference or all-backend/lifecycle grant.
#include "mlx/stream.h"
#include "mlx/backend/metal/device.h"
#ifdef FIOS_METAL_PRIVATE_FIXTURE
#include "mlx/backend/gpu/eval.h"
#endif
#include <atomic>
#include <dlfcn.h>
#include <stdexcept>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <memory>
#include <string>
#include <thread>
using namespace std::chrono_literals;
using namespace mlx::core;
static void require(bool value){if(!value){std::fputs("FAIL: Metal buffer custody assertion\n",stderr);std::exit(78);}}
static void wait(std::future<void>& future){require(future.wait_for(3s)==std::future_status::ready);future.get();}
static uint64_t close_all(){
 const auto creation=fios_hold_stream_creation(fios_metal_buffer_state().epoch);require(creation);
 const auto host=fios_hold_host_queues(creation,fios_metal_buffer_state().epoch);require(host);
 const auto metal=fios_hold_metal_buffers(creation,host,fios_metal_buffer_state().epoch);require(metal);
 require(!fios_release_host_queues(host)&&!fios_release_stream_creation(creation));return metal;
}
int main(int argc,char** argv){
 require(argc==2);const std::string mode=argv[1];
 Dl_info ordinary{},custody{};
 require(dladdr(reinterpret_cast<void*>(&new_stream),&ordinary)!=0&&dladdr(reinterpret_cast<void*>(&fios_metal_buffer_state),&custody)!=0&&ordinary.dli_fbase==custody.dli_fbase);
 require(fios_enable_stream_custody_fixture());const auto stream=new_stream(Device::gpu);
 auto& encoder=metal::get_command_encoder(stream);
 require(fios_metal_buffer_state().pending==0);
 if(mode=="--callback"||mode=="--payload"||mode=="--capture"){
  std::promise<void> entered,released;auto began=entered.get_future();auto release=released.get_future().share();
  std::atomic<bool> expired{false};
  if(mode=="--callback")encoder.commit([&]{entered.set_value();if(release.wait_for(5s)!=std::future_status::ready)expired.store(true);});
  else {
   auto payload=std::shared_ptr<int>(new int(1),[&](int* value){entered.set_value();if(release.wait_for(5s)!=std::future_status::ready)expired.store(true);delete value;});
   if(mode=="--capture") {encoder.add_completed_handler([payload=std::move(payload)](MTL::CommandBuffer*){});encoder.commit();}
   else encoder.commit([payload=std::move(payload)]{});
  }
  wait(began);
  const auto state=fios_metal_buffer_state();
  if(state.pending!=1){std::fputs("EARLY_METAL_CALLBACK_OR_PAYLOAD_RETIREMENT\n",stderr);std::exit(77);}
  require(!state.uncertain);
  if(state.captures!=(mode=="--capture"?1:0)){std::fputs("EARLY_METAL_CAPTURE_PAYLOAD_RETIREMENT\n",stderr);std::exit(77);}
  const auto creation=fios_hold_stream_creation(state.epoch);require(creation);
  const auto host=fios_hold_host_queues(creation,fios_metal_buffer_state().epoch);require(host);
  require(!fios_hold_metal_buffers(creation,host,fios_metal_buffer_state().epoch));
  released.set_value();encoder.synchronize();require(!expired.load());require(fios_metal_buffer_state().pending==0);
  const auto metal=fios_hold_metal_buffers(creation,host,fios_metal_buffer_state().epoch);require(metal);require(fios_release_metal_buffers(metal));
 }else if(mode=="--uncommitted"){
  const int value=1;encoder.set_bytes(value,0);
  require(fios_metal_buffer_state().pending==1);encoder.end_encoding();
  require(fios_metal_buffer_state().pending==1&&fios_metal_buffer_state().captures==1);encoder.synchronize();
  require(fios_metal_buffer_state().pending==0&&!fios_metal_buffer_state().uncertain);
  require(fios_release_metal_buffers(close_all()));
 }else if(mode=="--exact-gate"){
  encoder.synchronize();const auto metal=close_all();
  bool blocked=false;try{encoder.commit();}catch(const std::runtime_error&){blocked=true;}
  if(!blocked){std::fputs("METAL_GATE_ALLOWED_SUBMISSION\n",stderr);std::exit(77);}
  bool foreign=true;std::thread other([&]{foreign=fios_release_metal_buffers(metal);});other.join();require(!foreign);
  require(!fios_release_metal_buffers(metal+1)&&fios_metal_buffer_state().held);
  require(fios_release_metal_buffers(metal)&&!fios_release_metal_buffers(metal));encoder.synchronize();
  const auto replacement=close_all();require(replacement!=metal&&!fios_release_metal_buffers(metal));require(fios_release_metal_buffers(replacement));
 }else if(mode=="--foreign"){
  std::thread other([&]{encoder.synchronize();});other.join();
  require(fios_metal_buffer_state().uncertain&&!fios_hold_stream_creation(fios_metal_buffer_state().epoch));
 }else if(mode=="--owner-exit"){
  encoder.synchronize();uint64_t held=0;
  std::thread owner([&]{(void)new_stream(Device::cpu);held=close_all();});owner.join();
  require(!fios_release_metal_buffers(held)&&fios_metal_buffer_state().held&&fios_host_queue_state().held&&fios_stream_custody_state().held);
  std::puts("PASS: exiting owner does not refund three gates; deliberate fixture exit without new destructor submission, NOT device/context terminality");std::fflush(nullptr);std::_Exit(0);
 }else if(mode=="--exhausted-release"){
  encoder.synchronize();const auto held=close_all();require(!fios_release_metal_buffers(held));
  if(!fios_metal_buffer_state().held||!fios_host_queue_state().held||!fios_stream_custody_state().held){std::fputs("METAL_RELEASE_CLEARED_ON_EXHAUSTION\n",stderr);std::_Exit(77);}
  require(fios_metal_buffer_state().uncertain);
  std::puts("PASS: exhausted source boundary retains three gates/uncertainty; deliberate fixture exit, not retirement");std::fflush(nullptr);std::_Exit(0);
#ifdef FIOS_METAL_PRIVATE_FIXTURE
 }else if(mode=="--backend-clear-held"){
  encoder.synchronize();const auto creation=fios_hold_stream_creation(fios_metal_buffer_state().epoch);require(creation);
  const auto host=fios_hold_host_queues(creation,fios_metal_buffer_state().epoch);require(host);
  bool refused=false;try{gpu::clear_streams();}catch(const std::runtime_error&){refused=true;}
  require(fios_release_host_queues(host));
  if(!refused){std::fputs("GPU_BACKEND_CLEAR_ALLOWED_WITH_CREATION_HOST_HELD\n",stderr);return 77;}
  require(&metal::get_command_encoder(stream)==&encoder&&!fios_metal_buffer_state().uncertain);encoder.synchronize();
 }else if(mode=="--backend-clear-unheld"){
  encoder.synchronize();gpu::clear_streams();
  require(fios_metal_buffer_state().uncertain&&!fios_hold_stream_creation(fios_metal_buffer_state().epoch));
#endif
 }else if(mode=="--raw-alias"){
  require(encoder.get_command_buffer()!=nullptr);require(fios_metal_buffer_state().uncertain);
  require(!fios_hold_stream_creation(fios_metal_buffer_state().epoch));
 }else require(false);
 std::puts("PASS: genuine empty Metal buffer/callback/payload custody subdomain only; NOT all-context/lifecycle authority");
}
