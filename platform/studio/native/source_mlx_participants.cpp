// Only added to an explicitly composed private source experiment. The caller
// prepends the verified genuine patched mlx/stream.h, never an SDK substitute.
#include <cstdlib>
extern "C" int fios_private_mlx_source_components_json(char*,size_t);
namespace {
__attribute__((constructor)) void enable_private_mlx_source_participants() {
    // Pure metadata enablement before main/MLX initialization. Late adoption
    // refuses the experiment; no library/default/installed fallback is allowed.
    if (!mlx::core::fios_enable_stream_custody_fixture() || fios_mlx_register_source_renderer(fios_private_mlx_source_components_json)!=0) std::_Exit(78);
}
}

#include <cstdio>
#include <cstddef>
// The actual source SDK getters copy metadata only; no factories, device
// initialization, synchronization, holds or release API is called here.
extern "C" int fios_private_mlx_source_components_json(char* output,size_t capacity) {
    if (!output || capacity < 512 || capacity > 4096) return 0;
    try {
        const auto stream=mlx::core::fios_stream_custody_state();
        const auto host=mlx::core::fios_host_queue_state();
        const auto metal=mlx::core::fios_metal_buffer_state();
        const auto tf=[](bool value){return value?"true":"false";};
        const bool coherent=stream.epoch!=0 && stream.epoch==host.epoch && host.epoch==metal.epoch;
        const int n=std::snprintf(output,capacity,
            "{\"schema_version\":1,\"scope\":\"partial_mlx_source_components\",\"coverage\":\"unknown\",\"authority\":false,\"available\":true,\"coherent\":%s,"
            "\"stream\":{\"epoch\":%llu,\"registered\":%u,\"pending\":%u,\"enabled\":%s,\"uncertain\":%s,\"held\":%s,\"shared\":%s},"
            "\"host\":{\"epoch\":%llu,\"pending\":%llu,\"active\":%llu,\"enabled\":%s,\"uncertain\":%s,\"held\":%s},"
            "\"metal\":{\"epoch\":%llu,\"pending\":%llu,\"captures\":%llu,\"enabled\":%s,\"uncertain\":%s,\"held\":%s}}",
            tf(coherent),(unsigned long long)stream.epoch,stream.registered,stream.pending,tf(stream.enabled),tf(stream.uncertain),tf(stream.held),tf(stream.shared),
            (unsigned long long)host.epoch,(unsigned long long)host.pending,(unsigned long long)host.active,tf(host.enabled),tf(host.uncertain),tf(host.held),
            (unsigned long long)metal.epoch,(unsigned long long)metal.pending,(unsigned long long)metal.captures,tf(metal.enabled),tf(metal.uncertain),tf(metal.held));
        return n>0 && static_cast<size_t>(n)<capacity?n:0;
    } catch (...) { return 0; }
}
