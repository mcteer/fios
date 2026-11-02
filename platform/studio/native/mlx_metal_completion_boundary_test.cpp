// Genuine MLX/Metal SDK boundary witness only: empty command buffer, no
// arrays, kernels, models or inference. Host-only custody is NOT GPU custody.
#include "mlx/stream.h"
#include "mlx/backend/metal/device.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>
using namespace std::chrono_literals;
static void require(bool value) {if(!value){std::fputs("FAIL: genuine Metal boundary assertion\n",stderr);std::exit(78);}}
int main() {
 using namespace mlx::core;
 require(fios_enable_stream_custody_fixture());
 const auto stream=new_stream(Device::gpu);
 auto& encoder=metal::get_command_encoder(stream);
 std::promise<void> entered,released;
 auto began=entered.get_future();auto release=released.get_future().share();
 std::atomic<bool> live{false},timed_out{false};
 encoder.commit([&]{
  live.store(true);entered.set_value();
  if(release.wait_for(5s)!=std::future_status::ready)timed_out.store(true);
  live.store(false);
 });
 require(began.wait_for(3s)==std::future_status::ready);began.get();
 const auto observed=fios_host_queue_state();
 require(live.load()&&!timed_out.load()&&observed.pending==0&&observed.active==0&&!observed.uncertain);
 const auto creation=fios_hold_stream_creation(observed.epoch);
 require(creation!=0);
 const auto host=fios_hold_host_queues(creation,fios_host_queue_state().epoch);
 const bool partial_closed_while_gpu_callback_live=host!=0&&live.load();
 if(host)require(fios_release_host_queues(host));
 else require(fios_release_stream_creation(creation));
 released.set_value();encoder.synchronize();
 require(!live.load()&&!timed_out.load());
 if(partial_closed_while_gpu_callback_live){
  std::fputs("LIVE_METAL_COMPLETION_WITH_HOST_ONLY_GATE: actual empty GPU callback was live while actual host-only gate closed; safely released/drained, no all-backend/lifecycle authority\n",stderr);
  return 77;
 }
 std::fputs("FAIL: expected original host-only scope boundary was not observed\n",stderr);
 return 78;
}
