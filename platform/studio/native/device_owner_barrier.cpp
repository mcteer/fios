// Genuine pinned MLX API. Partial owner-stream primitive only, never global
// device idle, model completion or all-backend/quiescence authority.
#include "device_owner_barrier.h"
#include <pthread.h>
#include <array>
#include <limits>
#include <mutex>
#include "mlx/stream.h"
#include "mlx/c/private/stream.h"

namespace {
constexpr size_t limit = 256;
struct Entry { int index = 0; int type = 0; int device = 0; uint64_t owner = 0; };
struct Registry {
    std::mutex mutex;
    std::array<Entry, limit> streams{};
    size_t count = 0;
    size_t pending = 0;
    uint64_t next_owner = 0;
    uint64_t epoch = 1;
    uint64_t next_hold = 0;
    uint64_t hold = 0;
    uint64_t hold_owner = 0;
    bool uncertain = false;
} registry;
struct Local {
    uint64_t owner = 0;
    std::vector<mlx::core::Stream> streams;
};
thread_local Local local;
bool bump() { // Registry mutex held. Overflow never resets/adopts an epoch.
    if (registry.epoch == std::numeric_limits<uint64_t>::max()) { registry.uncertain = true; return false; }
    ++registry.epoch; return true;
}
bool matches(const Entry& entry, mlx::core::Stream stream) {
    return entry.index == stream.index && entry.type == static_cast<int>(stream.device.type) && entry.device == stream.device.index;
}
bool begin_creation() {
    // Reserve local storage before backend calls; no allocation under mutex.
    local.streams.reserve(limit);
    std::lock_guard guard(registry.mutex);
    if (registry.uncertain || registry.hold || registry.count + registry.pending >= limit || local.streams.size() >= limit) return false;
    if (!local.owner) {
        if (registry.next_owner == std::numeric_limits<uint64_t>::max()) { registry.uncertain = true; return false; }
        local.owner = ++registry.next_owner; // Distinct even if kernel TIDs recycle.
    }
    if (!bump()) return false;
    ++registry.pending;
    return true;
}
void fail_creation() {
    std::lock_guard guard(registry.mutex);
    if (registry.pending) --registry.pending;
    registry.uncertain = true; // A possibly-created unregistered stream stays unknown.
    (void)bump();
}
bool finish_creation(mlx::core::Stream stream) {
    std::lock_guard guard(registry.mutex);
    if (!registry.pending || registry.count >= limit) { registry.uncertain = true; return false; }
    --registry.pending;
    for (size_t i = 0; i < registry.count; ++i) if (matches(registry.streams[i], stream)) { registry.uncertain = true; return false; }
    registry.streams[registry.count++] = {stream.index, static_cast<int>(stream.device.type), stream.device.index, local.owner};
    local.streams.push_back(stream); // Capacity reserved before creation.
    return bump() && !registry.uncertain;
}
// Register only actual creation on THIS thread, never caller-supplied IDs.
int create(bool default_stream, mlx::core::Device device) {
    bool reserved = false;
    try {
        if (!begin_creation()) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
        reserved = true;
        auto stream = default_stream ? mlx::core::default_stream(device) : mlx::core::new_stream(device);
        return finish_creation(stream) ? FIOS_MLX_OWNER_STREAMS_SYNCHRONIZED : FIOS_MLX_UNSUPPORTED_OR_FAILED;
    } catch (...) {
        if (reserved) fail_creation();
        return FIOS_MLX_UNSUPPORTED_OR_FAILED;
    }
}
}
extern "C" uint64_t fios_mlx_current_thread(void) {
    uint64_t value = 0;
    return pthread_threadid_np(nullptr, &value) == 0 ? value : 0;
}
extern "C" int fios_mlx_create_owned_cpu_stream(uint64_t owner) {
    if (!owner || fios_mlx_current_thread() != owner) return FIOS_MLX_WRONG_OWNER;
    return create(false, mlx::core::Device::cpu);
}
extern "C" int fios_mlx_create_owned_c_stream(uint64_t owner, uint32_t type, int32_t device, void** out_context) {
    if (!out_context) return FIOS_MLX_INVALID;
    *out_context = nullptr;
    if (!owner || fios_mlx_current_thread() != owner) return FIOS_MLX_WRONG_OWNER;
    if (type > 1 || device != 0) return FIOS_MLX_INVALID;
    bool reserved = false;
    mlx_stream handle{nullptr};
    try {
        if (!begin_creation()) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
        reserved = true;
        // Actual creation and the genuine pinned mlx-c factory stay together;
        // no existing index, opaque pointer or caller ownership is adopted.
        auto stream = mlx::core::new_stream(mlx::core::Device(
            type == 0 ? mlx::core::Device::cpu : mlx::core::Device::gpu, device));
        handle = mlx_stream_new_(stream);
        const bool registered = finish_creation(stream);
        reserved = false;
        if (!registered) { mlx_stream_free_(handle); return FIOS_MLX_UNSUPPORTED_OR_FAILED; }
        *out_context = handle.ctx;
        return 0; // Creation only, NOT a synchronized/terminal receipt.
    } catch (...) {
        mlx_stream_free_(handle);
        if (reserved) fail_creation();
        return FIOS_MLX_UNSUPPORTED_OR_FAILED;
    }
}
extern "C" int fios_mlx_owned_default_c_stream(uint64_t owner, uint32_t type, int32_t device, void** out_context) {
    if (!out_context) return FIOS_MLX_INVALID;
    *out_context = nullptr;
    if (!owner || fios_mlx_current_thread() != owner) return FIOS_MLX_WRONG_OWNER;
    if (type > 1 || device != 0) return FIOS_MLX_INVALID;
    try {
        const mlx::core::Device target(type == 0 ? mlx::core::Device::cpu : mlx::core::Device::gpu, device);
        auto current = mlx::core::peek_default_stream(target);
        if (!current) {
            if (create(true, target) != 0) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
            current = mlx::core::peek_default_stream(target);
        }
        if (!current) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
        {
            std::lock_guard guard(registry.mutex);
            if (registry.uncertain || registry.pending || !local.owner) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
            bool recorded = false, retained = false;
            for (size_t i = 0; i < registry.count; ++i)
                if (matches(registry.streams[i], *current) && registry.streams[i].owner == local.owner) recorded = true;
            for (const auto& stream : local.streams) if (stream == *current) retained = true;
            if (!recorded || !retained) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
        }
        // Clone only a genuinely created/recorded owner default. Handle copies
        // preserve the actual default identity; do not create extra streams.
        *out_context = mlx_stream_new_(*current).ctx;
        return 0;
    } catch (...) { return FIOS_MLX_UNSUPPORTED_OR_FAILED; }
}
extern "C" int fios_mlx_initialize_owner_defaults(uint64_t owner) {
    if (!owner || fios_mlx_current_thread() != owner) return FIOS_MLX_WRONG_OWNER;
    try {
        // A preexisting default could be an assigned foreign/global stream.
        if (!local.streams.empty() || mlx::core::peek_default_stream(mlx::core::Device::cpu) ||
            mlx::core::peek_default_stream(mlx::core::Device::gpu)) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
        if (create(true, mlx::core::Device::cpu) != 0) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
        return create(true, mlx::core::Device::gpu);
    } catch (...) { return FIOS_MLX_UNSUPPORTED_OR_FAILED; }
}
extern "C" int fios_mlx_hold_owned_registry(uint64_t owner, uint64_t* out_ticket) {
    if (!out_ticket) return FIOS_MLX_INVALID;
    *out_ticket = 0;
    if (!owner || fios_mlx_current_thread() != owner) return FIOS_MLX_WRONG_OWNER;
    std::lock_guard guard(registry.mutex);
    if (registry.uncertain || registry.pending || registry.hold || !local.owner) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
    if (registry.next_hold == std::numeric_limits<uint64_t>::max()) {
        registry.uncertain = true;
        return FIOS_MLX_UNSUPPORTED_OR_FAILED;
    }
    if (!bump()) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
    registry.hold = ++registry.next_hold;
    registry.hold_owner = local.owner; // Never authorize by reusable kernel TID alone.
    *out_ticket = registry.hold;
    return 0;
}
extern "C" int fios_mlx_release_owned_registry(uint64_t owner, uint64_t ticket) {
    if (!owner || fios_mlx_current_thread() != owner) return FIOS_MLX_WRONG_OWNER;
    std::lock_guard guard(registry.mutex);
    if (!ticket || registry.hold != ticket || !local.owner || registry.hold_owner != local.owner) return FIOS_MLX_INVALID;
    if (!bump()) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
    registry.hold = 0;
    registry.hold_owner = 0;
    return 0;
}
extern "C" int fios_mlx_owner_barrier(uint64_t owner, fios_mlx_barrier_result* result) {
    if (!result) return FIOS_MLX_INVALID;
    *result = {};
    if (!owner || fios_mlx_current_thread() != owner) return FIOS_MLX_WRONG_OWNER;
    try {
        const auto before = mlx::core::get_streams();
        if (before.size() > limit) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
        uint64_t epoch = 0;
        {
            std::lock_guard guard(registry.mutex);
            if (registry.uncertain || registry.pending || before.size() != registry.count) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
            // Every global stream must have a recorded creation owner, but
            // other owners are NOT synchronized from this thread.
            for (const auto& stream : before) {
                bool found = false;
                for (size_t i = 0; i < registry.count; ++i) if (matches(registry.streams[i], stream)) { found = true; break; }
                if (!found) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
            }
            for (const auto& stream : local.streams) {
                bool found = false;
                for (size_t i = 0; i < registry.count; ++i) if (matches(registry.streams[i], stream) && registry.streams[i].owner == local.owner) { found = true; break; }
                if (!found) return FIOS_MLX_UNSUPPORTED_OR_FAILED;
            }
            epoch = registry.epoch;
        }
        result->streams_seen = static_cast<uint32_t>(local.streams.size());
        // No metadata/queue/registry/tracker mutex across backend calls.
        for (const auto& stream : local.streams) {
            mlx::core::synchronize(stream);
            ++result->streams_synchronized;
        }
        if (mlx::core::get_streams() != before) return FIOS_MLX_STREAMS_CHANGED;
        {
            std::lock_guard guard(registry.mutex);
            if (registry.uncertain || registry.pending || registry.epoch != epoch) return FIOS_MLX_STREAMS_CHANGED;
        }
        // ONLY this owner's streams at this point. Other owners may still be
        // live/retired/unresolved; no aggregate terminal receipt is produced.
        return FIOS_MLX_OWNER_STREAMS_SYNCHRONIZED;
    } catch (...) { return FIOS_MLX_UNSUPPORTED_OR_FAILED; }
}

// Optional project renderer, not a declaration/substitution of an SDK API.
// Constant initialization is independent of C++ constructor order.
#include <atomic>
namespace { std::atomic<fios_mlx_source_renderer> source_renderer{nullptr}; }
extern "C" int fios_mlx_register_source_renderer(fios_mlx_source_renderer renderer) {
    if (!renderer) return 1;
    fios_mlx_source_renderer expected=nullptr;
    return source_renderer.compare_exchange_strong(expected,renderer,std::memory_order_release,std::memory_order_relaxed)?0:1;
}
extern "C" int fios_mlx_source_components_json(char* output,size_t capacity) {
    const auto renderer=source_renderer.load(std::memory_order_acquire);
    if (!output || capacity < 512 || capacity > 4096 || !renderer) return 0;
    return renderer(output,capacity);
}
