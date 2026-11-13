// Ordinary ownership component contract. No device/backend retirement claim.
const std = @import("std");
const ownership = @import("ownership");

test "retained descendants preserve original request lineage and absence stays unknown" {
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(7));
    const id = try ownership.parseCorrelationHex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    const original = try tracker.enter(io);
    try tracker.associate(io, original, id);
    const before = tracker.correlationSnapshot(io, id);
    try std.testing.expect(before.found and !before.uncertain);
    try std.testing.expectEqual(original.sequence, before.root_sequence);
    const other = try tracker.enter(io);
    try std.testing.expectError(error.DuplicateCorrelation, tracker.associate(io, other, id));
    try tracker.leave(io, other);
    const retained = try tracker.retainTokens(io, &.{original});
    try tracker.leave(io, original);
    const descendant = tracker.correlationSnapshot(io, id);
    try std.testing.expect(descendant.found and !descendant.uncertain);
    try std.testing.expectEqual(before.root_sequence, descendant.root_sequence);
    try std.testing.expectEqual(@as(u64, 1), descendant.references);
    retained.release(io);
    const absent = tracker.correlationSnapshot(io, id);
    try std.testing.expect(!absent.found and absent.uncertain);
    // A missing record cannot become completion/not-sent/device-terminal proof.
}
