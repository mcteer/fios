// Ordinary negative-evidence admission integration; callback values are unit
// inputs, never a simulated SDK/device completion or coverage capability.
const std = @import("std");
const ownership = @import("request_ownership.zig");
test "fios known backend uncertainty refuses new work without changing reads" {
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(7));
    const Probe = struct {
        var original_tracker: *ownership.Tracker = undefined;
        var uncertain = false;
        var calls: usize = 0;
        fn read() bool {
            calls += 1;
            // This ordinary reentrant read requires that the callback runs
            // outside the tracker mutex. It performs no backend/model work.
            _ = original_tracker.snapshot(std.testing.io);
            return uncertain;
        }
    };
    Probe.original_tracker = &tracker;
    try tracker.enrollBackendUncertaintyProbe(io, &Probe.read);
    const first = try tracker.enter(io);
    try tracker.bind(io, first, "org/original");
    try tracker.active(io, first);
    const pending = try tracker.enter(io);
    try tracker.bind(io, pending, "org/original");
    const held = try tracker.retainTokens(io, &.{first});
    try tracker.leave(io, first);
    Probe.uncertain = true;
    const calls = Probe.calls;
    const before = tracker.snapshot(io);
    try std.testing.expect(!before.uncertain);
    try std.testing.expectEqual(calls, Probe.calls); // Reads never actuate a fence.
    try std.testing.expectError(error.CoverageUncertain, tracker.active(io, pending));
    const incoming = try tracker.enter(io); // Metadata connections remain observable.
    try std.testing.expectError(error.CoverageUncertain, tracker.bind(io, incoming, "org/other"));
    try std.testing.expectError(error.CoverageUncertain, tracker.reservePreparation(io, null, "org/other"));
    try std.testing.expectError(error.CoverageUncertain, tracker.bindAuxiliary(io, first, "org/auxiliary"));
    try std.testing.expectError(error.CoverageUncertain, tracker.beginModelMutation(io, "org/original"));
    const retained = tracker.snapshot(io);
    try std.testing.expect(retained.uncertain);
    try std.testing.expectEqual(@as(usize, 1), retained.active);
    try std.testing.expectEqual(@as(usize, 1), retained.preparing);
    try std.testing.expectEqual(@as(usize, 1), retained.model_count);
    try std.testing.expectEqual(@as(usize, 0), retained.model_mutations);
    try tracker.responding(io, first); // Existing accounting/release still proceeds.
    held.release(io);
    try tracker.leave(io, pending);
    try tracker.leave(io, incoming);
    Probe.uncertain = false;
    const later = try tracker.enter(io);
    try std.testing.expectError(error.CoverageUncertain, tracker.bind(io, later, "org/original"));
    try tracker.leave(io, later);
    const empty = tracker.snapshot(io);
    try std.testing.expect(empty.uncertain and empty.owned == 0);
    std.debug.print("PASS: known backend uncertainty refuses preparation/binding/execution/mutation outside callback locks, preserves original custody and cannot clear on later healthy input\n", .{});
}
