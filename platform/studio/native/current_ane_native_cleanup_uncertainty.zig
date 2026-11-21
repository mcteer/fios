//! Negative cleanup evidence only; no native completion or admission authority.
const std = @import("std");
const owners = @import("request_ownership.zig");
const backend = @import("current_ane_native_backend_uncertainty.zig");

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
    // Legacy metadata-only callers can precede source startup. Missing startup
    // is never positive native authority, and cannot hide an actual fence.
    return started and source.backendKnownUncertain(io);
}
