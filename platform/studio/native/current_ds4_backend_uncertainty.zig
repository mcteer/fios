//! Fixed negative-only composition. Zero never proves native completion,
//! resource idle, all-client coverage or admission. No dynamic callback.
const base = @import("current_backend_uncertainty.zig");
pub fn known(comptime sdk_enabled: bool, comptime llama_enabled: bool) bool {
    const options = @import("build_options");
    const Source = struct {
        extern "c" fn ds4_host_source_uncertainty() u32;
        extern "c" fn ds4_gpu_source_uncertainty() u32;
    };
    const ds4 = if (@hasDecl(options, "fios_source_ds4") and options.fios_source_ds4)
        Source.ds4_host_source_uncertainty() != 0 or Source.ds4_gpu_source_uncertainty() != 0
    else false;
    return ds4 or base.known(sdk_enabled, llama_enabled);
}
