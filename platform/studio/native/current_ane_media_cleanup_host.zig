//! Host-only negative composition for the portable media SDK callback surface.
const std = @import("std");
const options = @import("build_options");
const owners = @import("request_ownership.zig");
const cleanup = @import("current_ane_native_cleanup_uncertainty.zig");
const guard = @import("../sdk/ane/cleanup_guard.zig");
const sdk = @hasDecl(options, "fios_source_sdk") and options.fios_source_sdk;
const llama = @hasDecl(options, "llama_engine") and options.llama_engine;
fn known() callconv(.c) bool {
    const io = std.Io.Threaded.global_single_threaded.io();
    return cleanup.known(io, sdk, llama) or owners.shared().knownUncertain(io);
}
fn retain() callconv(.c) void {
    owners.shared().fence(std.Io.Threaded.global_single_threaded.io());
}
const hooks: guard.Hooks = .{ .known = known, .retain = retain };
pub fn install() bool {
    return guard.install(&hooks);
}
pub fn latched() bool {
    return guard.latched();
}

// Root metadata only; no model, GPU or ANE operation.
test "fios current media cleanup guard retains independent source uncertainty" {
    const io = std.testing.io;
    owners.shared().primary_guard = false;
    try owners.shared().initialize(io, @splat(231));
    try std.testing.expect(install());
    const root = try owners.shared().enter(io);
    try owners.shared().bind(io, root, "fixture/media-cleanup-source");
    owners.current().* = root;
    const held = (try owners.retainCurrent(io)).?;
    owners.shared().fence(io);
    if (!guard.knownWith(true, guard.hostKnown)) {
        std.debug.print("FIO_MEDIA_CLEANUP_ERASED_SOURCE_UNCERTAINTY\n", .{});
        try std.testing.expect(false);
    }
    try std.testing.expectError(error.NativeCleanupUncertain, guard.requireCertainWith(true, guard.hostKnown));
    owners.current().* = null;
    try owners.shared().leave(io, root);
    try std.testing.expect(!held.releaseIfCertain(io));
    try std.testing.expect(owners.shared().snapshot(io).uncertain);
}
test "fios current media cleanup guard preserves healthy and disabled metadata behavior" {
    const io = std.testing.io;
    owners.shared().primary_guard = false;
    try std.testing.expect(guard.knownWith(true, guard.hostKnown));
    try owners.shared().initialize(io, @splat(232));
    try std.testing.expect(install());
    try std.testing.expect(!guard.knownWith(true, guard.hostKnown));
    try guard.requireCertainWith(true, guard.hostKnown);
    guard.retainUncertainWith(true);
    try std.testing.expect(!guard.knownWith(false, guard.hostKnown));
    try std.testing.expect(owners.shared().snapshot(io).uncertain);
}
