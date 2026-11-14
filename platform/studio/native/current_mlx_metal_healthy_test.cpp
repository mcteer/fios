// Current c69303b SDK, healthy empty Metal buffers only. No arrays, kernels,
// models, failure injection or all-client/native terminal authority.
#include "mlx/stream.h"
#include "mlx/backend/metal/device.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <dlfcn.h>
#include <future>
#include <memory>
#include <string>
#include <thread>
using namespace mlx::core;
using namespace std::chrono_literals;
static void require(bool value,const char* message) {
  if(!value){std::fprintf(stderr,"%s\n",message);std::exit(78);}
}
int main(int argc,char** argv) {
  require(argc==2,"CURRENT_METAL_CONTROL_ARGUMENT");
  const std::string mode=argv[1];
  require(mode=="--callback"||mode=="--payload"||mode=="--capture","CURRENT_METAL_CONTROL_ARGUMENT");
  Dl_info ordinary{},custody{};
  require(dladdr(reinterpret_cast<void*>(&new_stream),&ordinary)!=0 &&
          dladdr(reinterpret_cast<void*>(&fios_metal_buffer_state),&custody)!=0 &&
          ordinary.dli_fbase==custody.dli_fbase,"CURRENT_METAL_LIBRARY_IDENTITY");
  require(fios_enable_stream_custody_fixture(),"CURRENT_METAL_FIXTURE_ENROLLMENT");
  const auto stream=new_stream(Device::gpu);
  auto& encoder=metal::get_command_encoder(stream);
  std::promise<void> entered,released;
  auto began=entered.get_future();auto release=released.get_future().share();
  std::atomic<bool> expired{false};
  auto pause=[&] {
    entered.set_value();
    if(release.wait_for(5s)!=std::future_status::ready)expired.store(true);
  };
  if(mode=="--callback")encoder.commit(pause);
  else {
    auto payload=std::shared_ptr<int>(new int(1),[&](int* value){pause();delete value;});
    if(mode=="--payload")encoder.commit([payload=std::move(payload)]{});
    else {encoder.add_completed_handler([payload=std::move(payload)](MTL::CommandBuffer*){});encoder.commit();}
  }
  require(began.wait_for(3s)==std::future_status::ready,"CURRENT_METAL_CALLBACK_DEADLINE");began.get();
  const auto held=fios_metal_buffer_state();
  require(held.pending==1&&!held.uncertain,"CURRENT_METAL_EARLY_BUFFER_RETIREMENT");
  // This SDK captures commit completion too. The explicit handler may overlap
  // that independent capture; its own payload must retain at least one.
  require(mode=="--capture" ? (held.captures>=1&&held.captures<=2):held.captures==1,
          "CURRENT_METAL_EARLY_PAYLOAD_RETIREMENT");
  released.set_value();encoder.synchronize();
  const auto until=std::chrono::steady_clock::now()+2s;
  while(std::chrono::steady_clock::now()<until) {
    const auto state=fios_metal_buffer_state();
    if(state.pending==0&&state.captures==0)break;
    std::this_thread::sleep_for(1ms);
  }
  const auto done=fios_metal_buffer_state();
  require(!expired.load()&&done.pending==0&&done.captures==0&&!done.uncertain,
          "CURRENT_METAL_LOCAL_RETIREMENT_DEADLINE");
  std::puts("PASS: current SDK healthy empty Metal callback/payload/capture lifetime; no model or all-client proof");
}
