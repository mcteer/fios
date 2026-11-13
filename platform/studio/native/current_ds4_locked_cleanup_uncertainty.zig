//! Negative cleanup evidence under an existing engine/book mutex. The fixed
//! backend getters and cached source state invoke no dynamic source callback.
//! This supplies neither native completion nor admission authority.
const std = @import("std");
const owners = @import("request_ownership.zig");
const backend = @import("current_ds4_backend_uncertainty.zig");

pub fn known(io: std.Io, comptime sdk_enabled: bool, comptime llama_enabled: bool) bool {
    const native_unknown = backend.known(sdk_enabled, llama_enabled);
    const source = owners.shared();
    source.mutex.lockUncancelable(io);
    const started = source.initialized;
    source.mutex.unlock(io);
    if (native_unknown) {
        if (started) source.fence(io);
        return true;
    }
    // Legacy metadata-only callers may precede startup; absence is never
    // positive authority and cannot hide the independent native flags.
    return started and source.knownUncertain(io);
}
