//! Isolated design fixture; not linked to the server or a receipt issuer.
const std = @import("std");

fn Slots(comptime capacity: usize, comptime Generation: type) type {
    return struct {
        const Self = @This();
        const Slot = struct { generation: Generation = 0, live: bool = false };
        const Handle = struct { epoch: u64, index: usize, generation: Generation };
        epoch: u64,
        slots: [capacity]Slot = @splat(.{}),

        fn allocate(self: *Self) ?Handle {
            for (&self.slots, 0..) |*slot, index| {
                if (slot.live or slot.generation == std.math.maxInt(Generation)) continue;
                slot.generation += 1;
                slot.live = true;
                return .{ .epoch = self.epoch, .index = index, .generation = slot.generation };
            }
            return null;
        }

        fn validate(self: *const Self, handle: Handle) bool {
            if (handle.epoch != self.epoch or handle.index >= capacity) return false;
            const slot = self.slots[handle.index];
            return slot.live and slot.generation == handle.generation;
        }

        // In a tracker this check and allocation belong in one critical
        // section. A failed reservation never consumes the live parent.
        fn reserveChild(self: *Self, parent: Handle) ?Handle {
            if (!self.validate(parent)) return null;
            return self.allocate();
        }

        fn release(self: *Self, handle: Handle) bool {
            if (!self.validate(handle)) return false;
            self.slots[handle.index].live = false;
            return true;
        }
    };
}

test "generation saturation retires one slot without affecting another" {
    var table = Slots(2, u2){ .epoch = 1 };
    const first = table.allocate().?;
    const held = table.allocate().?;
    try std.testing.expect(table.allocate() == null);
    try std.testing.expect(table.release(first));
    const second = table.allocate().?;
    try std.testing.expect(second.index == first.index and second.generation == 2);
    try std.testing.expect(!table.release(first));
    try std.testing.expect(table.release(second));
    const last = table.allocate().?;
    try std.testing.expect(last.generation == 3);
    try std.testing.expect(table.release(last));
    try std.testing.expect(table.allocate() == null);
    try std.testing.expect(table.validate(held));
    try std.testing.expect(table.release(held));
    const sibling = table.allocate().?;
    try std.testing.expect(sibling.index == held.index);
}

test "worker acknowledgement cannot invalidate a reserved callback" {
    var table = Slots(2, u64){ .epoch = 1 };
    const worker = table.allocate().?;
    const callback = table.reserveChild(worker).?;
    try std.testing.expect(table.reserveChild(worker) == null);
    try std.testing.expect(table.release(worker));
    try std.testing.expect(table.reserveChild(worker) == null);
    const destructor = table.reserveChild(callback).?;
    try std.testing.expect(destructor.index == worker.index);
    try std.testing.expect(destructor.generation != worker.generation);
    try std.testing.expect(table.release(callback));
    try std.testing.expect(table.validate(destructor));
    try std.testing.expect(table.release(destructor));
}

test "previous epoch cannot release coincident live slot" {
    var old = Slots(1, u64){ .epoch = 1 };
    var replacement = Slots(1, u64){ .epoch = 2 };
    const original = old.allocate().?;
    const current = replacement.allocate().?;
    try std.testing.expect(original.index == current.index and original.generation == current.generation);
    try std.testing.expect(!replacement.release(original));
    try std.testing.expect(replacement.release(current));
}
