// Genuine CPU-only MLX source fixture. No arrays, models or inference.
#include "mlx/stream.h"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string_view>
#include <thread>

static void require(bool condition) { if (!condition) std::exit(77); }
static bool refused_creation() {
    try { (void)mlx::core::new_stream(mlx::core::Device::cpu); }
    catch (const std::runtime_error&) { return true; }
    return false;
}
int main(int argc, char** argv) {
    using namespace mlx::core;
    require(argc == 2);
    const std::string_view mode(argv[1]);
    if (mode == "--assertion-negative") {require(false); return 0;}
    if (mode == "--late") {
        (void)new_stream(Device::cpu);
        require(!fios_enable_stream_custody_fixture());
        require(!fios_stream_custody_state().enabled);
        std::cout << "PASS: preexisting raw stream cannot be adopted.\n";
        return 0;
    }
    require(fios_enable_stream_custody_fixture());
    require(!fios_enable_stream_custody_fixture());
    if (mode == "--exhausted-release") {
        // Run only with the private source boundary injector setting epoch=max.
        (void)new_stream(Device::cpu);
        const auto ticket=fios_hold_stream_creation(fios_stream_custody_state().epoch);
        require(ticket!=0 && !fios_release_stream_creation(ticket));
        require(fios_stream_custody_state().held && refused_creation());
        require(get_streams().size()==1);
        std::cout << "PASS: forced epoch exhaustion retains the exact creation hold.\n";
    } else if (mode == "--raw") {
        const auto direct = new_stream(Device::cpu);
        const auto ordinary = default_stream(Device::cpu);
        const auto local = stream_from_thread_local_stream(new_thread_local_stream(Device::cpu));
        const auto owner = fios_current_stream_owner();
        require(owner != 0 && direct != ordinary && ordinary != local);
        const auto owned = fios_owned_streams();
        require(owned.size() == 3 && get_streams().size() == 3);
        auto state = fios_stream_custody_state();
        require(state.registered == 3 && state.pending == 0 && !state.uncertain);
        const auto ticket = fios_hold_stream_creation(state.epoch);
        require(ticket != 0 && fios_hold_stream_creation(state.epoch) == 0);
        require(refused_creation() && get_streams().size() == 3);
        std::thread foreign([&] {
            require(!fios_release_stream_creation(ticket));
            require(refused_creation());
        });
        foreign.join();
        for (const auto stream : owned) synchronize(stream);
        require(!fios_release_stream_creation(ticket + 1));
        require(refused_creation());
        require(fios_release_stream_creation(ticket));
        require(!fios_release_stream_creation(ticket));
        (void)new_stream(Device::cpu);
        state = fios_stream_custody_state();
        const auto next = fios_hold_stream_creation(state.epoch);
        require(next != 0 && next != ticket);
        require(!fios_release_stream_creation(ticket));
        require(refused_creation());
        require(fios_release_stream_creation(next));
        std::cout << "PASS: actual raw/default/thread-local creations have custody; exact creator one-use hold gates raw creation without holding metadata mutex across sync.\n";
    } else if (mode == "--owners") {
        (void)new_stream(Device::cpu);
        const auto first = fios_current_stream_owner();
        uint64_t second = 0, third = 0;
        std::thread other([&] {(void)new_stream(Device::cpu); second=fios_current_stream_owner();require(fios_owned_streams().size()==1);});
        other.join();
        std::thread replacement([&] {(void)new_stream(Device::cpu); third=fios_current_stream_owner();require(fios_owned_streams().size()==1);});
        replacement.join();
        require(first && second && third && first!=second && second!=third && first!=third);
        require(fios_owned_streams().size()==1 && fios_stream_custody_state().registered==3);
        std::cout << "PASS: creation-local tags are non-reusable and thread exit does not erase other owners.\n";
    } else if (mode == "--owner-exit") {
        uint64_t ticket=0;
        std::thread creator([&] {
            (void)new_stream(Device::cpu);
            ticket=fios_hold_stream_creation(fios_stream_custody_state().epoch);
            require(ticket!=0);
        });
        creator.join();
        require(fios_stream_custody_state().held);
        require(!fios_release_stream_creation(ticket) && refused_creation());
        std::cout << "PASS: creator thread exit never refunds a creation hold.\n";
    } else if (mode == "--shared") {
        (void)new_thread_unsafe_stream(Device::cpu);
        require(fios_stream_custody_state().shared);
        bool denied=false;
        try {(void)fios_owned_streams();} catch (const std::runtime_error&) {denied=true;}
        require(denied);
        std::cout << "PASS: shared/thread-unsafe stream never becomes an owner-only synchronization receipt.\n";
    } else if (mode == "--backend-failure") {
        // Genuine upstream CPU-only configuration has no GPU backend.
        bool failed=false;
        try {(void)new_stream(Device::gpu);} catch (const std::invalid_argument&) {failed=true;}
        const auto state=fios_stream_custody_state();
        require(failed && state.uncertain && state.pending==0);
        require(fios_hold_stream_creation(state.epoch)==0);
        std::cout << "PASS: real unavailable-backend failure leaves sticky creation uncertainty, no leaked pending ticket.\n";
    } else { return 77; }
    return 0;
}
