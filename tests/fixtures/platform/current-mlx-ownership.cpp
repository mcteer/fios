// Ordinary private SDK source fixture, no model/GPU dispatch or authority.
#include "mlx/stream.h"
#include "mlx/ops.h"
#include "mlx/transforms.h"
#include <cstdio>
#include <chrono>
#include <thread>
#include <stdexcept>
using namespace mlx::core;
static void require(bool condition) {
  if (!condition) throw std::runtime_error("CURRENT_MLX_OWNERSHIP_CONTRACT_UNAVAILABLE");
}
int main() {
  try {
    require(fios_enable_stream_custody_fixture());
    set_default_device(Device::cpu);
    auto value = add(array(1.0f), array(0.25f), Device::cpu);
    eval(value);
    require(value.item<float>() == 1.25f);
    synchronize(default_stream(Device::cpu));
    auto before = fios_host_queue_state();
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (!before.uncertain && (before.pending || before.active) && std::chrono::steady_clock::now() < deadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
      before = fios_host_queue_state();
    }
    require(!before.uncertain && before.pending == 0 && before.active == 0);
    const auto ticket = fios_hold_source_components(before.epoch);
    require(ticket != 0);
    require(fios_stream_custody_state().held && fios_host_queue_state().held && fios_metal_buffer_state().held);
    require(fios_release_metal_buffers(ticket));
    require(!fios_stream_custody_state().held && !fios_host_queue_state().held && !fios_metal_buffer_state().held);
    require(!fios_known_source_uncertain());
    std::puts("PASS: current genuine CPU scalar and ordinary source-component hold/release; no model or native authority");
    return 0;
  } catch (const std::exception& error) {
    std::fputs(error.what(), stderr);
    std::fputc('\n', stderr);
    return 77;
  }
}
