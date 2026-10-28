// Explicit empty-Metal source fixture. No arrays, kernels, models or inference.
#include "mlx/stream.h"
#include <cstdlib>
#include <dlfcn.h>
#include <iostream>
#include <stdexcept>
#include <string_view>
#include <thread>
static void require(bool value) {if (!value) std::exit(77);}
static bool refused() {
    try {(void)mlx::core::new_stream(mlx::core::Device::gpu);}
    catch (const std::runtime_error&) {return true;}
    return false;
}
int main(int argc,char** argv) {
    using namespace mlx::core;
    require(argc==2 && std::string_view(argv[1])=="--empty-gpu");
    Dl_info creation{},custody{};
    require(dladdr(reinterpret_cast<void*>(&new_stream),&creation)!=0);
    require(dladdr(reinterpret_cast<void*>(&fios_enable_stream_custody_fixture),&custody)!=0);
    require(creation.dli_fbase==custody.dli_fbase);
    require(fios_enable_stream_custody_fixture());
    const auto raw=new_stream(Device::gpu),ordinary=default_stream(Device::gpu);
    const auto local=stream_from_thread_local_stream(new_thread_local_stream(Device::gpu));
    require(raw!=ordinary && ordinary!=local && raw!=local);
    const auto owned=fios_owned_streams();
    require(owned.size()==3 && get_streams().size()==3);
    for (const auto stream:owned) {require(stream.device==Device::gpu);synchronize(stream);}
    const auto state=fios_stream_custody_state();
    require(state.registered==3 && state.pending==0 && !state.uncertain && !state.shared);
    const auto ticket=fios_hold_stream_creation(state.epoch);
    require(ticket!=0 && refused());
    std::thread other([&] {require(!fios_release_stream_creation(ticket));require(refused());});
    other.join();
    require(get_streams().size()==3 && !fios_release_stream_creation(ticket+1));
    for (const auto stream:owned) synchronize(stream);
    require(fios_release_stream_creation(ticket) && !fios_release_stream_creation(ticket));
    const auto resumed=new_stream(Device::gpu);
    synchronize(resumed);
    require(get_streams().size()==4 && fios_owned_streams().size()==4);
    std::cout << "PASS: same genuine source image creates/captures/synchronizes real empty Metal raw/default/thread-local streams; exact hold rejects raw/foreign creation, exact release permits creation. No arrays/kernels/models/inference or lifecycle grant.\n";
}
