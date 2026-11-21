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

test "primary phases retain exact model identity until the original last reference" {
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(8));
    const original = try tracker.enter(io);
    try tracker.bind(io, original, "fixture/Exact-Case");
    const preparing = tracker.primarySnapshot(io);
    try std.testing.expectEqual(@as(usize, 1), preparing.preparing);
    try std.testing.expectEqualStrings("fixture/Exact-Case", preparing.models[0].id[0..preparing.models[0].len]);
    const retained = try tracker.retainTokens(io, &.{original});
    try tracker.active(io, original);
    try std.testing.expectEqual(@as(usize, 1), tracker.primarySnapshot(io).active);
    try tracker.responding(io, original);
    try tracker.leave(io, original);
    try std.testing.expectEqual(@as(usize, 1), tracker.primarySnapshot(io).responding);
    retained.release(io);
    try std.testing.expectEqual(@as(usize, 0), tracker.primarySnapshot(io).owned);
}
