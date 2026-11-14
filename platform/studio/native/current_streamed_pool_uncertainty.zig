//! Fixed negative-only local streamed read-pool refusal. Never native terminality.
const options = @import("build_options");
pub fn known() bool {
    const Native = struct { extern "c" fn fios_q3ld_cleanup_uncertain() c_int; };
    return if (@hasDecl(options, "mlx_stream") and options.mlx_stream)
        Native.fios_q3ld_cleanup_uncertain() != 0 else false;
}
