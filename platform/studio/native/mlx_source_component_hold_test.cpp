// Ordinary genuine CPU scheduler lifecycle; no models, tensors, GPU dispatch,
// source mutation, artificial counter boundary or injected backend failure.
#include "mlx/stream.h"
#include "mlx/scheduler.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <stdexcept>
#include <thread>
using namespace mlx::core;
using namespace std::chrono_literals;
static void require(bool value) {
  if (!value) {std::fputs("FAIL: source component hold lifecycle\n",stderr);std::exit(77);}
}
static void wait(std::future<void>& future) {
  require(future.wait_for(3s)==std::future_status::ready);future.get();
}
static FiosHostQueueState drained() {
  const auto end=std::chrono::steady_clock::now()+3s;
  while (std::chrono::steady_clock::now()<end) {
    auto state=fios_host_queue_state();
    if (!state.pending&&!state.active) return state;
    std::this_thread::sleep_for(1ms);
  }
  require(false);return {};
}
int main() {
  require(fios_enable_stream_custody_fixture());
  const auto stream=new_stream(Device::cpu);
  std::promise<void> entered,release;
  auto ready=entered.get_future();auto released=release.get_future().share();
  scheduler::enqueue(stream,[&]{entered.set_value();released.wait();});wait(ready);
  const auto busy=fios_host_queue_state();
  require(busy.pending==1&&busy.active==1&&!busy.uncertain);
  require(!fios_hold_source_components(busy.epoch));
  // Refusal publishes none of the three gates, so queued ordinary work can
  // still be accepted and completed after the first callback returns.
  require(!fios_stream_custody_state().held&&!fios_host_queue_state().held&&!fios_metal_buffer_state().held);
  std::promise<void> next;auto completed=next.get_future();
  scheduler::enqueue(stream,[&]{next.set_value();});release.set_value();wait(completed);
  const auto idle=drained();require(!idle.uncertain);
  require(!fios_hold_source_components(busy.epoch)); // Genuine advanced epoch.
  const auto ticket=fios_hold_source_components(fios_host_queue_state().epoch);require(ticket);
  const auto streams=fios_stream_custody_state();const auto host=fios_host_queue_state();const auto metal=fios_metal_buffer_state();
  require(streams.held&&host.held&&metal.held&&streams.epoch==host.epoch&&host.epoch==metal.epoch);
  bool streamBlocked=false,taskBlocked=false;
  try {(void)new_stream(Device::cpu);}catch(const std::runtime_error&){streamBlocked=true;}
  try {scheduler::enqueue(stream,[]{});}catch(const std::runtime_error&){taskBlocked=true;}
  require(streamBlocked&&taskBlocked&&!fios_host_queue_state().uncertain);
  bool foreignReleased=true;
  std::thread other([&]{foreignReleased=fios_release_metal_buffers(ticket);});other.join();
  require(!foreignReleased&&fios_metal_buffer_state().held);
  require(fios_release_metal_buffers(ticket));
  require(!fios_stream_custody_state().held&&!fios_host_queue_state().held&&!fios_metal_buffer_state().held);
  const auto second=fios_hold_source_components(fios_host_queue_state().epoch);require(second&&second!=ticket);
  require(!fios_release_metal_buffers(ticket)&&fios_metal_buffer_state().held);
  require(fios_release_metal_buffers(second));
  std::promise<void> rearmed;auto done=rearmed.get_future();
  scheduler::enqueue(stream,[&]{rearmed.set_value();});wait(done);require(!drained().uncertain);
  std::puts("PASS: genuine CPU work refuses atomic source-component hold without partial gates; exact creator release and later work succeed; no all-backend authority");
}
