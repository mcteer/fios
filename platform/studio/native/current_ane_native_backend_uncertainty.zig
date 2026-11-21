//! Fixed negative-only raw ANE custody plus previous reported-run/SDK probes.
//! A zero bitmask is no device-terminal, all-client or admission authority.
const base = @import("current_ane_backend_uncertainty.zig");
pub fn known(comptime sdk_enabled: bool, comptime llama_enabled: bool) bool {
    const options = @import("build_options");
    const Source = struct { extern "c" fn msv_ane_source_uncertainty() u32; };
    const raw = if (@hasDecl(options, "fios_source_ane") and options.fios_source_ane)
        Source.msv_ane_source_uncertainty() != 0 else false;
    return raw or base.known(sdk_enabled, llama_enabled);
}
