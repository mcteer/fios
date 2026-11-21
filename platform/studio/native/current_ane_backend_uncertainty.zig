//! Fixed negative-only ANE/DS4/SDK/llama composition. Zero is no proof.
const base = @import("current_ds4_backend_uncertainty.zig");
const ane = @import("current_ane_run_uncertainty.zig");
pub fn known(comptime sdk_enabled: bool, comptime llama_enabled: bool) bool {
    return ane.known() or base.known(sdk_enabled, llama_enabled);
}
