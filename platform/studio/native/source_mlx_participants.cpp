// Only added to an explicitly composed private source experiment. The caller
// prepends the verified genuine patched mlx/stream.h, never an SDK substitute.
#include <cstdlib>
extern "C" int fios_private_mlx_source_components_json(char*,size_t);
#if defined(MLX_FIOS_REQUEST_HOST_OWNERS) && defined(FIOS_NATIVE_REQUEST_OWNERS)
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
#ifdef MLX_FIOS_REQUEST_OWNER_GROUPS
extern "C" void* fios_native_request_owners_merge(void*,void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
#endif
#endif
namespace {
#ifdef MLX_FIOS_KNOWN_UNCERTAINTY
int known_source_uncertainty() {
    return mlx::core::fios_known_source_uncertain() ? 1 : 0;
}
#endif
#ifdef FIOS_SOURCE_COMPONENT_HOLD
uint64_t acquire_source_components() {
    return mlx::core::fios_hold_source_components(mlx::core::fios_host_queue_state().epoch);
}
int release_source_components(uint64_t ticket) {
    return mlx::core::fios_release_metal_buffers(ticket)?0:1;
}
const fios_mlx_source_hold_hooks source_hold_hooks{acquire_source_components,release_source_components};
#endif
__attribute__((constructor)) void enable_private_mlx_source_participants() {
#if defined(MLX_FIOS_REQUEST_HOST_OWNERS) && defined(FIOS_NATIVE_REQUEST_OWNERS)
    static const mlx::core::FiosRequestOwnerHooks hooks{
        fios_native_request_owners_capture,fios_native_request_owners_enter,
        fios_native_request_owners_leave,fios_native_request_owners_release
#ifdef MLX_FIOS_REQUEST_OWNER_GROUPS
        ,fios_native_request_owners_merge,fios_native_request_owners_covers_current,
        fios_native_request_owners_uncertain
#endif
    };
    if (!mlx::core::fios_register_request_owner_hooks(&hooks)) std::_Exit(78);
#endif
    // Pure metadata enablement before main/MLX initialization. Late adoption
    // refuses the experiment; no library/default/installed fallback is allowed.
    if (!mlx::core::fios_enable_stream_custody_fixture() || fios_mlx_register_source_renderer(fios_private_mlx_source_components_json)!=0) std::_Exit(78);
#ifdef MLX_FIOS_KNOWN_UNCERTAINTY
    if (fios_mlx_register_source_uncertainty(known_source_uncertainty)!=0) std::_Exit(78);
#endif
#ifdef FIOS_SOURCE_COMPONENT_HOLD
    if (fios_mlx_register_source_hold(&source_hold_hooks)!=0) std::_Exit(78);
#endif
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
        const char* site="null";
#if defined(MLX_FIOS_UNCERTAINTY_DIAGNOSTICS)
        char site_buffer[16];
        std::snprintf(site_buffer,sizeof(site_buffer),"%u",mlx::core::fios_first_uncertainty_site());
        site=site_buffer;
#endif
        const int n=std::snprintf(output,capacity,
            "{\"schema_version\":2,\"scope\":\"partial_mlx_source_components\",\"coverage\":\"unknown\",\"authority\":false,\"available\":true,\"uncertainty_site\":%s,\"coherent\":%s,"
            "\"stream\":{\"epoch\":%llu,\"registered\":%u,\"pending\":%u,\"enabled\":%s,\"uncertain\":%s,\"held\":%s,\"shared\":%s},"
            "\"host\":{\"epoch\":%llu,\"pending\":%llu,\"active\":%llu,\"enabled\":%s,\"uncertain\":%s,\"held\":%s},"
            "\"metal\":{\"epoch\":%llu,\"pending\":%llu,\"captures\":%llu,\"enabled\":%s,\"uncertain\":%s,\"held\":%s}}",
            site,tf(coherent),(unsigned long long)stream.epoch,stream.registered,stream.pending,tf(stream.enabled),tf(stream.uncertain),tf(stream.held),tf(stream.shared),
            (unsigned long long)host.epoch,(unsigned long long)host.pending,(unsigned long long)host.active,tf(host.enabled),tf(host.uncertain),tf(host.held),
            (unsigned long long)metal.epoch,(unsigned long long)metal.pending,(unsigned long long)metal.captures,tf(metal.enabled),tf(metal.uncertain),tf(metal.held));
        return n>0 && static_cast<size_t>(n)<capacity?n:0;
    } catch (...) { return 0; }
}
