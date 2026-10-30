// Only added to an explicitly composed private source experiment. The caller
// prepends the verified genuine patched mlx/stream.h, never an SDK substitute.
#include <cstdlib>
namespace {
__attribute__((constructor)) void enable_private_mlx_source_participants() {
    // Pure metadata enablement before main/MLX initialization. Late adoption
    // refuses the experiment; no library/default/installed fallback is allowed.
    if (!mlx::core::fios_enable_stream_custody_fixture()) std::_Exit(78);
}
}
