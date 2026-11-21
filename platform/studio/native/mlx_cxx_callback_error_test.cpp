// Actual CPU callback + existing error channel. No hooks, replacement SDK,
// model, GPU dispatch, native server or installed operation.
#include "mlx/stream.h"
#include "mlx/scheduler.h"
#include <chrono>
#include <cstdio>
#include <stdexcept>
#include <string_view>
#include <thread>
int main() {
  namespace mx=mlx::core;
  if(!mx::fios_enable_stream_custody_fixture())return 1;
  const auto stream=mx::new_stream(mx::Device::cpu);
  mx::scheduler::enqueue(stream,[]{throw std::runtime_error("bounded ordinary CPU callback error");});
  bool caught=false;
  try {mx::synchronize(stream);}
  catch(const std::exception& error) {caught=std::string_view(error.what())=="bounded ordinary CPU callback error";}
  if(!caught)return 2;
  const auto end=std::chrono::steady_clock::now()+std::chrono::seconds(3);
  while(std::chrono::steady_clock::now()<end) {
    const auto state=mx::fios_host_queue_state();
    if(!state.pending&&!state.active&&state.uncertain) {
      std::puts("PASS: actual system C++ SDK callback error channel and completed CPU cleanup");return 0;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return 3;
}
