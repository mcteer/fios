// Genuine CPU-only bridge/source composition. No model, artificial backend
// error, counter boundary, source mutation or installed operation.
#include "device_owner_barrier.h"
#include "mlx/stream.h"
#include "mlx/scheduler.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <stdexcept>
#include <thread>
using namespace std::chrono_literals;
namespace mx=mlx::core;
static void require(bool value) {
  if (!value) {std::fputs("FAIL: source component bridge composition\n",stderr);std::exit(77);}
}
int main() {
  require(fios_mlx_source_known_uncertainty()==0);
  const auto owner=fios_mlx_current_thread();require(owner);
  require(fios_mlx_create_owned_cpu_stream(owner)==0);
  uint64_t ticket=0;require(fios_mlx_hold_owned_registry(owner,&ticket)==0&&ticket);
  require(!mx::fios_host_queue_state().held&&!mx::fios_metal_buffer_state().held);
  fios_mlx_barrier_result result{};
  require(fios_mlx_owner_barrier(owner,&result)==0&&result.streams_seen==1&&result.streams_synchronized==1);
  require(mx::fios_stream_custody_state().held&&mx::fios_host_queue_state().held&&mx::fios_metal_buffer_state().held);
  // A later probe cannot enqueue synchronization through the held source
  // gate. Its refusal must retain the first successful pause's physical holds.
  fios_mlx_barrier_result repeated{};
  require(fios_mlx_owner_barrier(owner,&repeated)!=0);
  require(mx::fios_stream_custody_state().held&&mx::fios_host_queue_state().held&&mx::fios_metal_buffer_state().held);
  bool directBlocked=false;
  try {(void)mx::new_stream(mx::Device::cpu);}catch(const std::runtime_error&){directBlocked=true;}
  require(directBlocked&&fios_mlx_create_owned_cpu_stream(owner)!=0);
  bool foreignReleased=true;
  std::thread other([&]{foreignReleased=fios_mlx_release_owned_registry(owner,ticket)==0;});other.join();
  require(!foreignReleased&&mx::fios_host_queue_state().held);
  require(fios_mlx_release_owned_registry(owner,ticket+1)!=0&&mx::fios_host_queue_state().held);
  require(fios_mlx_release_owned_registry(owner,ticket)==0);
  require(!mx::fios_stream_custody_state().held&&!mx::fios_host_queue_state().held&&!mx::fios_metal_buffer_state().held);
  require(fios_mlx_release_owned_registry(owner,ticket)!=0);
  std::promise<void> ran;auto done=ran.get_future();
  mx::scheduler::enqueue(mx::get_streams().front(),[&]{ran.set_value();});
  require(done.wait_for(3s)==std::future_status::ready);done.get();
  require(fios_mlx_create_owned_cpu_stream(owner)==0);
  require(fios_mlx_source_known_uncertainty()==0);
  // Actual ordinary stream cleanup marks the SDK source uncertain. The fixed
  // bridge getter only reads its atomic mirror, without taking either lock.
  mx::clear_streams();
  require(fios_mlx_source_known_uncertainty()==1);
  bool seen=false;
  std::thread observer([&]{seen=fios_mlx_source_known_uncertainty()==1;});observer.join();
  require(seen&&mx::fios_stream_custody_state().uncertain);
  std::puts("PASS: fixed bridge reads genuine sticky MLX source uncertainty after stream cleanup");
  std::puts("PASS: actual owned CPU synchronization seals tracked source gates afterward; exact bridge resume releases them before later work; partial source only");
}
