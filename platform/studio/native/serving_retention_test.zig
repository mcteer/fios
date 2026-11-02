// Ordinary local reference lifetime only; no device/backend completion proof.
const std = @import("std");
const ownership = @import("request_ownership.zig");
test "fios serving state follows retained owners and mutation tickets" {
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try std.testing.expect(tracker.hasRetainedWork(io)); // Undated source is unknown.
    try tracker.initialize(io, @splat(7));
    try std.testing.expect(!tracker.hasRetainedWork(io));
    const first = try tracker.enter(io);
    try tracker.bind(io, first, "fixture/original");
    try tracker.active(io, first);
    const mutation = try tracker.beginModelMutation(io, "fixture/other");
    const held = try tracker.retainTokens(io, &.{first});
    const Keeper = struct {
        fn finish(value: ownership.Retained, ready: *std.atomic.Value(bool)) void {
            while (!ready.load(.acquire)) {
                const interval: std.c.timespec = .{ .sec = 0, .nsec = std.time.ns_per_ms };
                _ = std.c.nanosleep(&interval, null);
            }
            value.release(std.testing.io);
        }
    };
    var ready = std.atomic.Value(bool).init(false);
    const worker = try std.Thread.spawn(.{}, Keeper.finish, .{ held, &ready });
    var joined = false;
    defer {
        ready.store(true, .release);
        if (!joined) worker.join();
    }
    try tracker.leave(io, first); // Original HTTP reference has already left.
    const before = tracker.snapshot(io);
    try std.testing.expect(before.active == 1 and before.owned == 1);
    try std.testing.expect(tracker.hasRetainedWork(io));
    const after = tracker.snapshot(io);
    try std.testing.expectEqual(before.sample_sequence + 1, after.sample_sequence);
    tracker.fence(io);
    ready.store(true, .release);
    worker.join();
    joined = true;
    try std.testing.expect(tracker.hasRetainedWork(io)); // Actual mutation remains.
    try tracker.endModelMutation(io, mutation);
    try std.testing.expect(!tracker.hasRetainedWork(io));
    try std.testing.expect(tracker.snapshot(io).uncertain);
    std.debug.print("PASS: original connection release retains actual worker references and mutation tickets; local release never clears uncertainty or refreshes source samples\n", .{});
}
