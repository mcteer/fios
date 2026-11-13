//! Read-only independent negative fences. False is never terminal/admission proof.
pub fn known(comptime sdk_enabled: bool, comptime llama_enabled: bool) bool {
    const Source = struct {
        extern "c" fn fios_current_sdk_known_uncertain() c_int;
        extern "c" fn mlx_llama_source_uncertainty() c_int;
    };
    const sdk = if (sdk_enabled) Source.fios_current_sdk_known_uncertain() != 0 else false;
    const llama = if (llama_enabled) Source.mlx_llama_source_uncertainty() != 0 else false;
    return sdk or llama;
}
