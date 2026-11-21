const std = @import("std");
const device = @import("device_owner.zig");

test "scheduler-only maintenance hold survives failed probes and foreign/older snapshots until exact tracker resume" {
    var hold: device.ActorPauseHold = .{};
    const instance: [16]u8 = @splat(1);
    const foreign: [16]u8 = @splat(2);
    try std.testing.expect(!hold.blocks(instance, false, 0));
    try std.testing.expectError(error.InvalidPause, hold.reserve(instance, 0));
    try hold.reserve(instance, 7);
    try std.testing.expect(hold.blocks(instance, true, 7));
    try std.testing.expect(hold.blocks(instance, false, 7)); // incoherent open/nonzero pause
    try std.testing.expect(hold.blocks(instance, true, 0)); // incoherent closed/zero pause
    try std.testing.expectError(error.InvalidPause, hold.reserve(foreign, 7));
    try std.testing.expectError(error.InvalidPause, hold.reserve(instance, 6));
    try std.testing.expect(hold.blocks(foreign, false, 0));
    try std.testing.expect(hold.blocks(instance, true, 6));
    try std.testing.expect(hold.blocks(instance, true, 7));
    try std.testing.expect(!hold.blocks(instance, false, 0));
    try std.testing.expect(!hold.blocks(instance, true, 7));
    try hold.reserve(instance, 8);
    // A newer pause in this SAME tracker is possible only after exact resume.
    try std.testing.expect(!hold.blocks(instance, true, 9));
    try std.testing.expect(!hold.blocks(instance, true, 9));
}
