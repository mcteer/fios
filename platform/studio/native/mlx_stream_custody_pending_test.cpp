// Real CPU backend with a private source checkpoint before actual creation.
#include "mlx/stream.h"
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <thread>
namespace mlx::core {MLX_API void fios_fixture_release_pending();}
static void require(bool value) {if (!value) std::exit(77);}
int main() {
    using namespace mlx::core;
    using namespace std::chrono_literals;
    require(fios_enable_stream_custody_fixture());
    require(fios_current_stream_owner()!=0);
    std::atomic<bool> finished=false;
    std::thread creator([&] {
        const auto stream=new_stream(Device::cpu);
        synchronize(stream);
        finished.store(true);
    });
    const auto until=std::chrono::steady_clock::now()+2s;
    while(fios_stream_custody_state().pending==0 && std::chrono::steady_clock::now()<until)
        std::this_thread::sleep_for(1ms);
    const auto pending=fios_stream_custody_state();
    require(pending.pending==1 && pending.registered==0 && !finished.load());
    require(fios_hold_stream_creation(pending.epoch)==0);
    bool snapshotDenied=false;
    try {(void)fios_owned_streams();} catch(const std::runtime_error&) {snapshotDenied=true;}
    require(snapshotDenied && fios_stream_custody_state().pending==1);
    fios_fixture_release_pending();
    creator.join();
    const auto complete=fios_stream_custody_state();
    require(finished.load() && complete.pending==0 && complete.registered==1 && !complete.uncertain);
    const auto ticket=fios_hold_stream_creation(complete.epoch);
    require(ticket!=0);
    bool held=false;
    try {(void)new_stream(Device::cpu);} catch(const std::runtime_error&) {held=true;}
    require(held && fios_release_stream_creation(ticket));
    const auto own=new_stream(Device::cpu);
    synchronize(own);
    require(fios_owned_streams().size()==1 && fios_stream_custody_state().registered==2);
    std::cout << "PASS: real pending creation denies reservation/snapshot without holding metadata mutex; exact completion permits hold, separate creators remain distinct.\n";
}
