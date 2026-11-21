const std = @import("std");
const device = @import("device_owner.zig");
// Pure injected metadata hooks. No MLX, process, PID signal or backend work.
const Fake = struct {
    var acquired: usize = 0;
    var released: usize = 0;
    var permit_release: bool = true;
    fn reset() void { acquired = 0; released = 0; permit_release = true; }
    fn acquire(owner: u64) ?u64 { if (owner != 9) return null; acquired += 1; return 17; }
    fn release(owner: u64, ticket: u64) bool {
        released += 1;
        return permit_release and owner == 9 and ticket == 17;
    }
    fn hooks() device.RegistryHooks { return .{ .acquire = acquire, .release = release }; }
};
test "partial registry ticket remains with parked actor until coherent exact resume" {
    Fake.reset();
    var actor: device.ActorPauseHold = .{};
    const instance: [16]u8 = @splat(3);
    try actor.reserve(instance, 11);
    try actor.reserveOwnedRegistry(9, Fake.hooks());
    try actor.reserveOwnedRegistry(9, Fake.hooks());
    try std.testing.expectEqual(@as(usize, 1), Fake.acquired);
    try std.testing.expect(actor.blocks(@splat(4), false, 0));
    try std.testing.expect(actor.blocks(instance, true, 11));
    try std.testing.expectEqual(@as(usize, 0), Fake.released);
    try std.testing.expect(!actor.blocks(instance, false, 0));
    try std.testing.expectEqual(@as(usize, 1), Fake.released);
    try std.testing.expect(!actor.blocks(instance, false, 0));
    try std.testing.expectEqual(@as(usize, 1), Fake.released);
}
test "no pause cannot acquire and another creator cannot retarget held metadata" {
    Fake.reset();
    var actor: device.ActorPauseHold = .{};
    try std.testing.expectError(error.InvalidPause, actor.reserveOwnedRegistry(9, Fake.hooks()));
    try std.testing.expectEqual(@as(usize, 0), Fake.acquired);
    try actor.reserve(@splat(3), 11);
    try actor.reserveOwnedRegistry(9, Fake.hooks());
    try std.testing.expectError(error.WrongOwner, actor.reserveOwnedRegistry(10, Fake.hooks()));
    try std.testing.expectEqual(@as(usize, 1), Fake.acquired);
    try std.testing.expect(!actor.blocks(@splat(3), false, 0));
}
test "failed registry release cannot unpark even after coherent resume" {
    Fake.reset();
    var actor: device.ActorPauseHold = .{};
    try actor.reserve(@splat(3), 11);
    try actor.reserveOwnedRegistry(9, Fake.hooks());
    Fake.permit_release = false;
    try std.testing.expect(actor.blocks(@splat(3), false, 0));
    try std.testing.expectEqual(@as(u64, 11), actor.sequence);
    Fake.permit_release = true;
    try std.testing.expect(!actor.blocks(@splat(3), false, 0));
}
