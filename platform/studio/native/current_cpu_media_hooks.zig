//! Opaque CPU-stage custody only. No host import, model policy or terminal proof.
const std = @import("std");
const shared = @import("../util/shared.zig");

pub const Payload = extern struct { bytes: [12 * 1024]u8 align(16) = undefined };
pub const Capture = enum { unavailable, retained, failed };
pub const Hooks = struct {
    capture: *const fn (*Payload) Capture,
    enter: *const fn (*Payload) bool,
    finish: *const fn (*Payload) void,
    abandon: *const fn (*Payload) void,
};
const Storage = shared.Shared(std.atomic.Value(?*const Hooks), "fios_cpu_media_hooks", .init(null));

// Trusted startup installs one immutable host implementation before workers.
pub fn install(hooks: *const Hooks) !void {
    if (Storage.get().cmpxchgStrong(null, hooks, .acq_rel, .acquire)) |previous| {
        if (previous != hooks) return error.CpuMediaHooksAlreadyInstalled;
    }
}
pub fn current() ?*const Hooks {
    return Storage.get().load(.acquire);
}
