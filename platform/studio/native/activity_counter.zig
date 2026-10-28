//! Conservative server-connection ownership. Includes ingress and response drain;
//! a status observer excludes only its own counted connection, never others.
const std = @import("std");

pub const Counter = struct {
    value: std.atomic.Value(u64) = .init(0),

    pub fn enter(self: *Counter) error{Overflow}!void {
        var old = self.value.load(.acquire);
        while (true) {
            if (old == std.math.maxInt(u64)) return error.Overflow;
            if (self.value.cmpxchgWeak(old, old + 1, .acq_rel, .acquire)) |actual| {
                old = actual;
            } else return;
        }
    }

    pub fn leave(self: *Counter) error{Underflow}!void {
        var old = self.value.load(.acquire);
        while (true) {
            if (old == 0) return error.Underflow;
            if (self.value.cmpxchgWeak(old, old - 1, .acq_rel, .acquire)) |actual| {
                old = actual;
            } else return;
        }
    }

    pub fn others(self: *const Counter) error{ObserverNotCounted}!u64 {
        const current = self.value.load(.acquire);
        if (current == 0) return error.ObserverNotCounted;
        return current - 1;
    }
};

test "observer never counts itself as inference or hides another connection" {
    var counter: Counter = .{};
    try std.testing.expectError(error.ObserverNotCounted, counter.others());
    try counter.enter();
    try std.testing.expectEqual(@as(u64, 0), try counter.others());
    try counter.enter();
    try std.testing.expectEqual(@as(u64, 1), try counter.others());
    try counter.leave();
    try std.testing.expectEqual(@as(u64, 0), try counter.others());
    try counter.leave();
    try std.testing.expectError(error.Underflow, counter.leave());
}

test "overflow cannot wrap into an idle snapshot" {
    var counter: Counter = .{ .value = .init(std.math.maxInt(u64)) };
    try std.testing.expectError(error.Overflow, counter.enter());
    try std.testing.expectEqual(std.math.maxInt(u64) - 1, try counter.others());
}
