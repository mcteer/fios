// CPU by default; explicit source-only --gpu-empty creates/syncs an empty GPU
// stream. No model, array, inference or GPU kernel in either mode.
#include "device_owner_barrier.h"
#include "mlx/stream.h"
#include "mlx/c/stream.h"
#include <cstdlib>
#include <thread>
#include <iostream>
#include <string_view>
#include <condition_variable>
#include <mutex>
#include <chrono>
#ifdef NDEBUG
#error "Native fixture checks require -UNDEBUG; never accept inert assertions"
#endif
static void require(bool condition) {
    if (!condition) { std::cerr << "FAIL: genuine MLX owner-stream fixture check\n"; std::exit(77); }
}
int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "--prove-failure") require(false);
    const auto owner = fios_mlx_current_thread();
    require(owner != 0);
    fios_mlx_barrier_result result{};
    if (argc == 2 && std::string_view(argv[1]) == "--registry-hold") {
        require(fios_mlx_create_owned_cpu_stream(owner) == 0);
        uint64_t ticket = 0, duplicate = 99;
        require(fios_mlx_hold_owned_registry(owner, nullptr) == FIOS_MLX_INVALID);
        require(fios_mlx_hold_owned_registry(owner, &ticket) == 0 && ticket != 0);
        require(fios_mlx_hold_owned_registry(owner, &duplicate) != 0 && duplicate == 0);
        require(fios_mlx_owner_barrier(owner, &result) == 0 && result.streams_synchronized == 1);
        require(fios_mlx_create_owned_cpu_stream(owner) == FIOS_MLX_UNSUPPORTED_OR_FAILED);
        require(mlx::core::get_streams().size() == 1);
        std::thread foreign([&] {require(fios_mlx_release_owned_registry(owner, ticket) == FIOS_MLX_WRONG_OWNER);});
        foreign.join();
        require(fios_mlx_release_owned_registry(owner, ticket + 1) != 0);
        require(fios_mlx_create_owned_cpu_stream(owner) == FIOS_MLX_UNSUPPORTED_OR_FAILED);
        require(fios_mlx_release_owned_registry(owner, ticket) == 0);
        require(fios_mlx_release_owned_registry(owner, ticket) != 0);
        require(fios_mlx_create_owned_cpu_stream(owner) == 0);
        uint64_t next = 0;
        require(fios_mlx_hold_owned_registry(owner, &next) == 0 && next != ticket);
        require(fios_mlx_release_owned_registry(owner, ticket) != 0);
        require(fios_mlx_create_owned_cpu_stream(owner) == FIOS_MLX_UNSUPPORTED_OR_FAILED);
        require(fios_mlx_release_owned_registry(owner, next) == 0);
        std::cout << "PASS: owned-wrapper registry hold blocks creation until exact one-use creator release; NOT raw MLX/backend/global transition authority.\n";
        return 0;
    }
    if (argc == 2 && std::string_view(argv[1]) == "--gpu-empty") {
        const auto* opt = std::getenv("FIOS_NATIVE_EMPTY_GPU_FIXTURE");
        require(opt && std::string_view(opt) == "isolated-source-fixture");
        void* context = nullptr;
        require(mlx::core::get_streams().empty());
        std::thread foreign([&] {
            void* denied = reinterpret_cast<void*>(1);
            require(fios_mlx_create_owned_c_stream(owner, 1, 0, &denied) == FIOS_MLX_WRONG_OWNER && denied == nullptr);
        });
        foreign.join();
        require(mlx::core::get_streams().empty());
        require(fios_mlx_create_owned_c_stream(owner, 1, 0, &context) == 0 && context != nullptr);
        const mlx_stream handle{context};
        const auto streams = mlx::core::get_streams();
        require(streams.size() == 1 && streams[0].device.type == mlx::core::Device::gpu);
        int index = -1;
        require(mlx_stream_get_index(&index, handle) == 0 && index == streams[0].index);
        require(mlx_synchronize(handle) == 0);
        require(fios_mlx_owner_barrier(owner, &result) == 0);
        require(result.streams_seen == 1 && result.streams_synchronized == 1);
        require(mlx_stream_free(handle) == 0);
        std::cout << "PASS: genuine empty GPU stream creation/index/sync/free and foreign-thread refusal; NO arrays/kernels/models/global terminal authority.\n";
        return 0;
    }
    if (argc == 2 && std::string_view(argv[1]) == "--c-api-defaults") {
        void* first = nullptr; void* second = nullptr;
        require(fios_mlx_owned_default_c_stream(owner, 0, 0, &first) == 0 && first != nullptr);
        require(fios_mlx_owned_default_c_stream(owner, 0, 0, &second) == 0 && second != nullptr && second != first);
        const mlx_stream a{first}, b{second};
        const auto public_default = mlx_default_cpu_stream_new();
        int i = -1, j = -1, k = -1;
        require(mlx_stream_get_index(&i, a) == 0 && mlx_stream_get_index(&j, b) == 0 && mlx_stream_get_index(&k, public_default) == 0);
        require(i == j && j == k && mlx::core::get_streams().size() == 1);
        require(mlx_synchronize(a) == 0 && fios_mlx_owner_barrier(owner, &result) == 0);
        require(result.streams_seen == 1 && result.streams_synchronized == 1);
        require(mlx_stream_free(a) == 0 && mlx_stream_free(b) == 0 && mlx_stream_free(public_default) == 0);
        std::cout << "PASS: genuine owned CPU default retains identity across real mlx-c handles; no extra stream, adoption or model authority.\n";
        return 0;
    }
    if (argc == 2 && std::string_view(argv[1]) == "--c-api-handle") {
        void* context = nullptr;
        require(fios_mlx_create_owned_c_stream(owner, 0, 0, nullptr) == FIOS_MLX_INVALID);
        require(fios_mlx_create_owned_c_stream(0, 0, 0, &context) == FIOS_MLX_WRONG_OWNER && context == nullptr);
        require(fios_mlx_create_owned_c_stream(owner, 2, 0, &context) == FIOS_MLX_INVALID && context == nullptr);
        require(fios_mlx_create_owned_c_stream(owner, 0, 1, &context) == FIOS_MLX_INVALID && context == nullptr);
        std::thread peer([&] {
            void* rejected = reinterpret_cast<void*>(1);
            require(fios_mlx_create_owned_c_stream(owner, 0, 0, &rejected) == FIOS_MLX_WRONG_OWNER && rejected == nullptr);
        });
        peer.join();
        require(mlx::core::get_streams().empty());
        require(fios_mlx_create_owned_c_stream(owner, 0, 0, &context) == 0 && context != nullptr);
        const mlx_stream handle{context};
        int index = -1;
        require(mlx_stream_get_index(&index, handle) == 0);
        require(mlx::core::get_streams().size() == 1 && mlx::core::get_streams()[0].index == index);
        require(mlx_synchronize(handle) == 0);
        require(fios_mlx_owner_barrier(owner, &result) == 0);
        require(result.streams_seen == 1 && result.streams_synchronized == 1);
        require(mlx_stream_free(handle) == 0);
        std::cout << "PASS: genuine owned CPU creation returns a real mlx-c handle; index/sync/free ABI, invalid/foreign rejection; no model/terminal authority.\n";
        return 0;
    }
    if (argc == 2 && std::string_view(argv[1]) == "--two-owners") {
        require(fios_mlx_create_owned_cpu_stream(owner) == 0);
        std::mutex mutex; std::condition_variable wake;
        bool created = false, release = false;
        std::thread peer([&] {
            const auto peer_owner = fios_mlx_current_thread();
            require(peer_owner != owner);
            require(fios_mlx_create_owned_cpu_stream(peer_owner) == 0);
            fios_mlx_barrier_result peer_result{};
            require(fios_mlx_owner_barrier(peer_owner, &peer_result) == 0);
            require(peer_result.streams_seen == 1 && peer_result.streams_synchronized == 1);
            std::unique_lock lock(mutex); created = true; wake.notify_all();
            require(wake.wait_for(lock, std::chrono::seconds(2), [&] { return release; }));
        });
        {
            std::unique_lock lock(mutex);
            require(wake.wait_for(lock, std::chrono::seconds(2), [&] { return created; }));
            require(mlx::core::get_streams().size() == 2);
            require(fios_mlx_owner_barrier(owner, &result) == 0);
            require(result.streams_seen == 1 && result.streams_synchronized == 1);
            release = true; wake.notify_all();
        }
        peer.join();
        std::cout << "PASS: two genuine CPU owners synchronize only their own stream; no cross-thread/global terminal claim.\n";
        return 0;
    }
    if (argc == 2 && std::string_view(argv[1]) == "--assigned-global-default") {
        const auto shared = mlx::core::new_thread_unsafe_stream(mlx::core::Device::cpu);
        mlx::core::set_default_stream(shared);
        void* rejected = reinterpret_cast<void*>(1);
        require(fios_mlx_owned_default_c_stream(owner, 0, 0, &rejected) == FIOS_MLX_UNSUPPORTED_OR_FAILED && rejected == nullptr);
        require(fios_mlx_initialize_owner_defaults(owner) == FIOS_MLX_UNSUPPORTED_OR_FAILED);
        require(fios_mlx_owner_barrier(owner, &result) == FIOS_MLX_UNSUPPORTED_OR_FAILED);
        require(result.streams_synchronized == 0);
        std::cout << "PASS: preexisting assigned global default is not adopted or synchronized.\n";
        return 0;
    }
    require(fios_mlx_owner_barrier(owner, nullptr) == FIOS_MLX_INVALID);
    require(fios_mlx_owner_barrier(0, &result) == FIOS_MLX_WRONG_OWNER);
    require(mlx::core::get_streams().empty());
    require(fios_mlx_owner_barrier(owner, &result) == FIOS_MLX_OWNER_STREAMS_SYNCHRONIZED);
    require(result.streams_seen == 0 && result.streams_synchronized == 0);
    std::thread foreign([&] {
        require(fios_mlx_current_thread() != owner);
        require(fios_mlx_owner_barrier(owner, &result) == FIOS_MLX_WRONG_OWNER);
        require(result.streams_seen == 0 && result.streams_synchronized == 0);
    });
    foreign.join();
    require(fios_mlx_create_owned_cpu_stream(owner) == FIOS_MLX_OWNER_STREAMS_SYNCHRONIZED);
    require(fios_mlx_owner_barrier(owner, &result) == FIOS_MLX_OWNER_STREAMS_SYNCHRONIZED);
    require(result.streams_seen == 1 && result.streams_synchronized == 1);
    require(fios_mlx_initialize_owner_defaults(owner) == FIOS_MLX_UNSUPPORTED_OR_FAILED);
    (void)mlx::core::new_stream(mlx::core::Device::cpu);
    require(fios_mlx_owner_barrier(owner, &result) == FIOS_MLX_UNSUPPORTED_OR_FAILED);
    require(mlx::core::get_streams().size() == 2 && result.streams_synchronized == 0);
    (void)mlx::core::new_thread_unsafe_stream(mlx::core::Device::cpu);
    require(fios_mlx_owner_barrier(owner, &result) == FIOS_MLX_UNSUPPORTED_OR_FAILED);
    require(mlx::core::get_streams().size() == 3 && result.streams_synchronized == 0);
    std::cout << "PASS: genuine MLX owned CPU/empty streams, wrong-thread and unowned/global-stream refusal; always-enabled checks. NOT GPU/model/terminal acceptance.\n";
}
