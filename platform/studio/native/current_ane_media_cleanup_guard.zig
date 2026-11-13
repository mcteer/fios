//! Fixed negative-only host callbacks. No host imports or native authority.
const std = @import("std");
const options = @import("build_options");
const shared = @import("../util/shared.zig");
pub const enabled = @hasDecl(options, "fios_source_ane") and options.fios_source_ane;
pub const Hooks = extern struct {
    known: *const fn () callconv(.c) bool,
    retain: *const fn () callconv(.c) void,
};
const State = struct {
    hooks: std.atomic.Value(?*const Hooks) = .init(null),
    retained: std.atomic.Value(bool) = .init(false),
};
const storage = shared.Shared(State, "fios_media_cleanup_hooks", .{});
// Trusted host startup only. A unit cannot replace the immutable callback pair.
pub fn install(hooks: *const Hooks) bool {
    const state = storage.get();
    if (comptime shared.in_unit) {
        state.retained.store(true, .release);
        return false;
    }
    if (state.hooks.cmpxchgStrong(null, hooks, .acq_rel, .acquire)) |old| {
        if (old != hooks) {
            state.retained.store(true, .release);
            return false;
        }
    }
    return true;
}
pub fn latched() bool {
    return storage.get().retained.load(.acquire);
}
pub fn hostKnown() bool {
    const state = storage.get();
    if (state.retained.load(.acquire)) return true;
    const hooks = state.hooks.load(.acquire) orelse return true;
    return hooks.known();
}
pub fn known() bool {
    return knownWith(enabled, hostKnown);
}
pub fn knownWith(comptime active: bool, comptime read: anytype) bool {
    if (!active) return false;
    return read();
}
pub fn retainUncertain() void {
    retainUncertainWith(enabled);
}
pub fn retainUncertainWith(comptime active: bool) void {
    if (!active) return;
    const state = storage.get();
    state.retained.store(true, .release);
    if (state.hooks.load(.acquire)) |hooks| hooks.retain();
}
pub fn retainIfKnown() bool {
    if (!known()) return false;
    retainUncertain();
    return true;
}
pub fn requireCertain() error{NativeCleanupUncertain}!void {
    return requireCertainWith(enabled, hostKnown);
}
pub fn requireCertainWith(comptime active: bool, comptime read: anytype) error{NativeCleanupUncertain}!void {
    if (knownWith(active, read)) return error.NativeCleanupUncertain;
}
