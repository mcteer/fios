//! Per-root SDK event observations, not whole-request completion or admission.
const std = @import("std");

pub const Phase = enum { origin, retired, uncertain };
pub const Snapshot = struct {
    root: u64,
    sequence: u64,
    originated: u64,
    retired: u64,
    pending: u64,
    history_retained: bool,
    uncertain: bool,
};

pub const Observation = struct {
    initialized: bool,
    source_uncertain: bool,
    instance: [16]u8 = @splat(0),
    host: ?Snapshot = null,
    metal: ?Snapshot = null,
};

pub fn RootEvents(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Row = struct {
            root: u64 = 0,
            originated: u64 = 0,
            retired: u64 = 0,
            pending: u64 = 0,
            touched: u64 = 0,
            history_retained: bool = true,
            uncertain: bool = false,
        };
        rows: [capacity]Row = @splat(.{}),
        sequence: u64 = 0,
        eviction_floor: u64 = 0,
        observations_lost: bool = false,

        fn find(self: *Self, root: u64) ?*Row {
            for (&self.rows) |*row| if (row.root == root) return row;
            return null;
        }

        fn originRow(self: *Self, root: u64) ?*Row {
            if (self.find(root)) |row| return row;
            var available: ?*Row = null;
            for (&self.rows) |*row| {
                if (row.root == 0) {
                    available = row;
                    break;
                }
                if (row.pending == 0 and (available == null or row.touched < available.?.touched)) available = row;
            }
            const row = available orelse return null;
            self.eviction_floor = @max(self.eviction_floor, row.root);
            row.* = .{ .root = root, .history_retained = root > self.eviction_floor };
            return row;
        }

        // The caller supplies distinct immutable roots for one accepted event.
        pub fn observe(self: *Self, roots: []const u64, phase: Phase) void {
            if (self.sequence == std.math.maxInt(u64) or roots.len == 0) {
                self.observations_lost = true;
                return;
            }
            self.sequence += 1;
            for (roots) |root| {
                if (root == 0) {
                    self.observations_lost = true;
                    continue;
                }
                const row = (if (phase == .origin) self.originRow(root) else self.find(root)) orelse {
                    self.observations_lost = true;
                    continue;
                };
                row.touched = self.sequence;
                switch (phase) {
                    .origin => {
                        if (row.originated == std.math.maxInt(u64)) {
                            self.observations_lost = true;
                            continue;
                        }
                        row.originated += 1;
                        row.pending += 1;
                    },
                    .retired => {
                        if (row.pending == 0) {
                            self.observations_lost = true;
                            continue;
                        }
                        row.pending -= 1;
                        row.retired += 1;
                    },
                    .uncertain => row.uncertain = true,
                }
            }
        }

        pub fn snapshot(self: *const Self, root: u64) ?Snapshot {
            for (self.rows) |row| {
                if (row.root == 0 or row.root != root) continue;
                return .{ .root = root, .sequence = self.sequence, .originated = row.originated, .retired = row.retired, .pending = row.pending, .history_retained = row.history_retained and !self.observations_lost, .uncertain = row.uncertain };
            }
            return null;
        }
    };
}

test "overlapping request SDK events keep distinct root counts" {
    var events: RootEvents(4) = .{};
    events.observe(&.{ 11, 22 }, .origin);
    events.observe(&.{22}, .origin);
    try std.testing.expectEqual(@as(u64, 1), events.snapshot(11).?.pending);
    try std.testing.expectEqual(@as(u64, 2), events.snapshot(22).?.pending);
    events.observe(&.{22}, .retired);
    events.observe(&.{ 11, 22 }, .retired);
    const first = events.snapshot(11).?;
    const second = events.snapshot(22).?;
    try std.testing.expect(first.originated == 1 and first.retired == 1 and first.pending == 0);
    try std.testing.expect(second.originated == 2 and second.retired == 2 and second.pending == 0);
    try std.testing.expect(first.history_retained and second.history_retained);
}

test "completed event history rolls without relabelling roots" {
    var events: RootEvents(2) = .{};
    for ([_]u64{ 1, 2, 3 }) |root| {
        events.observe(&.{root}, .origin);
        events.observe(&.{root}, .retired);
    }
    try std.testing.expect(events.snapshot(1) == null);
    try std.testing.expect(events.snapshot(3).?.history_retained);
    events.observe(&.{1}, .origin);
    try std.testing.expect(!events.snapshot(1).?.history_retained);
    try std.testing.expectEqual(@as(u64, 1), events.snapshot(1).?.pending);
}
