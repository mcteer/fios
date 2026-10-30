const std = @import("std");
const custody = @import("backend_lifetime.zig");
test "native lifetime holds children, closes once and rejects reuse" {
    var parent = try custody.Lifetime.init();
    var child = try custody.Lifetime.init();
    const parent_lease = try parent.borrow();
    const operation = try child.borrow();
    try std.testing.expect(!parent.canClose(null));
    try std.testing.expect(!child.canClose(null));
    if (child.beginClose(null)) |_| {
        std.debug.print("FIO_BACKEND_LIFETIME_CLOSED_HELD_CHILD\n", .{});
        return error.HeldChildCloseAccepted;
    } else |err| try std.testing.expectEqual(error.LifetimeBusy, err);
    const closing = try parent.beginClose(parent_lease);
    try std.testing.expectError(error.LifetimeUnavailable, parent.borrow());
    try std.testing.expect(!parent.commitClose(closing));
    try std.testing.expect(child.release(operation));
    const child_close = try child.beginClose(null);
    try std.testing.expect(child.commitClose(child_close));
    try std.testing.expect(!child.commitClose(child_close));
    try std.testing.expect(parent.release(parent_lease));
    try std.testing.expect(parent.commitClose(closing));
    try std.testing.expect(!parent.commitClose(closing));
}
test "native lifetime foreign replay overflow and full slots fail closed" {
    var first = try custody.Lifetime.init();
    var second = try custody.Lifetime.init();
    const lease = try first.borrow();
    try std.testing.expect(!second.release(lease));
    try std.testing.expectError(error.LifetimeUnavailable, second.borrow());
    try std.testing.expect(first.release(lease));
    const newer = try first.borrow();
    try std.testing.expect(newer.sequence != lease.sequence);
    try std.testing.expect(!first.release(lease));
    try std.testing.expect(first.release(newer));
    try std.testing.expect(!first.canClose(null)); // Replay uncertainty persists.
    var full = try custody.Lifetime.init();
    var leases: [64]custody.Ticket = undefined;
    for (&leases) |*ticket| ticket.* = try full.borrow();
    try std.testing.expectError(error.LifetimeBusy, full.borrow());
    for (leases) |ticket| try std.testing.expect(full.release(ticket));
    full.sequence = std.math.maxInt(u64);
    try std.testing.expectError(error.LifetimeExhausted, full.borrow());
    try std.testing.expectError(error.LifetimeBusy, full.beginClose(null));
    var fenced = try custody.Lifetime.init();
    const outstanding = try fenced.borrow();
    fenced.fence();
    if (fenced.borrow()) |unexpected| {
        _ = fenced.release(unexpected);
        std.debug.print("FIO_BACKEND_LIFETIME_FENCE_REOPENED\n", .{});
        return error.BackendUncertaintyLost;
    } else |err| try std.testing.expectEqual(error.LifetimeUnavailable, err);
    try std.testing.expect(!fenced.canClose(outstanding));
    try std.testing.expect(fenced.release(outstanding));
    fenced.fence();
    try std.testing.expect(!fenced.canClose(null));
    try std.testing.expectError(error.LifetimeBusy, fenced.beginClose(null));
    var invalid: custody.Lifetime = .{};
    try std.testing.expectError(error.LifetimeUnavailable, invalid.borrow());
}

test "native lifetime borrow and close serialize their decision" {
    const Shared = struct {
        object: custody.Lifetime,
        start: std.atomic.Value(bool) = .init(false),
        borrowed: bool = false,
        fn run(self: *@This()) void {
            while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
            if (self.object.borrow()) |ticket| {
                self.borrowed = true;
                if (!self.object.release(ticket)) @panic("Native lifetime release failed");
            } else |err| if (err != error.LifetimeUnavailable) @panic("Unexpected native lifetime borrow failure");
        }
    };
    for (0..32) |_| {
        var shared: Shared = .{ .object = try custody.Lifetime.init() };
        const thread = try std.Thread.spawn(.{}, Shared.run, .{&shared});
        shared.start.store(true, .release);
        const claim = shared.object.beginClose(null) catch null;
        thread.join();
        const close = claim orelse try shared.object.beginClose(null);
        try std.testing.expect(shared.object.commitClose(close));
        try std.testing.expectError(error.LifetimeUnavailable, shared.object.borrow());
    }
}
